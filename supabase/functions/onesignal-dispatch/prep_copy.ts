/**
 * The words of a starred Prep player's "new games" push.
 *
 * The title is the count: "GM Magnus Carlsen played 12 games today!". A push
 * that follows an earlier one about the same player the same day says "12
 * more" and gives the day's total, so the number never repeats games the
 * reader was already told about. The body names the accounts the games came
 * from. Tapping opens the player's Games tab.
 *
 * The reader's own profile (kind "mine") is about them, so it speaks to
 * them: "7 new games of yours. Spot the leak?". It promises a
 * look at their play, never a result the push cannot know.
 */
export type PrepGamesCopy = { title: string; body: string };

export type PrepGamesPush = {
  profileName: string;
  /** New games since the reader was last told about this player. */
  games: number;
  /** "GM", "IM", ... or null. */
  profileTitle: string | null;
  /** The accounts the new games came from, busiest first. */
  accounts: { source: string; username: string }[];
  /**
   * Games of this player the reader was already told about today: 0 on the
   * day's first push about them, so "more" is only said when it is true.
   */
  earlierToday: number;
  /** Other starred players with new games today, each with a push of their own. */
  otherPlayers: number;
  /** "mine" for the reader's own profile; null from older apps. */
  profileKind: string | null;
};

const SITES: Record<string, string> = {
  lichess: "Lichess",
  chesscom: "Chess.com",
};

function accountList(accounts: PrepGamesPush["accounts"]): string {
  const named = accounts
    .filter((a) => a.username.trim() !== "")
    .slice(0, 2)
    .map((a) => `${a.username} on ${SITES[a.source] ?? a.source}`);
  return named.join(" and ");
}

/** Sites the games came from, "Lichess and Chess.com", for the reader's own copy. */
function siteList(accounts: PrepGamesPush["accounts"]): string {
  const sites = [
    ...new Set(accounts.map((a) => SITES[a.source] ?? a.source)),
  ].filter((s) => s.trim() !== "").slice(0, 2);
  return sites.join(" and ");
}

/** The reader's own new games: their play, waiting to be looked at. */
function ownGamesCopy(push: PrepGamesPush): PrepGamesCopy {
  const n = Math.max(1, push.games);
  const sites = siteList(push.accounts);
  const on = sites ? ` on ${sites}` : "";
  const others = push.otherPlayers === 1
    ? " One of your players is at it too."
    : push.otherPlayers > 1
    ? ` ${push.otherPlayers} of your players are at it too.`
    : "";

  if (push.earlierToday > 0) {
    const total = push.earlierToday + n;
    return {
      title: `${total} games today. Still the same opening?`,
      body: `${n} more${on} just landed in Prep.${others} ` +
        "Tap to see which lines held up and which keep costing you.",
    };
  }
  if (n === 1) {
    return {
      title: "Your new game is in. Where did it turn?",
      body: `It's waiting in Prep, next to every game you've played${on}.` +
        `${others} Tap to find the move that decided it.`,
    };
  }
  return {
    title: `${n} new games of yours. Spot the leak?`,
    body: `They're all in Prep${on}.${others} ` +
      "Tap to see the opening you keep reaching, and how it's really going.",
  };
}

export function prepGamesAddedCopy(push: PrepGamesPush): PrepGamesCopy {
  if (push.profileKind === "mine") return ownGamesCopy(push);
  const name = push.profileName.trim() || "Your player";
  const title = push.profileTitle?.trim();
  const who = title && !name.startsWith(`${title} `)
    ? `${title} ${name}`
    : name;
  const n = Math.max(1, push.games);
  const games = n === 1 ? "game" : "games";
  const more = push.earlierToday > 0 ? " more" : "";

  const from = accountList(push.accounts);
  const parts = [from ? `Fresh from ${from}.` : "Fresh games are in."];
  if (push.earlierToday > 0) {
    parts.push(`That's ${push.earlierToday + n} today.`);
  }
  if (push.otherPlayers === 1) {
    parts.push("Another of your players is playing too.");
  } else if (push.otherPlayers > 1) {
    parts.push(`${push.otherPlayers} more of your players are playing too.`);
  }
  parts.push(n === 1 ? "Tap to see it." : `Tap to see all ${n}.`);

  return {
    title: `${who} played ${n}${more} ${games} today!`,
    body: parts.join(" "),
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
    games: Math.max(1, toInt(p.added, 1)),
    profileTitle: typeof p.profile_title === "string" ? p.profile_title : null,
    accounts,
    earlierToday: Math.max(0, toInt(p.earlier_today, 0)),
    otherPlayers: Math.max(0, toInt(p.other_players, 0)),
    profileKind: typeof p.profile_kind === "string" ? p.profile_kind : null,
  };
}
