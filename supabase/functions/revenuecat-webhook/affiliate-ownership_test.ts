// Exercise the deployed entrypoint with all outbound requests intercepted.
let handleWebhook: (request: Request) => Promise<Response>;
const originalServe = Deno.serve;
try {
  Deno.serve = ((handler: typeof handleWebhook) => {
    handleWebhook = handler;
  }) as typeof Deno.serve;
  await import("./index.ts");
} finally {
  Deno.serve = originalServe;
}

const userId = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
const purchasedAt = Date.parse("2026-10-22T12:00:00Z");
type Call = { url: URL; method: string; body: unknown };

function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

async function deliver(
  event: Record<string, unknown>,
  options: {
    authorized?: boolean;
    syncFails?: boolean;
    duplicate?: boolean;
    installAt?: string;
    ledger?: Record<string, unknown>[];
    referral?: Record<string, unknown> | null;
    mapping?: Record<string, unknown> | null;
    mappingFails?: boolean;
    dbFailure?: "referral" | "affiliate" | "refund";
    referralConflict?: boolean;
  } = {},
) {
  const environment = {
    SUPABASE_URL: "https://webhook.test",
    SUPABASE_SERVICE_ROLE_KEY: "test-only-service-key",
    PAYMENT_ANALYTICS_TOKEN: "test-only-reporting-token",
    REVENUECAT_WEBHOOK_AUTH: "test-only-webhook-secret",
    REVENUECAT_SYNC_TOKEN: "test-only-sync-secret",
  };
  const previous = new Map<string, string | undefined>();
  for (const [key, value] of Object.entries(environment)) {
    previous.set(key, Deno.env.get(key));
    Deno.env.set(key, value);
  }
  const calls: Call[] = [];
  const ledger = structuredClone(options.ledger ?? []);
  const originalFetch = globalThis.fetch;
  // supabase-js starts background auth timers even for a service-role client.
  // Track and close them so each delivery keeps Deno's leak checks enabled.
  const originalTimeout = globalThis.setTimeout;
  const originalInterval = globalThis.setInterval;
  const timers = new Set<number>();
  globalThis.setTimeout = ((
    callback: (...args: unknown[]) => void,
    delay?: number,
    ...args: unknown[]
  ) => {
    const id = originalTimeout(callback, delay, ...args);
    timers.add(id);
    return id;
  }) as typeof setTimeout;
  globalThis.setInterval = ((
    callback: (...args: unknown[]) => void,
    delay?: number,
    ...args: unknown[]
  ) => {
    const id = originalInterval(callback, delay, ...args);
    timers.add(id);
    return id;
  }) as typeof setInterval;
  globalThis.fetch = (input, init) => {
    const url = new URL(input instanceof Request ? input.url : String(input));
    const request = init as { method?: string; body?: unknown } | undefined;
    const method = request?.method ?? "GET";
    const body = typeof request?.body === "string"
      ? JSON.parse(request.body)
      : null;
    calls.push({ url, method, body });
    if (url.pathname === "/functions/v1/payment-analytics") {
      return Promise.resolve(Response.json({ status: "queued" }));
    }
    if (
      (options.dbFailure === "referral" &&
        url.pathname === "/rest/v1/affiliate_referrals" && method === "GET") ||
      (options.dbFailure === "affiliate" &&
        url.pathname === "/rest/v1/affiliates") ||
      (options.dbFailure === "refund" &&
        url.pathname === "/rest/v1/affiliate_conversions" && method === "PATCH")
    ) {
      return Promise.resolve(
        Response.json({ message: "temporary database failure" }, {
          status: 503,
        }),
      );
    }
    if (
      options.referralConflict &&
      url.pathname === "/rest/v1/affiliate_referrals" && method === "POST"
    ) return Promise.resolve(Response.json({ code: "23505" }, { status: 409 }));
    if (url.pathname === "/functions/v1/revenuecat-sync") {
      return Promise.resolve(
        options.syncFails
          ? new Response(null, { status: 503 })
          : Response.json({ summary: { error: 0 } }),
      );
    }
    if (url.pathname === "/rest/v1/affiliate_referrals" && method === "GET") {
      return Promise.resolve(
        Response.json(
          options.referral === null ? [] : [
            options.referral ?? {
              affiliate_code: "partner",
              is_sandbox: event.environment === "SANDBOX",
              install_at: options.installAt ?? "2026-10-21T12:00:00Z",
              created_at: "2026-10-21T12:00:00Z",
              appsflyer_data: { af_status: "Non-organic" },
              platform: null,
            },
          ],
        ),
      );
    }
    if (url.pathname === "/rest/v1/affiliate_referrals" && method === "POST") {
      return Promise.resolve(Response.json([]));
    }
    if (url.pathname === "/rest/v1/affiliate_native_offer_codes") {
      if (options.mappingFails) {
        return Promise.resolve(
          Response.json({ message: "database unavailable" }, { status: 503 }),
        );
      }
      const mapping = options.mapping;
      const matches = mapping &&
        ["code", "store", "is_active"].every((key) =>
          !url.searchParams.has(key) ||
          url.searchParams.get(key) === `eq.${mapping[key]}`
        );
      return Promise.resolve(Response.json(matches ? [mapping] : []));
    }
    if (url.pathname === "/rest/v1/affiliates" && method === "GET") {
      return Promise.resolve(Response.json([{
        code: "partner",
        is_active: true,
        commission_rate: 0.15,
      }]));
    }
    if (url.pathname === "/rest/v1/affiliate_conversions") {
      if (options.duplicate && method === "POST") {
        return Promise.resolve(
          Response.json({ code: "23505" }, { status: 409 }),
        );
      }
      const matching = ledger.filter((row) =>
        [
          "referred_user_id",
          "affiliate_code",
          "is_trial_period",
          "is_sandbox",
          "product_id",
          "event_type",
          "status",
        ].every((key) => {
          const filter = url.searchParams.get(key);
          if (!filter) return true;
          if (filter.startsWith("eq.")) {
            return filter.slice(3) === String(row[key]);
          }
          if (filter.startsWith("in.(")) {
            return filter.slice(4, -1).split(",").includes(String(row[key]));
          }
          throw new Error(`Unsupported fixture filter: ${filter}`);
        })
      );
      if (method === "PATCH") {
        for (const row of matching) Object.assign(row, body);
      } else if (method === "POST") {
        ledger.push(body as Record<string, unknown>);
      }
      return Promise.resolve(Response.json(method === "GET" ? matching : []));
    }
    throw new Error(`Unexpected request: ${method} ${url}`);
  };
  try {
    const response = await handleWebhook(
      new Request("https://webhook.test", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          ...(options.authorized === false
            ? {}
            : { authorization: environment.REVENUECAT_WEBHOOK_AUTH }),
        },
        body: JSON.stringify({
          event: {
            id: "test-only-event",
            app_user_id: userId,
            environment: "PRODUCTION",
            store: "STRIPE",
            type: "INITIAL_PURCHASE",
            product_id: "test-only-product",
            purchased_at_ms: purchasedAt,
            price: 10,
            currency: "USD",
            ...event,
          },
        }),
      }),
    );
    return {
      status: response.status,
      body: await response.json(),
      calls,
      ledger,
    };
  } finally {
    await new Promise((resolve) => originalTimeout(resolve, 0));
    for (const id of timers) {
      clearTimeout(id);
      clearInterval(id);
    }
    globalThis.setTimeout = originalTimeout;
    globalThis.setInterval = originalInterval;
    globalThis.fetch = originalFetch;
    for (const [key, value] of previous) {
      if (value === undefined) Deno.env.delete(key);
      else Deno.env.set(key, value);
    }
  }
}

const stripeSubscriptionEvents = [
  { type: "INITIAL_PURCHASE" },
  { type: "RENEWAL" },
  { type: "INITIAL_PURCHASE", period_type: "TRIAL" },
  { type: "TRIAL_STARTED" },
  { type: "TRIAL_CONVERTED" },
  { type: "RENEWAL", is_trial_conversion: true },
  { type: "TRIAL_CANCELLED" },
  { type: "EXPIRATION" },
];
for (const event of stripeSubscriptionEvents) {
  Deno.test(`Stripe ${JSON.stringify(event)} syncs access without affiliate reads or writes`, async () => {
    // Retries must be acknowledged without ever adding a second commission.
    for (let delivery = 0; delivery < 2; delivery++) {
      const result = await deliver(event);
      equal(result.status, 200);
      equal(result.body.message, "Affiliate event handled by Stripe");
      equal(result.calls.length, 1);
      equal(result.calls[0].url.pathname, "/functions/v1/revenuecat-sync");
      equal(result.calls[0].body, { userIds: [userId], concurrency: 4 });
    }
  });
}

Deno.test("Stripe still retries failed entitlement synchronization", async () => {
  const result = await deliver({}, { syncFails: true });
  equal(result.status, 500);
  equal(result.calls.length, 1);
});

Deno.test("unauthenticated Stripe events cannot reach subscription or affiliate storage", async () => {
  const result = await deliver({}, { authorized: false });
  equal(result.status, 401);
  equal(result.calls.length, 0);
});

for (
  const event of [
    { store: "STRIPE", type: "NON_RENEWING_PURCHASE" },
    { store: "APP_STORE", type: "INITIAL_PURCHASE" },
    { store: "PLAY_STORE", type: "RENEWAL" },
    { store: "RC_BILLING", type: "INITIAL_PURCHASE" },
  ]
) {
  Deno.test(`${event.store} ${event.type} keeps its RevenueCat commission`, async () => {
    const result = await deliver(event);
    equal(result.status, 200);
    equal(result.body.message, "Conversion recorded");
    const inserts = result.calls.filter((call) =>
      call.method === "POST" &&
      call.url.pathname === "/rest/v1/affiliate_conversions"
    );
    equal(inserts.length, 1);
    const row = inserts[0].body as Record<string, unknown>;
    equal(row.event_type, event.type);
    equal(row.affiliate_code, "partner");
    equal(row.commission_usd, 1.5);
  });
}

Deno.test("lifetime retries retain RevenueCat event-id deduplication", async () => {
  const result = await deliver({ type: "NON_RENEWING_PURCHASE" }, {
    duplicate: true,
  });
  equal(result.status, 200);
  equal(result.body.message, "Event already processed");
});

for (const store of ["STRIPE", "APP_STORE", "PLAY_STORE"]) {
  Deno.test(`${store} refund preserves store ownership`, async () => {
    const result = await deliver({
      store,
      type: "CANCELLATION",
      cancel_reason: "REFUND",
    });
    equal(result.status, 200);
    const updates = result.calls.filter((call) => call.method === "PATCH");
    equal(updates.length, 1);
    equal(updates[0].body, { status: "refunded" });
    equal(
      updates[0].url.searchParams.get("product_id"),
      "eq.test-only-product",
    );
    equal(
      updates[0].url.searchParams.get("event_type"),
      store === "STRIPE" ? "eq.NON_RENEWING_PURCHASE" : null,
    );
  });
}

Deno.test("Stripe refund without a product cannot reverse unrelated commissions", async () => {
  const result = await deliver({
    type: "CANCELLATION",
    cancel_reason: "REFUND",
    product_id: null,
  });
  equal(result.status, 200);
  equal(result.calls.length, 1);
});

function commission(isSandbox: boolean, status = "pending") {
  return {
    id: isSandbox ? "sandbox-row" : "production-row",
    referred_user_id: userId,
    affiliate_code: "partner",
    product_id: "test-only-product",
    event_type: "INITIAL_PURCHASE",
    is_trial_period: status === "trial",
    status,
    is_sandbox: isSandbox,
  };
}

for (const sandbox of [false, true]) {
  Deno.test(`${sandbox ? "sandbox" : "production"} refund cannot reverse the other environment`, async () => {
    const result = await deliver({
      store: "APP_STORE",
      type: "CANCELLATION",
      cancel_reason: "REFUND",
      environment: sandbox ? "SANDBOX" : "PRODUCTION",
    }, { ledger: [commission(false), commission(true)] });
    equal(result.status, 200);
    equal(
      result.ledger.find((row) => row.is_sandbox === sandbox)?.status,
      "refunded",
    );
    equal(
      result.ledger.find((row) => row.is_sandbox !== sandbox)?.status,
      "pending",
    );
  });

  Deno.test(`${sandbox ? "sandbox" : "production"} trial cancellation cannot cancel the other environment`, async () => {
    const result = await deliver({
      store: "PLAY_STORE",
      type: "TRIAL_CANCELLED",
      environment: sandbox ? "SANDBOX" : "PRODUCTION",
    }, { ledger: [commission(false, "trial"), commission(true, "trial")] });
    equal(result.status, 200);
    equal(
      result.ledger.find((row) => row.is_sandbox === sandbox)?.status,
      "refunded",
    );
    equal(
      result.ledger.find((row) => row.is_sandbox !== sandbox)?.status,
      "trial",
    );
  });

  Deno.test(`${sandbox ? "sandbox" : "production"} renewal cannot qualify from the other environment's purchase`, async () => {
    const result = await deliver({
      store: "APP_STORE",
      type: "RENEWAL",
      environment: sandbox ? "SANDBOX" : "PRODUCTION",
    }, { installAt: "2026-09-01T12:00:00Z", ledger: [commission(!sandbox)] });
    equal(result.status, 200);
    equal(result.body.message, "Affiliate attribution window expired");
    equal(result.ledger.length, 1);
  });
}

for (const sandbox of [false, true]) {
  Deno.test(`${sandbox ? "sandbox" : "production"} trial conversion cannot promote the other environment`, async () => {
    const result = await deliver({
      store: "PLAY_STORE",
      type: "RENEWAL",
      is_trial_conversion: true,
      environment: sandbox ? "SANDBOX" : "PRODUCTION",
    }, { ledger: [commission(false, "trial"), commission(true, "trial")] });
    equal(result.status, 200);
    const trials = result.ledger.filter((row) => row.is_trial_period);
    equal(trials.find((row) => row.is_sandbox === sandbox)?.status, "cleared");
    equal(trials.find((row) => row.is_sandbox !== sandbox)?.status, "trial");
  });
}

Deno.test("a prior production purchase still qualifies its own renewal after the window", async () => {
  const result = await deliver({ store: "APP_STORE", type: "RENEWAL" }, {
    installAt: "2026-09-01T12:00:00Z",
    ledger: [commission(false)],
  });
  equal(result.status, 200);
  equal(result.body.message, "Conversion recorded");
  equal(result.ledger.length, 2);
});

const nativeMapping = {
  affiliate_id: "partner-id",
  code: "native-partner",
  store: "APP_STORE",
  is_active: true,
  product_ids: ["test-only-product"],
  expires_at: null,
  created_at: "2026-10-20T12:00:00Z",
};
Deno.test("a provider-confirmed mapped native code credits a new user without install attribution", async () => {
  const result = await deliver({
    store: "APP_STORE",
    offer_code: "NATIVE-PARTNER",
  }, { referral: null, mapping: nativeMapping });
  equal(result.status, 200);
  equal(result.ledger.length, 1);
  equal(result.ledger[0].affiliate_code, "partner");
  const referral = result.calls.find((c) =>
    c.url.pathname === "/rest/v1/affiliate_referrals" && c.method === "POST"
  );
  equal((referral?.body as Record<string, unknown>)?.appsflyer_data, {
    source: "offer_code",
    via: "redemption",
    af_status: "Non-organic",
    offer_code: "NATIVE-PARTNER",
    verified_store: "APP_STORE",
  });
});
for (
  const [name, mapping] of Object.entries({
    inactive: { ...nativeMapping, is_active: false },
    wrongStore: { ...nativeMapping, store: "PLAY_STORE" },
    wrongProduct: { ...nativeMapping, product_ids: ["other"] },
    expired: { ...nativeMapping, expires_at: "2026-10-21T00:00:00Z" },
  })
) {
  Deno.test(`native code cannot credit an ${name} mapping`, async () => {
    const result = await deliver({
      store: "APP_STORE",
      offer_code: "native-partner",
    }, { referral: null, mapping });
    equal(result.ledger.length, 0);
  });
}
Deno.test("a native renewal cannot establish a fresh code-only referral", async () => {
  const result = await deliver({
    store: "APP_STORE",
    type: "RENEWAL",
    offer_code: "native-partner",
  }, { referral: null, mapping: nativeMapping });
  equal(result.ledger.length, 0);
});
Deno.test("client-stamped redemption code cannot establish native financial attribution", async () => {
  const result = await deliver({
    store: "APP_STORE",
    subscriber_attributes: { redemption_code: { value: "native-partner" } },
  }, { referral: null, mapping: nativeMapping });
  equal(result.ledger.length, 0);
});
Deno.test("native code mapping database failures request provider retry", async () => {
  const result = await deliver({
    store: "APP_STORE",
    offer_code: "native-partner",
  }, { referral: null, mappingFails: true });
  equal(result.status, 500);
  equal(result.ledger.length, 0);
});
Deno.test("sandbox referrals cannot qualify production purchases", async () => {
  const result = await deliver({ store: "APP_STORE" }, {
    referral: {
      affiliate_code: "partner",
      is_sandbox: true,
      appsflyer_data: { af_status: "Non-organic" },
      install_at: "2026-10-21T12:00:00Z",
    },
  });
  equal(result.ledger.length, 0);
});

for (const dbFailure of ["referral", "affiliate", "refund"] as const) {
  Deno.test(`a ${dbFailure} database failure retries instead of silently losing attribution`, async () => {
    const result = await deliver(
      dbFailure === "refund"
        ? { store: "APP_STORE", type: "CANCELLATION", cancel_reason: "REFUND" }
        : { store: "APP_STORE" },
      { dbFailure },
    );
    equal(result.status, 500);
  });
}
Deno.test("a competing referral is re-read on provider retry before awarding commission", async () => {
  const result = await deliver({
    store: "APP_STORE",
    offer_code: "native-partner",
  }, { referral: null, mapping: nativeMapping, referralConflict: true });
  equal(result.status, 500);
  equal(result.ledger.length, 0);
});
