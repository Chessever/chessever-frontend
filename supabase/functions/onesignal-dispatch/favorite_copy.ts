/** Copy only: callers supply recipients after the existing preference gates. */
export type Board = { white: string; black: string };
export type Copy = { title: string; body: string };

export function naturalPlayerName(name: string): string {
  const clean = name.trim().replace(/^(?:GM|IM|FM|CM|WGM|WIM|WFM|WCM)\s+/i, "")
    .replace(/\s+/g, " ");
  const comma = clean.indexOf(",");
  if (comma < 0) return clean;
  const family = clean.slice(0, comma).trim();
  const given = clean.slice(comma + 1).trim();
  return [given, family].filter(Boolean).join(" ");
}

export function playerNameKey(name: string): string {
  return naturalPlayerName(name).toLowerCase();
}

/** Resolve by the named JSONB player, never unordered player_fide_ids positions. */
export function favoriteNamesForBoard(
  rows: Array<{ fide_id: string | null; player_name: string | null }>,
  players: Record<string, unknown>[],
): string[] {
  return rows.map((row) => {
    const player = row.fide_id
      ? players.find((p) =>
        p.fideId != null && String(p.fideId) === String(row.fide_id)
      )
      : undefined;
    return typeof player?.name === "string" ? player.name : row.player_name;
  }).filter((name): name is string => Boolean(name));
}

export function favoriteBoardCopy(args: {
  board: Board;
  favorites: string[];
  eventType: "game_started" | "game_finished";
  status?: string;
  eventHeader: string | null;
  fallback: Copy;
}): Copy {
  const { board, favorites, eventType, fallback } = args;
  const keys = new Set(favorites.map(playerNameKey));
  const whiteFollowed = keys.has(playerNameKey(board.white));
  const blackFollowed = keys.has(playerNameKey(board.black));
  if (!whiteFollowed && !blackFollowed) return fallback;
  const white = naturalPlayerName(board.white);
  const black = naturalPlayerName(board.black);
  const matchup = `${white} vs ${black}`;
  const favorite = whiteFollowed ? white : black;
  let title: string;
  if (eventType === "game_started") {
    title = whiteFollowed && blackFollowed
      ? `${matchup} is live`
      : `${favorite} is live`;
  } else {
    const status = (args.status ?? "").trim();
    const normalized = status.toUpperCase();
    const draw = ["1/2-1/2", "\u00bd-\u00bd", "D", "DRAW"].includes(normalized);
    const whiteWon = ["1-0", "W"].includes(normalized);
    const blackWon = ["0-1", "B"].includes(normalized);
    if (whiteFollowed && blackFollowed) {
      title = `${matchup}: ${draw ? "draw" : status || "Game over"}`;
    } else if (draw) {
      title = `${favorite} drew`;
    } else if (whiteWon || blackWon) {
      const won = whiteFollowed ? whiteWon : blackWon;
      title = `${favorite} ${won ? "won" : "lost"}`;
    } else {
      title = `${favorite} finished`;
    }
  }
  // Preserve the existing pairing/result line, adding context moved out of title.
  return {
    title,
    body: args.eventHeader
      ? `${fallback.body}${
        /[.!?]$/.test(fallback.body) ? "" : "."
      } ${args.eventHeader}`
      : fallback.body,
  };
}

/** Partition a send without adding/removing recipients or changing their payload. */
export function groupFavoriteBoardCopy(
  userIds: Iterable<string>,
  favorites: Map<string, string[]>,
  args: Omit<Parameters<typeof favoriteBoardCopy>[0], "favorites">,
): Array<{ userIds: string[]; copy: Copy }> {
  const groups = new Map<string, { userIds: string[]; copy: Copy }>();
  for (const uid of userIds) {
    const copy = favoriteBoardCopy({
      ...args,
      favorites: favorites.get(uid) ?? [],
    });
    const key = JSON.stringify(copy);
    const group = groups.get(key);
    if (group) group.userIds.push(uid);
    else groups.set(key, { userIds: [uid], copy });
  }
  return [...groups.values()];
}
