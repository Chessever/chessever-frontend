/**
 * Transient-failure classification and in-process retry for the dispatcher.
 *
 * Every PostgREST call rides a pooled HTTP/2 connection to the Supabase
 * gateway. When the gateway recycles that connection while a request is in
 * flight, Deno reports it as a stream or connection error ("error sending
 * request for url (…): http2 error: stream error received …"). The very next
 * request opens a fresh connection and succeeds, so the right response is an
 * immediate in-process retry — not a 15 s outbox backoff, and never a terminal
 * `failed` row.
 *
 * On 2026-09-01 (15:00–16:00 UTC) one such disruption burned 137 game_started
 * and 15 round_started rows: the only retry lived in the outbox (four claims at
 * 15 s × attempt backoff, ≈2 minutes end to end) and the favorite-player name
 * lookup threw straight through it.
 *
 * Two layers now stand between a dropped stream and a lost push:
 *  1. `withTransientRetry` / `runQuery` retry the single request in-process
 *     (sub-second, fresh connection) — this absorbs the common one-off reset.
 *  2. `processItem` gives errors that classify as transient a much longer
 *     outbox budget than deterministic ones, so a multi-minute provider
 *     incident parks the row instead of burning it.
 */

export type PostgrestError = {
  message: string;
  code?: string | null;
  details?: string | null;
  hint?: string | null;
};

export type PostgrestResult<T> = {
  data: T | null;
  error: PostgrestError | null;
  /** HTTP status of the PostgREST response; 0 when no response ever arrived. */
  status?: number;
};

/** In-process retries per request: the first call plus two quick re-tries. */
export const IN_PROCESS_RETRY_ATTEMPTS = 3;
/** Base delay before the first in-process retry; doubles each time, jittered. */
export const IN_PROCESS_RETRY_BASE_DELAY_MS = 250;

// Only shapes that mean "the network, the gateway or Postgres was busy" belong
// here. Anything that could also describe a wrong query (PGRST1xx, 4xx, a
// column name) must stay out, or a permanently broken row would retry for half
// an hour instead of failing in four attempts. Status and SQLSTATE codes are
// matched only through the explicit `[status …]` / `[code …]` tags that
// `formatPostgrestError` writes, never as bare numbers — a request URL echoed
// in a Deno error carries fide ids and uuids that look exactly like them.
const TRANSIENT_PATTERNS: RegExp[] = [
  // Deno / hyper transport failures (a pooled HTTP/2 connection went away).
  /error sending request/i,
  /http2 error/i,
  /stream (error|closed|reset)/i,
  /connection (error|closed|reset|refused|aborted|failure)/i,
  /broken pipe/i,
  /\bECONN(RESET|REFUSED|ABORTED)\b/,
  /\b(ETIMEDOUT|EPIPE|EAI_AGAIN|EHOSTUNREACH|ENETUNREACH)\b/,
  /\btimed? ?out\b/i,
  /fetch failed/i,
  /network error/i,
  /dns error/i,
  /tls (handshake|error|alert)/i,
  /unexpected (eof|end of file)/i,
  /socket hang ?up/i,
  // Gateway / upstream answers that say "try again", never "you are wrong".
  /\[status (0|408|425|429|500|502|503|504)\]/,
  /OneSignal API error: (408|429|500|502|503|504)\b/,
  /\b(bad gateway|service unavailable|gateway time-?out|too many requests)\b/i,
  /\b(no healthy upstream|upstream (connect|request) (error|timeout))\b/i,
  /<title>\s*5\d\d/i,
  // PostgREST could not reach or query Postgres (PGRST000–003), or Postgres
  // itself was busy: statement_timeout, connection limits, lock contention.
  /\[code (PGRST00[0-3]|57014|53300|53400|08000|08001|08003|08006|40001|40P01)\]/,
  /canceling statement due to (statement|lock) timeout/i,
  /too many (connections|clients)/i,
  /remaining connection slots are reserved/i,
  /server closed the connection unexpectedly/i,
  /the database system is (starting up|shutting down)/i,
];

/** Renders any thrown value as one line, tagging PostgREST status/code. */
function errorText(error: unknown): string {
  if (error instanceof Error) return `${error.name}: ${error.message}`;
  if (typeof error === "string") return error;
  if (error && typeof error === "object") {
    const record = error as Record<string, unknown>;
    if (typeof record.message === "string") {
      return formatPostgrestError(
        {
          message: record.message,
          code: typeof record.code === "string" ? record.code : null,
        },
        typeof record.status === "number" ? record.status : undefined,
      );
    }
    try {
      return JSON.stringify(error);
    } catch {
      // Circular or otherwise unserialisable: fall through to String().
    }
  }
  return String(error);
}

/**
 * `[status 503] [code PGRST001] message` — the tags are what
 * `isTransientError` keys on, so a gateway 5xx or a PostgREST connection
 * error is recognised even when the message text is an HTML page.
 */
export function formatPostgrestError(
  error: PostgrestError,
  status?: number,
): string {
  const tags: string[] = [];
  if (typeof status === "number") tags.push(`[status ${status}]`);
  if (error.code) tags.push(`[code ${error.code}]`);
  return tags.length > 0 ? `${tags.join(" ")} ${error.message}` : error.message;
}

/**
 * True when the failure is one a fresh request could reasonably survive.
 * Walks the `cause` chain so a wrapped transport error still classifies.
 */
export function isTransientError(error: unknown): boolean {
  const seen = new Set<unknown>();
  let current: unknown = error;
  while (current != null && !seen.has(current)) {
    seen.add(current);
    const text = errorText(current);
    if (TRANSIENT_PATTERNS.some((pattern) => pattern.test(text))) return true;
    current = current instanceof Error ? current.cause : null;
  }
  return false;
}

/**
 * One-line description safe to persist in `notification_outbox.last_error`.
 *
 * Deno echoes the full request URL, query string included — a favorite lookup
 * carries a hundred uuids in it. Keep the path so the failing table is still
 * visible, drop the query, and cap the length.
 */
export function describeError(error: unknown, maxLength = 1000): string {
  const stripped = errorText(error).replace(
    /(https?:\/\/[^\s()?]+)\?[^\s()]*/g,
    "$1?…",
  );
  if (stripped.length <= maxLength) return stripped;
  return `${stripped.slice(0, Math.max(0, maxLength - 1))}…`;
}

export type RetryOptions = {
  /** Total attempts including the first call. */
  attempts?: number;
  baseDelayMs?: number;
  /** Injectable for tests; defaults to a real timer. */
  sleep?: (ms: number) => Promise<void>;
  onRetry?: (
    label: string,
    attempt: number,
    delayMs: number,
    error: unknown,
  ) => void;
};

function defaultSleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function defaultOnRetry(
  label: string,
  attempt: number,
  delayMs: number,
  error: unknown,
) {
  console.warn(
    `[onesignal-dispatch] ${label}: transient failure on attempt ${attempt}, retrying in ${delayMs}ms: ${
      describeError(error, 300)
    }`,
  );
}

/**
 * Runs `fn`, retrying in-process while it throws something transient.
 * Deterministic errors propagate on the first throw; the final transient
 * error propagates after the budget is spent so the caller's outbox retry
 * takes over.
 */
export async function withTransientRetry<T>(
  label: string,
  fn: () => Promise<T>,
  options: RetryOptions = {},
): Promise<T> {
  const attempts = Math.max(1, options.attempts ?? IN_PROCESS_RETRY_ATTEMPTS);
  const baseDelayMs = options.baseDelayMs ?? IN_PROCESS_RETRY_BASE_DELAY_MS;
  const sleep = options.sleep ?? defaultSleep;
  const onRetry = options.onRetry ?? defaultOnRetry;

  let lastError: unknown;
  for (let attempt = 1; attempt <= attempts; attempt++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error;
      if (attempt === attempts || !isTransientError(error)) throw error;
      // Exponential base with full jitter: 250 ms, 500 ms, 1 s (× 0.5–1.5).
      const delayMs = Math.round(
        baseDelayMs * 2 ** (attempt - 1) * (0.5 + Math.random()),
      );
      onRetry(label, attempt, delayMs, error);
      await sleep(delayMs);
    }
  }
  throw lastError;
}

/**
 * Awaits one PostgREST query and throws `<label> failed: …` on error, with
 * transient failures retried in-process first. `query` is a factory because a
 * builder must be rebuilt for each attempt.
 */
export async function runQuery<T>(
  label: string,
  query: () => PromiseLike<PostgrestResult<T>>,
  options: RetryOptions = {},
): Promise<T | null> {
  return await withTransientRetry(label, async () => {
    const { data, error, status } = await query();
    if (error) {
      throw new Error(
        `${label} failed: ${formatPostgrestError(error, status)}`,
      );
    }
    return data;
  }, options);
}

/**
 * Like `runQuery`, but hands deterministic PostgREST errors back to the
 * caller as `{ error }` instead of throwing, for lookups that deliberately
 * degrade (time-control resolution). Transient errors are still retried
 * in-process; the last one is returned, not thrown.
 */
export async function runQuerySettled<T>(
  label: string,
  query: () => PromiseLike<PostgrestResult<T>>,
  options: RetryOptions = {},
): Promise<PostgrestResult<T>> {
  try {
    return await withTransientRetry(label, async () => {
      const result = await query();
      if (
        result.error &&
        isTransientError(formatPostgrestError(result.error, result.status))
      ) {
        throw new Error(
          `${label} failed: ${
            formatPostgrestError(result.error, result.status)
          }`,
        );
      }
      return result;
    }, options);
  } catch (error) {
    return { data: null, error: { message: describeError(error) }, status: 0 };
  }
}
