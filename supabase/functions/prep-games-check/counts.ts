/**
 * How prep-games-check turns two sites' profile numbers into "this player
 * has new games". Pure, so it is tested without the network or a database.
 *
 * Neither site is asked for games. Lichess answers up to 300 players in one
 * `POST /api/users`, each with how many rated games they have played per
 * speed. Chess.com's `/pub/player/{name}/stats` holds each time class's
 * win/loss/draw record, updated as each game ends. A total that grew since
 * yesterday's check is the news; the push never says by how much.
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

/** A row of due_prep_profile_watches. */
export type WatchRow = {
  id: string;
  user_id: string;
  profile_id: string;
  profile_name: string;
  source: string;
  username: string;
  time_controls: string[] | null;
  baseline_games: number | null;
  /** The owner's date, `YYYY-MM-DD`. */
  local_date: string;
  /** Today's check, which may announce new games. */
  daily: boolean;
};

/** One row for record_prep_watch_checks. */
export type Check = {
  id: string;
  games: number | null;
  checked_on: string | null;
  time_controls: string[];
};

/** One push: the profile's new games over all its accounts. */
export type Notice = {
  user_id: string;
  profile_id: string;
  profile_name: string;
  added: number;
  local_date: string;
};

/**
 * What to record and whom to tell, given what the sites said. An account
 * with no [Reading] could not be read this time and is left for the next
 * hour. A first total announces nothing: it is what tomorrow compares with.
 * A total that fell (a site recounting) only moves the baseline down.
 */
export function planChecks(
  rows: readonly WatchRow[],
  readingOf: (row: WatchRow) => Reading | undefined,
): { checks: Check[]; notices: Notice[] } {
  const checks: Check[] = [];
  const notices = new Map<string, Notice>();
  for (const row of rows) {
    const clocks = row.time_controls ?? [];
    const reading = readingOf(row);
    if (!reading) continue;
    const today = row.daily ? row.local_date : null;
    if (reading.kind === "missing") {
      checks.push({
        id: row.id,
        games: null,
        checked_on: today,
        time_controls: clocks,
      });
      continue;
    }
    const games = gamesOver(reading.totals, clocks);
    if (row.baseline_games === null) {
      checks.push({
        id: row.id,
        games,
        checked_on: today,
        time_controls: clocks,
      });
      continue;
    }
    // Came along with a sibling account that is due; nothing of its own.
    if (!row.daily) continue;
    checks.push({
      id: row.id,
      games,
      checked_on: row.local_date,
      time_controls: clocks,
    });
    const added = games - row.baseline_games;
    if (added <= 0) continue;
    const key = `${row.user_id}:${row.profile_id}`;
    const notice = notices.get(key);
    if (notice) {
      notice.added += added;
    } else {
      notices.set(key, {
        user_id: row.user_id,
        profile_id: row.profile_id,
        profile_name: row.profile_name,
        added,
        local_date: row.local_date,
      });
    }
  }
  return { checks, notices: [...notices.values()] };
}

/** The outbox row for [notice]: one per profile per local day. */
export function outboxRow(notice: Notice) {
  return {
    event_type: "prep_games_added",
    payload: {
      user_id: notice.user_id,
      profile_id: notice.profile_id,
      profile_name: notice.profile_name,
      added: notice.added,
      local_date: notice.local_date,
    },
    dedupe_key:
      `prep_games_added:${notice.user_id}:${notice.profile_id}:${notice.local_date}`,
  };
}
