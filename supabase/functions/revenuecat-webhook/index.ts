import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.39.0";

console.log("RevenueCat Webhook Function Started!");

const ATTRIBUTION_WINDOW_MS = 14 * 24 * 60 * 60 * 1000;

// Free-tier caps enforced server-side when a user drops back to free. Keep in
// sync with kFreeFavoriteLimit / kFreeSavedGamesLimit in the Flutter app
// (lib/utils/favorite_constants.dart, lib/utils/library_utils.dart).
const FREE_FAVORITE_PLAYERS_LIMIT = 3;
const FREE_SAVED_ANALYSES_LIMIT = 10;

async function trimToFreeTier(
  supabase: ReturnType<typeof createClient>,
  appUserId: string,
): Promise<void> {
  if (!appUserId) return;

  const [favRes, savedRes] = await Promise.all([
    supabase.rpc("trim_favorite_players_to_top_n", {
      p_user_id: appUserId,
      p_keep: FREE_FAVORITE_PLAYERS_LIMIT,
    }),
    supabase.rpc("trim_saved_analyses_to_recent_n", {
      p_user_id: appUserId,
      p_keep: FREE_SAVED_ANALYSES_LIMIT,
    }),
  ]);

  if (favRes.error) {
    console.warn(
      `trim_favorite_players_to_top_n failed for ${appUserId}: ${favRes.error.message}`,
    );
  } else {
    console.log(
      `Trimmed ${favRes.data ?? 0} favorite players for ${appUserId} (cap ${FREE_FAVORITE_PLAYERS_LIMIT}).`,
    );
  }

  if (savedRes.error) {
    console.warn(
      `trim_saved_analyses_to_recent_n failed for ${appUserId}: ${savedRes.error.message}`,
    );
  } else {
    console.log(
      `Trimmed ${savedRes.data ?? 0} saved analyses for ${appUserId} (cap ${FREE_SAVED_ANALYSES_LIMIT}).`,
    );
  }
}

type Platform = "ios" | "android" | "web" | "unknown";
type AttributionSource = "install" | "stamp";

type SubscriberAttributes = Record<string, { value?: string }>;

type ReferralRow = {
  affiliate_code: string;
  created_at: string | null;
  install_at: string | null;
  appsflyer_data: Record<string, unknown> | null;
  platform: Platform | null;
};

type AffiliateRow = {
  code: string;
  commission_rate: number | string;
  is_active: boolean;
};

function storeToPlatform(store: string | undefined): Platform {
  if (!store) return "unknown";
  const s = store.toLowerCase();
  if (s === "app_store" || s === "mac_app_store" || s === "apple") {
    return "ios";
  }
  if (
    s === "play_store" ||
    s === "amazon" ||
    s === "google" ||
    s === "google_play"
  ) {
    return "android";
  }
  if (s === "stripe" || s === "rc_billing" || s === "web") return "web";
  return "unknown";
}

function nonEmpty(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  const str = String(value).trim();
  return str.length === 0 || str === "null" ? null : str;
}

function attrValue(attrs: SubscriberAttributes, key: string): string | null {
  return nonEmpty(attrs[key]?.value);
}

function isNonOrganicStatus(value: unknown): boolean {
  const status = nonEmpty(value)?.toLowerCase();
  return status === "non-organic" || status === "nonorganic";
}

function parseDate(value: unknown): Date | null {
  const raw = nonEmpty(value);
  if (!raw) return null;

  if (/^\d{10}$/.test(raw)) return new Date(Number(raw) * 1000);
  if (/^\d{13}$/.test(raw)) return new Date(Number(raw));

  const normalized = raw.includes("T") ? raw : raw.replace(" ", "T");
  const withZone = /(?:Z|[+-]\d{2}:?\d{2})$/.test(normalized)
    ? normalized
    : `${normalized}Z`;
  const parsed = new Date(withZone);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function dateFromMillis(value: unknown): Date | null {
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  return new Date(value);
}

function eventDate(event: Record<string, unknown>): Date {
  return (
    dateFromMillis(event.purchased_at_ms) ??
    dateFromMillis(event.event_timestamp_ms) ??
    new Date()
  );
}

function referralInstallDate(referral: ReferralRow): Date | null {
  return (
    parseDate(referral.install_at) ??
    parseDate(referral.appsflyer_data?.install_time) ??
    parseDate(referral.created_at)
  );
}

function installDateFromAttributes(attrs: SubscriberAttributes): Date | null {
  return (
    parseDate(attrValue(attrs, "appsflyer_install_at")) ??
    parseDate(attrValue(attrs, "redemption_install_at")) ??
    parseDate(attrValue(attrs, "install_at"))
  );
}

function referralIsNonOrganic(referral: ReferralRow): boolean {
  return isNonOrganicStatus(referral.appsflyer_data?.af_status);
}

function attributesAreNonOrganic(attrs: SubscriberAttributes): boolean {
  return (
    isNonOrganicStatus(attrValue(attrs, "appsflyer_af_status")) ||
    isNonOrganicStatus(attrValue(attrs, "redemption_af_status"))
  );
}

function withinAttributionWindow(
  installAt: Date | null,
  convertedAt: Date,
): boolean {
  if (!installAt) return false;
  const ageMs = convertedAt.getTime() - installAt.getTime();
  return ageMs >= 0 && ageMs <= ATTRIBUTION_WINDOW_MS;
}

async function findActiveAffiliate(
  supabase: ReturnType<typeof createClient>,
  code: string,
): Promise<AffiliateRow | null> {
  const variants = Array.from(
    new Set([code, code.toLowerCase(), code.toUpperCase()]),
  );
  const { data } = await supabase
    .from("affiliates")
    .select("code, commission_rate, is_active")
    .in("code", variants)
    .eq("is_active", true)
    .limit(1)
    .maybeSingle();
  return data as AffiliateRow | null;
}

Deno.serve(async (req) => {
  try {
    if (req.method !== "POST") {
      return new Response(JSON.stringify({ error: "Method not allowed" }), {
        status: 405,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Shared-secret auth. If REVENUECAT_WEBHOOK_AUTH is set, the incoming
    // request must carry an identical Authorization header — this is the only
    // thing that proves the POST is actually from RevenueCat and not someone
    // who guessed the function URL fabricating commission rows. The secret is
    // intentionally optional so the function still responds during initial
    // bring-up before the secret is configured on both ends.
    const expectedAuth = Deno.env.get("REVENUECAT_WEBHOOK_AUTH");
    if (expectedAuth && expectedAuth.length > 0) {
      const provided = req.headers.get("authorization") ?? "";
      if (provided !== expectedAuth) {
        console.warn("Rejected webhook: bad Authorization header");
        return new Response(JSON.stringify({ error: "Unauthorized" }), {
          status: 401,
          headers: { "Content-Type": "application/json" },
        });
      }
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const supabase = createClient(supabaseUrl, supabaseKey);

    const body = await req.json();
    const event = body.event as Record<string, unknown> | undefined;

    if (!event) {
      return new Response(
        JSON.stringify({ error: "No event object found in payload" }),
        {
          status: 400,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    const isSandbox = event.environment === "SANDBOX";
    const eventType = String(event.type ?? "");
    const appUserId = String(event.app_user_id ?? "");
    const eventId = String(event.id ?? "");
    const productId = nonEmpty(event.product_id);
    const price = typeof event.price === "number" ? event.price : 0;
    const currency = nonEmpty(event.currency) ?? "USD";
    const cancelReason = nonEmpty(event.cancel_reason);
    const platform = storeToPlatform(nonEmpty(event.store) ?? undefined);
    const periodType = nonEmpty(event.period_type);
    const convertedAt = eventDate(event);

    const isInitial = eventType === "INITIAL_PURCHASE";
    const isRenewal = eventType === "RENEWAL";
    const isNonRenew = eventType === "NON_RENEWING_PURCHASE";
    const isTrialPeriod =
      event.is_trial_period === true || periodType === "TRIAL";
    const isTrialStarted =
      eventType === "TRIAL_STARTED" || (isInitial && isTrialPeriod);
    const isTrialConverted =
      eventType === "TRIAL_CONVERTED" ||
      (isRenewal && event.is_trial_conversion === true);
    const isTrialCancelled = eventType === "TRIAL_CANCELLED";
    const isPurchase =
      (isInitial && !isTrialPeriod) ||
      isRenewal ||
      isNonRenew ||
      isTrialConverted;
    const isRefund =
      eventType === "CANCELLATION" &&
      (cancelReason === "CUSTOMER_SUPPORT" ||
        cancelReason === "FRAUD" ||
        cancelReason === "REFUND");

    console.log(
      `Event: ${eventType} env=${event.environment} user=${appUserId} store=${event.store} period=${periodType}`,
    );

    // EXPIRATION fires when the user's entitlement actually ends (auto-renew
    // off + period_end reached, or revoked). At that point the user is back
    // on the free tier and must obey the free-tier caps server-side, since
    // the client guards only block *new* adds — they never prune existing
    // overage left behind by the previous premium session.
    if (eventType === "EXPIRATION") {
      if (appUserId) {
        await trimToFreeTier(supabase, appUserId);
      }
      return new Response(
        JSON.stringify({ message: "Free-tier limits enforced" }),
        {
          status: 200,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    if (!isPurchase && !isRefund && !isTrialStarted && !isTrialCancelled) {
      console.log(`Event ignored: ${eventType}`);
      return new Response(JSON.stringify({ message: "Event ignored" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    if (isRefund) {
      let query = supabase
        .from("affiliate_conversions")
        .update({ status: "refunded" })
        .eq("referred_user_id", appUserId)
        .in("status", ["pending", "cleared"]);
      if (productId) query = query.eq("product_id", productId);
      await query;

      return new Response(JSON.stringify({ message: "Refund processed" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    if (isTrialCancelled) {
      let query = supabase
        .from("affiliate_conversions")
        .update({ status: "refunded" })
        .eq("referred_user_id", appUserId)
        .eq("status", "trial");
      if (productId) query = query.eq("product_id", productId);
      await query;

      return new Response(JSON.stringify({ message: "Trial cancelled" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    const subAttrs = (event.subscriber_attributes ??
      {}) as SubscriberAttributes;
    // Flutter writes `appsflyer_affiliate_code` via Purchases.setAttributes()
    // when forwarding cached install metadata; `redemption_affiliate_code` is
    // the older key reserved for promo-code flows. Accept either so the
    // anonymous-RC → identified-Supabase race (trial fires before logIn) has
    // a recovery path when affiliate_referrals can't be joined by user id.
    const stampedAffiliateCode =
      attrValue(subAttrs, "redemption_affiliate_code") ??
      attrValue(subAttrs, "appsflyer_affiliate_code");

    let affiliateCode: string | null = null;
    let attributionSource: AttributionSource = "install";
    let installAt: Date | null = null;
    let referralPlatform: Platform | null = null;

    const { data: referral } = await supabase
      .from("affiliate_referrals")
      .select("affiliate_code, install_at, created_at, appsflyer_data, platform")
      .eq("referred_user_id", appUserId)
      .maybeSingle();

    if (referral) {
      const referralRow = referral as ReferralRow;
      if (referralIsNonOrganic(referralRow)) {
        affiliateCode = referralRow.affiliate_code;
        installAt = referralInstallDate(referralRow);
        referralPlatform = referralRow.platform;
      } else {
        console.log(`Referral for ${appUserId} is not non-organic. Ignoring.`);
      }
    }

    if (
      !affiliateCode &&
      stampedAffiliateCode &&
      attributesAreNonOrganic(subAttrs)
    ) {
      const affiliate = await findActiveAffiliate(supabase, stampedAffiliateCode);
      if (affiliate) {
        affiliateCode = affiliate.code;
        installAt = installDateFromAttributes(subAttrs);
        attributionSource = "stamp";
      }
    }

    if (!affiliateCode) {
      console.log(`User ${appUserId} has no eligible affiliate attribution.`);
      return new Response(
        JSON.stringify({ message: "User not referred by affiliate" }),
        {
          status: 200,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    let hasPriorPaidConversion = false;
    if (isRenewal && !isTrialConverted) {
      const { data: priorConversion } = await supabase
        .from("affiliate_conversions")
        .select("id")
        .eq("referred_user_id", appUserId)
        .eq("affiliate_code", affiliateCode)
        .eq("is_trial_period", false)
        .in("status", ["pending", "cleared", "paid"])
        .limit(1)
        .maybeSingle();
      hasPriorPaidConversion = !!priorConversion;
    }

    if (
      !hasPriorPaidConversion &&
      !withinAttributionWindow(installAt, convertedAt)
    ) {
      console.log(
        `Affiliate attribution expired for ${appUserId}: install=${installAt?.toISOString() ?? "unknown"} conversion=${convertedAt.toISOString()}`,
      );
      return new Response(
        JSON.stringify({ message: "Affiliate attribution window expired" }),
        {
          status: 200,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    if (attributionSource !== "install") {
      const { error: backfillErr } = await supabase
        .from("affiliate_referrals")
        .insert({
          referred_user_id: appUserId,
          affiliate_code: affiliateCode,
          appsflyer_data: {
            source: attributionSource,
            via: "redemption",
            af_status:
              attrValue(subAttrs, "redemption_af_status") ??
              attrValue(subAttrs, "appsflyer_af_status"),
          },
          install_at: installAt?.toISOString(),
          is_sandbox: isSandbox,
          platform,
        });
      if (backfillErr && backfillErr.code !== "23505") {
        console.warn(`Referral back-fill failed: ${backfillErr.message}`);
      } else {
        console.log(
          `Back-filled affiliate_referrals via ${attributionSource} for ${appUserId} -> ${affiliateCode}`,
        );
      }
    }

    if (isTrialStarted) {
      const { error } = await supabase
        .from("affiliate_conversions")
        .insert({
          referred_user_id: appUserId,
          affiliate_code: affiliateCode,
          event_type: eventType || "TRIAL_STARTED",
          revenue_usd: 0,
          currency,
          commission_usd: 0,
          product_id: productId,
          rc_event_id: eventId,
          status: "trial",
          is_trial_period: true,
          is_sandbox: isSandbox,
          platform: referralPlatform ?? platform,
        });
      if (error && error.code !== "23505") throw error;

      return new Response(JSON.stringify({ message: "Trial recorded" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    if (isPurchase) {
      const affiliate = await findActiveAffiliate(supabase, affiliateCode);

      if (!affiliate) {
        console.log(`Affiliate ${affiliateCode} missing/inactive`);
        return new Response(
          JSON.stringify({ message: "Affiliate not found or inactive" }),
          {
            status: 200,
            headers: { "Content-Type": "application/json" },
          },
        );
      }

      const commissionAmount = price * Number(affiliate.commission_rate);

      const { error } = await supabase
        .from("affiliate_conversions")
        .insert({
          referred_user_id: appUserId,
          affiliate_code: affiliate.code,
          event_type: eventType,
          revenue_usd: price,
          currency,
          commission_usd: commissionAmount,
          product_id: productId,
          rc_event_id: eventId,
          status: "pending",
          is_trial_period: false,
          is_sandbox: isSandbox,
          platform: referralPlatform ?? platform,
        });

      if (error) {
        if (error.code === "23505") {
          console.log(`Duplicate event ${eventId} ignored.`);
          return new Response(
            JSON.stringify({ message: "Event already processed" }),
            {
              status: 200,
              headers: { "Content-Type": "application/json" },
            },
          );
        }
        throw error;
      }

      if (isTrialConverted && productId) {
        await supabase
          .from("affiliate_conversions")
          .update({ status: "cleared" })
          .eq("referred_user_id", appUserId)
          .eq("product_id", productId)
          .eq("status", "trial");
      }

      return new Response(JSON.stringify({ message: "Conversion recorded" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ message: "No-op" }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("Critical Function Error:", err);
    return new Response(JSON.stringify({ error: "Internal Server Error" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
