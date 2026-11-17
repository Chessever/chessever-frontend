/**
 * The words of a starred smart event's evening push.
 *
 * A smart event is a filter over games, so its push is about games: how many
 * the filter caught today (since midnight where the reader lives), then the
 * strongest of them. Each mix
 * of filters (an opening, a rating band, time controls, live or finished)
 * gets its own line, named by [smartEventDigestKind] — a Najdorf star hears
 * about the Najdorf, a GM Blitz star about GM-level blitz.
 *
 * The evening push leads with the day's story when there is one: an upset
 * ("Upset in the Najdorf: 2390 beat 2610"), else a decisive strongest game
 * ("GM Firouzja beat GM Caruana in 37 moves"); the count moves to the body.
 * The afternoon push (smart_event_live) names the strongest board in play.
 *
 * The counts come from `public.smart_event_stories_since`.
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
  /** "GM", "IM", ... of the strongest game's players, when the relay has one. */
  topWhiteTitle?: string | null;
  topBlackTitle?: string | null;
  /** Full moves the strongest game took; 0 when unknown. */
  topMoves?: number;
  /** The day's upset: the lower-rated player won by 150-450 points. */
  upset?: SmartEventUpset | null;
  /** The reader's other smart events that caught games today too. */
  otherSmartEvents: number;
};

export type SmartEventUpset = {
  winner: string | null;
  winnerTitle: string | null;
  winnerRating: number;
  loser: string | null;
  loserTitle: string | null;
  loserRating: number;
  /** Full moves; 0 when unknown. */
  moves: number;
};

export type SmartEventDigestState = "played" | "live" | "finished";

export type SmartEventDigestShape = {
  opening: string | null;
  /** "at GM level", "at 2450+", "at 2200–2400", "rated 1800 or less". */
  level: string | null;
  /** "GM", "IM", ... when the level is a named floor with no cap. */
  tier: string | null;
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
  const tier = floor !== null && cap === null
    ? TIER_FLOORS.get(floor) ?? null
    : null;
  let level: string | null = null;
  if (floor !== null && cap !== null) level = `at ${floor}–${cap}`;
  else if (tier) level = `at ${tier} level`;
  else if (floor !== null) level = `at ${floor}+`;
  else if (cap !== null) level = `rated ${cap} or less`;

  const ecoCode = digest.ecoCode?.trim() ?? "";
  const opening = ecoCode === ""
    ? null
    : digest.label?.trim() || ecoCode.toUpperCase();

  return { opening, level, tier, timeControl, state };
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

/** "4 GM-level Blitz games", "1 game": the count, then what it counts. */
function counted(
  n: number,
  shape: SmartEventDigestShape,
  noun: [string, string] = ["game", "games"],
): string {
  const tier = shape.tier ? `${shape.tier}-level ` : "";
  const tc = shape.timeControl ? `${shape.timeControl} ` : "";
  return `${n} ${tier}${tc}${n === 1 ? noun[0] : noun[1]}`;
}

/**
 * The title line for [shape] with [n] games, number first so it is read
 * first: "Caro-Kann has been played 4 times today", "28 GM-level games
 * played today", "6 Blitz games are live right now".
 */
export function smartEventDigestTitle(
  shape: SmartEventDigestShape,
  n: number,
): string {
  const { opening, state } = shape;
  // A named level ("GM") reads as an adjective on the count; any other band
  // ("2450+", "2200–2400") trails the line.
  const at = shape.level && !shape.tier ? ` ${shape.level}` : "";
  const narrowed = Boolean(shape.tier || shape.timeControl);

  if (opening) {
    switch (state) {
      case "played":
        if (narrowed) {
          return `${opening} has been played in ${
            counted(n, shape)
          } today${at}`;
        }
        return n === 1
          ? `${opening} has been played once today${at}`
          : `${opening} has been played ${n} times today${at}`;
      case "live":
        return `${opening} is live on ${
          counted(n, shape, ["board", "boards"])
        } right now${at}`;
      case "finished":
        return `${counted(n, shape)} in the ${opening} finished today${at}`;
    }
  }

  switch (state) {
    case "played":
      return `${counted(n, shape)} played today${at}`;
    case "live":
      return `${counted(n, shape)} ${
        n === 1 ? "is" : "are"
      } live right now${at}`;
    case "finished":
      return `${counted(n, shape)} finished today${at}`;
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

/**
 * The body line: the strongest game (or how a finished batch went), then
 * what the tap opens. "Top game: Yakubboev beat Godart (2551 avg). 3 still
 * live. Tap to see all 28."
 */
export function smartEventDigestBody(
  shape: SmartEventDigestShape,
  digest: SmartEventDigest,
): string {
  const total = Math.max(1, digest.games);
  const parts = [`${smartEventDigestHighlight(shape, digest)}.`];

  // On a "played" filter the live share is news; a live-only filter already
  // said so in its title.
  if (shape.state === "played" && digest.liveGames > 0 && total > 1) {
    parts.push(
      digest.liveGames >= total
        ? "All still live."
        : `${digest.liveGames} still live.`,
    );
  }

  const others = digest.otherSmartEvents;
  if (others === 1) {
    parts.push("Another of your smart events caught games too.");
  }
  if (others > 1) {
    parts.push(`${others} more of your smart events caught games too.`);
  }

  if (total === 1) {
    parts.push(shape.state === "live" ? "Tap to watch it." : "Tap to see it.");
  } else if (shape.state === "live") parts.push(`Tap to watch all ${total}.`);
  else parts.push(`Tap to see all ${total}.`);
  return parts.join(" ");
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
  const lead = digest.games <= 1
    ? ""
    : shape.state === "live"
    ? "Top board: "
    : "Top game: ";
  if (digest.topStatus === "1-0") {
    return `${lead}${white} beat ${black}${rated}`;
  }
  if (digest.topStatus === "0-1") {
    return `${lead}${black} beat ${white}${rated}`;
  }
  if (digest.topStatus === "1/2-1/2" || digest.topStatus === "½-½") {
    return `${lead}${white} drew ${black}${rated}`;
  }
  return `${lead}${white} vs ${black}${rated}`;
}

export function smartEventDigestCopy(
  digest: SmartEventDigest,
): SmartEventDigestCopy {
  const shape = smartEventDigestShape(digest);
  const kind = smartEventDigestKind(shape);
  const story = smartEventStoryCopy(shape, digest);
  if (story) return { kind: `${kind}:${story.story}`, ...story.copy };
  return {
    kind,
    title: smartEventDigestTitle(shape, Math.max(1, digest.games)),
    body: smartEventDigestBody(shape, digest),
  };
}

/** "GM Firouzja", "Rautela": the title the relay gives, then the surname. */
export function smartEventPlayerLabel(
  name: string | null,
  title: string | null | undefined,
): string {
  const surname = smartEventPlayerName(name);
  const t = title?.trim();
  return t ? `${t} ${surname}` : surname;
}

/**
 * Where the story happened, for a title: "in the Najdorf", "in GM-level
 * Blitz", "at 2200–2400", or "" when the filter is every game.
 */
function storyScope(shape: SmartEventDigestShape): string {
  if (shape.opening) return ` in the ${shape.opening}`;
  const tier = shape.tier ? `${shape.tier}-level` : null;
  const parts = [tier, shape.timeControl].filter(Boolean).join(" ");
  if (parts) return ` in ${parts}`;
  if (shape.level) return ` ${shape.level}`;
  return "";
}

/** "494 Sicilian games today, 3 still live." The count, as a body sentence. */
function storyTally(
  shape: SmartEventDigestShape,
  digest: SmartEventDigest,
): string {
  const total = Math.max(1, digest.games);
  const noun = total === 1 ? "game" : "games";
  const what = shape.opening ? `${shape.opening} ${noun}` : counted(
    total,
    shape,
  ).replace(/^\d+ /, "");
  const live = digest.liveGames > 0 && digest.liveGames < total
    ? `, ${digest.liveGames} still live`
    : "";
  return `${total} ${what} today${live}.`;
}

function othersSentence(others: number, verb = "caught games"): string | null {
  if (others === 1) return `Another of your smart events ${verb} too.`;
  if (others > 1) return `${others} more of your smart events ${verb} too.`;
  return null;
}

function tapLine(total: number): string {
  return total <= 1 ? "Tap to see it." : `Tap to see all ${total}.`;
}

/**
 * The evening's story, when the day has one: an upset first, then a decisive
 * strongest game. Null when neither is there (the count line stays).
 */
export function smartEventStoryCopy(
  shape: SmartEventDigestShape,
  digest: SmartEventDigest,
): { story: "upset" | "top_win"; copy: { title: string; body: string } } | null {
  const total = Math.max(1, digest.games);
  const tail = [
    storyTally(shape, digest),
    othersSentence(digest.otherSmartEvents),
    tapLine(total),
  ].filter(Boolean).join(" ");

  const upset = digest.upset;
  if (
    upset && upset.winnerRating > 0 && upset.loserRating > upset.winnerRating
  ) {
    const winner = smartEventPlayerLabel(upset.winner, upset.winnerTitle);
    const loser = smartEventPlayerLabel(upset.loser, upset.loserTitle);
    const gap = upset.loserRating - upset.winnerRating;
    const inMoves = upset.moves > 0 ? ` in ${upset.moves} moves` : "";
    return {
      story: "upset",
      copy: {
        title: `Upset${storyScope(shape)}: ${upset.winnerRating} beat ${
          upset.loserRating
        }`,
        body: `${winner} took down ${loser}${inMoves}, giving away ${gap} ` +
          `rating points. ${tail}`,
      },
    };
  }

  const decisive = digest.topStatus === "1-0" || digest.topStatus === "0-1";
  if (decisive && shape.state !== "live") {
    const white = smartEventPlayerLabel(digest.topWhite, digest.topWhiteTitle);
    const black = smartEventPlayerLabel(digest.topBlack, digest.topBlackTitle);
    const [winner, loser] = digest.topStatus === "1-0"
      ? [white, black]
      : [black, white];
    const moves = digest.topMoves ?? 0;
    const inMoves = moves > 0 ? ` in ${moves} moves` : "";
    const rated = digest.topAverage > 0 ? ` (${digest.topAverage} avg)` : "";
    return {
      story: "top_win",
      copy: {
        title: `${winner} beat ${loser}${inMoves}`,
        body: `The strongest game${storyScope(shape)} today${rated}. ${tail}`,
      },
    };
  }
  return null;
}

/** One starred smart event's afternoon push: its strongest board in play. */
export type SmartEventLive = {
  label: string | null;
  minElo: number;
  maxElo: number;
  formats: string[];
  ecoCode: string | null;
  games: number;
  liveGames: number;
  white: string | null;
  black: string | null;
  whiteTitle: string | null;
  blackTitle: string | null;
  average: number;
  /** The move the board is on; 0 when unknown. */
  move: number;
  otherSmartEvents: number;
};

/**
 * "GM Firouzja vs GM Caruana, live now" / "Move 7 in the Sicilian, 2770 avg.
 * 6 more Sicilian boards live. Tap to watch."
 */
export function smartEventLiveCopy(live: SmartEventLive): SmartEventDigestCopy {
  const shape = smartEventDigestShape({
    label: live.label,
    minElo: live.minElo,
    maxElo: live.maxElo,
    formats: live.formats,
    ecoCode: live.ecoCode,
    games: live.games,
    liveGames: live.liveGames,
    whiteWins: 0,
    blackWins: 0,
    draws: 0,
    topWhite: live.white,
    topBlack: live.black,
    topStatus: "*",
    topAverage: live.average,
    otherSmartEvents: live.otherSmartEvents,
  });
  const white = smartEventPlayerLabel(live.white, live.whiteTitle);
  const black = smartEventPlayerLabel(live.black, live.blackTitle);

  const where = storyScope(shape).trim();
  const lead = [
    live.move > 0 ? `Move ${live.move}` : "In play",
    where ? ` ${where}` : "",
    live.average > 0 ? `, ${live.average} avg.` : ".",
  ].join("");
  const more = Math.max(0, live.liveGames - 1);
  const boards = more === 1 ? "board" : "boards";
  const moreLine = more > 0
    ? shape.opening
      ? `${more} more ${shape.opening} ${boards} live.`
      : `${more} more ${boards} live.`
    : null;
  const body = [
    lead,
    moreLine,
    othersSentence(live.otherSmartEvents, "is live"),
    more > 0 ? `Tap to watch all ${live.liveGames}.` : "Tap to watch.",
  ].filter(Boolean).join(" ");

  return {
    kind: `${smartEventDigestKind(shape)}:live_board`,
    title: `${white} vs ${black}, live now`,
    body,
  };
}

/** The outbox payload a `smart_event_live` row carries, read safely. */
export function smartEventLiveFromPayload(
  payload: Record<string, unknown> | null | undefined,
): SmartEventLive {
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
    white: toText(p.live_white),
    black: toText(p.live_black),
    whiteTitle: toText(p.live_white_title),
    blackTitle: toText(p.live_black_title),
    average: toInt(p.live_average, 0),
    move: Math.max(0, toInt(p.live_move, 0)),
    otherSmartEvents: Math.max(0, toInt(p.other_smart_events, 0)),
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
    topWhiteTitle: toText(p.top_white_title),
    topBlackTitle: toText(p.top_black_title),
    topMoves: Math.max(0, toInt(p.top_moves, 0)),
    upset: toText(p.upset_game_id)
      ? {
        winner: toText(p.upset_winner),
        winnerTitle: toText(p.upset_winner_title),
        winnerRating: toInt(p.upset_winner_rating, 0),
        loser: toText(p.upset_loser),
        loserTitle: toText(p.upset_loser_title),
        loserRating: toInt(p.upset_loser_rating, 0),
        moves: Math.max(0, toInt(p.upset_moves, 0)),
      }
      : null,
    otherSmartEvents: Math.max(0, toInt(p.other_smart_events, 0)),
  };
}
