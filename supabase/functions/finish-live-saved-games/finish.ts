/**
 * A game liked or saved while it was being played is stored as it stood at
 * that moment: `user_saved_analyses.chess_game` holds the moves played so far
 * and `Result "*"`. Nothing ever caught it up, so My Likes and the reader's
 * databases kept a half game after the broadcast ended (Trello #1387).
 *
 * This module turns such a row into the finished game. It is pure: the
 * caller reads the row and the broadcast's final PGN, and writes back what
 * [finishSavedGame] returns.
 *
 * The stored JSON is the apps' `ChessGame.toJson()`
 * (chessever-frontend `lib/screens/chessboard/analysis/chess_game.dart`, the
 * same model in chessever_frontend_desktop). [movesFromPgn] is a port of
 * `ChessGame.fromPgn` on chessops, which dartchess itself is a port of, so a
 * move written here is the move the app would have written.
 *
 * What the reader added is kept. Their variations, comments and move marks
 * stay where they were; the moves played after the save are added after
 * them. When the saved moves left the game's own line, the line the reader
 * had is kept as a variation beside the real move; only a line holding
 * nothing of the reader's (the relay corrected a move) gives way, and only in
 * a row linked by `source_game_id`. Annotations stored outside the moves
 * (`variation_comments`, `move_nags`) are keyed by move position, so a row
 * carrying any of them only gains moves on the end: the moves it already has
 * never shift. Anything that cannot be joined that way keeps its moves and
 * gains only the result.
 */
import { parsePgn, startingPosition } from "npm:chessops@0.15.1/pgn";
import type { ChildNode, PgnNodeData } from "npm:chessops@0.15.1/pgn";
import { makeFen } from "npm:chessops@0.15.1/fen";
import { parseSan } from "npm:chessops@0.15.1/san";
import { makeUci } from "npm:chessops@0.15.1/util";
import type { Position } from "npm:chessops@0.15.1/chess";

export const FINISHED_RESULTS = ["1-0", "0-1", "1/2-1/2"] as const;

/**
 * `games.status` as a PGN result, or null while the game is not over. The
 * relay writes draws both ways (`1/2-1/2` and `½-½`, about half each in
 * November 2026).
 */
export function finishedResult(
  status: string | null | undefined,
): string | null {
  const value = `${status ?? ""}`.trim();
  if (value === "½-½" || value === "0.5-0.5") return "1/2-1/2";
  return (FINISHED_RESULTS as readonly string[]).includes(value) ? value : null;
}

/** One move as the apps store it (`ChessMove.toJson`). */
export interface SavedMove {
  n: number;
  f: string;
  s: string;
  u: string;
  t: "white" | "black";
  ct?: string | null;
  e?: string | null;
  c?: string[];
  g?: number[];
  v?: SavedMove[][];
  [key: string]: unknown;
}

/** A stored game (`ChessGame.toJson`). Unknown keys are carried through. */
export interface SavedChessGame {
  id: string;
  sf: string;
  md: Record<string, unknown>;
  m: SavedMove[];
  analysisCleared?: boolean;
  [key: string]: unknown;
}

export interface SavedRow {
  /** The game the row was saved from. Null on rows linked by `chess_game.id`. */
  source_game_id?: string | null;
  chess_game: SavedChessGame;
  variation_comments?: Record<string, unknown> | null;
  move_nags?: Record<string, unknown> | null;
}

export type FinishOutcome =
  /** The moves played after the save were added. */
  | "extended"
  /** The saved line left the game; the real line now leads, theirs is a variation. */
  | "regrafted"
  /** Nothing of the reader's was in the row, so it is the broadcast game now. */
  | "replaced"
  /** Moves could not be joined without moving the reader's notes: result only. */
  | "result_only";

export interface FinishResult {
  outcome: FinishOutcome;
  chessGame: SavedChessGame;
}

/**
 * Metadata a game saved from the live board carries about that moment: the
 * live flag (the board treats such a game as still being played) and the
 * clock snapshot (which wins over the clocks in the moves). All of it is
 * stale once the game is over.
 */
const LIVE_ONLY_METADATA = [
  "isLiveGame",
  "WhiteClockSeconds",
  "BlackClockSeconds",
  "WhiteTimeDisplay",
  "BlackTimeDisplay",
];

/** Headers the finished broadcast is the authority on. */
const FINISHED_HEADERS = ["Result", "Termination", "PlyCount"];

const CLOCK = /\[%clk (\d+:)?(\d+:\d+)(?:\.\d+)?\]/;
const EVAL = /\[%eval ([^\]]+)\]/;

/** Port of `extractPgnClockStringFromComment` (lib/utils/pgn_clock_utils.dart). */
function clockFromComment(comment: string): string | null {
  const match = CLOCK.exec(comment);
  if (!match) return null;
  const clock = `${match[1] ?? ""}${match[2] ?? ""}`.trim();
  return clock.length === 0 ? null : clock;
}

/** Port of `ChessGame._parsePgnLineFromChild`. */
function lineFrom(
  node: ChildNode<PgnNodeData>,
  position: Position,
): SavedMove[] {
  const line: SavedMove[] = [];
  let current: ChildNode<PgnNodeData> | undefined = node;
  let pos = position;
  while (current) {
    const data: PgnNodeData = current.data;
    const move = parseSan(pos, data.san);
    if (!move) break;
    const next = pos.clone();
    next.play(move);

    const variations: SavedMove[][] = [];
    for (const child of current.children.slice(1)) {
      variations.push(lineFrom(child, next));
    }

    let clockTime: string | null = null;
    let evaluation: string | null = null;
    for (const comment of data.comments ?? []) {
      const clock = clockFromComment(comment);
      if (clock !== null) clockTime = clock;
      const evalMatch = EVAL.exec(comment);
      if (evalMatch) evaluation = evalMatch[1];
    }

    const saved: SavedMove = {
      n: pos.fullmoves,
      f: makeFen(next.toSetup()),
      s: data.san,
      u: makeUci(move),
      t: pos.turn,
      ct: clockTime,
      e: evaluation,
    };
    if (data.comments) saved.c = data.comments;
    if (data.nags) saved.g = data.nags;
    if (variations.length > 0) saved.v = variations;
    line.push(saved);

    current = current.children[0];
    pos = next;
  }
  return line;
}

export interface ParsedPgn {
  headers: Map<string, string>;
  startingFen: string;
  mainline: SavedMove[];
}

/** Port of `ChessGame.fromPgn`: the first game of [pgn], or null. */
export function movesFromPgn(pgn: string): ParsedPgn | null {
  const game = parsePgn(pgn)[0];
  if (!game) return null;
  const start = startingPosition(game.headers);
  if (start.isErr) return null;
  const position = start.unwrap();
  const first = game.moves.children[0];
  return {
    headers: game.headers,
    startingFen: makeFen(position.toSetup()),
    mainline: first ? lineFrom(first, position) : [],
  };
}

/** The keys `ChessMove.toJson` writes on the phone. */
const KNOWN_MOVE_KEYS = new Set([
  "n",
  "f",
  "s",
  "u",
  "t",
  "ct",
  "e",
  "c",
  "g",
  "v",
]);
/** A PGN command such as `[%clk 1:30:00]`, which the relay writes. */
const PGN_COMMAND = /\[%[^\]]*\]/g;

/**
 * Whether [line] holds anything the reader added, rather than what the relay
 * sent: a variation, a move mark, comment text (desktop and chessever.com keep
 * the reader's comments in `c`, beside the relay's `[%clk]`), a comment before
 * a move (`sc`), or a key this module does not know.
 */
function holdsReadersWork(line: SavedMove[]): boolean {
  return line.some((move) => {
    if (Array.isArray(move.v) && move.v.length > 0) return true;
    if (Array.isArray(move.g) && move.g.length > 0) return true;
    if (
      (move.c ?? []).some((c) => `${c}`.replace(PGN_COMMAND, "").trim() !== "")
    ) {
      return true;
    }
    return Object.keys(move).some((key) =>
      !KNOWN_MOVE_KEYS.has(key) && move[key] !== null &&
      move[key] !== undefined
    );
  });
}

function isEmptyMap(value: unknown): boolean {
  if (value === null || value === undefined) return true;
  if (typeof value !== "object") return true;
  return Object.keys(value as Record<string, unknown>).length === 0;
}

/** `ChessGame.withoutAnalysis` keeps only these on a move. */
function bare(move: SavedMove): SavedMove {
  return {
    n: move.n,
    f: move.f,
    s: move.s.replace(/[!?]+$/, ""),
    u: move.u,
    t: move.t,
    ct: null,
    e: null,
  };
}

/**
 * The finished game for a saved row, or null when there is nothing to do:
 * the row is not a game saved while live, the broadcast is not over, or its
 * PGN does not read to the end ([expectedPlies], `games.live_ply_count`, is
 * more moves than it parses to; 0 when unknown).
 */
export function finishSavedGame(
  row: SavedRow,
  finalPgn: string,
  finalStatus: string,
  expectedPlies = 0,
): FinishResult | null {
  const saved = row.chess_game;
  if (!saved || !Array.isArray(saved.m) || typeof saved.md !== "object") {
    return null;
  }
  if (`${saved.md.Result ?? ""}` !== "*") return null;
  const result = finishedResult(finalStatus);
  if (result === null) return null;

  const parsed = movesFromPgn(finalPgn);
  if (!parsed) return null;
  // chessops stops at the first move it cannot play. A game cut short there
  // must never stand in for the real one.
  if (expectedPlies > 0 && parsed.mainline.length < expectedPlies) return null;

  // Every outcome: the live-board snapshot is stale and the game has its
  // result. The status column is the result every app shows; some relays
  // finish a game there and never rewrite the PGN's `[Result "*"]`.
  const settled: Record<string, unknown> = { ...saved.md };
  for (const key of LIVE_ONLY_METADATA) delete settled[key];
  settled.Result = result;

  // When the moves are the game's: what the live PGN said about its end is
  // stale whether or not the final one repeats it.
  const finishedMetadata: Record<string, unknown> = { ...settled };
  for (const key of FINISHED_HEADERS) {
    if (key === "Result") continue;
    const value = parsed.headers.get(key);
    if (value !== undefined && value !== "") {
      finishedMetadata[key] = value;
    } else {
      delete finishedMetadata[key];
    }
  }

  const savedLine = saved.m;
  const sameStart = parsed.startingFen === saved.sf;
  const cleared = saved.analysisCleared === true;
  const finalLine = cleared ? parsed.mainline.map(bare) : parsed.mainline;

  // Moves are the same move when they reach the same position. `u` and `t`
  // cannot say it: a move the board's navigator wrote (live updates, the
  // reader's own moves) stores `t` as the side to move next and castling as
  // `e1g1`, where PGN parsing stores the mover and `e1h1`. The apps read both
  // in one line and so does this; only the FEN is the same in both.
  let common = 0;
  if (sameStart) {
    while (
      common < savedLine.length &&
      common < finalLine.length &&
      savedLine[common].f === finalLine[common].f
    ) {
      common++;
    }
  }

  const resultOnly = (): FinishResult => ({
    outcome: "result_only",
    chessGame: { ...saved, md: settled },
  });

  // The broadcast game is not a continuation of what was saved: another
  // start position, or no moves at all.
  if (!sameStart || finalLine.length === 0) return resultOnly();

  if (common === savedLine.length) {
    // Saved line is the start of the game: add what came after it. A move
    // the save caught without its clock gains it, nothing else is touched.
    const kept = savedLine.map((move, i) => {
      const played = finalLine[i];
      if ((move.ct === null || move.ct === undefined) && played.ct) {
        return { ...move, ct: played.ct };
      }
      return move;
    });
    return {
      outcome: "extended",
      chessGame: {
        ...saved,
        md: finishedMetadata,
        m: [...kept, ...finalLine.slice(savedLine.length)],
      },
    };
  }

  // The saved line runs past the end of the game: the reader played on, or
  // the PGN lost its last moves. Their moves stay as they are.
  if (common === finalLine.length) return resultOnly();

  const notesByPosition = !isEmptyMap(row.variation_comments) ||
    !isEmptyMap(row.move_nags);
  const readersOwn = notesByPosition || holdsReadersWork(savedLine);
  // A row matched on `chess_game.id` alone may not be a save of that game at
  // all: its moves are only ever added to, never swapped.
  const linked = typeof row.source_game_id === "string" &&
    row.source_game_id.length > 0;

  // Not one move in common. With `source_game_id` and nothing of the
  // reader's this is the relay's noise before the game began (a board sends
  // `1. h3`, then resets): the row takes the real game. Otherwise there is no
  // move before the first one to hang the reader's own line on.
  if (common === 0) {
    if (linked && !readersOwn) {
      return {
        outcome: "replaced",
        chessGame: { ...saved, md: finishedMetadata, m: finalLine },
      };
    }
    return resultOnly();
  }

  if (linked && !readersOwn) {
    // Nothing of the reader's after the fork: the relay corrected its moves
    // (or the save caught a move it later took back). The moves both share
    // stay as saved, the game as played follows.
    return {
      outcome: "replaced",
      chessGame: {
        ...saved,
        md: finishedMetadata,
        m: [...savedLine.slice(0, common), ...finalLine.slice(common)],
      },
    };
  }

  // The reader's notes sit at fixed move positions: moving their line into a
  // variation would point those notes at other moves.
  if (notesByPosition) return resultOnly();

  // Real game from the fork on, the reader's line kept as a variation on the
  // move before the fork (in this model a move's variations are the
  // alternatives to the move after it).
  const fork = savedLine[common - 1];
  const theirs = savedLine.slice(common);
  const merged = [
    ...savedLine.slice(0, common - 1),
    { ...fork, v: [...(fork.v ?? []), theirs] },
    ...finalLine.slice(common),
  ];
  return {
    outcome: "regrafted",
    chessGame: { ...saved, md: finishedMetadata, m: merged },
  };
}
