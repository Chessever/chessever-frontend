/**
 * Run: deno test supabase/functions/onesignal-dispatch/smart_event_match_test.ts
 */
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  sameRoundStartSlot,
  smartEventAverageRating,
  smartEventMatchesRound,
  type SmartEventRound,
  smartEventsNeedGameAverages,
  smartEventSubscribersForRound,
  type SmartEventSubscription,
  smartEventTimeControlOf,
} from "./smart_event_match.ts";

function sub(
  overrides: Partial<SmartEventSubscription> = {},
): SmartEventSubscription {
  return {
    user_id: "u1",
    min_elo: 0,
    max_elo: 3200,
    formats: [],
    eco: null,
    ...overrides,
  };
}

function round(overrides: Partial<SmartEventRound> = {}): SmartEventRound {
  return {
    timeControl: "classical",
    gameAverages: [],
    phase: "start",
    ...overrides,
  };
}

Deno.test("average rating mirrors the SQL: floor of the mean, 0 unless both are rated", () => {
  assertEquals(
    smartEventAverageRating([{ rating: 2591 }, { rating: 2371 }]),
    2481,
  );
  assertEquals(
    smartEventAverageRating([{ rating: 2700.9 }, { rating: 2701 }]),
    2700,
  );
  assertEquals(smartEventAverageRating([{ rating: 2700 }, {}]), 0);
  assertEquals(smartEventAverageRating([{ rating: 2700 }, { rating: 0 }]), 0);
  assertEquals(
    smartEventAverageRating([{ rating: "2700" }, { rating: 2700 }]),
    0,
  );
  assertEquals(smartEventAverageRating(null), 0);
});

Deno.test("the level is a floor on a game's two-player average, not on the event", () => {
  const gm = sub({ min_elo: 2500 });
  // The reported GM boards averaging 2481 stay out; one 2500 board is enough.
  assertEquals(
    smartEventMatchesRound(gm, round({ gameAverages: [2481, 2480] })),
    false,
  );
  assertEquals(
    smartEventMatchesRound(gm, round({ gameAverages: [2100, 2500] })),
    true,
  );
  // An unrated round (no averages) never passes a level.
  assertEquals(smartEventMatchesRound(gm, round()), false);
});

Deno.test("3200 is the app's open ceiling, anything below it is a real cap", () => {
  const open = sub({ min_elo: 2500, max_elo: 3200 });
  assertEquals(
    smartEventMatchesRound(open, round({ gameAverages: [3300] })),
    true,
  );
  const band = sub({ min_elo: 2300, max_elo: 2499 });
  assertEquals(
    smartEventMatchesRound(band, round({ gameAverages: [2600] })),
    false,
  );
  assertEquals(
    smartEventMatchesRound(band, round({ gameAverages: [2600, 2400] })),
    true,
  );
  // A cap alone still needs a rated board.
  assertEquals(
    smartEventMatchesRound(
      sub({ max_elo: 2000 }),
      round({ gameAverages: [0] }),
    ),
    false,
  );
});

Deno.test("chosen time controls gate the round; none or all three is every one", () => {
  const classical = sub({ formats: ["standard"] });
  assertEquals(smartEventMatchesRound(classical, round()), true);
  assertEquals(
    smartEventMatchesRound(classical, round({ timeControl: "blitz" })),
    false,
  );
  // A round whose time control cannot be told is not guessed into a match.
  assertEquals(
    smartEventMatchesRound(classical, round({ timeControl: null })),
    false,
  );
  assertEquals(
    smartEventMatchesRound(
      sub({ formats: ["Standard", " rapid ", "blitz"] }),
      round({ timeControl: null }),
    ),
    true,
  );
  assertEquals(
    smartEventMatchesRound(sub(), round({ timeControl: null })),
    true,
  );
});

Deno.test("completed-only waits for results; live-only skips the results digest", () => {
  const completed = sub({ formats: ["completed"] });
  assertEquals(smartEventMatchesRound(completed, round()), false);
  assertEquals(
    smartEventMatchesRound(completed, round({ phase: "finish" })),
    true,
  );
  const live = sub({ formats: ["live"] });
  assertEquals(smartEventMatchesRound(live, round()), true);
  assertEquals(
    smartEventMatchesRound(live, round({ phase: "finish" })),
    false,
  );
  const both = sub({ formats: ["live", "completed"] });
  assertEquals(smartEventMatchesRound(both, round()), true);
  assertEquals(smartEventMatchesRound(both, round({ phase: "finish" })), true);
});

Deno.test("an opening smart event never matches a round", () => {
  assertEquals(smartEventMatchesRound(sub({ eco: "B90" }), round()), false);
});

Deno.test("subscribers are each user once, and only those whose criteria gather the round", () => {
  const rows = [
    sub({ user_id: "gm", min_elo: 2500 }),
    sub({ user_id: "gm", formats: ["blitz"] }),
    sub({ user_id: "im", min_elo: 2400, formats: ["standard"] }),
    sub({ user_id: "blitz", formats: ["blitz"] }),
    sub({ user_id: null, min_elo: 2400 }),
  ];
  assertEquals(
    smartEventSubscribersForRound(rows, round({ gameAverages: [2450] })),
    ["im"],
  );
  assertEquals(
    smartEventSubscribersForRound(rows, round({ gameAverages: [2650] })),
    ["gm", "im"],
  );
});

Deno.test("the round's boards are only needed when a level is set", () => {
  assertEquals(
    smartEventsNeedGameAverages([sub({ formats: ["rapid"] })]),
    false,
  );
  assertEquals(
    smartEventsNeedGameAverages([sub(), sub({ min_elo: 2500 })]),
    true,
  );
  assertEquals(smartEventsNeedGameAverages([sub({ max_elo: 2400 })]), true);
});

Deno.test("sections share a start slot the way the producer keys it: by the rounded second", () => {
  assertEquals(
    sameRoundStartSlot(
      "2026-10-16T15:32:31.387+00:00",
      "2026-10-16T15:32:31.112+00:00",
    ),
    true,
  );
  assertEquals(
    sameRoundStartSlot("2026-10-16T15:32:31.000Z", "2026-10-16T17:32:31+02:00"),
    true,
  );
  assertEquals(
    sameRoundStartSlot("2026-10-16T15:32:31.387Z", "2026-10-16T15:32:32.600Z"),
    false,
  );
  assertEquals(
    sameRoundStartSlot("2026-10-16T15:30:00Z", "2026-10-16T16:30:00Z"),
    false,
  );
  assertEquals(sameRoundStartSlot(null, "2026-10-16T15:30:00Z"), false);
  assertEquals(sameRoundStartSlot("not a date", "not a date"), false);
});

Deno.test("time control is the event's bucket, read as the app's smart event query reads it", () => {
  assertEquals(smartEventTimeControlOf("standard"), "classical");
  assertEquals(smartEventTimeControlOf(" Classical "), "classical");
  assertEquals(smartEventTimeControlOf("Rapid"), "rapid");
  assertEquals(smartEventTimeControlOf("blitz"), "blitz");
  assertEquals(smartEventTimeControlOf("bullet"), "blitz");
  assertEquals(smartEventTimeControlOf(null), null);
  assertEquals(smartEventTimeControlOf("90 min + 30 sec / move"), null);
});

Deno.test("a standard event's blitz section reaches a Classical smart event, not a Blitz one", () => {
  // Group bucket "standard", section clock 3+2: the app lists these games
  // under the Classical smart event, so its round must notify there.
  const timeControl = smartEventTimeControlOf("standard");
  const classical = sub({ user_id: "c", formats: ["standard", "live"] });
  const blitz = sub({ user_id: "b", formats: ["blitz", "live"] });
  assertEquals(
    smartEventSubscribersForRound(
      [classical, blitz],
      round({ timeControl, phase: "start" }),
    ),
    ["c"],
  );
});

Deno.test("an event with no bucket reaches only smart events with no time control", () => {
  const timeControl = smartEventTimeControlOf(null);
  assertEquals(
    smartEventSubscribersForRound(
      [sub({ user_id: "any" }), sub({ user_id: "rapid", formats: ["rapid"] })],
      round({ timeControl }),
    ),
    ["any"],
  );
});
