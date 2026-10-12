/**
 * Starred smart events as round-notification subscribers.
 *
 * A smart event is a set of criteria (a game-average rating band, time
 * controls, live or completed), not a tournament: its favorites row is keyed
 * `smart_event:v2:<criteria>` and never equals a `group_broadcasts.id`. Once
 * its owner has turned notifications on (`metadata.notificationsEnabled`),
 * a round whose event the smart event would gather reaches them exactly as it
 * reaches someone who starred that event.
 *
 * The rules mirror the app's own (`smartEventFetchScopeFor` in
 * smart_aggregate_event_provider.dart): the rating band is on each game's
 * two-player average, never the event's.
 */

export type TimeControlBucket = "classical" | "rapid" | "blitz";

/** One opted-in smart event, as selected from `user_favorite_events`. */
export type SmartEventSubscription = {
  user_id: string | null;
  min_elo: unknown;
  max_elo: unknown;
  formats: unknown;
  eco: unknown;
};

export type SmartEventRound = {
  /** The round's time control; null when it could not be told. */
  timeControl: TimeControlBucket | null;
  /** Two-player average of each board in the round (0 = unrated). */
  gameAverages: number[];
  /** "start": the round is going live. "finish": its results are in. */
  phase: "start" | "finish";
};

/** The app's open-ended rating ceiling: at or above it there is no cap. */
const OPEN_MAX_ELO = 3200;

/**
 * Mirrors SQL `public.smart_event_average_rating(players)`: the floor of the
 * two players' mean, or 0 unless both carry a positive numeric rating.
 */
export function smartEventAverageRating(players: unknown): number {
  if (!Array.isArray(players)) return 0;
  const white = (players[0] as Record<string, unknown> | undefined)?.rating;
  const black = (players[1] as Record<string, unknown> | undefined)?.rating;
  if (typeof white !== "number" || typeof black !== "number") return 0;
  const w = Math.trunc(white);
  const b = Math.trunc(black);
  if (!(w > 0) || !(b > 0)) return 0;
  return Math.floor((w + b) / 2);
}

function toInt(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.trunc(value);
  }
  if (typeof value === "string" && value.trim() !== "") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return Math.trunc(parsed);
  }
  return null;
}

function tokensOf(formats: unknown): Set<string> {
  const tokens = new Set<string>();
  if (!Array.isArray(formats)) return tokens;
  for (const value of formats) {
    if (typeof value !== "string") continue;
    const token = value.trim().toLowerCase();
    if (token) tokens.add(token);
  }
  return tokens;
}

function bucketOf(token: string): TimeControlBucket | null {
  if (token === "standard" || token === "classical") return "classical";
  if (token === "rapid") return "rapid";
  if (token === "blitz") return "blitz";
  return null;
}

/** Whether [subscription] would gather [round]. */
export function smartEventMatchesRound(
  subscription: SmartEventSubscription,
  round: SmartEventRound,
): boolean {
  // An opening is not known when a round starts, and a results digest is not
  // about one opening: opening smart events are never asked (the app stars
  // them without the question).
  if (typeof subscription.eco === "string" && subscription.eco.trim() !== "") {
    return false;
  }

  const tokens = tokensOf(subscription.formats);

  const live = tokens.has("live");
  const completed = tokens.has("completed");
  if (round.phase === "start" && completed && !live) return false;
  if (round.phase === "finish" && live && !completed) return false;

  const buckets = new Set<TimeControlBucket>();
  for (const token of tokens) {
    const bucket = bucketOf(token);
    if (bucket) buckets.add(bucket);
  }
  // None chosen, or all three, is every time control.
  if (buckets.size > 0 && buckets.size < 3) {
    if (!round.timeControl || !buckets.has(round.timeControl)) return false;
  }

  const minElo = toInt(subscription.min_elo) ?? 0;
  const maxElo = toInt(subscription.max_elo) ?? OPEN_MAX_ELO;
  const hasFloor = minElo > 0;
  const hasCap = maxElo < OPEN_MAX_ELO;
  if (!hasFloor && !hasCap) return true;

  return round.gameAverages.some((average) =>
    average > 0 &&
    (!hasFloor || average >= minElo) &&
    (!hasCap || average <= maxElo)
  );
}

/** True when any of [subscriptions] needs the round's boards to decide. */
export function smartEventsNeedGameAverages(
  subscriptions: SmartEventSubscription[],
): boolean {
  return subscriptions.some((subscription) =>
    (toInt(subscription.min_elo) ?? 0) > 0 ||
    (toInt(subscription.max_elo) ?? OPEN_MAX_ELO) < OPEN_MAX_ELO
  );
}

/** The users whose opted-in smart events gather [round], each once. */
export function smartEventSubscribersForRound(
  subscriptions: SmartEventSubscription[],
  round: SmartEventRound,
): string[] {
  const userIds = new Set<string>();
  for (const subscription of subscriptions) {
    if (!subscription.user_id || userIds.has(subscription.user_id)) continue;
    if (smartEventMatchesRound(subscription, round)) {
      userIds.add(subscription.user_id);
    }
  }
  return Array.from(userIds);
}
