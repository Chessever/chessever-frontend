/**
 * Who hears that a starred collection gained games.
 *
 * A star is a `user_favorite_events` row keyed `collection:<slug>`. Starring a
 * collection is asking to hear about its new games, so every star notifies
 * unless its owner turned that off (`metadata.notificationsEnabled: false`,
 * written by the app's "Not now" or its "Turn off notifications" row). A star
 * that never answered, made before the question existed, on the desktop app,
 * or on a build without the question, notifies.
 *
 * Smart event stars are the opposite (opt-in only, see smart_event_match.ts):
 * a broad smart event can match every round of every event.
 */
export function collectionStarNotifies(flag: unknown): boolean {
  return flag !== false && flag !== "false";
}

/** The distinct users among [rows] whose star notifies. */
export function collectionStarRecipients(
  rows: { user_id: string | null; notifications: unknown }[],
): string[] {
  const users = new Set<string>();
  for (const row of rows) {
    if (row.user_id && collectionStarNotifies(row.notifications)) {
      users.add(row.user_id);
    }
  }
  return [...users];
}
