/**
 * Run: deno test supabase/functions/onesignal-dispatch/smart_event_match_test.ts
 */
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  smartEventAverageRating,
  smartEventMatchesRound,
  type SmartEventRound,
  smartEventsNeedGameAverages,
  smartEventSubscribersForRound,
  type SmartEventSubscription,
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
