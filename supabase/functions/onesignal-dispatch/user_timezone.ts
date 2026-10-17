/**
 * A reader's timezone, as OneSignal knows it.
 *
 * The app logs every device in with `OneSignal.login(<user id>)`, and the
 * SDK reports the phone's IANA timezone on the user (`properties.timezone_id`,
 * from `GET /apps/<app>/users/by/external_id/<user id>`). Smart event pushes
 * use it to arrive in the reader's evening (`public.user_timezones`).
 */

/** The IANA zone in a OneSignal user record, or null when it has none. */
export function timezoneFromOneSignalUser(user: unknown): string | null {
  if (!user || typeof user !== "object") return null;
  const properties = (user as Record<string, unknown>).properties;
  if (!properties || typeof properties !== "object") return null;
  const zone = (properties as Record<string, unknown>).timezone_id;
  if (typeof zone !== "string") return null;
  const name = zone.trim();
  return isTimezone(name) ? name : null;
}

/** Whether [name] is a zone the runtime can convert to ("Asia/Baku"). */
export function isTimezone(name: string): boolean {
  if (!/^[A-Za-z][A-Za-z0-9_+\-]*(\/[A-Za-z0-9_+\-]+)*$/.test(name)) {
    return false;
  }
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: name });
    return true;
  } catch {
    return false;
  }
}
