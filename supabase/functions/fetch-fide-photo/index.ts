import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const STORAGE_BUCKET = "player-photos";
const STORAGE_FOLDER = "fide";
const CACHE_TABLE = "fide_photo_fetch_cache";

// FIDE placeholders are usually tiny images. Ignore anything under 5KB.
const MIN_VALID_PHOTO_SIZE = 5_000;
const FIDE_FETCH_TIMEOUT_MS = 8_000;
const FIDE_FETCH_RETRIES = 1;
const PHOTO_REVALIDATE_TTL_MS = 30 * 24 * 60 * 60 * 1000; // 30 days
const NO_PHOTO_TTL_MS = 24 * 60 * 60 * 1000; // 24 hours
const UPSTREAM_FAILURE_TTL_MS = 20 * 60 * 1000; // 20 minutes

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type CacheStatus = "photo" | "no_photo" | "fetch_failed";

type CacheRow = {
  fide_id: string;
  status: CacheStatus;
  reason: string | null;
  storage_path: string | null;
  retry_after: string;
};

type PhotoResult =
  | { success: true; bytes: Uint8Array; format: string }
  | { success: false; reason: string; transient: boolean };

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function isValidFideId(value: string): boolean {
  return /^[0-9]{4,12}$/.test(value);
}

function hasRefreshPermission(req: Request): boolean {
  const expected = Deno.env.get("FIDE_PHOTO_REFRESH_TOKEN") ?? "";
  if (!expected) return false;

  const headerToken = req.headers.get("x-fide-photo-refresh-token") ?? "";
  const authorization = req.headers.get("authorization") ?? "";
  const [scheme, bearer] = authorization.split(" ");

  return headerToken === expected ||
    (scheme?.toLowerCase() === "bearer" && bearer === expected);
}

function toIsoAfter(msFromNow: number): string {
  return new Date(Date.now() + msFromNow).toISOString();
}

function parseSize(value: unknown): number {
  const size = typeof value === "number" ? value : Number(value);
  return Number.isFinite(size) ? size : 0;
}

async function fetchWithTimeout(
  input: string,
  init: RequestInit,
  timeoutMs: number,
): Promise<Response> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(input, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timeout);
  }
}

function extractEmbeddedPhoto(html: string): { format: string; base64: string } | null {
  const patterns = [
    /class=["']profile-top__photo["'][^>]*src=["']data:image\/([^;]+);base64,([^"']+)["']/i,
    /src=["']data:image\/([^;]+);base64,([^"']+)["'][^>]*class=["']profile-top__photo["']/i,
    /src=["']data:image\/([^;]+);base64,([^"']+)["']/i,
  ];

  for (const pattern of patterns) {
    const match = html.match(pattern);
    if (match && match[1] && match[2]) {
      return { format: match[1], base64: match[2] };
    }
  }

  return null;
}

async function fetchFideProfilePhoto(fideId: string): Promise<PhotoResult> {
  const url = `https://ratings.fide.com/profile/${fideId}`;
  let lastReason = "upstream_error";
  let lastTransient = true;

  for (let attempt = 0; attempt <= FIDE_FETCH_RETRIES; attempt++) {
    try {
      const response = await fetchWithTimeout(
        url,
        {
          headers: {
            "User-Agent":
              "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
          },
        },
        FIDE_FETCH_TIMEOUT_MS,
      );

      if (!response.ok) {
        if (response.status === 404) {
          return { success: false, reason: "profile_not_found", transient: false };
        }
        lastReason = `upstream_http_${response.status}`;
        lastTransient = response.status >= 500 || response.status === 429;
        if (lastTransient && attempt < FIDE_FETCH_RETRIES) {
          await new Promise((resolve) => setTimeout(resolve, 200 * (attempt + 1)));
          continue;
        }
        return { success: false, reason: lastReason, transient: lastTransient };
      }

      const html = await response.text();
      const photo = extractEmbeddedPhoto(html);
      if (!photo) {
        return { success: false, reason: "no_photo_in_profile", transient: false };
      }

      let bytes: Uint8Array;
      try {
        const binaryString = atob(photo.base64);
        bytes = new Uint8Array(binaryString.length);
        for (let i = 0; i < binaryString.length; i++) {
          bytes[i] = binaryString.charCodeAt(i);
        }
      } catch (_e) {
        return { success: false, reason: "invalid_base64_payload", transient: true };
      }

      if (bytes.length < MIN_VALID_PHOTO_SIZE) {
        return { success: false, reason: "placeholder_image", transient: false };
      }

      return { success: true, bytes, format: photo.format };
    } catch (_error) {
      lastReason = "upstream_timeout";
      lastTransient = true;
      if (attempt < FIDE_FETCH_RETRIES) {
        await new Promise((resolve) => setTimeout(resolve, 200 * (attempt + 1)));
        continue;
      }
    }
  }

  return { success: false, reason: lastReason, transient: lastTransient };
}

async function readCacheRow(supabase: ReturnType<typeof createClient>, fideId: string) {
  const { data, error } = await supabase
    .from(CACHE_TABLE)
    .select("fide_id,status,reason,storage_path,retry_after")
    .eq("fide_id", fideId)
    .maybeSingle();
  if (error) return null;
  return data as CacheRow | null;
}

async function upsertCacheRow(
  supabase: ReturnType<typeof createClient>,
  fideId: string,
  status: CacheStatus,
  reason: string | null,
  storagePath: string | null,
  retryAfterIso: string,
) {
  await supabase.from(CACHE_TABLE).upsert({
    fide_id: fideId,
    status,
    reason,
    storage_path: storagePath,
    checked_at: new Date().toISOString(),
    retry_after: retryAfterIso,
  }, { onConflict: "fide_id" });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const requestUrl = new URL(req.url);
    let fideId = requestUrl.searchParams.get("fide_id");
    let requestedForceRefresh =
      requestUrl.searchParams.get("force_refresh") === "true";

    if (!fideId && req.method === "POST") {
      const body = await req.json();
      fideId = typeof body?.fide_id === "string" ? body.fide_id : null;
      requestedForceRefresh = body?.force_refresh === true;
    }

    if (!fideId) {
      return jsonResponse({ error: "Missing fide_id parameter" }, 400);
    }
    if (!isValidFideId(fideId)) {
      return jsonResponse({ error: "Invalid fide_id format" }, 400);
    }
    if (requestedForceRefresh && !hasRefreshPermission(req)) {
      return jsonResponse({ error: "force_refresh is not allowed" }, 403);
    }
    const forceRefresh = requestedForceRefresh;

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceKey) {
      return jsonResponse({ error: "Missing Supabase environment variables" }, 500);
    }
    const supabase = createClient(supabaseUrl, serviceKey);
    const storagePath = `${STORAGE_FOLDER}/${fideId}.jpg`;
    const { data: publicUrlData } = supabase.storage
      .from(STORAGE_BUCKET)
      .getPublicUrl(storagePath);

    if (!forceRefresh) {
      const cacheRow = await readCacheRow(supabase, fideId);
      if (cacheRow && new Date(cacheRow.retry_after).getTime() > Date.now()) {
        if (cacheRow.status === "photo") {
          return jsonResponse({
            url: publicUrlData.publicUrl,
            cached: true,
            fide_id: fideId,
            source: "cache_table",
          });
        }
        return jsonResponse({
          url: null,
          cached: true,
          fide_id: fideId,
          reason: cacheRow.reason ?? cacheRow.status,
        });
      }

      const { data: listedFiles } = await supabase.storage
        .from(STORAGE_BUCKET)
        .list(STORAGE_FOLDER, { limit: 1, search: `${fideId}.jpg` });
      const existingFile = listedFiles?.find((f) => f.name === `${fideId}.jpg`);
      if (existingFile) {
        const fileSize = parseSize(existingFile.metadata?.size ??
          existingFile.metadata?.contentLength);
        if (fileSize > 0 && fileSize < MIN_VALID_PHOTO_SIZE) {
          await supabase.storage.from(STORAGE_BUCKET).remove([storagePath]);
        } else {
          await upsertCacheRow(
            supabase,
            fideId,
            "photo",
            "storage_hit",
            storagePath,
            toIsoAfter(PHOTO_REVALIDATE_TTL_MS),
          );
          return jsonResponse({
            url: publicUrlData.publicUrl,
            cached: true,
            fide_id: fideId,
            source: "storage",
          });
        }
      }
    }

    const result = await fetchFideProfilePhoto(fideId);
    if (!result.success) {
      const status: CacheStatus = result.transient ? "fetch_failed" : "no_photo";
      const retryAfterIso = toIsoAfter(
        result.transient ? UPSTREAM_FAILURE_TTL_MS : NO_PHOTO_TTL_MS,
      );
      await upsertCacheRow(supabase, fideId, status, result.reason, null, retryAfterIso);
      return jsonResponse({
        url: null,
        fide_id: fideId,
        reason: result.reason,
        transient: result.transient,
        retry_after: retryAfterIso,
      });
    }

    const contentType = `image/${result.format}`;
    const { error: uploadError } = await supabase.storage
      .from(STORAGE_BUCKET)
      .upload(storagePath, result.bytes, {
        contentType,
        upsert: true,
      });
    if (uploadError) {
      const retryAfterIso = toIsoAfter(UPSTREAM_FAILURE_TTL_MS);
      await upsertCacheRow(
        supabase,
        fideId,
        "fetch_failed",
        `storage_upload_failed:${uploadError.message}`,
        null,
        retryAfterIso,
      );
      return jsonResponse({
        url: null,
        fide_id: fideId,
        reason: "storage_upload_failed",
        retry_after: retryAfterIso,
      });
    }

    await upsertCacheRow(
      supabase,
      fideId,
      "photo",
      "fetched_from_fide",
      storagePath,
      toIsoAfter(PHOTO_REVALIDATE_TTL_MS),
    );
    return jsonResponse({
      url: publicUrlData.publicUrl,
      cached: false,
      fide_id: fideId,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return jsonResponse({ error: message }, 500);
  }
});
