/**
 * Run: deno test --allow-read supabase/functions/prep-games-check/counts_test.ts
 */
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  chessComTotals,
  gamesOver,
  lichessReadings,
  outboxRow,
  planChecks,
  type Reading,
  type WatchRow,
} from "./counts.ts";

Deno.test("Lichess counts standard speeds, never variants or puzzles", () => {
  // The shape `POST /api/users` answered with on 2026-10-17.
  const readings = lichessReadings(["drnykterstein", "gone", "closed"], [
    {
      id: "drnykterstein",
      perfs: {
        ultraBullet: { games: 92 },
        bullet: { games: 9585 },
        blitz: { games: 609 },
        rapid: { games: 0 },
        chess960: { games: 129 },
        atomic: { games: 25 },
        puzzle: { games: 400 },
      },
    },
    { id: "closed", disabled: true },
    { id: "nobody-asked", perfs: { blitz: { games: 1 } } },
  ]);
  assertEquals(readings.get("drnykterstein"), {
    kind: "totals",
    totals: { ultrabullet: 92, bullet: 9585, blitz: 609, rapid: 0 },
  });
  assertEquals(readings.get("gone"), { kind: "missing" });
  assertEquals(readings.get("closed"), { kind: "missing" });
  assertEquals(readings.has("nobody-asked"), false);
});

Deno.test("Chess.com adds up each class's record; Daily is correspondence", () => {
  // Hikaru's /stats on 2026-10-17, trimmed.
  const totals = chessComTotals({
    chess_daily: { record: { win: 73, loss: 11, draw: 4 } },
    chess960_daily: { record: { win: 1, loss: 2, draw: 0 } },
    chess_rapid: { record: { win: 205, loss: 69, draw: 220 } },
    chess_bullet: { record: { win: 17074, loss: 2503, draw: 1171 } },
    chess_blitz: { record: { win: 35960, loss: 5538, draw: 4372 } },
    tactics: { highest: { rating: 3000 } },
  });
  assertEquals(totals, {
    correspondence: 88,
    rapid: 494,
    bullet: 20748,
    blitz: 45870,
  });
});

Deno.test("an account's games follow the clocks it downloads", () => {
  const totals = { bullet: 10, blitz: 5, rapid: 2 };
  assertEquals(gamesOver(totals, []), 17);
  assertEquals(gamesOver(totals, ["blitz", "rapid"]), 7);
  // Chess.com has no classical class: none of those games, ever.
  assertEquals(gamesOver(totals, ["classical"]), 0);
});

function row(overrides: Partial<WatchRow>): WatchRow {
  return {
    id: "row",
    user_id: "user",
    profile_id: "opponent-1",
    profile_name: "Hikaru Nakamura",
    source: "chesscom",
    username: "Hikaru",
    time_controls: ["blitz"],
    baseline_games: 100,
    local_date: "2026-10-17",
    daily: true,
    ...overrides,
  };
}

const totals = (blitz: number): Reading => ({
  kind: "totals",
  totals: { blitz, bullet: 999 },
});

Deno.test("a grown total is news, once per profile across its accounts", () => {
  const rows = [
    row({ id: "a", baseline_games: 100 }),
    row({ id: "b", source: "lichess", username: "x", baseline_games: 40 }),
    row({ id: "c", profile_id: "opponent-2", baseline_games: 7 }),
  ];
  const readings: Record<string, Reading> = {
    a: totals(103),
    b: totals(42),
    c: totals(7),
  };
  const { checks, notices } = planChecks(rows, (r) => readings[r.id]);
  assertEquals(notices, [{
    user_id: "user",
    profile_id: "opponent-1",
    profile_name: "Hikaru Nakamura",
    added: 5,
    local_date: "2026-10-17",
  }]);
  assertEquals(
    checks.map((c) => [c.id, c.games, c.checked_on]),
    [["a", 103, "2026-10-17"], ["b", 42, "2026-10-17"], [
      "c",
      7,
      "2026-10-17",
    ]],
  );
});

Deno.test("a first total is only remembered", () => {
  const { checks, notices } = planChecks(
    [row({ baseline_games: null, daily: false })],
    () => totals(50),
  );
  assertEquals(notices, []);
  assertEquals(checks, [{
    id: "row",
    games: 50,
    checked_on: null,
    time_controls: ["blitz"],
  }]);
});

Deno.test("outside the daily check a known account is left alone", () => {
  const { checks, notices } = planChecks(
    [row({ daily: false })],
    () => totals(150),
  );
  assertEquals(checks, []);
  assertEquals(notices, []);
});

Deno.test("an unread account waits; a gone one closes the day quietly", () => {
  const unread = planChecks([row({})], () => undefined);
  assertEquals(unread, { checks: [], notices: [] });

  const gone = planChecks([row({})], () => ({ kind: "missing" }));
  assertEquals(gone.notices, []);
  assertEquals(gone.checks, [{
    id: "row",
    games: null,
    checked_on: "2026-10-17",
    time_controls: ["blitz"],
  }]);
});

Deno.test("a total that fell moves the baseline without a push", () => {
  const { checks, notices } = planChecks([row({})], () => totals(90));
  assertEquals(notices, []);
  assertEquals(checks[0].games, 90);
});

Deno.test("one outbox row per profile per day", () => {
  const queued = outboxRow({
    user_id: "u",
    profile_id: "opponent-1",
    profile_name: "Hikaru",
    added: 12,
    local_date: "2026-10-17",
  });
  assertEquals(queued.event_type, "prep_games_added");
  assertEquals(
    queued.dedupe_key,
    "prep_games_added:u:opponent-1:2026-10-17",
  );
  assertEquals(queued.payload.added, 12);
});
