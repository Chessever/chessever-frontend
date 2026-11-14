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
  /** The relay corrected moves the save caught; they give way to the game. */
  | "replaced"
  /** Moves could not be joined without moving the reader's notes: result only. */
  | "result_only"
  /**
   * The row cannot be shown as this game: not one move in common that may
   * give way, or another start position. Nothing is written; the row stays
   * as the reader saved it (`chessGame` is that row).
   */
  | "unjoinable";

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

/**
 * Headers the finished broadcast is the authority on once the moves are the
 * game's: how it ended, the clocks at the end (DGT boards write them as
 * headers), and the report stamp. The stamp covers each mainline move's
 * position, ChessEver code and eval, so it verifies only when the row's
 * mainline carries exactly the report's; otherwise every app ignores it.
 */
const FINISHED_HEADERS = [
  "Termination",
  "PlyCount",
  "WhiteClock",
  "BlackClock",
  "WhiteClockMs",
  "BlackClockMs",
  "ReferenceTime",
  "ChessEverReport",
];

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

function hasCommentText(move: SavedMove): boolean {
  return (move.c ?? []).some((c) =>
    `${c}`.replace(PGN_COMMAND, "").trim() !== ""
  );
}

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
    if (hasCommentText(move)) return true;
    return Object.keys(move).some((key) =>
      !KNOWN_MOVE_KEYS.has(key) && move[key] !== null &&
      move[key] !== undefined
    );
  });
}

/**
 * Whether every move of [line] came from the relay: each carries a clock. A
 * move the reader played on the board has none (desktop puts a reader's
 * moves at the end of a saved game on its main line), so a line without
 * clocks is never let go.
 */
function cameFromRelay(line: SavedMove[]): boolean {
  return line.length > 0 &&
    line.every((move) =>
      (typeof move.ct === "string" && move.ct !== "") ||
      (move.c ?? []).some((c) => CLOCK.test(`${c}`))
    );
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
 * How a writer numbered a move. Parsed PGN (`ChessGame.fromPgn`, this
 * module, chessever.com) stores `t` as the side that moved and `n` as the
 * move number before it; the board's navigator stores the side to move next
 * and the move number after it. Read from the move's own FEN (the position
 * after it), which both writers fill the same way.
 */
type Numbering = "mover" | "next";

function sideAfter(move: SavedMove): "white" | "black" {
  return move.f.split(" ")[1] === "b" ? "black" : "white";
}

function numberingOf(move: SavedMove): Numbering {
  return move.t === sideAfter(move) ? "next" : "mover";
}

/**
 * [line], and every variation in it, numbered the [numbering] way. Clients
 * tell a variation that replaces a move from one that follows it by
 * comparing `t` (chessever.com, desktop since 20.28.24), so moves joined
 * into one line must share one numbering.
 */
function renumber(line: SavedMove[], numbering: Numbering): SavedMove[] {
  return line.map((move) => {
    const after = sideAfter(move);
    const fullmoveAfter = Number(move.f.split(" ")[5]) || move.n;
    const mover = after === "white" ? "black" : "white";
    const renumbered: SavedMove = numbering === "next"
      ? { ...move, t: after, n: fullmoveAfter }
      : {
        ...move,
        t: mover,
        n: mover === "black" ? fullmoveAfter - 1 : fullmoveAfter,
      };
    if (Array.isArray(move.v)) {
      renumbered.v = move.v.map((variation) => renumber(variation, numbering));
    }
    return renumbered;
  });
}

/** The numbering of moves joined after [line]'s move [at]: the line's own. */
function numberingAt(line: SavedMove[], at: number): Numbering {
  return at >= 0 && at < line.length ? numberingOf(line[at]) : "mover";
}

/**
 * A saved move that reaches the same position as the game's [played] move,
 * given what the broadcast knows about it: its clock, its eval, its marks
 * and comments when the save caught none (the analysis service adds
 * ChessEver codes and evals once the game is over). The reader's own marks
 * and comment text always win.
 */
function withBroadcastAnnotations(
  move: SavedMove,
  played: SavedMove,
): SavedMove {
  const next: SavedMove = { ...move };
  if ((move.ct === null || move.ct === undefined) && played.ct) {
    next.ct = played.ct;
  }
  if (played.e !== null && played.e !== undefined) next.e = played.e;
  if (
    (!Array.isArray(move.g) || move.g.length === 0) &&
    Array.isArray(played.g) && played.g.length > 0
  ) {
    next.g = played.g;
  }
  if (!hasCommentText(move) && Array.isArray(played.c)) next.c = played.c;
  return next;
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

  // When the mainline is the game's: what the live PGN said about its end
  // is stale whether or not the final one repeats it.
  const finishedMetadata: Record<string, unknown> = { ...settled };
  for (const key of FINISHED_HEADERS) {
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

  const unjoinable = (): FinishResult => ({
    outcome: "unjoinable",
    chessGame: saved,
  });
  // Another start position, or a game with no moves: not this save's game.
  if (!sameStart || finalLine.length === 0) return unjoinable();

  // Moves are the same move when they reach the same position. `u` and `t`
  // cannot say it: a move the board's navigator wrote (live updates, the
  // reader's own moves) stores `t` as the side to move next and castling as
  // `e1g1`, where PGN parsing stores the mover and `e1h1`. The apps read both
  // in one line and so does this; only the FEN is the same in both.
  let common = 0;
  while (
    common < savedLine.length &&
    common < finalLine.length &&
    savedLine[common].f === finalLine[common].f
  ) {
    common++;
  }

  const shared = savedLine
    .slice(0, common)
    .map((move, i) => withBroadcastAnnotations(move, finalLine[i]));
  // The game's moves after the shared ones, numbered like the line they join.
  const gameAfter = (from: number) =>
    renumber(finalLine.slice(from), numberingAt(savedLine, from - 1));

  if (common === savedLine.length) {
    // Saved line is the start of the game: add what came after it.
    return {
      outcome: "extended",
      chessGame: {
        ...saved,
        md: finishedMetadata,
        m: [...shared, ...gameAfter(common)],
      },
    };
  }

  const resultOnly = (): FinishResult => ({
    outcome: "result_only",
    chessGame: { ...saved, md: settled },
  });

  // The saved line runs past the end of the game: the reader played on, or
  // the PGN lost its last moves. Their moves stay as they are.
  if (common === finalLine.length) return resultOnly();

  const notesByPosition = !isEmptyMap(row.variation_comments) ||
    !isEmptyMap(row.move_nags);
  const theirs = savedLine.slice(common);
  // Saved moves the relay later took back may give way to the game: only in
  // a row linked to it by `source_game_id` (a row matched on `chess_game.id`
  // alone may not be a save of that game), with nothing of the reader's in
  // the row, and every move that goes carrying the relay's clock.
  const linked = typeof row.source_game_id === "string" &&
    row.source_game_id.length > 0;
  const relayNoise = linked && !notesByPosition &&
    !holdsReadersWork(savedLine) && cameFromRelay(theirs);

  if (relayNoise) {
    return {
      outcome: "replaced",
      chessGame: {
        ...saved,
        md: finishedMetadata,
        m: [...shared, ...gameAfter(common)],
      },
    };
  }

  // Not one move in common, and the saved moves may be the reader's or
  // another game's: there is no move before the first to hang them on.
  if (common === 0) return unjoinable();

  // The reader's notes sit at fixed move positions: moving their line into a
  // variation would point those notes at other moves.
  if (notesByPosition) return resultOnly();

  // Real game from the fork on, the reader's line kept as a variation on the
  // move before the fork (in this model a move's variations are the
  // alternatives to the move after it), numbered like that move.
  const fork = shared[common - 1];
  const numbering = numberingOf(fork);
  return {
    outcome: "regrafted",
    chessGame: {
      ...saved,
      md: finishedMetadata,
      m: [
        ...shared.slice(0, common - 1),
        { ...fork, v: [...(fork.v ?? []), renumber(theirs, numbering)] },
        ...gameAfter(common),
      ],
    },
  };
}
