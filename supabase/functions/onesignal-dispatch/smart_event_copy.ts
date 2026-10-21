/**
 * The words of a starred smart event's evening push.
 *
 * A smart event is a filter over games, so its push is about games: how many
 * the filter caught today (the 24 hours since the reader's last evening
 * push), then the strongest of them. Each mix
 * of filters (an opening, a rating band, time controls, live or finished)
 * gets its own line, named by [smartEventDigestKind] — a Najdorf star hears
 * about the Najdorf, a GM Blitz star about GM-level blitz.
 *
 * The counts come from `public.smart_event_digest_rows`.
 */

export type SmartEventDigest = {
  /** `tierLabel`: the opening's name on an opening smart event. */
  label: string | null;
  minElo: number;
  maxElo: number;
  /** `formatsAndStates`: live / completed and standard / rapid / blitz. */
  formats: string[];
  ecoCode: string | null;
  games: number;
  liveGames: number;
  whiteWins: number;
  blackWins: number;
  draws: number;
  topWhite: string | null;
  topBlack: string | null;
  topStatus: string | null;
  topAverage: number;
  /** The reader's other smart events that caught games today too. */
  otherSmartEvents: number;
};

export type SmartEventDigestState = "played" | "live" | "finished";

export type SmartEventDigestShape = {
  opening: string | null;
  /** "at GM level", "at 2450+", "at 2200–2400", "rated 1800 or less". */
  level: string | null;
  /** "Classical", "Rapid", "Blitz", or two of them joined. */
  timeControl: string | null;
  state: SmartEventDigestState;
};

export type SmartEventDigestCopy = {
  /** e.g. `opening+level:live`, sent as push data for analytics. */
  kind: string;
  title: string;
  body: string;
};

/** The app's open rating ceiling (`kFilterMaxElo`): at or above it, no cap. */
const OPEN_MAX_ELO = 3200;

/** The app's named level floors (`SmartEventRequest._tierFloors`). */
const TIER_FLOORS = new Map<number, string>([
  [2500, "GM"],
  [2400, "IM"],
  [2300, "FM"],
  [2200, "CM"],
]);

const BUCKETS: [string, string][] = [
  ["classical", "Classical"],
  ["rapid", "Rapid"],
  ["blitz", "Blitz"],
];

function bucketOf(token: string): string | null {
  if (token === "standard" || token === "classical") return "classical";
  if (token === "rapid") return "rapid";
  if (token === "blitz" || token === "bullet") return "blitz";
  return null;
}

/** The filters [digest] combines, worded for its push. */
export function smartEventDigestShape(
  digest: SmartEventDigest,
): SmartEventDigestShape {
  const tokens = new Set(
    digest.formats.map((token) => token.trim().toLowerCase()),
  );

  const live = tokens.has("live");
  const finished = tokens.has("completed");
  const state: SmartEventDigestState = live && !finished
    ? "live"
    : finished && !live
    ? "finished"
    : "played";

  const buckets = new Set(
    [...tokens].map(bucketOf).filter((b): b is string => b !== null),
  );
  // None chosen, or all three, is every time control.
  const timeControl = buckets.size === 0 || buckets.size === 3
    ? null
    : BUCKETS.filter(([bucket]) => buckets.has(bucket))
      .map(([, name]) => name)
      .join(" & ");

  const hasRange = digest.minElo > 0 || digest.maxElo < OPEN_MAX_ELO;
  const floor = hasRange && digest.minElo > 0 ? digest.minElo : null;
  const cap = hasRange && digest.maxElo < OPEN_MAX_ELO ? digest.maxElo : null;
  let level: string | null = null;
  if (floor !== null && cap !== null) level = `at ${floor}–${cap}`;
  else if (floor !== null) {
    const tier = TIER_FLOORS.get(floor);
    level = tier ? `at ${tier} level` : `at ${floor}+`;
  } else if (cap !== null) level = `rated ${cap} or less`;

  const ecoCode = digest.ecoCode?.trim() ?? "";
  const opening = ecoCode === ""
    ? null
    : digest.label?.trim() || ecoCode.toUpperCase();

  return { opening, level, timeControl, state };
}

/** `opening+level+time:live` style id of [shape], one per filter mix. */
export function smartEventDigestKind(shape: SmartEventDigestShape): string {
  const parts = [
    shape.opening ? "opening" : null,
    shape.level ? "level" : null,
    shape.timeControl ? "time" : null,
  ].filter(Boolean);
  return `${parts.length ? parts.join("+") : "all"}:${shape.state}`;
}

function games(n: number, timeControl: string | null = null): string {
  const kind = timeControl ? `${timeControl} ` : "";
  return `${n} ${kind}${n === 1 ? "game" : "games"}`;
}

/** The title line for [shape] with [n] games. */
export function smartEventDigestTitle(
  shape: SmartEventDigestShape,
  n: number,
): string {
  const { opening, level, timeControl: tc, state } = shape;
  const at = level ? ` ${level}` : "";

  if (opening) {
    switch (state) {
      case "played":
        return `${opening} played in ${games(n, tc)}${at} today`;
      case "live":
        return n === 1
          ? `${opening} is live in 1 ${tc ? `${tc} ` : ""}game${at}`
          : `${opening} is live on ${n} ${tc ? `${tc} ` : ""}boards${at}`;
      case "finished":
        return `${opening}: ${games(n, tc)}${at} finished today`;
    }
  }

  switch (state) {
    case "played":
      if (level) return `${games(n, tc)} played today ${level}`;
      if (tc) return `${games(n, tc)} played today`;
      return `${games(n)} played today`;
    case "live":
      if (level) return `${games(n, tc)} live now ${level}`;
      return `${games(n, tc)} live right now`;
    case "finished":
      if (level) return `${games(n, tc)} ${level} finished today`;
      if (tc) return `${n} ${tc} ${n === 1 ? "result" : "results"} today`;
      return `${games(n)} finished today`;
  }
}

/** "Carlsen, Magnus" → "Carlsen"; "Gukesh D" → "Gukesh"; else last word. */
export function smartEventPlayerName(name: string | null): string {
  const trimmed = (name ?? "").trim();
  if (!trimmed) return "?";
  if (trimmed.includes(",")) {
    const before = trimmed.split(",")[0].trim().split(/\s+/);
    return before[before.length - 1];
  }
  const parts = trimmed.split(/\s+/);
  if (parts.length > 1 && parts[parts.length - 1].length <= 2) return parts[0];
  return parts[parts.length - 1];
}

/** The body line: the strongest game, or how the finished ones went. */
export function smartEventDigestBody(
  shape: SmartEventDigestShape,
  digest: SmartEventDigest,
): string {
  const n = digest.otherSmartEvents;
  const others = n === 1
    ? " Another of your smart events had new games too."
    : n > 1
    ? ` ${n} more of your smart events had new games too.`
    : "";
  return `${smartEventDigestHighlight(shape, digest)}.${others} Tap to see.`;
}

function smartEventDigestHighlight(
  shape: SmartEventDigestShape,
  digest: SmartEventDigest,
): string {
  const white = smartEventPlayerName(digest.topWhite);
  const black = smartEventPlayerName(digest.topBlack);
  const rated = digest.topAverage > 0 ? ` (${digest.topAverage} avg)` : "";

  if (shape.state === "finished" && digest.games > 1) {
    const draws = digest.draws === 1 ? "1 draw" : `${digest.draws} draws`;
    return `White won ${digest.whiteWins}, Black ${digest.blackWins}, ${draws}`;
  }
  if (digest.topStatus === "1-0") return `${white} beat ${black}${rated}`;
  if (digest.topStatus === "0-1") return `${black} beat ${white}${rated}`;
  if (digest.topStatus === "1/2-1/2" || digest.topStatus === "½-½") {
    return `${white} drew ${black}${rated}`;
  }
  const lead = digest.games === 1 ? "" : "Top game: ";
  return `${lead}${white} vs ${black}${rated}`;
}

export function smartEventDigestCopy(
  digest: SmartEventDigest,
): SmartEventDigestCopy {
  const shape = smartEventDigestShape(digest);
  return {
    kind: smartEventDigestKind(shape),
    title: smartEventDigestTitle(shape, Math.max(1, digest.games)),
    body: smartEventDigestBody(shape, digest),
  };
}

function toInt(value: unknown, fallback: number): number {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.trunc(value);
  }
  if (typeof value === "string" && value.trim() !== "") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return Math.trunc(parsed);
  }
  return fallback;
}

function toText(value: unknown): string | null {
  return typeof value === "string" && value.trim() !== "" ? value : null;
}

/** The outbox payload `queue_smart_event_digests` writes, read safely. */
export function smartEventDigestFromPayload(
  payload: Record<string, unknown> | null | undefined,
): SmartEventDigest {
  const p = payload ?? {};
  return {
    label: toText(p.label),
    minElo: toInt(p.min_elo, 0),
    maxElo: toInt(p.max_elo, OPEN_MAX_ELO),
    formats: Array.isArray(p.formats)
      ? p.formats.filter((v): v is string => typeof v === "string")
      : [],
    ecoCode: toText(p.eco_code),
    games: toInt(p.games, 0),
    liveGames: toInt(p.live_games, 0),
    whiteWins: toInt(p.white_wins, 0),
    blackWins: toInt(p.black_wins, 0),
    draws: toInt(p.draws, 0),
    topWhite: toText(p.top_white),
    topBlack: toText(p.top_black),
    topStatus: toText(p.top_status),
    topAverage: toInt(p.top_average, 0),
    otherSmartEvents: Math.max(0, toInt(p.other_smart_events, 0)),
  };
}
