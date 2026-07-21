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
 * Product rules (Scenarios A/B/C):
 * - Round window: already got a game_started for this round → suppress.
 * - Multi-favorite in the same round (count >= 2) → covered by round_started.
 * - Count === 1 → single-favorite Scenario A → deliver.
 * - Count === 0 → favorite map failed to resolve names but the user is still
 *   in playerUserIds (fide/name match for THIS game) → deliver, do NOT treat
 *   as multi-fav. (Old bug: `count !== 1` deleted these users.)
 */
export function shouldReceiveGameStartedForPlayerFavorite(
  favoriteCountInRound: number,
  alreadyCoveredByGameStartWindow: boolean,
): boolean {
  if (alreadyCoveredByGameStartWindow) return false;
  if (favoriteCountInRound >= 2) return false;
  return true;
}

/**
 * Apply the game_started multi-fav + window filters to a recipient set.
 * Returns kept user ids and skip reason tags for honesty / logging.
 */
export function filterGameStartedPlayerRecipients(
  candidateUserIds: Iterable<string>,
  playerFavoriteMap: Map<string, string[]>,
  alreadyCoveredByWindow: Set<string>,
): {
  keep: Set<string>;
  skippedMultiFavorite: string[];
  skippedWindow: string[];
} {
  const keep = new Set<string>();
  const skippedMultiFavorite: string[] = [];
  const skippedWindow: string[] = [];

  for (const uid of candidateUserIds) {
    const favCount = (playerFavoriteMap.get(uid) ?? []).length;
    const covered = alreadyCoveredByWindow.has(uid);
    if (covered) {
      skippedWindow.push(uid);
      continue;
    }
    if (favCount >= 2) {
      skippedMultiFavorite.push(uid);
      continue;
    }
    keep.add(uid);
  }

  return { keep, skippedMultiFavorite, skippedWindow };
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
