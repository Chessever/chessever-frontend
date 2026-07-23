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
 * A confirmed game-start window means either the combined `round_started`
 * notification or an earlier per-game fallback already covered this user.
 * Without that confirmation, keep the first per-game notification even when
 * several favorites play in the round; otherwise an early skipped
 * `round_started` row can suppress every start alert.
 */
export function shouldReceiveGameStartedForPlayerFavorite(
  alreadyCoveredByGameStartWindow: boolean,
): boolean {
  return !alreadyCoveredByGameStartWindow;
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
