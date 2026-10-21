/**
 * Run: deno test --allow-read supabase/functions/prep-games-check/counts_test.ts
 */
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  chessComTotals,
  gamesOver,
  lichessReadings,
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
    id: "w1",
    source: "lichess",
    username: "durarbayli",
    time_controls: ["blitz"],
    baseline_games: 100,
    ...overrides,
  };
}

function totals(blitz: number): Reading {
  return { kind: "totals", totals: { blitz, bullet: 999 } };
}

Deno.test("each read account records its total over its own clocks", () => {
  const rows = [
    row({ id: "a" }),
    row({ id: "b", source: "chesscom", time_controls: [] }),
  ];
  const checks = planChecks(rows, () => totals(103));
  assertEquals(checks, [
    { id: "a", games: 103, time_controls: ["blitz"] },
    { id: "b", games: 1102, time_controls: [] },
  ]);
});

Deno.test("an unread account waits for the next hour", () => {
  assertEquals(planChecks([row({})], () => undefined), []);
});

Deno.test("a gone account is checked, its total kept", () => {
  assertEquals(planChecks([row({})], () => ({ kind: "missing" })), [
    { id: "w1", games: null, time_controls: ["blitz"] },
  ]);
});

Deno.test("an account with no clocks of its own counts every clock", () => {
  assertEquals(
    planChecks([row({ time_controls: null })], () => totals(5))[0].games,
    1004,
  );
});
