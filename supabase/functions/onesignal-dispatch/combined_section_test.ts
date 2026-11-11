/**
 * Run: deno test supabase/functions/onesignal-dispatch/combined_section_test.ts
 */
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  isCombinedSection,
  isMirrorSection,
  speaksForEventStars,
  suppressCombinedMirror,
} from "./combined_section.ts";

const combined = {
  name:
    "Total Chess World Championship Tour Pilot 2026 | Group Stage | Combined",
  slug: "total-chess-world-championship-tour-pilot-2026-group-stage-combined",
};
const groupA = {
  name: "Total Chess World Championship Tour Pilot 2026 | Group Stage | A",
  slug: "total-chess-world-championship-tour-pilot-2026-group-stage-a",
};

Deno.test("isCombinedSection reads the name or the slug as a whole word", () => {
  assertEquals(isCombinedSection(combined), true);
  assertEquals(isCombinedSection({ name: null, slug: "event-combined" }), true);
  assertEquals(isCombinedSection(groupA), false);
  assertEquals(
    isCombinedSection({ name: "Uncombinedness Open", slug: null }),
    false,
  );
  assertEquals(isCombinedSection(null), false);
});

const flaggedMirror = {
  name: "Some Open 2026 | All Groups",
  slug: "some-open-2026-all-groups",
  is_mirror: true,
};

Deno.test("isMirrorSection honours the tour flag regardless of name", () => {
  assertEquals(isMirrorSection(flaggedMirror), true);
  assertEquals(isMirrorSection({ ...groupA, is_mirror: false }), false);
  assertEquals(isMirrorSection(groupA), false);
  assertEquals(isMirrorSection(null), false);
});

Deno.test("The Combined name still marks a mirror when the flag is missing or false", () => {
  // Outbox rows queued before the migration, or a flag not yet backfilled.
  assertEquals(isMirrorSection(combined), true);
  assertEquals(isMirrorSection({ ...combined, is_mirror: null }), true);
  assertEquals(isMirrorSection({ ...combined, is_mirror: false }), true);
});

Deno.test("A flagged mirror's board and round pushes are dropped while real sections exist", () => {
  for (
    const type of [
      "game_started",
      "game_finished",
      "round_started",
      "round_heads_up",
    ]
  ) {
    assertEquals(suppressCombinedMirror(type, flaggedMirror, 4), true, type);
  }
  assertEquals(suppressCombinedMirror("game_started", flaggedMirror, 0), false);
});

Deno.test("Event-star sections exclude flagged and named mirrors", () => {
  // Mirrors index.ts: sectionTourIds = grouped tours filtered by !isMirrorSection.
  const grouped = [
    { id: "A", ...groupA, is_mirror: false },
    { id: "M", ...flaggedMirror },
    { id: "C", ...combined, is_mirror: null },
  ];
  assertEquals(
    grouped.filter((row) => !isMirrorSection(row)).map((row) => row.id),
    ["A"],
  );
});

Deno.test("Combined board and round pushes are dropped while real sections exist", () => {
  for (
    const type of [
      "game_started",
      "game_finished",
      "round_started",
      "round_heads_up",
    ]
  ) {
    assertEquals(suppressCombinedMirror(type, combined, 4), true, type);
    assertEquals(suppressCombinedMirror(type, groupA, 4), false, type);
  }
});

Deno.test("A Combined tour that is the event's only section still notifies", () => {
  assertEquals(suppressCombinedMirror("game_started", combined, 0), false);
});

Deno.test("Unrelated event types are left alone", () => {
  assertEquals(suppressCombinedMirror("book_game_added", combined, 4), false);
});

Deno.test("Only the first simultaneous section round speaks to event stars", () => {
  const sections = ["wgiPyqN7", "5oU7Rh6b", "TmMKVfX7", "1k8qXou1"];
  const speakers = sections.filter((id) => speaksForEventStars(id, sections));
  assertEquals(speakers, ["1k8qXou1"]);
});

Deno.test("A round missing from the lookup keeps its event-star copy", () => {
  assertEquals(speaksForEventStars("solo", []), true);
  assertEquals(speaksForEventStars("solo", ["other"]), true);
});
