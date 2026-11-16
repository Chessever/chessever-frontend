/**
 * Pure helpers for favorite-player game_started and round_started recipient
 * selection: the round's board index, the preference split and the per-board
 * round_started plan.
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

/**
 * Key a player name for board lookup.
 *
 * The same player reaches us under two spellings: `games.player_white` /
 * `player_black` and the `name` inside the `players` JSONB. A favorite resolved
 * through fide_id carries the JSONB spelling, one resolved by name carries the
 * column spelling, so the board index must accept either.
 */
export function playerBoardKey(name: string): string {
  return name.trim().toLowerCase();
}

/** One board of a round, used to word a per-game notification. */
export type RoundBoard = { white: string; black: string };

/** The `games` columns a round_started / round_heads_up row reads. */
export type RoundBoardRow = {
  id: string;
  player_white: string | null;
  player_black: string | null;
  player_fide_ids: Array<number | string> | null;
  players: Record<string, unknown>[] | null;
  // Read by the match-play gate only (match_play.ts).
  status?: string | null;
  last_move?: string | null;
  last_move_time?: string | null;
  date_start?: string | null;
};

/**
 * The round's players and boards: every name and FIDE id (to match
 * favorites), name → boards (`playerBoardKey`, both spellings), and the
 * fully-paired boards that can be worded "White vs Black is live.".
 */
export function indexRoundBoards(rows: Iterable<RoundBoardRow>) {
  const playerNames = new Set<string>();
  const fideIds = new Set<string>();
  // name → the boards that player sits at this round. A Set of game ids (not a
  // single id) because a knockout round can pair the same player twice.
  const playerGameIds = new Map<string, Set<string>>();
  const roundBoards = new Map<string, RoundBoard>();

  for (const row of rows) {
    if (row.player_white) playerNames.add(row.player_white);
    if (row.player_black) playerNames.add(row.player_black);
    for (const id of row.player_fide_ids ?? []) {
      fideIds.add(id.toString());
    }

    // Only a fully-paired board can be worded as "White vs Black is live."
    if (!row.id || !row.player_white || !row.player_black) continue;
    roundBoards.set(row.id, {
      white: row.player_white,
      black: row.player_black,
    });

    const boardNames = [row.player_white, row.player_black];
    if (Array.isArray(row.players)) {
      for (const p of row.players) {
        const name = (p?.name as string | undefined) ?? null;
        if (name) boardNames.push(name);
      }
    }
    for (const name of boardNames) {
      const key = playerBoardKey(name);
      if (!key) continue;
      const existing = playerGameIds.get(key);
      if (existing) existing.add(row.id);
      else playerGameIds.set(key, new Set([row.id]));
    }
  }

  return {
    playerNames: Array.from(playerNames),
    fideIds: Array.from(fideIds),
    playerGameIds,
    roundBoards,
  };
}

/** A favorite's name → the boards of this round it sits at. */
export function boardsForFavorite(
  playerGameIds: Map<string, Set<string>>,
): (name: string) => Set<string> | undefined {
  return (name) => playerGameIds.get(playerBoardKey(name));
}

/**
 * round_started, after the preference split: which board each favorite reader
 * is told about. A reader gets one push per board of their favorites, minus
 * the boards whose start push already reached them (`coveredBoards`). With a
 * `liveBoardScope` (match-play round) only boards in it count, and a reader
 * left with none gets nothing; without one, a reader whose favorites resolve
 * to no board takes the event-template fallback (`unresolved`) unless a board
 * alert already reached them this round.
 */
export function planRoundStartBoards(args: {
  playerRecipients: Iterable<string>;
  favoriteNames: Map<string, string[]>;
  playerGameIds: Map<string, Set<string>>;
  roundBoards: { has(gameId: string): boolean };
  liveBoardScope: Set<string> | null;
  coveredBoards: Map<string, Set<string>>;
}): {
  boardBatches: Map<string, string[]>;
  unresolved: string[];
  reached: Set<string>;
} {
  const boardsFor = boardsForFavorite(args.playerGameIds);
  const boardBatches = new Map<string, string[]>();
  const unresolved: string[] = []; // no favorite board → event fallback
  const reached = new Set<string>();

  for (const userId of args.playerRecipients) {
    const favNames = args.favoriteNames.get(userId) ?? [];
    const gameIds = new Set<string>();
    for (const name of favNames) {
      for (const gameId of boardsFor(name) ?? []) {
        if (!args.roundBoards.has(gameId)) continue;
        // Match-play: a board without a move is not live yet.
        if (args.liveBoardScope && !args.liveBoardScope.has(gameId)) continue;
        gameIds.add(gameId);
      }
    }
    const covered = args.coveredBoards.get(userId);

    if (gameIds.size === 0) {
      // A board alert already reached them this round (their favorite
      // matched a board this index missed): the generic round
      // template would only repeat it.
      if (covered) continue;
      // Match-play: no event-template fallback for a favorite. Only
      // readers with a live board get here, so this is a guard.
      if (args.liveBoardScope) continue;
      unresolved.push(userId);
      reached.add(userId);
      continue;
    }

    for (const gameId of gameIds) {
      if (covered?.has(gameId)) continue;
      reached.add(userId);
      const batch = boardBatches.get(gameId);
      if (batch) batch.push(userId);
      else boardBatches.set(gameId, [userId]);
    }
  }

  return { boardBatches, unresolved, reached };
}

/**
 * Split round_started / round_heads_up readers into the favorite-player path
 * and the event path, by their preferences. A favorite reader who blocked
 * this time control falls back to the event path when they star the event.
 * A reader in neither set gets nothing.
 */
export function splitRoundRecipients(
  eventUserIds: Set<string>,
  playerUserIds: Set<string>,
  prefsMap: Map<string, Record<string, unknown>>,
  gameTimeControl: NotifTimeControl | null = null,
): { playerRecipients: string[]; eventRecipients: string[] } {
  const ids = Array.from(new Set([...eventUserIds, ...playerUserIds]));
  const playerRecipients = new Set<string>();
  const eventRecipients = new Set<string>();

  for (const userId of ids) {
    const prefs = prefsMap.get(userId);
    if (prefs && prefs.push_enabled === false) continue;

    const isPlayerFav = playerUserIds.has(userId);
    const isEventFav = eventUserIds.has(userId);
    const playerAllowed = !prefs || prefs.favorite_player_alerts !== false;
    const eventAllowed = !prefs || prefs.favorite_event_alerts !== false;

    // Category-specific time-control gate.
    if (gameTimeControl && prefs) {
      const tc = gameTimeControl;
      if (isPlayerFav && playerAllowed && prefs[`fp_${tc}`] === false) {
        // This player-fav user has blocked this time control — demote to event
        // recipient only if they also star the event, otherwise skip entirely.
        if (!isEventFav || !eventAllowed || prefs[`se_${tc}`] === false) {
          continue;
        }
        // Falls through to event-recipient branch below.
        eventRecipients.add(userId);
        continue;
      }
      if (
        isEventFav && !isPlayerFav && eventAllowed &&
        prefs[`se_${tc}`] === false
      ) {
        continue;
      }
    }

    if (isPlayerFav && playerAllowed) {
      playerRecipients.add(userId);
      continue;
    }

    if (isEventFav && eventAllowed && !playerRecipients.has(userId)) {
      eventRecipients.add(userId);
    }
  }

  return {
    playerRecipients: Array.from(playerRecipients),
    eventRecipients: Array.from(eventRecipients),
  };
}
