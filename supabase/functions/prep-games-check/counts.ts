/**
 * How prep-games-check turns two sites' profile numbers into "this player
 * has new games". Pure, so it is tested without the network or a database.
 *
 * Neither site is asked for games. Lichess answers up to 300 players in one
 * `POST /api/users`, each with how many rated games they have played per
 * speed. Chess.com's `/pub/player/{name}/stats` holds each time class's
 * win/loss/draw record, updated as each game ends. A total that grew since
 * the last check is the news; `record_prep_watch_checks` adds the growth to
 * the owner's day and `queue_prep_games_pushes` decides when to tell them.
 */

/** The clocks My Prep downloads by, as PrepTimeControl names them. */
export type Clock =
  | "ultrabullet"
  | "bullet"
  | "blitz"
  | "rapid"
  | "classical"
  | "correspondence";

/** One player's game totals per clock on one site. */
export type Totals = Partial<Record<Clock, number>>;

/** What a site said about an account: its totals, or that it is gone. */
export type Reading =
  | { kind: "totals"; totals: Totals }
  | { kind: "missing" };

/** Standard chess only: variants and puzzles are not what Prep downloads. */
const LICHESS_PERFS: Record<string, Clock> = {
  ultraBullet: "ultrabullet",
  bullet: "bullet",
  blitz: "blitz",
  rapid: "rapid",
  classical: "classical",
  correspondence: "correspondence",
};

/** Chess.com has no classical or ultrabullet class; Daily is correspondence. */
const CHESSCOM_CLASSES: Record<string, Clock> = {
  chess_bullet: "bullet",
  chess_blitz: "blitz",
  chess_rapid: "rapid",
  chess_daily: "correspondence",
};

function count(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) && value > 0
    ? Math.trunc(value)
    : 0;
}

/**
 * Lichess's answer to `POST /api/users` for [requested] (lowercase ids).
 * A closed account, or one the answer leaves out, is missing.
 */
export function lichessReadings(
  requested: readonly string[],
  body: unknown,
): Map<string, Reading> {
  const readings = new Map<string, Reading>();
  for (const id of requested) readings.set(id, { kind: "missing" });
  if (!Array.isArray(body)) return readings;
  for (const user of body) {
    if (typeof user !== "object" || user === null) continue;
    const raw = user as Record<string, unknown>;
    const id = typeof raw.id === "string" ? raw.id.toLowerCase() : null;
    if (!id || !readings.has(id) || raw.disabled === true) continue;
    const perfs = typeof raw.perfs === "object" && raw.perfs !== null
      ? raw.perfs as Record<string, unknown>
      : {};
    const totals: Totals = {};
    for (const [perf, clock] of Object.entries(LICHESS_PERFS)) {
      const entry = perfs[perf];
      if (typeof entry !== "object" || entry === null) continue;
      totals[clock] = count((entry as Record<string, unknown>).games);
    }
    readings.set(id, { kind: "totals", totals });
  }
  return readings;
}

/** Chess.com's `/stats`: every ended game of a class is a win, loss or draw. */
export function chessComTotals(body: unknown): Totals {
  const totals: Totals = {};
  if (typeof body !== "object" || body === null) return totals;
  const stats = body as Record<string, unknown>;
  for (const [key, clock] of Object.entries(CHESSCOM_CLASSES)) {
    const entry = stats[key];
    if (typeof entry !== "object" || entry === null) continue;
    const record = (entry as Record<string, unknown>).record;
    if (typeof record !== "object" || record === null) continue;
    const r = record as Record<string, unknown>;
    totals[clock] = count(r.win) + count(r.loss) + count(r.draw);
  }
  return totals;
}

/** The games over [clocks], or over every clock when there are none. */
export function gamesOver(totals: Totals, clocks: readonly string[]): number {
  const picked = clocks.length === 0
    ? Object.values(totals)
    : clocks.map((clock) => totals[clock as Clock]);
  return picked.reduce<number>((sum, games) => sum + count(games), 0);
}

/** A row of prep_watches_to_check. */
export type WatchRow = {
  id: string;
  source: string;
  username: string;
  time_controls: string[] | null;
  baseline_games: number | null;
};

/** One row for record_prep_watch_checks. */
export type Check = {
  id: string;
  /** Null: the account is gone, so its total stays as it was. */
  games: number | null;
  time_controls: string[];
};

/**
 * What to record, given what the sites said. An account with no [Reading]
 * could not be read this time and is left for the next hour; one that is
 * gone is recorded as checked with its total unchanged. Growth is worked
 * out in the database, against the owner's local day.
 */
export function planChecks(
  rows: readonly WatchRow[],
  readingOf: (row: WatchRow) => Reading | undefined,
): Check[] {
  const checks: Check[] = [];
  for (const row of rows) {
    const clocks = row.time_controls ?? [];
    const reading = readingOf(row);
    if (!reading) continue;
    checks.push({
      id: row.id,
      games: reading.kind === "missing"
        ? null
        : gamesOver(reading.totals, clocks),
      time_controls: clocks,
    });
  }
  return checks;
}
