/**
 * Some organizers publish a "Combined" section next to the real ones (Total
 * Chess World Championship Tour Pilot 2026: Group Stage A-D plus Group Stage
 * Combined). Combined repeats every board of the other sections as separate
 * games with their own ids, so any push it raises reaches the same followers
 * a second time under a different collapse id. The real sections own every
 * alert; Combined stays silent whenever at least one of them exists.
 */

type SectionLabel = { name: string | null; slug: string | null };

export function isCombinedSection(tour: SectionLabel | null): boolean {
  const label = `${tour?.name ?? ""} ${tour?.slug ?? ""}`.toLowerCase();
  return /(^|[^a-z0-9])combined([^a-z0-9]|$)/.test(label);
}

/** Pushes a Combined section never sends while a real section covers it. */
const COMBINED_MIRRORED_EVENTS = new Set([
  "game_started",
  "game_finished",
  "round_started",
  "round_heads_up",
]);

export function suppressCombinedMirror(
  eventType: string,
  tour: SectionLabel | null,
  realSectionCount: number,
): boolean {
  return COMBINED_MIRRORED_EVENTS.has(eventType) &&
    realSectionCount > 0 &&
    isCombinedSection(tour);
}

/**
 * Sections of one event usually start a round at the same instant, and each
 * raises its own heads-up. Event stars would get one identical "Round 2 in
 * ~30 min" per section. Only the section round with the smallest id speaks to
 * them; favorite-player copy stays per section, since it names different
 * players. Deterministic on purpose: sibling rows are dispatched concurrently,
 * so "has a sibling sent yet?" would race.
 */
export function speaksForEventStars(
  roundId: string,
  simultaneousSectionRoundIds: string[],
): boolean {
  if (!simultaneousSectionRoundIds.includes(roundId)) return true;
  const first = [...simultaneousSectionRoundIds].sort()[0];
  return first === roundId;
}
