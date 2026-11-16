/**
 * Match-play knockout rounds (Speed Chess Championship style).
 *
 * Chess.com publishes every match of a knockout stage in ONE round and plays
 * one match per day for a month. Game 1 of every match is pre-created as a
 * 0-move `*` shell, then game 2, and so on. On 2026-11-16 (SCC XI Round of 16,
 * round `60IswAYI`) only Nakamura-Erdogmus was played, yet round_started told
 * Carlsen, Caruana, So... followers "X vs Y is live." for all 16 boards, and
 * the heads-up named players whose matches were weeks away.
 *
 * The gate: a round of a (player) knockout event in which one unordered player
 * pair has 2+ games. In such a round:
 *  - a board is live only once it has a move and is not finished;
 *  - round_started announces live boards only. A board without a move gets
 *    its own game_started at its first move;
 *  - a favorite counts only through a live board (or one whose start push
 *    already reached the reader), so a reader whose players are not playing
 *    now is treated as if they were not in the round;
 *  - the heads-up names only players of the match(es) starting now: every
 *    favorite when the round holds one match, the matches scheduled for this
 *    start in `tours.info.matchSchedule`, nobody when the round's shells were
 *    published days ahead (matches spread over days), and every favorite
 *    otherwise (same-day stages such as EWC or the Dutch tiebreaks).
 * Every other round keeps today's behaviour exactly.
 */

/** The `games` columns the gate reads. */
export type MatchPlayBoard = {
  id: string;
  player_white: string | null;
  player_black: string | null;
  /** Arrives as strings from PostgREST despite the int column type. */
  player_fide_ids: Array<number | string> | null;
  /** The two players as stored on the board; only `team` is read here. */
  players?: Array<Record<string, unknown> | null> | null;
  status?: string | null;
  last_move?: string | null;
  last_move_time?: string | null;
  /** PGN [Date]. On a chess.com shell, the day the board was created. */
  date_start?: string | null;
};

/** What the knockout and team checks read from `tours` and `rounds`. */
export type KnockoutFacts = {
  /** `tours.info.format`, the curated format text. */
  format: string | null;
  /** `tours.info.teamTable`, the lichess "team leaderboard" flag. */
  teamTable?: boolean | null;
  /** `tours.info.officialTeamStandings` is present. */
  hasOfficialTeamTable?: boolean;
  /** `team` of every `tours.players` entry. */
  rosterTeams?: Array<string | null>;
  tourName?: string | null;
  roundName?: string | null;
};

function normalizedFormat(format: string | null | undefined): string {
  return (format ?? "").toLowerCase().replaceAll("_", " ").replaceAll(
    "-",
    " ",
  );
}

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * The team, two-sided, of each player at a board, or null when a side has no
 * team tag. `players` holds the two players of the board, in either order.
 */
function boardTeams(board: MatchPlayBoard): [string, string] | null {
  const players = Array.isArray(board.players) ? board.players : [];
  if (players.length < 2) return null;
  const teams = players.slice(0, 2).map((player) => {
    const team = isPlainRecord(player) ? player.team : null;
    return typeof team === "string" ? team.trim() : "";
  });
  if (!teams[0] || !teams[1]) return null;
  return [teams[0], teams[1]];
}

/**
 * `gamesOnlyPairTeammates` of the app: every team-tagged board pairs two
 * players of the same team (a "Group A" label, not a team match).
 */
export function gamesOnlyPairTeammates(
  boards: Iterable<MatchPlayBoard>,
): boolean {
  let teammateBoards = 0;
  for (const board of boards) {
    const teams = boardTeams(board);
    if (!teams) continue;
    if (teams[0] !== teams[1]) return false;
    teammateBoards++;
  }
  return teammateBoards >= 2;
}

/**
 * `gamesShowTeamMatches` of the app, over this round: two boards between the
 * same two (different) teams.
 */
export function gamesShowTeamMatches(
  boards: Iterable<MatchPlayBoard>,
): boolean {
  const seen = new Set<string>();
  for (const board of boards) {
    const teams = boardTeams(board);
    if (!teams || teams[0] === teams[1]) continue;
    const key = [...teams].sort().join("\u0001");
    if (seen.has(key)) return true;
    seen.add(key);
  }
  return false;
}

/** At least 80% of a non-empty roster carries a team tag. */
function mostPlayersHaveTeam(teams: Array<string | null>): boolean {
  if (teams.length === 0) return false;
  const teamed = teams.filter((team) => (team ?? "").trim() !== "").length;
  return teamed * 5 >= teams.length * 4;
}

/**
 * The app's `resolveIsTeamEvent` (knockout_tournament_state_provider.dart),
 * in the same precedence: games that only pair teammates are never a team
 * event; `teamTable == true` or an official team table is; a team battle or
 * arena is not; `teamTable == false` leaves only the format's `team` token;
 * otherwise a `team` token, or (with no `player` token) team matches in the
 * games or a mostly teamed roster. The official table counts when present,
 * without the app's validation, so a doubtful tour stays out of the gate.
 */
export function isTeamTour(
  facts: KnockoutFacts,
  boards: Iterable<MatchPlayBoard>,
): boolean {
  const rows = [...boards];
  if (gamesOnlyPairTeammates(rows)) return false;
  if (facts.teamTable === true || facts.hasOfficialTeamTable === true) {
    return true;
  }
  const normalized = normalizedFormat(facts.format);
  if (normalized.includes("team battle") || /\barenas?\b/.test(normalized)) {
    return false;
  }
  const formatSaysTeam = /\bteams?\b/.test(normalized);
  if (facts.teamTable === false) return formatSaysTeam;
  const formatSaysPlayer = /\bplayers?\b/.test(normalized);
  return formatSaysTeam ||
    (!formatSaysPlayer &&
      (gamesShowTeamMatches(rows) ||
        mostPlayersHaveTeam(facts.rosterTeams ?? [])));
}

/** The app's `formatRulesOutKnockout`: an explicit non-knockout format. */
function formatRulesOutKnockout(normalized: string): boolean {
  return normalized.includes("swiss") ||
    normalized.includes("round robin") ||
    normalized.includes("all play all") ||
    normalized.includes("league");
}

/**
 * Elimination-stage words in a round name: the notifications' form of the
 * app's round-metadata evidence (`hasTrustworthyKnockoutStageMetadata`) for
 * tours whose format says nothing (EWC Play-in and LCQ, China Chess King
 * Stage 3: format null, rounds "Upper | Round 1", "Quarterfinals | Game 1").
 */
const ROUND_STAGE =
  /\b(?:round of \d+|last \d+|(?:quarter|semi|grand) ?finals?|finals?|third place|\d+(?:st|nd|rd|th) place|bronze|tie ?breaks?|armageddon|play ?offs?|play ?ins?|knock ?outs?|elimination|(?:upper|lower) (?:bracket|round))\b/;

/**
 * The stricter list for a tour name, where "Final" also names a Grand Prix
 * final or a series final ("2025 Final Rapid Grand Prix", "India Rising |
 * Finals") that is not an elimination bracket.
 */
const TOUR_STAGE =
  /\b(?:round of \d+|last \d+|(?:quarter|semi) ?finals?|play ?offs?|play ?ins?|knock ?outs?|elimination)\b/;

function normalizedLabel(label: string | null | undefined): string {
  return (label ?? "").toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
}

/**
 * The tour is a player knockout, decided like the app's knockout gate:
 * never a team event; never a format that rules knockouts out (Swiss, round
 * robin, league); a format that says knockout or elimination; else, unless
 * the format names a match (a 1v1 match event is not a knockout), a round or
 * tour name that names an elimination stage.
 */
export function isKnockoutTour(
  facts: KnockoutFacts,
  boards: Iterable<MatchPlayBoard> = [],
): boolean {
  if (isTeamTour(facts, boards)) return false;
  const format = normalizedFormat(facts.format);
  if (formatRulesOutKnockout(format)) return false;
  if (/knock ?out|elimination/.test(format)) return true;
  if (/\bmatch(?:es)?\b/.test(format)) return false;
  return ROUND_STAGE.test(normalizedLabel(facts.roundName)) ||
    TOUR_STAGE.test(normalizedLabel(facts.tourName));
}

/** The format text alone says player knockout (no names, no roster). */
export function isPlayerKnockoutFormat(
  format: string | null | undefined,
): boolean {
  return isKnockoutTour({ format: format ?? null });
}

/** Title prefixes the app strips before comparing names. */
const TITLE_PREFIX = /^(?:(?:GM|IM|FM|CM|WGM|WIM|WFM|WCM|NM|WNM)\.?\s+)+/i;

function normalizedName(name: string | null | undefined): string {
  return (name ?? "")
    .trim()
    .replace(TITLE_PREFIX, "")
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

/** The app's `_isPlaceholderPlayerName`, on a normalized name. */
function isPlaceholderName(normalized: string): boolean {
  return normalized === "" ||
    normalized === "tbd" ||
    normalized === "tba" ||
    normalized === "unknown" ||
    normalized === "unknown player" ||
    normalized === "to be determined" ||
    normalized.startsWith("winner of ") ||
    normalized.startsWith("loser of ");
}

function fidePairKey(ids: Iterable<number | string>): string | null {
  const valid = [
    ...new Set(
      [...ids]
        .map((id) => String(id).trim())
        .filter((id) => /^[1-9]\d*$/.test(id)),
    ),
  ].sort();
  return valid.length === 2 ? valid.join("|") : null;
}

/**
 * Order-independent keys for the pair at a board: the two FIDE ids when the
 * board carries both, and the two normalized names. Colours alternate within
 * a match, so neither key depends on who has White. A placeholder pairing
 * ("TBD", "Winner of ...") has no key.
 */
export function matchPairKeys(
  board: MatchPlayBoard,
): { fide: string | null; names: string | null } {
  const white = normalizedName(board.player_white);
  const black = normalizedName(board.player_black);
  if (isPlaceholderName(white) || isPlaceholderName(black)) {
    return { fide: null, names: null };
  }
  const fide = fidePairKey(board.player_fide_ids ?? []);
  const names = white !== black ? [white, black].sort().join("|") : null;
  return { fide, names };
}

/** One match of a round: the boards of one unordered pair. */
export type MatchGroup = { fide: string | null; boards: MatchPlayBoard[] };

/**
 * The round's boards grouped by match. Two boards are the same pair when both
 * carry FIDE ids and the ids match, or, when either lacks them, when the
 * names match (the app backfills a missing FIDE id from the same name). Board
 * numbers are never read: the ingest renumbers them every cycle.
 */
export function groupMatches(boards: Iterable<MatchPlayBoard>): MatchGroup[] {
  const groups: MatchGroup[] = [];
  const byFide = new Map<string, MatchGroup>();
  const byNames = new Map<string, MatchGroup[]>();
  for (const board of boards) {
    const { fide, names } = matchPairKeys(board);
    if (!fide && !names) continue;
    let group = fide ? byFide.get(fide) : undefined;
    if (!group && names) {
      // Same names under two different FIDE pairs are namesakes, not a match.
      group = byNames.get(names)?.find((other) =>
        other.fide === null || fide === null || other.fide === fide
      );
    }
    if (!group) {
      group = { fide, boards: [] };
      groups.push(group);
    }
    group.boards.push(board);
    if (fide) {
      group.fide ??= fide;
      byFide.set(fide, group);
    }
    if (names) {
      const known = byNames.get(names) ?? [];
      if (!known.includes(group)) known.push(group);
      byNames.set(names, known);
    }
  }
  return groups;
}

/** Whether one unordered pair has two or more games in these boards. */
export function hasRepeatedPair(boards: Iterable<MatchPlayBoard>): boolean {
  return groupMatches(boards).some((group) => group.boards.length >= 2);
}

/** The gate: a player knockout round in which a pair has 2+ games. */
export function isMatchPlayRound(
  facts: KnockoutFacts,
  boards: Iterable<MatchPlayBoard>,
): boolean {
  const rows = [...boards];
  return hasRepeatedPair(rows) && isKnockoutTour(facts, rows);
}

/**
 * The facts the gate reads from a `tours` row (`name,info,players`), plus the
 * curated `info.matchSchedule` the heads-up reads.
 */
export function knockoutFactsFromTour(
  tour: { name?: unknown; info?: unknown; players?: unknown } | null,
): KnockoutFacts & { matchSchedule: unknown } {
  const info = isPlainRecord(tour?.info) ? tour.info : {};
  const roster = Array.isArray(tour?.players) ? tour.players : [];
  return {
    format: typeof info.format === "string" ? info.format : null,
    teamTable: typeof info.teamTable === "boolean" ? info.teamTable : null,
    hasOfficialTeamTable: isPlainRecord(info.officialTeamStandings),
    rosterTeams: roster.map((player) =>
      isPlainRecord(player) && typeof player.team === "string"
        ? player.team
        : null
    ),
    tourName: typeof tour?.name === "string" ? tour.name : null,
    matchSchedule: info.matchSchedule ?? null,
  };
}

/** Same reading as `isGameOverStatus` in index.ts. */
function isFinishedStatus(status: string | null | undefined): boolean {
  if (!status) return false;
  const trimmed = status.trim().toLowerCase();
  if (trimmed.length === 0) return false;
  return trimmed !== "*" && trimmed !== "ongoing";
}

/** A move has been played at this board. */
export function boardHasStarted(board: MatchPlayBoard): boolean {
  return board.last_move_time != null ||
    (typeof board.last_move === "string" && board.last_move.trim() !== "");
}

/** Started and not finished: the only boards "X vs Y is live." may name. */
export function isLiveBoard(board: MatchPlayBoard): boolean {
  return boardHasStarted(board) && !isFinishedStatus(board.status);
}

export function liveBoardIds(boards: Iterable<MatchPlayBoard>): Set<string> {
  const ids = new Set<string>();
  for (const board of boards) {
    if (board.id && isLiveBoard(board)) ids.add(board.id);
  }
  return ids;
}

/**
 * The boards a round_started row may announce: every paired board (`null`,
 * today's behaviour) unless the round is match-play, then the live ones plus
 * the boards this row already announced before a timeout (so a resumed run
 * keeps their readers on the board path, where those boards are skipped).
 */
export function roundStartBoardScope(
  matchPlay: boolean,
  live: Set<string>,
  alreadySent: Iterable<string> = [],
): Set<string> | null {
  return matchPlay ? new Set([...live, ...alreadySent]) : null;
}

/**
 * Each reader's favorites that sit at a board in `scope`; readers with none
 * are left out.
 */
export function favoritesAtBoards(
  playerUserIds: Iterable<string>,
  favoriteNames: Map<string, string[]>,
  boardsForName: (name: string) => Iterable<string> | undefined,
  scope: Set<string>,
): Map<string, string[]> {
  const result = new Map<string, string[]>();
  for (const userId of playerUserIds) {
    const names = (favoriteNames.get(userId) ?? []).filter((name) =>
      [...(boardsForName(name) ?? [])].some((gameId) => scope.has(gameId))
    );
    if (names.length > 0) result.set(userId, names);
  }
  return result;
}

/**
 * Favorite-player readers who take the favorite path of round_started in a
 * match-play round: a favorite at a board in `scope` (live, or announced by
 * this row), or at a board whose start push already reached them (`covered`:
 * they stay on the board path, which skips that board, instead of getting the
 * event-level copy on top). The others count as event stars (when they star
 * the event) or get nothing; their player's board raises game_started at its
 * first move.
 */
export function readersWithLiveFavorite(
  playerUserIds: Iterable<string>,
  favoriteNames: Map<string, string[]>,
  boardsForName: (name: string) => Iterable<string> | undefined,
  scope: Set<string>,
  covered: Map<string, Set<string>> = new Map(),
): Set<string> {
  const readers = new Set<string>();
  for (const userId of playerUserIds) {
    const told = covered.get(userId);
    const names = favoriteNames.get(userId) ?? [];
    const counts = names.some((name) =>
      [...(boardsForName(name) ?? [])].some((gameId) =>
        scope.has(gameId) || (told?.has(gameId) ?? false)
      )
    );
    if (counts) readers.add(userId);
  }
  return readers;
}

/** One `tours.info.matchSchedule` entry of this round. */
type ScheduledMatch = { pair: string; startsAtMs: number };

function scheduleForRound(raw: unknown, roundId: string): ScheduledMatch[] {
  if (!Array.isArray(raw)) return [];
  const entries: ScheduledMatch[] = [];
  for (const entry of raw) {
    if (!isPlainRecord(entry) || entry.roundId !== roundId) continue;
    const pair = Array.isArray(entry.fideIds)
      ? fidePairKey(entry.fideIds as Array<number | string>)
      : null;
    const startsAtMs = typeof entry.startsAt === "string"
      ? Date.parse(entry.startsAt)
      : NaN;
    if (pair && !Number.isNaN(startsAtMs)) entries.push({ pair, startsAtMs });
  }
  return entries;
}

const DAY_MS = 86_400_000;

function utcDay(ms: number): number {
  return Math.floor(ms / DAY_MS) * DAY_MS;
}

/**
 * Two or more matches whose every game is a 0-move shell dated two or more
 * days before the start day: the stage was published ahead of a schedule that
 * spans days (SCC XI R16: shells dated 11-14 for a round starting 11-16). A
 * single stale placeholder (Dutch Championship, DreamHack) is not enough, and
 * a day of slack covers PGN dates written in local time.
 */
export function shellsPublishedAhead(
  groups: MatchGroup[],
  startsAtMs: number,
): boolean {
  const latestAheadDay = utcDay(startsAtMs) - 2 * DAY_MS;
  let ahead = 0;
  for (const group of groups) {
    const allAhead = group.boards.every((board) => {
      if (boardHasStarted(board) || !board.date_start) return false;
      const dated = Date.parse(board.date_start.slice(0, 10));
      return !Number.isNaN(dated) && dated <= latestAheadDay;
    });
    if (allAhead && ++ahead >= 2) return true;
  }
  return false;
}

/**
 * The boards whose players a round_heads_up may name: `null` names every
 * favorite (today's behaviour). Only a match-play round with two or more
 * matches is narrowed, since a round of one match holds exactly the match
 * that starts (EWC Grand Final, the Dutch final tiebreak):
 *  - `tours.info.matchSchedule` lists the round: the boards of the matches
 *    scheduled at this start, possibly none;
 *  - the shells were published days ahead: none, nothing says which match
 *    is played today;
 *  - otherwise every favorite: same-day stages (EWC quarterfinals, Dutch
 *    tiebreaks) play all their matches at the start.
 */
export function headsUpBoardScope(args: {
  matchPlay: boolean;
  boards: Iterable<MatchPlayBoard>;
  roundId: string;
  startsAt: string | null | undefined;
  matchSchedule: unknown;
}): Set<string> | null {
  if (!args.matchPlay) return null;
  const groups = groupMatches(args.boards);
  if (groups.length <= 1) return null;
  const startsAtMs = args.startsAt ? Date.parse(args.startsAt) : NaN;

  const schedule = scheduleForRound(args.matchSchedule, args.roundId);
  if (schedule.length > 0) {
    const now = new Set(
      schedule
        .filter((entry) => entry.startsAtMs === startsAtMs)
        .map((entry) => entry.pair),
    );
    const boards = new Set<string>();
    for (const group of groups) {
      if (!group.fide || !now.has(group.fide)) continue;
      for (const board of group.boards) boards.add(board.id);
    }
    return boards;
  }

  if (!Number.isNaN(startsAtMs) && shellsPublishedAhead(groups, startsAtMs)) {
    return new Set();
  }
  return null;
}

/**
 * The readers a heads-up may name, and the favorites to name for each. With
 * no scope, the very same set and map (today's behaviour). With a scope, only
 * favorites at its boards; a reader left with none takes the event path when
 * they star the event, and gets nothing otherwise.
 */
export function headsUpReaders(
  scope: Set<string> | null,
  playerUserIds: Set<string>,
  favoriteNames: Map<string, string[]>,
  boardsForName: (name: string) => Iterable<string> | undefined,
): { playerUserIds: Set<string>; favoriteNames: Map<string, string[]> } {
  if (!scope) return { playerUserIds, favoriteNames };
  const scoped = favoritesAtBoards(
    playerUserIds,
    favoriteNames,
    boardsForName,
    scope,
  );
  return { playerUserIds: new Set(scoped.keys()), favoriteNames: scoped };
}
