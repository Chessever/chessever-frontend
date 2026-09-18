/**
 * PostgREST `.in()` filters ride on the request URL. That is a transport
 * page size, not a product ceiling: we pack as many values as the URL can
 * hold and walk every page. The caller never drops a leftover.
 *
 * 46th Olympiad 2026 Round 1 Open is 404 boards (~800 names). One unchunked
 * `.in("player_name", …)` overflowed the URL. The gateway answered 400 and
 * the grouped `round_started` burned. Favorite matching now goes through
 * `match_notification_favorite_players` (POST body). This helper remains
 * for the leftover REST `.in()` calls (user ids, muted rows).
 */

/** Cloudflare / PostgREST start rejecting oversized GET URLs around here. */
export const POSTGREST_IN_URL_BUDGET_BYTES = 8 * 1024;

export function chunk<T>(list: T[], size: number): T[][] {
  if (list.length === 0) return [];
  const chunks: T[][] = [];
  const step = size > 0 ? size : list.length;
  for (let i = 0; i < list.length; i += step) {
    chunks.push(list.slice(i, i + step));
  }
  return chunks;
}

/** Conservative size of `col=in.("a","b",…)` after URL-encoding. */
export function estimatedInFilterUrlBytes(values: readonly string[]): number {
  let bytes = 8; // "col=in.()"
  for (let i = 0; i < values.length; i++) {
    if (i > 0) bytes += 3; // encoded comma
    bytes += encodeURIComponent(`"${values[i]}"`).length;
  }
  return bytes;
}

/**
 * Pack values into as few URL-safe `.in()` pages as possible.
 * A single value that is itself over budget still gets its own page —
 * we never drop it.
 */
export function packForUrlBudget(
  values: readonly string[],
  budgetBytes: number = POSTGREST_IN_URL_BUDGET_BYTES,
): string[][] {
  if (values.length === 0) return [];
  const pages: string[][] = [];
  let current: string[] = [];
  for (const value of values) {
    const next = current.concat(value);
    if (
      current.length > 0 &&
      estimatedInFilterUrlBytes(next) > budgetBytes
    ) {
      pages.push(current);
      current = [value];
    } else {
      current = next;
    }
  }
  if (current.length > 0) pages.push(current);
  return pages;
}
