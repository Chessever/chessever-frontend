import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/screens/chessboard/classification_fx/classification_fx.dart';
import 'package:chessever2/screens/chessboard/classification_fx/move_class.dart';
import 'package:chessever2/screens/chessboard/game_review/classification_style.dart';
import 'package:chessever2/screens/feed/race/race_audio.dart';
import 'package:chessever2/screens/feed/race/race_chess.dart';
import 'package:chessever2/screens/feed/race/race_controller.dart';
import 'package:chessever2/screens/feed/race/race_widgets.dart';
import 'package:chessever2/services/lichess_move_annotations_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

/// Where one race board stands.
enum RaceBoardStage {
  /// The position before the opponent's setup move.
  intro,

  /// The player's turn.
  solving,

  /// The player's move is out; the room has not answered.
  sent,

  /// Right so far; the opponent's reply plays next.
  replying,
  solved,
  missed,

  /// The puzzle's position did not parse.
  broken,
}

/// One puzzle of the race stream: the board screen's interactive board in
/// the viewer's theme (tap or drag), turned to the solver, with a status
/// line under it.
///
/// The opponent's setup move plays first, once the page is the current one.
/// The player's move goes to the room ([onMove]); the room's verdict
/// ([moveEvent]) lands a short classification on the square (best while
/// the line goes on, brilliant on the solve) or a red flash and a small
/// shake on a miss. A continuing line plays the room's reply and hands the
/// board back. The board never decides right or wrong itself.
class RacePuzzleBoard extends ConsumerStatefulWidget {
  const RacePuzzleBoard({
    required this.puzzle,
    required this.record,
    required this.isCurrent,
    required this.canMove,
    required this.moveEvent,
    required this.rejectEvent,
    required this.onMove,
    required this.boardSize,
    super.key,
  });

  final RacePuzzle puzzle;

  /// Set once this puzzle is over (a rebuilt page shows how it ended).
  final RacePuzzleRecord? record;

  /// This is the page on screen.
  final bool isCurrent;

  /// The race is running and connected.
  final bool canMove;

  /// The room's latest verdict when it is for this puzzle.
  final RaceMoveEvent? moveEvent;

  /// The room's latest refusal when it is for this puzzle.
  final RaceRejectEvent? rejectEvent;

  /// Sends a move (UCI); false when it could not go out.
  final bool Function(String uci) onMove;
  final double boardSize;

  static const double statusHeight = 26;
  static const double statusGap = 12;

  @override
  ConsumerState<RacePuzzleBoard> createState() => _RacePuzzleBoardState();
}

class _RacePuzzleBoardState extends ConsumerState<RacePuzzleBoard> {
  /// Long enough for the page to finish landing before the setup plays.
  static const Duration _setupDelay = Duration(milliseconds: 380);
  static const Duration _replyDelay = Duration(milliseconds: 240);

  ChessboardController? _board;
  Position? _position;
  NormalMove? _lastMove;
  RaceBoardStage _stage = RaceBoardStage.intro;
  Timer? _timer;

  Position? _before;
  NormalMove? _beforeLast;
  NormalMove? _sent;

  Square? _markSquare;
  MoveClass? _markClass;
  int _markSeq = 0;
  int _wrongSeq = 0;

  int _handledMove = -1;
  int _handledReject = -1;

  bool get _canMove =>
      widget.isCurrent &&
      widget.canMove &&
      _stage == RaceBoardStage.solving &&
      _position?.turn == widget.puzzle.solver;

  RaceAudio get _audio => ref.read(raceDepsProvider).audio;

  @override
  void initState() {
    super.initState();
    _handledMove = widget.moveEvent?.seq ?? -1;
    _handledReject = widget.rejectEvent?.seq ?? -1;
    _load();
    _sync();
  }

  @override
  void didUpdateWidget(covariant RacePuzzleBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final reloaded =
        oldWidget.puzzle.index != widget.puzzle.index ||
        oldWidget.puzzle.revision != widget.puzzle.revision;
    if (reloaded) {
      _timer?.cancel();
      _timer = null;
      _board?.dispose();
      _board = null;
      _load();
    }
    final move = widget.moveEvent;
    if (move != null && move.seq != _handledMove) {
      _handledMove = move.seq;
      _onVerdict(move);
    }
    final reject = widget.rejectEvent;
    if (reject != null && reject.seq != _handledReject) {
      _handledReject = reject.seq;
      _takeBack();
    }
    if (reloaded ||
        oldWidget.isCurrent != widget.isCurrent ||
        oldWidget.canMove != widget.canMove) {
      _sync();
      // Only a reload snaps. A `canMove`/`isCurrent` flip leaves the FEN
      // alone, and chessground's `animate: false` stops the controller and
      // clears the translating pieces, which would cut short the move
      // `_onMove` just started (sending it flips `canMove` a frame later).
      // With an unchanged FEN, `animate: true` only swaps the game data.
      _push(animate: !reloaded);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _board?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- setup

  void _load() {
    _clearMark();
    _before = null;
    _beforeLast = null;
    _sent = null;
    final puzzle = widget.puzzle;
    final start = raceParseFen(puzzle.fen);
    if (start == null) {
      _stage = RaceBoardStage.broken;
      _position = null;
      return;
    }
    final record = widget.record;
    if (record != null) {
      final end = raceReplay(start, puzzle.setupMove, record.finalLine);
      _position = end.position;
      _lastMove = end.lastMove;
      _stage = record.solved ? RaceBoardStage.solved : RaceBoardStage.missed;
    } else if (puzzle.ply > 1 || puzzle.progress.isNotEmpty) {
      // Back from a reconnect mid-puzzle: the room says what is on the board.
      final now = raceReplay(start, puzzle.setupMove, puzzle.progress);
      _position = now.position;
      _lastMove = now.lastMove;
      _stage = RaceBoardStage.solving;
    } else {
      _position = start;
      _lastMove = null;
      _stage = RaceBoardStage.intro;
    }
    _board = ChessboardController(game: _data());
  }

  GameData _data() {
    final pos = _position!;
    final interactive = _canMove;
    final solver = widget.puzzle.solver;
    return GameData(
      fen: pos.fen,
      playerSide: interactive
          ? (solver == Side.white ? PlayerSide.white : PlayerSide.black)
          : PlayerSide.none,
      sideToMove: pos.turn,
      validMoves: interactive ? makeLegalMoves(pos) : const {},
      lastMove: _lastMove,
      kingSquareInCheck: pos.isCheck ? pos.board.kingOf(pos.turn) : null,
    );
  }

  void _push({bool animate = true}) {
    final board = _board;
    if (board == null || _position == null) return;
    board.updatePosition(_data(), animate: animate);
  }

  /// Starts the setup move once this page is the one on screen.
  void _sync() {
    if (!widget.isCurrent) {
      if (_stage == RaceBoardStage.intro) {
        _timer?.cancel();
        _timer = null;
      }
      return;
    }
    if (_stage == RaceBoardStage.intro && _timer == null) {
      _timer = Timer(_setupDelay, () {
        _timer = null;
        if (mounted) _playSetup();
      });
    }
  }

  void _playSetup() {
    final pos = _position;
    if (pos == null || _stage != RaceBoardStage.intro) return;
    final step = racePlay(pos, widget.puzzle.setupMove);
    setState(() {
      if (step != null) {
        _position = step.after;
        _lastMove = step.move;
      }
      _stage = RaceBoardStage.solving;
    });
    _push();
    if (step != null) _audio.move(step.san);
  }

  // ---------------------------------------------------------------- moves

  void _onMove(Move move, {bool? viaDragAndDrop}) {
    final pos = _position;
    if (pos == null || !_canMove) return;
    final step = racePlay(pos, move.uci);
    if (step == null) {
      _push(animate: false);
      return;
    }
    final uci = step.move.uci;
    _before = pos;
    _beforeLast = _lastMove;
    _sent = step.move;
    setState(() {
      _clearMark();
      _position = step.after;
      _lastMove = step.move;
      _stage = RaceBoardStage.sent;
    });
    _push(animate: viaDragAndDrop != true);
    if (!widget.onMove(uci)) {
      _takeBack();
      return;
    }
    _audio.move(step.san);
  }

  void _onVerdict(RaceMoveEvent event) {
    final sent = _sent;
    if (_stage != RaceBoardStage.sent) {
      // A verdict for a move sent before a reconnect: only the outcome.
      if (event.complete) {
        setState(
          () => _stage = event.correct
              ? RaceBoardStage.solved
              : RaceBoardStage.missed,
        );
      }
      return;
    }
    _sent = null;
    _before = null;
    _beforeLast = null;

    if (event.correct && !event.complete) {
      setState(() {
        if (sent != null) _mark(sent.to, MoveClass.best);
        _stage = RaceBoardStage.replying;
      });
      unawaited(HapticFeedbackService.light());
      final reply = event.reply;
      _timer?.cancel();
      _timer = Timer(_replyDelay, () {
        _timer = null;
        if (mounted) _playReply(reply);
      });
      return;
    }
    if (event.correct) {
      setState(() {
        if (sent != null) _mark(sent.to, MoveClass.brilliant);
        _stage = RaceBoardStage.solved;
      });
      unawaited(HapticFeedbackService.success());
      return;
    }
    setState(() {
      if (sent != null) _mark(sent.to, MoveClass.mistake);
      _stage = RaceBoardStage.missed;
      _wrongSeq += 1;
    });
    unawaited(HapticFeedbackService.medium());
  }

  void _playReply(String? reply) {
    final pos = _position;
    if (pos == null || _stage != RaceBoardStage.replying) return;
    final step = reply == null ? null : racePlay(pos, reply);
    setState(() {
      _clearMark();
      if (step != null) {
        _position = step.after;
        _lastMove = step.move;
      }
      _stage = RaceBoardStage.solving;
    });
    _push();
    if (step != null) _audio.move(step.san);
  }

  /// The room refused the move without judging it: back it goes.
  void _takeBack() {
    final before = _before;
    if (before == null) return;
    setState(() {
      _position = before;
      _lastMove = _beforeLast;
      _before = null;
      _beforeLast = null;
      _sent = null;
      _stage = RaceBoardStage.solving;
    });
    _push();
  }

  void _mark(Square square, MoveClass moveClass) {
    _markSquare = square;
    _markClass = moveClass;
    _markSeq += 1;
  }

  void _clearMark() {
    _markSquare = null;
    _markClass = null;
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final size = widget.boardSize;
    final board = _board;
    final pos = _position;
    final solver = widget.puzzle.solver;

    Widget boardArea;
    if (board == null || pos == null) {
      boardArea = SizedBox.square(
        dimension: size,
        child: ColoredBox(
          color: colors.surface,
          child: Center(
            child: Text(
              "This puzzle didn't load",
              style: AppTypography.textSmMedium.copyWith(
                fontSize: 14,
                color: colors.textSecondary,
              ),
            ),
          ),
        ),
      );
    } else {
      final settings =
          ref.watch(boardSettingsProviderNew).valueOrNull ??
          const BoardSettingsNew();
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      final markSquare = _markSquare;
      final markClass = _markClass;
      final stack = SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Chessboard(
              size: size,
              controller: board,
              orientation: solver,
              settings: ChessboardSettings(
                enableCoordinates: settings.showCoordinates,
                animationDuration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                pieceShiftMethod: PieceShiftMethod.either,
                autoQueenPromotionOnPremove: false,
                enablePremoves: false,
                pieceOrientationBehavior: PieceOrientationBehavior.facingUser,
                colorScheme: settings.colorScheme,
                pieceAssets: settings.pieceAssets,
              ),
              landingSquare: markClass != null ? markSquare : null,
              landingKey: markClass != null ? _markSeq : null,
              onMove: _onMove,
            ),
            if (markSquare != null && markClass != null)
              _RaceMoveBadge(
                square: markSquare,
                moveClass: markClass,
                boardSize: size,
                orientation: solver,
              ),
            Positioned.fill(
              child: IgnorePointer(
                child: ClassificationLanding(
                  square: markSquare,
                  moveClass: markClass,
                  orientation: solver,
                  trigger: _markSeq,
                ),
              ),
            ),
            if (_wrongSeq > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: _MissFlash(
                    key: ValueKey('miss-$_wrongSeq'),
                    color: colors.danger,
                  ),
                ),
              ),
          ],
        ),
      );
      boardArea = _wrongSeq > 0 && !reduceMotion
          ? _Shake(key: ValueKey('shake-$_wrongSeq'), child: stack)
          : stack;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        boardArea,
        const SizedBox(height: RacePuzzleBoard.statusGap),
        SizedBox(
          width: size,
          height: RacePuzzleBoard.statusHeight,
          child: _BoardStatus(
            stage: _stage,
            solver: solver,
            number: widget.puzzle.index + 1,
            rating: widget.puzzle.rating,
          ),
        ),
      ],
    );
  }
}

/// The status line under a board: what to do, or how it went, and which
/// puzzle this is.
class _BoardStatus extends StatelessWidget {
  const _BoardStatus({
    required this.stage,
    required this.solver,
    required this.number,
    required this.rating,
  });

  final RaceBoardStage stage;
  final Side solver;
  final int number;
  final int rating;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final side = solver == Side.white ? 'White' : 'Black';
    final opponent = solver == Side.white ? 'Black' : 'White';
    // As text these need AA on the page in both themes (see raceVerdictInk).
    final best = raceVerdictInk(context, solved: true);
    final miss = raceVerdictInk(context, solved: false);
    final (String lead, String rest, Color? tint) = switch (stage) {
      RaceBoardStage.intro => ('Watch', ' · $opponent to play', null),
      RaceBoardStage.solving ||
      RaceBoardStage.sent => ('Your move', ' · $side to play', null),
      RaceBoardStage.replying => ('Correct', ' · keep going', best),
      RaceBoardStage.solved => ('Solved', '', best),
      RaceBoardStage.missed => ('Missed', '', miss),
      RaceBoardStage.broken => ('Skipped', '', null),
    };
    final base = AppTypography.textMdBold.copyWith(
      fontSize: 16,
      height: 22 / 16,
      color: colors.textPrimary,
    );
    final meta = AppTypography.textXsMedium.copyWith(
      fontSize: 12,
      height: 16 / 12,
      color: raceQuietInk(colors),
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      children: [
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: lead,
                      style: tint == null ? null : base.copyWith(color: tint),
                    ),
                    if (rest.isNotEmpty)
                      TextSpan(
                        text: rest,
                        style: base.copyWith(
                          fontWeight: FontWeight.w500,
                          color: colors.textSecondary,
                        ),
                      ),
                  ],
                ),
                style: base,
                maxLines: 1,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '#$number · $rating',
          maxLines: 1,
          style: meta,
          semanticsLabel: 'Puzzle $number, rated $rating',
        ),
      ],
    );
  }
}

/// A miss: the board washes red and clears, about a third of a second.
class _MissFlash extends StatelessWidget {
  const _MissFlash({required this.color, super.key});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SingleMotionBuilder(
      from: 1,
      value: 0,
      motion: const CupertinoMotion.smooth(
        duration: Duration(milliseconds: 340),
        snapToEnd: true,
      ),
      builder: (context, t, _) =>
          ColoredBox(color: color.withValues(alpha: 0.34 * t.clamp(0.0, 1.0))),
    );
  }
}

/// A small sideways shake that dies out: a spring-driven decay under a sine.
class _Shake extends StatelessWidget {
  const _Shake({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleMotionBuilder(
      from: 1,
      value: 0,
      motion: const CupertinoMotion.smooth(
        duration: Duration(milliseconds: 320),
        snapToEnd: true,
      ),
      builder: (context, t, child) {
        final life = t.clamp(0.0, 1.0);
        final dx = math.sin((1 - life) * math.pi * 5) * 7 * life;
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: child,
    );
  }
}

/// The board screen's classification badge (top-right of the square,
/// clamped inside the board) for the judged move.
class _RaceMoveBadge extends StatelessWidget {
  const _RaceMoveBadge({
    required this.square,
    required this.moveClass,
    required this.boardSize,
    required this.orientation,
  });

  final Square square;
  final MoveClass moveClass;
  final double boardSize;
  final Side orientation;

  static LichessMoveAnnotationType? _typeOf(MoveClass c) => switch (c) {
    MoveClass.brilliant => LichessMoveAnnotationType.brilliant,
    MoveClass.great => LichessMoveAnnotationType.goodMove,
    MoveClass.best => LichessMoveAnnotationType.bestMove,
    MoveClass.inaccuracy => LichessMoveAnnotationType.inaccuracy,
    MoveClass.mistake => LichessMoveAnnotationType.mistake,
    MoveClass.blunder => LichessMoveAnnotationType.blunder,
    MoveClass.missedWin => LichessMoveAnnotationType.missedWin,
    MoveClass.book => LichessMoveAnnotationType.bookMove,
    MoveClass.interesting => null,
  };

  @override
  Widget build(BuildContext context) {
    final type = _typeOf(moveClass);
    if (type == null) return const SizedBox.shrink();
    final sq = boardSize / 8;
    final file = orientation == Side.white ? square.file : 7 - square.file;
    final row = orientation == Side.white ? 7 - square.rank : square.rank;
    final size = sq * 0.40;
    final left = (file * sq + sq - size / 2).clamp(0.0, boardSize - size);
    final top = (row * sq - size / 2 + sq * 0.04).clamp(0.0, boardSize - size);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final badge = DecoratedBox(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: SvgPicture.asset(
        moveAnnotationIconAsset(type),
        width: size,
        height: size,
        fit: BoxFit.contain,
      ),
    );
    return Positioned(
      left: left,
      top: top,
      width: size,
      height: size,
      child: IgnorePointer(
        child: reduceMotion
            ? badge
            : SingleMotionBuilder(
                key: ValueKey(Object.hash(square, moveClass)),
                from: 0.6,
                value: 1,
                motion: const CupertinoMotion.bouncy(),
                builder: (context, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: badge,
              ),
      ),
    );
  }
}
