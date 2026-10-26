/**
 * Brings partner publications' articles into `partner_news`, where the app's
 * Feed and chessever.com read them under the partner's own name. pg_cron
 * starts it every ten minutes (kick_partner_news_sync); a POST with
 * `{"source": "<id>"}` syncs that one source on demand.
 *
 * For each enabled row of `partner_news_sources` it reads the RSS feed,
 * converts every item (feed.ts) and upserts the lot (upsert_partner_news):
 * new articles are added, edited ones replaced, unchanged ones left alone,
 * and an article an editor hid stays hidden. The source row records the
 * outcome, so a feed that stops answering shows up there
 * (`last_success_at`, `consecutive_failures`, `last_error`).
 *
 * Authenticates with the dispatcher's stream token, so it stays behind
 * `verify_jwt = false` like every function here.
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { type PartnerSource, parsePartnerFeed } from "./feed.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
  Deno.env.get("SERVICE_ROLE_KEY") ??
  "";
if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error("Missing Supabase environment variables.");
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

const USER_AGENT = "ChessEver/1.0 (+https://chessever.com; partner news)";
const FETCH_TIMEOUT_MS = 20_000;
/** A feed is a few hundred kilobytes; anything near this is not a feed. */
const MAX_FEED_BYTES = 5 * 1024 * 1024;
const jsonHeaders = { "Content-Type": "application/json" };

let tokenCache: { token: string; expiresAtMs: number } | null = null;

async function streamToken(): Promise<string | null> {
  const now = Date.now();
  if (tokenCache && tokenCache.expiresAtMs > now) return tokenCache.token;
  const { data, error } = await supabase.rpc("get_vault_secret", {
    secret_name: "live_dispatch_token",
  });
  if (error || typeof data !== "string" || data.length === 0) return null;
  tokenCache = { token: data, expiresAtMs: now + 60_000 };
  return data;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

interface SourceRow {
  id: string;
  site_url: string;
  feed_url: string;
  asset_hosts: string[] | null;
}

async function readFeed(url: string): Promise<string> {
  const response = await fetch(url, {
    headers: {
      "User-Agent": USER_AGENT,
      // The wildcard matters: RookReview answers 406 to an Accept header
      // that names only feed types.
      Accept:
        "application/rss+xml, application/xml;q=0.9, text/xml;q=0.8, */*;q=0.5",
    },
    redirect: "follow",
    signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
  });
  if (!response.ok) {
    await response.body?.cancel();
    throw new Error(`feed answered HTTP ${response.status}`);
  }
  const declared = Number(response.headers.get("content-length") ?? "0");
  if (declared > MAX_FEED_BYTES) {
    await response.body?.cancel();
    throw new Error(`feed is ${declared} bytes`);
  }
  const reader = response.body?.getReader();
  if (!reader) throw new Error("feed had no body");
  const chunks: Uint8Array[] = [];
  let size = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > MAX_FEED_BYTES) {
      await reader.cancel();
      throw new Error(`feed is over ${MAX_FEED_BYTES} bytes`);
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder().decode(bytes);
}

async function syncSource(row: SourceRow) {
  const source: PartnerSource = {
    id: row.id,
    siteUrl: row.site_url,
    assetHosts: row.asset_hosts ?? [],
  };
  try {
    const articles = parsePartnerFeed(await readFeed(row.feed_url), source);
    if (articles.length === 0) throw new Error("feed had no usable items");
    const { data, error } = await supabase.rpc("upsert_partner_news", {
      p_source_id: row.id,
      p_items: articles.map((article) => ({
        guid: article.guid,
        url: article.url,
        title: article.title,
        summary: article.summary,
        content: article.content,
        image_url: article.imageUrl,
        published_at: article.publishedAt,
      })),
    });
    if (error) throw new Error(`upsert failed: ${error.message}`);
    return { source: row.id, ok: true, ...(data as Record<string, number>) };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`[partner-news-sync] ${row.id}: ${message}`);
    const { error: recordError } = await supabase.rpc(
      "record_partner_news_failure",
      { p_source_id: row.id, p_error: message },
    );
    if (recordError) {
      console.error(
        `[partner-news-sync] ${row.id}: could not record failure: ${recordError.message}`,
      );
    }
    return { source: row.id, ok: false, error: message };
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }
  const token = await streamToken();
  if (!token || req.headers.get("x-stream-token") !== token) {
    return new Response("Unauthorized", { status: 401 });
  }

  let only: string | null = null;
  try {
    const body = await req.json();
    if (body && typeof body.source === "string") only = body.source;
  } catch {
    // No body: every enabled source.
  }

  let query = supabase
    .from("partner_news_sources")
    .select("id, site_url, feed_url, asset_hosts")
    .eq("enabled", true)
    .order("id");
  if (only) query = query.eq("id", only);
  const { data, error } = await query;
  if (error) {
    console.error(`[partner-news-sync] source lookup failed: ${error.message}`);
    return json({ error: "source_lookup_failed" }, 500);
  }

  const results = [];
  for (const row of (data ?? []) as SourceRow[]) {
    results.push(await syncSource(row));
  }
  const failed = results.some((result) => !result.ok);
  return json({ results }, failed ? 502 : 200);
});
