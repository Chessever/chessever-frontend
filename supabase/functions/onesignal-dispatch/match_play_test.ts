/**
 * Match-play knockout rounds: which boards may be called live, which readers
 * a heads-up may name. Fixtures are production rows: SCC XI Round of 16 (tour
 * fqCjSUpE, round 60IswAYI) on 2026-11-16, EWC 2026 Grand Final (ohv5F74c)
 * and Quarterfinals Match 1 & 2 (sUYv1kXr), Dutch Ch. 2026 Round 4.Tiebreaks
 * (LLiWXZe6).
 * Run: deno test supabase/functions/onesignal-dispatch/match_play_test.ts
 */
import {
  assert,
  assertEquals,
  assertStrictEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  boardHasStarted,
  groupMatches,
  hasRepeatedPair,
  headsUpBoardScope,
  headsUpReaders,
  isKnockoutTour,
  isLiveBoard,
  isMatchPlayRound,
  isPlayerKnockoutFormat,
  isTeamTour,
  knockoutFactsFromTour,
  liveBoardIds,
  matchPairKeys,
  type MatchPlayBoard,
  readersWithLiveFavorite,
  roundStartBoardScope,
} from "./match_play.ts";
import {
  boardsForFavorite,
  coveredBoardsByUser,
  gameStartWindowFamily,
  indexRoundBoards,
  planRoundStartBoards,
  type RoundBoardRow,
  splitRoundRecipients,
} from "./player_game_recipients.ts";

const SCC_FORMAT =
  "16-player single-elimination knockout, with a consolation match";
const SCC = {
  format: SCC_FORMAT,
  tourName: "Speed Chess Championship XI (2026–27)",
  roundName: "Round of 16",
};

type Row = RoundBoardRow & MatchPlayBoard & { board_nr: number };

function board(
  id: string,
  boardNr: number,
  white: string,
  black: string,
  fide: [string, string],
  status: string,
  moved: boolean,
  dateStart = "2026-11-16",
): Row {
  return {
    id,
    board_nr: boardNr,
    player_white: white,
    player_black: black,
    // PostgREST hands these back as strings, sorted, not white/black.
    player_fide_ids: [...fide].sort(),
    players: [
      { name: white, fideId: Number(fide[0]), team: null },
      { name: black, fideId: Number(fide[1]), team: null },
    ],
    status,
    last_move: moved ? "e2e4" : null,
    last_move_time: moved ? "2026-11-16T17:14:54.535Z" : null,
    date_start: dateStart,
  };
}

/** Production at ~17:20: game 1 drawn, game 2 of Nakamura-Erdogmus live. */
// deno-fmt-ignore
const SCC_R16: Row[] = [
  board("60IswAYI-pq36vc", 1, "Nakamura, Hikaru", "Erdogmus, Yagiz Kaan", ["2016192", "44599790"], "1/2-1/2", true),
  board("60IswAYI-src7cv", 2, "Carlsen, Magnus", "Movahed, Sina", ["1503014", "42520835"], "*", false),
  board("60IswAYI-1iw36s7", 3, "Abdusattorov, Nodirbek", "Keymer, Vincent", ["14204118", "12940690"], "*", false),
  board("60IswAYI-ck9pdy", 4, "Nihal Sarin", "Niemann, Hans Moke", ["25092340", "2093596"], "*", false),
  board("60IswAYI-78pcxs", 5, "Firouzja, Alireza", "Artemiev, Vladislav", ["12573981", "24101605"], "*", false),
  board("60IswAYI-um9vyy", 6, "Caruana, Fabiano", "Sindarov, Javokhir", ["2020009", "14205483"], "*", false),
  board("60IswAYI-1lcthoy", 7, "Lazavik, Denis", "Andreikin, Dmitry", ["13515110", "4158814"], "*", false),
  board("60IswAYI-1siueax", 8, "So, Wesley", "Praggnanandhaa R", ["5202213", "25059530"], "*", false),
  board("60IswAYI-67v3yr", 9, "Niemann, Hans Moke", "Nihal Sarin", ["2093596", "25092340"], "*", false),
  board("60IswAYI-1fw7jih", 10, "Andreikin, Dmitry", "Lazavik, Denis", ["4158814", "13515110"], "*", false),
  board("60IswAYI-1a45jh4", 11, "Movahed, Sina", "Carlsen, Magnus", ["42520835", "1503014"], "*", false),
  board("60IswAYI-1md2dlh", 12, "Erdogmus, Yagiz Kaan", "Nakamura, Hikaru", ["44599790", "2016192"], "*", true),
  board("60IswAYI-1i7jwd7", 13, "Artemiev, Vladislav", "Firouzja, Alireza", ["24101605", "12573981"], "*", false),
  board("60IswAYI-1igry3e", 14, "Praggnanandhaa R", "So, Wesley", ["25059530", "5202213"], "*", false),
  board("60IswAYI-w84g18", 15, "Keymer, Vincent", "Abdusattorov, Nodirbek", ["12940690", "14204118"], "*", false),
  board("60IswAYI-166s5u7", 16, "Sindarov, Javokhir", "Caruana, Fabiano", ["14205483", "2020009"], "*", false),
];

/** The same round at 17:00, when round_started dispatched: game 1 in play. */
const SCC_R16_AT_START: Row[] = SCC_R16.map((row) =>
  row.id === "60IswAYI-pq36vc"
    ? { ...row, status: "*" }
    : row.id === "60IswAYI-1md2dlh"
    ? { ...row, last_move: null, last_move_time: null }
    : row
);

/** Game 01.03 (Nakamura White) inserted mid-file; the ingest renumbered. */
// deno-fmt-ignore
const SCC_R16_RENUMBERED: Row[] = [
  ...SCC_R16.slice(0, 4).map((row) => ({ ...row, board_nr: row.board_nr + 1 })),
  board("chess.com:187347521148", 1, "Nakamura, Hikaru", "Erdogmus, Yagiz Kaan", ["2016192", "44599790"], "*", true),
  ...SCC_R16.slice(4).map((row) => ({ ...row, board_nr: row.board_nr + 1 })),
];

/** A normal Swiss round: eight different pairs, every board under way. */
// deno-fmt-ignore
const SWISS_ROUND: Row[] = [
  board("swiss-1", 1, "Gukesh D", "Firouzja, Alireza", ["46616543", "12573981"], "*", true),
  board("swiss-2", 2, "Caruana, Fabiano", "So, Wesley", ["2020009", "5202213"], "*", false),
  board("swiss-3", 3, "Giri, Anish", "Aronian, Levon", ["24116068", "13300474"], "*", true),
  board("swiss-4", 4, "Keymer, Vincent", "Erigaisi Arjun", ["12940690", "35009192"], "1-0", true),
];

Deno.test("the SCC format is a player knockout; teams and non-knockouts are not", () => {
  assertEquals(isPlayerKnockoutFormat(SCC_FORMAT), true);
  for (
    const format of [
      "Knockout",
      "16-player knock-out",
      "16-player-knock-out",
      "206-player Single-Elimination Knockout",
      "107-player Single Elimination",
      "16-player Double Elimination",
      "16-player double knockout",
    ]
  ) {
    assertEquals(isPlayerKnockoutFormat(format), true, format);
  }
  for (
    const format of [
      "4-team knockout",
      "4-teams Knockout",
      "Team knockout tournament",
      "2-player match",
      "12-game Match",
      "9-round Swiss",
      "Round Robin",
      "",
      null,
      undefined,
    ]
  ) {
    assertEquals(isPlayerKnockoutFormat(format), false, String(format));
  }
});

Deno.test("SCC R16 is a match-play round: eight pairs, two games each", () => {
  assertEquals(hasRepeatedPair(SCC_R16), true);
  assertEquals(isMatchPlayRound(SCC, SCC_R16), true);
  const pairs = new Set(SCC_R16.map((row) => matchPairKeys(row).fide));
  assertEquals(pairs.size, 8);
});

Deno.test("the pair key ignores colour, board order and FIDE id order", () => {
  const game1 = matchPairKeys(SCC_R16[0]);
  const game2 = matchPairKeys(SCC_R16[11]);
  assertEquals(game1, game2);
  assertEquals(game1.fide, "2016192|44599790");
});

Deno.test("renumbered boards and a mid-file game 3 change nothing", () => {
  assertEquals(isMatchPlayRound(SCC, SCC_R16_RENUMBERED), true);
  const reversed = [...SCC_R16_RENUMBERED].reverse();
  assertEquals(hasRepeatedPair(reversed), true);
  assertEquals(
    liveBoardIds(SCC_R16_RENUMBERED),
    new Set(["chess.com:187347521148", "60IswAYI-1md2dlh"]),
  );
});

Deno.test("names decide when a board lacks FIDE ids", () => {
  const noFide = SCC_R16.map((row) => ({ ...row, player_fide_ids: null }));
  assertEquals(hasRepeatedPair(noFide), true);

  // Game 1 carries FIDE ids, game 2 does not: still the same match.
  assertEquals(
    hasRepeatedPair([SCC_R16[0], { ...SCC_R16[11], player_fide_ids: [] }]),
    true,
  );

  // Same names, different FIDE pairs: namesakes, not a match.
  assertEquals(
    hasRepeatedPair([
      board("a", 1, "Kumar, A", "Singh, R", ["1001", "1002"], "*", false),
      board("b", 2, "Singh, R", "Kumar, A", ["2001", "2002"], "*", false),
    ]),
    false,
  );
});

Deno.test("one game per pair is not match-play, whatever the format", () => {
  const gameOnes = SCC_R16.slice(0, 8);
  assertEquals(hasRepeatedPair(gameOnes), false);
  assertEquals(isMatchPlayRound(SCC, gameOnes), false);
  assertEquals(
    isMatchPlayRound({ format: "9-round Swiss" }, SWISS_ROUND),
    false,
  );
  assertEquals(isMatchPlayRound(SCC, SWISS_ROUND), false);
});

Deno.test("a repeated pair outside a player knockout is not match-play", () => {
  // Ghost generations of one board (an ingest duplicate) in a team league.
  const ghosts = [...SWISS_ROUND, { ...SWISS_ROUND[0], id: "swiss-1-ghost" }];
  assertEquals(hasRepeatedPair(ghosts), true);
  assertEquals(isMatchPlayRound({ format: "Team league" }, ghosts), false);
  assertEquals(isMatchPlayRound({ format: "4-team knockout" }, ghosts), false);
  assertEquals(isMatchPlayRound({ format: "2-player match" }, SCC_R16), false);
});

Deno.test("a 0-move shell has not started and is not live", () => {
  const shell = SCC_R16[1];
  assertEquals(boardHasStarted(shell), false);
  assertEquals(isLiveBoard(shell), false);
  assertEquals(isLiveBoard(SCC_R16[11]), true);
  // Finished: started, but no longer live.
  assertEquals(boardHasStarted(SCC_R16[0]), true);
  assertEquals(isLiveBoard(SCC_R16[0]), false);
  // A move with no timestamp still counts as a start.
  assertEquals(
    boardHasStarted({ ...shell, last_move: "d2d4", last_move_time: null }),
    true,
  );
  assertEquals(boardHasStarted({ ...shell, last_move: "  " }), false);
});

Deno.test("round_started at 17:00 announces Nakamura-Erdogmus game 1 only", () => {
  const live = liveBoardIds(SCC_R16_AT_START);
  assertEquals(live, new Set(["60IswAYI-pq36vc"]));

  const scope = roundStartBoardScope(
    isMatchPlayRound(SCC, SCC_R16_AT_START),
    live,
  );
  const announced = SCC_R16_AT_START.map((row) => row.id).filter((id) =>
    scope === null || scope.has(id)
  );
  // Production sent all 16, including 14 boards of 7 unstarted matches.
  assertEquals(announced, ["60IswAYI-pq36vc"]);
});

Deno.test("at 17:20 only game 2 is live; the drawn game 1 is not re-announced", () => {
  assertEquals(liveBoardIds(SCC_R16), new Set(["60IswAYI-1md2dlh"]));
});

Deno.test("a non-match-play round keeps every paired board in scope", () => {
  assertEquals(roundStartBoardScope(false, liveBoardIds(SWISS_ROUND)), null);
  // Even with no board live: today's fan-out is untouched.
  assertEquals(roundStartBoardScope(false, new Set()), null);
});

// ---------------------------------------------------------------------------
// round_started wiring: the production index (indexRoundBoards,
// playerBoardKey via boardsForFavorite), the preference split and the
// per-board plan, on the round as it stood at ~17:50.
// ---------------------------------------------------------------------------

const LIVE_GAME_4 = "chess.com:187348254664";

/** Production at ~17:50: 18 games; game 4 (Erdogmus White) live. */
// deno-fmt-ignore
const SCC_R16_NOW: Row[] = [
  ...SCC_R16.map((row) =>
    row.id === "60IswAYI-1md2dlh" ? { ...row, status: "0-1" } : row
  ),
  board("chess.com:187347521148", 17, "Nakamura, Hikaru", "Erdogmus, Yagiz Kaan", ["2016192", "44599790"], "1-0", true),
  board(LIVE_GAME_4, 18, "Erdogmus, Yagiz Kaan", "Nakamura, Hikaru", ["44599790", "2016192"], "*", true),
];

const FAVORITES = new Map<string, string[]>([
  ["u-nakamura", ["Nakamura, Hikaru"]],
  // The name as the favorite map hands it back, spaced and cased otherwise.
  ["u-erdogmus", ["  ERDOGMUS, Yagiz Kaan "]],
  ["u-carlsen", ["Carlsen, Magnus"]],
  ["u-carlsen-star", ["Carlsen, Magnus"]],
  ["u-told", ["Nakamura, Hikaru"]],
  ["u-unresolved", []],
]);
const PLAYER_READERS = new Set(FAVORITES.keys());

function roundStartRun(
  rows: Row[],
  eventStars: Set<string>,
  windows: Array<{ user_id: string; family: string }>,
  boardsSent: string[] = [],
) {
  const index = indexRoundBoards(rows);
  const scope = roundStartBoardScope(
    isMatchPlayRound(SCC, rows),
    liveBoardIds(rows),
    boardsSent,
  );
  const covered = coveredBoardsByUser(windows);
  const readers = scope
    ? readersWithLiveFavorite(
      PLAYER_READERS,
      FAVORITES,
      boardsForFavorite(index.playerGameIds),
      scope,
      covered,
    )
    : PLAYER_READERS;
  const split = splitRoundRecipients(eventStars, readers, new Map(), null);
  const plan = planRoundStartBoards({
    playerRecipients: split.playerRecipients,
    favoriteNames: FAVORITES,
    playerGameIds: index.playerGameIds,
    roundBoards: index.roundBoards,
    liveBoardScope: scope,
    coveredBoards: covered,
  });
  return { scope, split, plan };
}

Deno.test("round_started at 17:50: the live game 4 reaches only its players' readers", () => {
  const { scope, split, plan } = roundStartRun(
    SCC_R16_NOW,
    new Set(["u-carlsen-star", "u-event-only"]),
    // u-told already got game 4 from its own game_started row.
    [{ user_id: "u-told", family: gameStartWindowFamily(LIVE_GAME_4) }],
  );
  assertEquals(scope, new Set([LIVE_GAME_4]));
  assertEquals(
    new Set(split.playerRecipients),
    new Set(["u-nakamura", "u-erdogmus", "u-told"]),
  );
  // Carlsen's match is weeks away: his follower who stars the event gets the
  // event-level copy, the one who does not gets nothing.
  assertEquals(
    new Set(split.eventRecipients),
    new Set(["u-carlsen-star", "u-event-only"]),
  );
  assertEquals(
    plan.boardBatches,
    new Map([[LIVE_GAME_4, ["u-nakamura", "u-erdogmus"]]]),
  );
  assertEquals(plan.unresolved, []);
  assertEquals(plan.reached, new Set(["u-nakamura", "u-erdogmus"]));
});

Deno.test("a resumed run after game 4 finished sends nothing twice and adds no event copy", () => {
  // The first run sent game 4 (window recorded, boards_sent) and timed out
  // before the event-level send; game 4 then finished.
  const finished = SCC_R16_NOW.map((row) =>
    row.id === LIVE_GAME_4 ? { ...row, status: "0-1" } : row
  );
  const windows = ["u-nakamura", "u-erdogmus", "u-told"].map((user_id) => ({
    user_id,
    family: gameStartWindowFamily(LIVE_GAME_4),
  }));
  const { scope, split, plan } = roundStartRun(
    finished,
    new Set(["u-nakamura", "u-carlsen-star"]),
    windows,
    [LIVE_GAME_4],
  );
  assertEquals([...liveBoardIds(finished)], []);
  assertEquals(scope, new Set([LIVE_GAME_4]));
  // Still on the board path, where game 4 is skipped: not on the event path.
  assert(split.playerRecipients.includes("u-nakamura"));
  assertEquals(split.eventRecipients, ["u-carlsen-star"]);
  assertEquals(plan.boardBatches.size, 0);
  assertEquals(plan.unresolved, []);
});

Deno.test("a covered reader stays off the event path even with no board in scope", () => {
  // game_started told u-told about game 4, which finished before the
  // round_started row ran: no board is live, nothing was sent by this row.
  const finished = SCC_R16_NOW.map((row) =>
    row.id === LIVE_GAME_4 ? { ...row, status: "0-1" } : row
  );
  const { split, plan } = roundStartRun(
    finished,
    new Set(["u-told"]),
    [{ user_id: "u-told", family: gameStartWindowFamily(LIVE_GAME_4) }],
  );
  assertEquals(split.playerRecipients, ["u-told"]);
  assertEquals(split.eventRecipients, []);
  assertEquals(plan.boardBatches.size, 0);
  assertEquals(plan.reached.size, 0);
});

Deno.test("round_started at 17:00 sends game 1 only, even to a Carlsen and Nakamura reader", () => {
  const index = indexRoundBoards(SCC_R16_AT_START);
  const scope = roundStartBoardScope(true, liveBoardIds(SCC_R16_AT_START));
  const favorites = new Map([["u-both", [
    "Carlsen, Magnus",
    "Nakamura, Hikaru",
  ]]]);
  const plan = planRoundStartBoards({
    playerRecipients: ["u-both"],
    favoriteNames: favorites,
    playerGameIds: index.playerGameIds,
    roundBoards: index.roundBoards,
    liveBoardScope: scope,
    coveredBoards: new Map(),
  });
  assertEquals(plan.boardBatches, new Map([["60IswAYI-pq36vc", ["u-both"]]]));
});

Deno.test("the board index takes the JSONB spelling too", () => {
  const rows = [{
    ...SCC_R16_NOW[0],
    players: [{ name: "Hikaru Nakamura" }, { name: "Yagiz Kaan Erdogmus" }],
  }];
  const boardsFor = boardsForFavorite(indexRoundBoards(rows).playerGameIds);
  assertEquals(boardsFor("Hikaru Nakamura"), new Set(["60IswAYI-pq36vc"]));
  assertEquals(boardsFor(" nakamura, hikaru"), new Set(["60IswAYI-pq36vc"]));
});

Deno.test("outside match-play the plan is today's: shells announced, unresolved fall back", () => {
  const index = indexRoundBoards(SWISS_ROUND);
  const favorites = new Map([
    ["u-caruana", ["Caruana, Fabiano"]],
    ["u-unresolved", ["Somebody, Else"]],
    ["u-told", ["Giri, Anish"]],
  ]);
  const plan = planRoundStartBoards({
    playerRecipients: ["u-caruana", "u-unresolved", "u-told"],
    favoriteNames: favorites,
    playerGameIds: index.playerGameIds,
    roundBoards: index.roundBoards,
    liveBoardScope: roundStartBoardScope(false, liveBoardIds(SWISS_ROUND)),
    coveredBoards: coveredBoardsByUser([
      { user_id: "u-told", family: gameStartWindowFamily("swiss-3") },
    ]),
  });
  // swiss-2 has no move yet and is still announced, as before.
  assertEquals(plan.boardBatches, new Map([["swiss-2", ["u-caruana"]]]));
  assertEquals(plan.unresolved, ["u-unresolved"]);
  assertEquals(plan.reached, new Set(["u-caruana", "u-unresolved"]));
});

Deno.test("pinned: a stage holding only game-1 shells is not match-play yet", () => {
  // The literal gate needs a pair with 2+ games. A quarterfinal published
  // with game 1 of each match only keeps today's fan-out until game 2 of
  // some match is in the round.
  const gameOnes = SCC_R16_AT_START.slice(0, 8);
  assertEquals(isMatchPlayRound(SCC, gameOnes), false);
  const index = indexRoundBoards(gameOnes);
  const plan = planRoundStartBoards({
    playerRecipients: ["u-carlsen"],
    favoriteNames: FAVORITES,
    playerGameIds: index.playerGameIds,
    roundBoards: index.roundBoards,
    liveBoardScope: roundStartBoardScope(false, liveBoardIds(gameOnes)),
    coveredBoards: new Map(),
  });
  assertEquals(
    plan.boardBatches,
    new Map([["60IswAYI-src7cv", ["u-carlsen"]]]),
  );
});

// ---------------------------------------------------------------------------
// round_heads_up: whom it may name.
// ---------------------------------------------------------------------------

/** SCC R16 at 16:30: every board a shell, published on 11-14. */
const SCC_R16_AT_HEADS_UP: Row[] = SCC_R16.map((row) => ({
  ...row,
  status: "*",
  last_move: null,
  last_move_time: null,
  date_start: "2026-11-14",
}));

/** tours.info.matchSchedule of fqCjSUpE (six of eight matches dated). */
const SCC_SCHEDULE = [
  ["2016192", "44599790", "2026-11-16T17:00:00Z"],
  ["13515110", "4158814", "2026-11-20T17:00:00Z"],
  ["12573981", "24101605", "2026-11-27T17:30:00Z"],
  ["5202213", "25059530", "2026-12-09T15:00:00Z"],
  ["1503014", "42520835", "2026-12-16T14:00:00Z"],
  ["2020009", "14205483", "2026-12-16T17:30:00Z"],
].map(([a, b, startsAt]) => ({
  fideIds: [a, b],
  roundId: "60IswAYI",
  startsAt,
  sourceUrl:
    "https://www.chess.com/events/2026-speed-chess-championship/schedule",
}));

/** EWC 2026 Grand Final (ohv5F74c) before 13:30: games 1-2 of one match. */
// deno-fmt-ignore
const EWC_GRAND_FINAL: Row[] = [
  board("mJnv1YBU", 1, "Carlsen, Magnus", "Lazavik, Denis", ["1503014", "13515110"], "*", false, "2026-08-15"),
  board("1UDI2Flj", 2, "Lazavik, Denis", "Carlsen, Magnus", ["13515110", "1503014"], "*", false, "2026-08-15"),
];

/** Dutch Ch. 2026 Round 4.Tiebreaks (LLiWXZe6): a placeholder from 06-09. */
// deno-fmt-ignore
const DUTCH_R4_TIEBREAK: Row[] = [
  board("4qlrYx0x", 1, "Tiviakov, Sergei", "Vrolijk, Liam", ["1008013", "1048333"], "*", false, "2026-06-09"),
  board("t5KIGHYA", 2, "Vrolijk, Liam", "Tiviakov, Sergei", ["1048333", "1008013"], "*", false, "2026-07-11"),
];

/** EWC 2026 QF "Match 1 & 2" (sUYv1kXr) before 11:00: two same-day matches. */
// deno-fmt-ignore
const EWC_QF_MATCH_1_2: Row[] = [
  board("Ft1ZyICD", 1, "Nakamura, Hikaru", "Erigaisi Arjun", ["2016192", "35009192"], "*", false, "2026-08-14"),
  board("dBEetIX1", 2, "Abdusattorov, Nodirbek", "Lazavik, Denis", ["14204118", "13515110"], "*", false, "2026-08-14"),
  board("AOXTTkQk", 3, "Lazavik, Denis", "Abdusattorov, Nodirbek", ["13515110", "14204118"], "*", false, "2026-08-14"),
  board("I4BuUCfb", 4, "Erigaisi Arjun", "Nakamura, Hikaru", ["35009192", "2016192"], "*", false, "2026-08-14"),
];

function scopeFor(
  rows: Row[],
  facts: Parameters<typeof isMatchPlayRound>[0],
  startsAt: string,
  matchSchedule: unknown = null,
) {
  return headsUpBoardScope({
    matchPlay: isMatchPlayRound(facts, rows),
    boards: rows,
    roundId: "60IswAYI",
    startsAt,
    matchSchedule,
  });
}

Deno.test("heads-up of a one-match round names the players (EWC Grand Final, Dutch R4 tiebreak)", () => {
  const ewc = { format: "8-player Knockout", roundName: "Grand Final" };
  assertEquals(isMatchPlayRound(ewc, EWC_GRAND_FINAL), true);
  assertEquals(scopeFor(EWC_GRAND_FINAL, ewc, "2026-08-15T13:30:00Z"), null);

  const dutch = {
    format: "16-player knock-out",
    roundName: "Round 4.Tiebreaks",
  };
  assertEquals(isMatchPlayRound(dutch, DUTCH_R4_TIEBREAK), true);
  assertEquals(
    scopeFor(DUTCH_R4_TIEBREAK, dutch, "2026-07-11T14:15:00Z"),
    null,
  );

  // No scope: the very same reader set and favorite names as before.
  const players = new Set(["u-carlsen", "u-lazavik"]);
  const favorites = new Map([["u-carlsen", ["Carlsen, Magnus"]]]);
  const readers = headsUpReaders(
    null,
    players,
    favorites,
    boardsForFavorite(indexRoundBoards(EWC_GRAND_FINAL).playerGameIds),
  );
  assertStrictEquals(readers.playerUserIds, players);
  assertStrictEquals(readers.favoriteNames, favorites);
});

Deno.test("heads-up of same-day matches names every player (EWC quarterfinals)", () => {
  const ewc = {
    format: "8-player Knockout",
    roundName: "Quarterfinals | Match 1 & 2",
  };
  assertEquals(isMatchPlayRound(ewc, EWC_QF_MATCH_1_2), true);
  assertEquals(groupMatches(EWC_QF_MATCH_1_2).length, 2);
  assertEquals(scopeFor(EWC_QF_MATCH_1_2, ewc, "2026-08-14T11:00:00Z"), null);
});

Deno.test("heads-up names nobody when the shells were published days ahead (SCC, no schedule)", () => {
  const scope = scopeFor(SCC_R16_AT_HEADS_UP, SCC, "2026-11-16T17:00:00Z");
  assertEquals(scope, new Set());
  const readers = headsUpReaders(
    scope,
    new Set(["u-carlsen", "u-nakamura"]),
    new Map([["u-carlsen", ["Carlsen, Magnus"]], ["u-nakamura", [
      "Nakamura, Hikaru",
    ]]]),
    boardsForFavorite(indexRoundBoards(SCC_R16_AT_HEADS_UP).playerGameIds),
  );
  assertEquals(readers.playerUserIds.size, 0);
  // One stale shell is not "published ahead" (Dutch, DreamHack placeholders).
  const oneStale = SCC_R16_AT_HEADS_UP.map((row) =>
    row.id === "60IswAYI-src7cv" ? row : { ...row, date_start: "2026-11-16" }
  );
  assertEquals(scopeFor(oneStale, SCC, "2026-11-16T17:00:00Z"), null);
  // A day of slack for PGN dates in local time.
  const dayBefore = SCC_R16_AT_HEADS_UP.map((row) => ({
    ...row,
    date_start: "2026-11-15",
  }));
  assertEquals(scopeFor(dayBefore, SCC, "2026-11-16T17:00:00Z"), null);
});

Deno.test("heads-up with the curated schedule names only the match starting now", () => {
  const scope = scopeFor(
    SCC_R16_AT_HEADS_UP,
    SCC,
    "2026-11-16T17:00:00Z",
    SCC_SCHEDULE,
  );
  assertEquals(scope, new Set(["60IswAYI-pq36vc", "60IswAYI-1md2dlh"]));

  const readers = headsUpReaders(
    scope,
    new Set(["u-nakamura", "u-carlsen", "u-carlsen-nakamura"]),
    new Map([
      ["u-nakamura", ["Nakamura, Hikaru"]],
      ["u-carlsen", ["Carlsen, Magnus"]],
      ["u-carlsen-nakamura", ["Carlsen, Magnus", "Nakamura, Hikaru"]],
    ]),
    boardsForFavorite(indexRoundBoards(SCC_R16_AT_HEADS_UP).playerGameIds),
  );
  assertEquals(
    readers.playerUserIds,
    new Set(["u-nakamura", "u-carlsen-nakamura"]),
  );
  // "Nakamura at the board", not "Carlsen & Nakamura".
  assertEquals(readers.favoriteNames.get("u-carlsen-nakamura"), [
    "Nakamura, Hikaru",
  ]);

  // A start the schedule does not list names nobody.
  assertEquals(
    scopeFor(SCC_R16_AT_HEADS_UP, SCC, "2026-11-18T17:00:00Z", SCC_SCHEDULE),
    new Set(),
  );
});

// ---------------------------------------------------------------------------
// The knockout and team checks, as the app makes them.
// ---------------------------------------------------------------------------

/** One team-tagged board pair, played twice (or a shadow duplicate). */
function teamBoards(teamA: string, teamB: string): Row[] {
  return ["t-1", "t-2"].map((id, index) => ({
    ...board(id, index + 1, "Jatakk", "sachinpro", ["1", "2"], "*", false),
    player_fide_ids: null,
    players: [{ name: "Jatakk", team: teamA }, {
      name: "sachinpro",
      team: teamB,
    }],
  }));
}

Deno.test("a team knockout with a bare format stays out (corporate brackets, xec93ZPP)", () => {
  const facts = knockoutFactsFromTour({
    name: "FIDE World Corporate Chess Championship 2025 | Online Knockouts",
    info: { format: "Knockout" },
    players: Array.from({ length: 10 }, (_, i) => ({
      name: `p${i}`,
      team: i % 2 ? "Google C" : "Microsoft A",
    })),
  });
  assertEquals(facts.format, "Knockout");
  assertEquals(facts.rosterTeams?.length, 10);
  const boards = teamBoards("Microsoft A", "Google C");
  assertEquals(isTeamTour(facts, boards), true);
  assertEquals(isMatchPlayRound(facts, boards), false);
});

Deno.test("teamTable and an official team table rule a tour out, whatever the format", () => {
  const boards = teamBoards("India", "Norway");
  const facts = knockoutFactsFromTour({
    info: { format: "16-player knockout", teamTable: true },
  });
  assertEquals(facts.teamTable, true);
  assertEquals(isMatchPlayRound(facts, boards), false);
  const official = knockoutFactsFromTour({
    info: {
      format: "Knockout",
      officialTeamStandings: { source: "chess-results" },
    },
  });
  assertEquals(official.hasOfficialTeamTable, true);
  assertEquals(isMatchPlayRound(official, SCC_R16), false);
  // teamTable false keeps an individual knockout individual.
  assertEquals(
    isMatchPlayRound({ format: "Knockout", teamTable: false }, boards),
    true,
  );
});

Deno.test("an N-player format with club-tagged players stays a player knockout", () => {
  const facts = {
    format: "206-player Single-Elimination Knockout",
    rosterTeams: ["Club A", "Club B", "Club C"],
  };
  assertEquals(isMatchPlayRound(facts, teamBoards("Club A", "Club B")), true);
});

Deno.test("teamTable on boards that only pair teammates is not a team event", () => {
  // Total Chess "Combined": teamTable on, every board "Group A" vs "Group A".
  const facts = { format: "Knockout", teamTable: true };
  const boards = [
    ...teamBoards("Group A", "Group A"),
    ...teamBoards("Group A", "Group A").map((row) => ({
      ...row,
      id: `${row.id}b`,
    })),
  ];
  assertEquals(isTeamTour(facts, boards), false);
  assertEquals(isMatchPlayRound(facts, boards), true);
});

Deno.test("a tour whose format says nothing is a knockout by its stage names", () => {
  // EWC 2026 Play-in / LCQ Playoff and China Chess King Stage 3: format null.
  for (
    const facts of [
      {
        format: null,
        tourName: "Esports World Cup 2026 | Play-in",
        roundName: "Upper | Round 1",
      },
      {
        format: null,
        tourName: "Esports World Cup 2026 | Last Chance Qualifier Playoff",
        roundName: "Lower | Round 2",
      },
      {
        format: null,
        tourName: "4th China Chess King Tournament 2026 | Stage 3 (Main Event)",
        roundName: "Quarterfinals | Tiebreaks",
      },
      { format: null, tourName: "Some Cup", roundName: "5th Place Match" },
    ]
  ) {
    assertEquals(isKnockoutTour(facts), true, JSON.stringify(facts));
    assertEquals(isMatchPlayRound(facts, EWC_QF_MATCH_1_2), true);
  }
  for (
    const facts of [
      { format: null, tourName: "Some Open 2026", roundName: "Round 5" },
      {
        format: "Cup",
        tourName: "Capechecs 2026 | Capexpress Finale",
        roundName: "Round 1",
      },
      { format: "9-round Swiss", tourName: "Open", roundName: "Final round" },
      {
        format: "2-player match",
        tourName: "Title Match",
        roundName: "Tiebreaks",
      },
      {
        format: "Double round robin",
        tourName: "Finals",
        roundName: "Round 3",
      },
      // A Grand Prix final and a series final are not elimination brackets.
      {
        format: null,
        tourName: "2025 Final Rapid Grand Prix TOP 28 Women",
        roundName: "Тур 5",
      },
      {
        format: null,
        tourName: "India Rising 2026 | Finals",
        roundName: "Set 1",
      },
    ]
  ) {
    assertEquals(isKnockoutTour(facts), false, JSON.stringify(facts));
    assertEquals(isMatchPlayRound(facts, EWC_QF_MATCH_1_2), false);
  }
});

Deno.test("names match as the app compares them: titles off, placeholders never pair", () => {
  const titled = [
    {
      ...SCC_R16[1],
      player_fide_ids: null,
      player_white: "GM Carlsen, Magnus",
    },
    { ...SCC_R16[10], player_fide_ids: null },
  ];
  assertEquals(hasRepeatedPair(titled), true);

  const placeholders = ["p-1", "p-2"].map((id, index) => ({
    ...board(
      id,
      index + 1,
      "Winner of QF1",
      "Winner of QF2",
      ["1", "2"],
      "*",
      false,
    ),
    player_fide_ids: null,
  }));
  assertEquals(hasRepeatedPair(placeholders), false);
  assertEquals(matchPairKeys(placeholders[0]), { fide: null, names: null });
  const tbd = ["q-1", "q-2"].map((id, index) => ({
    ...board(id, index + 1, "TBD", "Carlsen, Magnus", ["1", "2"], "*", false),
    player_fide_ids: null,
  }));
  assertEquals(hasRepeatedPair(tbd), false);
});
