/**
 * Run: deno test --allow-read --allow-env --allow-net=registry.npmjs.org \
 *   supabase/functions/finish-live-saved-games/finish_test.ts
 */
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  finishedResult,
  finishSavedGame,
  movesFromPgn,
  type SavedChessGame,
  type SavedMove,
  type SavedRow,
} from "./finish.ts";

const START = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

function pgn(result: string, moves: string): string {
  return [
    '[Event "Test Open"]',
    '[White "Carlsen, Magnus"]',
    '[Black "Martirosyan, Haik M."]',
    `[Result "${result}"]`,
    '[TimeControl "2700+30"]',
    "",
    `${moves} ${result}`,
  ].join("\n");
}

const LIVE = pgn(
  "*",
  "1. d4 {[%clk 0:45:37]} Nf6 {[%clk 0:45:34]} 2. c4 {[%clk 0:45:30]}",
);
const FINISHED = pgn(
  "1/2-1/2",
  "1. d4 {[%clk 0:45:37]} Nf6 {[%clk 0:45:34]} 2. c4 {[%clk 0:45:30]} " +
    "e6 {[%clk 0:45:01]} 3. Nc3 {[%clk 0:44:50]} Bb4 {[%clk 0:44:40]} " +
    "4. O-O-O?? {[%clk 0:44:00]}",
);

/** The row an app writes when the game is liked at LIVE. */
function likedAt(
  livePgn: string,
  extra: Record<string, unknown> = {},
): SavedRow {
  const parsed = movesFromPgn(livePgn)!;
  const md: Record<string, unknown> = Object.fromEntries(parsed.headers);
  md.TcCategory = "rapid";
  md.IsOnline = "false";
  Object.assign(md, extra);
  return {
    source_game_id: "ct5MTG4Y",
    chess_game: {
      id: "ct5MTG4Y",
      sf: parsed.startingFen,
      md,
      m: parsed.mainline,
    },
    variation_comments: {},
    move_nags: {},
  };
}

// 4. O-O-O is illegal here, so the finished line is cut before it, exactly as
// ChessGame.fromPgn stops at the first move it cannot play.
const FINAL_PLIES = 6;

Deno.test("moves carry the apps' JSON shape", () => {
  const parsed = movesFromPgn(LIVE)!;
  assertEquals(parsed.startingFen, START);
  assertEquals(parsed.mainline[0], {
    n: 1,
    f: "rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1",
    s: "d4",
    u: "d2d4",
    t: "white",
    ct: "0:45:37",
    e: null,
    c: ["[%clk 0:45:37]"],
  });
  assertEquals(parsed.mainline[1].n, 1);
  assertEquals(parsed.mainline[1].t, "black");
  assertEquals(parsed.mainline[2].n, 2);
});

Deno.test("castling is stored king to rook, as dartchess writes it", () => {
  const parsed = movesFromPgn(
    pgn("*", "1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. O-O"),
  )!;
  assertEquals(parsed.mainline[6].u, "e1h1");
});

Deno.test("a game liked live gains the moves played after the like", () => {
  const row = likedAt(LIVE);
  const done = finishSavedGame(row, FINISHED, "1/2-1/2")!;
  assertEquals(done.outcome, "extended");
  assertEquals(done.chessGame.m.length, FINAL_PLIES);
  assertEquals(done.chessGame.md.Result, "1/2-1/2");
  // What the like captured is untouched, app-written headers stay.
  assertEquals(done.chessGame.m.slice(0, 3), row.chess_game.m);
  assertEquals(done.chessGame.md.TcCategory, "rapid");
  assertEquals(done.chessGame.id, "ct5MTG4Y");
  assertEquals(done.chessGame.m[5].s, "Bb4");
});

Deno.test("the reader's variations and marks on the liked moves survive", () => {
  const row = likedAt(LIVE);
  const side: SavedMove[] = movesFromPgn(pgn("*", "1. d4 Nf6 2. Nf3"))!
    .mainline.slice(2);
  row.chess_game.m[1] = { ...row.chess_game.m[1], v: [side], g: [1] };
  row.variation_comments = { "2": "Why not Nf3?" };
  row.move_nags = { "1": [3] };
  const done = finishSavedGame(row, FINISHED, "1/2-1/2")!;
  assertEquals(done.outcome, "extended");
  assertEquals(done.chessGame.m[1].v, [side]);
  assertEquals(done.chessGame.m[1].g, [1]);
  assertEquals(done.chessGame.m.length, FINAL_PLIES);
});

Deno.test("live-board snapshot metadata is dropped once the game is over", () => {
  const row = likedAt(LIVE, {
    isLiveGame: true,
    WhiteClockSeconds: "2730",
    BlackTimeDisplay: "45:34",
    BoardNr: "1",
  });
  const done = finishSavedGame(row, FINISHED, "1/2-1/2")!;
  assertEquals(done.chessGame.md.isLiveGame, undefined);
  assertEquals(done.chessGame.md.WhiteClockSeconds, undefined);
  assertEquals(done.chessGame.md.BlackTimeDisplay, undefined);
  assertEquals(done.chessGame.md.BoardNr, "1");
});

Deno.test("a move caught without its clock gets the clock", () => {
  const row = likedAt(pgn("*", "1. d4 {[%clk 0:45:37]} Nf6"));
  assertEquals(row.chess_game.m[1].ct, null);
  const done = finishSavedGame(row, FINISHED, "1/2-1/2")!;
  assertEquals(done.chessGame.m[1].ct, "0:45:34");
});

Deno.test("nothing to do while the broadcast is still live or the row is finished", () => {
  assertEquals(finishSavedGame(likedAt(LIVE), LIVE, "*"), null);
  assertEquals(finishSavedGame(likedAt(LIVE), FINISHED, "ongoing"), null);
  const finished = likedAt(FINISHED);
  assertEquals(finishSavedGame(finished, FINISHED, "1/2-1/2"), null);
});

Deno.test("the status column is the result, in either draw spelling", () => {
  assertEquals(finishedResult("½-½"), "1/2-1/2");
  assertEquals(finishedResult("1/2-1/2"), "1/2-1/2");
  assertEquals(finishedResult("*"), null);
  assertEquals(finishedResult(null), null);
  const draw = finishSavedGame(likedAt(LIVE), FINISHED, "½-½")!;
  assertEquals(draw.chessGame.md.Result, "1/2-1/2");
  // A relay that finished the game but left the PGN's `[Result "*"]`.
  const win = finishSavedGame(
    likedAt(LIVE),
    FINISHED.replace(/1\/2-1\/2/g, "*"),
    "1-0",
  )!;
  assertEquals(win.outcome, "extended");
  assertEquals(win.chessGame.md.Result, "1-0");
});

Deno.test("moves the board's navigator wrote join the game like parsed ones", () => {
  // The navigator stores `t` as the side to move next and castling king to
  // destination; the moves are the same positions.
  const castled = pgn(
    "*",
    "1. e4 {[%clk 1:00:00]} e5 2. Nf3 Nc6 3. Bc4 Bc5 4. O-O",
  );
  const done = pgn(
    "1-0",
    "1. e4 {[%clk 1:00:00]} e5 2. Nf3 Nc6 3. Bc4 Bc5 4. O-O Nf6 5. d3",
  );
  const row = likedAt(castled);
  row.chess_game.m = row.chess_game.m.map((m) => ({
    ...m,
    t: m.t === "white" ? "black" : "white",
    u: m.u === "e1h1" ? "e1g1" : m.u,
  }));
  const finished = finishSavedGame(row, done, "1-0")!;
  assertEquals(finished.outcome, "extended");
  assertEquals(finished.chessGame.m.slice(0, 7), row.chess_game.m);
  assertEquals(finished.chessGame.m.map((m) => m.s).slice(7), ["Nf6", "d3"]);
});

Deno.test("a corrected broadcast replaces a like that holds nothing of the reader's", () => {
  // The like caught 2... e5, which the relay later corrected to 2... e6.
  const row = likedAt(pgn("*", "1. d4 Nf6 2. c4 e5"));
  const done = finishSavedGame(row, FINISHED, "1/2-1/2")!;
  assertEquals(done.outcome, "replaced");
  assertEquals(done.chessGame.m.map((m) => m.s), [
    "d4",
    "Nf6",
    "c4",
    "e6",
    "Nc3",
    "Bb4",
  ]);
  assertEquals(done.chessGame.md.TcCategory, "rapid");
});

Deno.test("moves the reader played on the main line are kept as a variation", () => {
  // Liked after 2. c4, then the reader played 2... g6 3. Nc3 on the main line.
  const row = likedAt(pgn("*", "1. d4 Nf6 2. c4 g6 3. Nc3"));
  row.chess_game.m[0] = { ...row.chess_game.m[0], v: [], g: [1] };
  const theirs = row.chess_game.m.slice(3);
  const done = finishSavedGame(row, FINISHED, "1/2-1/2")!;
  assertEquals(done.outcome, "regrafted");
  assertEquals(done.chessGame.m.map((m) => m.s), [
    "d4",
    "Nf6",
    "c4",
    "e6",
    "Nc3",
    "Bb4",
  ]);
  // A move's variations are the alternatives to the move after it.
  assertEquals(done.chessGame.m[2].v, [theirs]);
});

Deno.test("notes keyed by position keep the moves where they are", () => {
  const row = likedAt(pgn("*", "1. d4 Nf6 2. c4 g6 3. Nc3"));
  row.variation_comments = { "4": "my idea" };
  const done = finishSavedGame(row, FINISHED, "1/2-1/2")!;
  assertEquals(done.outcome, "result_only");
  assertEquals(done.chessGame.m, row.chess_game.m);
  assertEquals(done.chessGame.md.Result, "1/2-1/2");
});

Deno.test("relay noise before the game began gives way to the game", () => {
  // The board sent 1. h3 e5, then reset and the game began 1. d4.
  const row = likedAt(pgn("*", "1. h3 e5"));
  const done = finishSavedGame(row, FINISHED, "1/2-1/2")!;
  assertEquals(done.outcome, "replaced");
  assertEquals(done.chessGame.m[0].s, "d4");
});

Deno.test("a row that shares no move with the game keeps the reader's own", () => {
  // Linked on chess_game.id alone: it may not be a save of this game.
  const unlinked = likedAt(pgn("*", "1. e4 e5"));
  unlinked.source_game_id = null;
  const kept = finishSavedGame(unlinked, FINISHED, "1/2-1/2")!;
  assertEquals(kept.outcome, "result_only");
  assertEquals(kept.chessGame.m, unlinked.chess_game.m);
  // The reader analysed it: nowhere to hang their line before move one.
  const analysed = likedAt(pgn("*", "1. e4 e5 (1... c5)"));
  const done = finishSavedGame(analysed, FINISHED, "1/2-1/2")!;
  assertEquals(done.outcome, "result_only");
  assertEquals(done.chessGame.m, analysed.chess_game.m);
});

Deno.test("another start position is never joined", () => {
  const row = likedAt(LIVE);
  row.chess_game = { ...row.chess_game, sf: "8/8/8/8/8/8/8/K6k w - - 0 1" };
  const done = finishSavedGame(row, FINISHED, "1/2-1/2")!;
  assertEquals(done.outcome, "result_only");
  assertEquals(done.chessGame.m, row.chess_game.m);
});

Deno.test("a cleared analysis gains bare moves", () => {
  const row = likedAt(LIVE);
  row.chess_game = { ...row.chess_game, analysisCleared: true };
  const done = finishSavedGame(row, FINISHED, "1/2-1/2")!;
  const added = done.chessGame.m[4];
  assertEquals(added.ct, null);
  assertEquals(added.c, undefined);
});

Deno.test("keys this module does not know are carried through", () => {
  const row = likedAt(LIVE);
  const game = row.chess_game as SavedChessGame & {
    rc: string[];
    dra: unknown;
  };
  game.rc = ["root note"];
  game.dra = [[]];
  game.m[0] = { ...game.m[0], sc: ["before d4"] };
  const done = finishSavedGame(row, FINISHED, "1/2-1/2")!;
  assertEquals(done.chessGame.rc, ["root note"]);
  assertEquals(done.chessGame.dra, [[]]);
  assertEquals(done.chessGame.m[0].sc, ["before d4"]);
  assert(done.chessGame.m.length === FINAL_PLIES);
});

// Review cases (2026-11-14): nothing the reader wrote may be dropped.

Deno.test("comment text a reader typed counts as theirs", () => {
  // Desktop and chessever.com keep the reader's comments in `c`, beside the
  // relay's clock. 2... e5 was later corrected by the relay to 2... e6.
  const row = likedAt(pgn("*", "1. d4 Nf6 2. c4 e5 {[%clk 0:45:00] my plan}"));
  const done = finishSavedGame(row, FINISHED, "1/2-1/2")!;
  assertEquals(done.outcome, "regrafted");
  assertEquals(done.chessGame.m[2].v, [row.chess_game.m.slice(3)]);
});

Deno.test("a comment before a move counts as theirs", () => {
  const row = likedAt(pgn("*", "1. d4 Nf6 2. c4 e5"));
  row.chess_game.m[3] = { ...row.chess_game.m[3], sc: ["why e5?"] };
  const done = finishSavedGame(row, FINISHED, "1/2-1/2")!;
  assertEquals(done.outcome, "regrafted");
});

Deno.test("a replaced line keeps the moves both share as saved", () => {
  const row = likedAt(pgn("*", "1. d4 {[%clk 0:45:37]} Nf6 2. c4 e5"));
  row.chess_game.m[0] = { ...row.chess_game.m[0], extraFlag: null };
  const done = finishSavedGame(row, FINISHED, "1/2-1/2")!;
  assertEquals(done.outcome, "replaced");
  assertEquals(done.chessGame.m.slice(0, 3), row.chess_game.m.slice(0, 3));
  assertEquals(done.chessGame.m[3].s, "e6");
});

Deno.test("a row linked on chess_game.id alone is only ever added to", () => {
  const row = likedAt(pgn("*", "1. d4 Nf6 2. c4 e5"));
  row.source_game_id = null;
  const done = finishSavedGame(row, FINISHED, "1/2-1/2")!;
  assertEquals(done.outcome, "regrafted");
  assertEquals(done.chessGame.m[2].v, [row.chess_game.m.slice(3)]);
});

Deno.test("a saved line longer than the game keeps every move", () => {
  // The reader played on past the end, or the PGN lost its last moves.
  const row = likedAt(
    pgn("*", "1. d4 Nf6 2. c4 e6 3. Nc3 Bb4 4. Qc2 O-O 5. a3"),
  );
  const done = finishSavedGame(row, FINISHED, "1/2-1/2")!;
  assertEquals(done.outcome, "result_only");
  assertEquals(done.chessGame.m, row.chess_game.m);
});

Deno.test("a PGN that stops short of its ply count is never used", () => {
  // FINISHED parses to 6 plies (its 4. O-O-O is illegal); the relay says 7.
  assertEquals(finishSavedGame(likedAt(LIVE), FINISHED, "1/2-1/2", 7), null);
  assertEquals(
    finishSavedGame(likedAt(LIVE), FINISHED, "1/2-1/2", 6)!.outcome,
    "extended",
  );
});

Deno.test("result only never claims the moves are complete", () => {
  const final = FINISHED.replace(
    '[TimeControl "2700+30"]',
    '[TimeControl "2700+30"]\n[Termination "Normal"]\n[PlyCount "6"]',
  );
  const row = likedAt(pgn("*", "1. d4 Nf6 2. c4 g6 3. Nc3"));
  row.variation_comments = { "4": "my idea" };
  row.chess_game.md.PlyCount = "5";
  const done = finishSavedGame(row, final, "1/2-1/2")!;
  assertEquals(done.outcome, "result_only");
  assertEquals(done.chessGame.md.Termination, undefined);
  assertEquals(done.chessGame.md.PlyCount, "5");
  const extended = finishSavedGame(likedAt(LIVE), final, "1/2-1/2")!;
  assertEquals(extended.chessGame.md.Termination, "Normal");
  assertEquals(extended.chessGame.md.PlyCount, "6");
});
