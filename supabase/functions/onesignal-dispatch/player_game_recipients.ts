/**
 * Pure helpers for favorite-player game_started recipient selection.
 *
 * Extracted from onesignal-dispatch so deliverability + preference rules can
 * be unit-tested without OneSignal or Supabase.
 */

/** Time-control keys matching user_notification_preferences.fp_* / se_*. */
export type NotifTimeControl = "classical" | "rapid" | "blitz";

export type PreferenceRow = {
  push_enabled?: boolean | null;
  favorite_player_alerts?: boolean | null;
  favorite_event_alerts?: boolean | null;
  fp_classical?: boolean | null;
  fp_rapid?: boolean | null;
  fp_blitz?: boolean | null;
  se_classical?: boolean | null;
  se_rapid?: boolean | null;
  se_blitz?: boolean | null;
};

/**
 * Whether a user who already passed applyPreferences should receive a
 * per-game `game_started` push for a favorite-player board.
 *
 * A confirmed window for THIS board means its `round_started` board push
 * already reached the user. Without one the user is kept, whatever other
 * boards of the round they were already told about.
 */
export function shouldReceiveGameStartedForPlayerFavorite(
  alreadyCoveredByGameStartWindow: boolean,
): boolean {
  return !alreadyCoveredByGameStartWindow;
}

/**
 * A start window covers ONE BOARD for one user, never the whole round.
 *
 * Start alerts are per board: favorite two players on two boards and you get
 * two "… is live." pushes, mirroring the two results at the end. The window
 * exists only so the round_started board push and the later game_started row
 * for the SAME board do not both reach you. It used to be keyed by round, so
 * the first board alert a user got silenced every other favorite's board in
 * that round. European Club Cup 2026 R3: 19 of 22 reachable Suleymanli
 * favoriters got Mamedyarov's (or another favorite's) board and nothing for
 * his; 252 of 609 board alerts went missing that weekend.
 */
export const GAME_START_WINDOW_PREFIX = "game_start:";

export function gameStartWindowFamily(gameId: string): string {
  return `${GAME_START_WINDOW_PREFIX}${gameId}`;
}

/** Board id of a per-board window; null for the old round-wide family. */
export function gameIdFromWindowFamily(family: string): string | null {
  if (!family.startsWith(GAME_START_WINDOW_PREFIX)) return null;
  const gameId = family.slice(GAME_START_WINDOW_PREFIX.length);
  return gameId.length > 0 ? gameId : null;
}

/** user → boards of this round whose start push already reached them. */
export function coveredBoardsByUser(
  rows: Iterable<{ user_id: string; family: string }>,
): Map<string, Set<string>> {
  const covered = new Map<string, Set<string>>();
  for (const row of rows) {
    const gameId = gameIdFromWindowFamily(row.family);
    if (!gameId) continue;
    const boards = covered.get(row.user_id);
    if (boards) boards.add(gameId);
    else covered.set(row.user_id, new Set([gameId]));
  }
  return covered;
}

/** Users whose start push for this one board has already gone out. */
export function usersCoveredForBoard(
  covered: Map<string, Set<string>>,
  gameId: string,
): Set<string> {
  const users = new Set<string>();
  for (const [userId, boards] of covered) {
    if (boards.has(gameId)) users.add(userId);
  }
  return users;
}

/** Apply the confirmed-delivery window filter to game_started recipients. */
export function filterGameStartedPlayerRecipients(
  candidateUserIds: Iterable<string>,
  alreadyCoveredByWindow: Set<string>,
): {
  keep: Set<string>;
  skippedWindow: string[];
} {
  const keep = new Set<string>();
  const skippedWindow: string[] = [];

  for (const uid of candidateUserIds) {
    if (alreadyCoveredByWindow.has(uid)) {
      skippedWindow.push(uid);
      continue;
    }
    keep.add(uid);
  }

  return { keep, skippedWindow };
}

/**
 * Preference gate for game_started / game_finished (player-favorite only).
 * Fail-open when no prefs row: defaults match product (player alerts on).
 *
 * Mirrors applyPreferences branches for game_started while remaining pure.
 */
export function playerAllowedForGameNotification(
  prefs: PreferenceRow | null | undefined,
  isPlayerFav: boolean,
  gameTimeControl: NotifTimeControl | null = null,
): boolean {
  if (!isPlayerFav) return false;
  if (prefs && prefs.push_enabled === false) return false;
  if (prefs && prefs.favorite_player_alerts === false) return false;

  if (gameTimeControl && prefs) {
    const key = `fp_${gameTimeControl}` as keyof PreferenceRow;
    if (prefs[key] === false) return false;
  }

  return true;
}
