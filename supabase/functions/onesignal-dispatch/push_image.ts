/**
 * The picture a push may carry, from an outbox payload's `image_url`.
 *
 * Only an absolute https URL of sane length is passed on to OneSignal: the
 * device fetches it, so anything else (http, a data URI, a path, junk) is
 * dropped and the push goes out as text.
 */
const MAX_IMAGE_URL_LENGTH = 2000;

export function pushImageUrl(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (trimmed.length === 0 || trimmed.length > MAX_IMAGE_URL_LENGTH) {
    return null;
  }
  if (/\s/.test(trimmed)) return null;
  let url: URL;
  try {
    url = new URL(trimmed);
  } catch {
    return null;
  }
  if (url.protocol !== "https:" || url.username || url.password) return null;
  if (!url.hostname.includes(".")) return null;
  return url.toString();
}
