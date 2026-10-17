/**
 * The words of a starred Prep player's "playing now" push.
 *
 * It names the player as the profile is called (with their title) and the
 * accounts the new games came from, and says when, in the reader's day. The
 * count is deliberately left out: the push says that the player played, the
 * reader taps to see what (the app shows the number on the profile the push
 * opens, data `added`). The second push of a day says they kept playing.
 */
export type PrepGamesCopy = { title: string; body: string };

export type PrepGamesPush = {
  profileName: string;
  /** "GM", "IM", ... or null. */
  profileTitle: string | null;
  /** The accounts the new games came from, busiest first. */
  accounts: { source: string; username: string }[];
  /** 1 for the day's first push, 2 for the second. */
  slot: number;
  /** The reader's local hour when it is sent. */
  localHour: number;
  /** Other starred players with new games today. */
  otherPlayers: number;
};

const SITES: Record<string, string> = {
  lichess: "Lichess",
  chesscom: "Chess.com",
};

function partOfDay(hour: number): string {
  if (hour < 12) return "this morning";
  if (hour < 18) return "this afternoon";
  return "this evening";
}

function accountList(accounts: PrepGamesPush["accounts"]): string {
  const named = accounts
    .filter((a) => a.username.trim() !== "")
    .slice(0, 2)
    .map((a) => `${a.username} on ${SITES[a.source] ?? a.source}`);
  return named.join(" and ");
}

export function prepGamesAddedCopy(push: PrepGamesPush): PrepGamesCopy {
  const name = push.profileName.trim() || "Your player";
  const title = push.profileTitle?.trim();
  const who = title && !name.startsWith(`${title} `)
    ? `${title} ${name}`
    : name;
  const from = accountList(push.accounts);
  const others = push.otherPlayers === 1
    ? " Another of your players played too."
    : push.otherPlayers > 1
    ? ` ${push.otherPlayers} more of your players played too.`
    : "";

  if (push.slot >= 2) {
    return {
      title: `${who} is still playing`,
      body: `${
        from ? `More new games from ${from}.` : "More new games."
      }${others} Tap to see.`,
    };
  }
  return {
    title: `${who} played ${partOfDay(push.localHour)}`,
    body: `${
      from ? `New games from ${from}.` : "New games are in."
    }${others} Tap to see.`,
  };
}

function toInt(value: unknown, fallback: number): number {
  const n = typeof value === "number" ? value : Number(value);
  return Number.isFinite(n) ? Math.trunc(n) : fallback;
}

/** The outbox payload `queue_prep_games_pushes` writes, read safely. */
export function prepGamesPushFromPayload(
  payload: Record<string, unknown> | null | undefined,
): PrepGamesPush {
  const p = payload ?? {};
  const accounts = Array.isArray(p.accounts)
    ? p.accounts.flatMap((a) => {
      if (!a || typeof a !== "object") return [];
      const { source, username } = a as Record<string, unknown>;
      return typeof source === "string" && typeof username === "string"
        ? [{ source, username }]
        : [];
    })
    : [];
  return {
    profileName: typeof p.profile_name === "string" ? p.profile_name : "",
    profileTitle: typeof p.profile_title === "string" ? p.profile_title : null,
    accounts,
    slot: Math.max(1, toInt(p.slot, 1)),
    localHour: Math.min(23, Math.max(0, toInt(p.local_hour, 12))),
    otherPlayers: Math.max(0, toInt(p.other_players, 0)),
  };
}
