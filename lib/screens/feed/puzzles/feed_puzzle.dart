import 'dart:async';

import 'package:chessever2/config/puzzle_service_config.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/screens/chessboard/classification_fx/classification_fx.dart';
import 'package:chessever2/screens/chessboard/classification_fx/move_class.dart';
import 'package:chessever2/screens/feed/feed_visibility.dart';
import 'package:chessever2/screens/feed/puzzles/feed_puzzle_model.dart';
import 'package:chessever2/screens/feed/puzzles/puzzle_repository.dart';
import 'package:chessever2/screens/feed/puzzles/puzzle_service_client.dart';
import 'package:chessever2/screens/feed/puzzles/puzzle_session.dart';
import 'package:chessever2/screens/feed/puzzles/puzzle_store.dart';
import 'package:chessever2/screens/feed/puzzles/puzzle_difficulty_sheet.dart';
import 'package:chessever2/screens/feed/puzzles/puzzle_widgets.dart';
import 'package:chessever2/screens/feed/race/puzzle_rating_range.dart';
import 'package:chessever2/screens/feed/widgets/feed_action_row.dart';
import 'package:chessever2/screens/feed/widgets/feed_classification.dart';
import 'package:chessever2/screens/feed/widgets/feed_glyphs.dart';
import 'package:chessever2/screens/feed/widgets/feed_post_header.dart';
import 'package:chessever2/screens/feed/widgets/feed_layout.dart';
import 'package:chessever2/screens/feed/widgets/feed_sfx_provider.dart';
import 'package:chessever2/screens/feed/widgets/feed_states.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

export 'package:chessever2/screens/feed/puzzles/feed_puzzle_model.dart';

/// Puzzles for the Feed: ChessEver's puzzle service ([kRaceApiUrl]), the
/// local cache and the list. Overridable in tests.
final feedPuzzleRepositoryProvider = Provider<FeedPuzzleRepository>((ref) {
  final client = PuzzleServiceClient(baseUrl: kRaceApiUrl);
  ref.onDispose(client.close);
  return FeedPuzzleRepository(
    client: client,
    store: SqliteFeedPuzzleStore(AppDatabase.instance),
    // The difficulty the viewer picked, shared with Puzzle Race.
    band: () {
      final range = ref.read(puzzleRatingRangeProvider);
      return (min: range.min, max: range.max);
    },
  );
});

/// Puzzles to interleave into the Feed.
///
/// Served from the local cache when it has puzzles (the service is only
/// asked in the background then); puzzles the viewer finished are dropped.
/// Resolves to an empty list, never an error, when the service is out of
/// reach, and stays empty without retrying when none is configured.
///
/// The list is not frozen for the life of the process. It loads again:
/// * after a back-off when it came back empty (offline, a timeout, a 429, a
///   failed load), never before the service's own 429 window ends;
/// * when a top-up for a load that came up short lands in the cache;
/// * on returning to the app, when the list is empty or older than
///   [kFeedPuzzlesResumeRefresh].
///
/// Pages the viewer already reached keep their puzzle through a reload (the
/// Feed freezes them), so only pages ahead of them pick up the change.
final feedPuzzlesProvider = FutureProvider<List<FeedPuzzle>>((ref) async {
  final repository = ref.watch(feedPuzzleRepositoryProvider);
  if (!repository.isConfigured) {
    // Nothing to ask and nothing to retry; the repository logs it once.
    return repository.load();
  }
  var alive = true;
  Timer? retry;
  AppLifecycleListener? lifecycle;
  ref.onDispose(() {
    alive = false;
    retry?.cancel();
    lifecycle?.dispose();
  });
  void reload() {
    if (alive) ref.invalidateSelf();
  }

  // A new difficulty: puzzles outside it leave the cache and the list loads
  // again inside it. Pages the viewer already reached keep their puzzle.
  ref.listen<PuzzleRatingRange>(puzzleRatingRangeProvider, (previous, next) {
    if (previous == next) return;
    unawaited(
      repository.retainWithin(next.min, next.max).then((_) => reload()),
    );
  });

  List<FeedPuzzle> puzzles;
  try {
    puzzles = await repository.load();
  } catch (error) {
    // load() is not meant to throw; if it ever does, an error here would
    // never be retried, so it counts as an empty load instead.
    debugPrint('[FeedPuzzles] load failed: $error');
    puzzles = const [];
  }
  if (!alive) return puzzles;
  final loadedAt = DateTime.now();

  if (puzzles.isEmpty) {
    final attempt = _emptyLoads[repository] ?? 0;
    _emptyLoads[repository] = attempt + 1;
    retry = Timer(
      feedPuzzlesRetryDelay(
        attempt: attempt,
        now: loadedAt,
        blockedUntil: repository.blockedUntil,
      ),
      reload,
    );
  } else {
    _emptyLoads[repository] = null;
    unawaited(
      repository.backgroundUpdate.then((arrived) {
        if (arrived) reload();
      }),
    );
  }

  lifecycle = _listenForResume(() {
    final now = DateTime.now();
    if (puzzles.isEmpty) {
      // Maybe back online; the retry timer covers a 429 window.
      final blocked = repository.blockedUntil;
      if (blocked == null || !now.isBefore(blocked)) reload();
      return;
    }
    if (now.difference(loadedAt) >= kFeedPuzzlesResumeRefresh) reload();
  });
  return puzzles;
});

/// A non-empty puzzle list older than this loads again when the app comes
/// back to the foreground (finished puzzles drop out, the pool tops up).
const Duration kFeedPuzzlesResumeRefresh = Duration(minutes: 15);

/// Consecutive empty loads per repository, for the retry back-off.
final Expando<int> _emptyLoads = Expando<int>('feedPuzzleEmptyLoads');

/// How long an empty puzzle list waits before loading again: 30 s, doubling
/// per consecutive empty load up to 5 min, and never before the service's
/// 429 window ([blockedUntil]) ends.
@visibleForTesting
Duration feedPuzzlesRetryDelay({
  required int attempt,
  required DateTime now,
  DateTime? blockedUntil,
}) {
  const base = Duration(seconds: 30);
  const cap = Duration(minutes: 5);
  final backoff = base * (1 << attempt.clamp(0, 4));
  var delay = backoff > cap ? cap : backoff;
  if (blockedUntil != null) {
    final blocked = blockedUntil.difference(now) + const Duration(seconds: 1);
    if (blocked > delay) delay = blocked;
  }
  return delay;
}

/// Calls [onResume] whenever the app returns to the foreground. Null without
/// a Flutter binding (plain Dart tests), where there is no app lifecycle.
AppLifecycleListener? _listenForResume(VoidCallback onResume) {
  try {
    return AppLifecycleListener(onResume: onResume);
  } on FlutterError {
    return null;
  }
}

/// Where puzzle sounds go: the classified-move sounds when a move is judged,
/// the board's usual sounds otherwise. Silent while the Feed is muted or the
/// board's sound setting is off. Tests override it with a recorder.
class FeedPuzzleSounds {
  const FeedPuzzleSounds({this._isSilent, this._onSounded});

  final bool Function()? _isSilent;

  /// Told of every sound asked for, so leaving Feed can cut one still
  /// ringing ([FeedSfx.hush]).
  final void Function()? _onSounded;

  /// Fire-and-forget; a sound failure never reaches the puzzle.
  void move({required String san, MoveClass? moveClass}) {
    try {
      if (_isSilent?.call() ?? false) return;
      _onSounded?.call();
      ClassificationSfx.playMove(san: san, moveClass: moveClass);
    } catch (error) {
      debugPrint('[FeedPuzzles] sound failed: $error');
    }
  }
}

final feedPuzzleSoundsProvider = Provider<FeedPuzzleSounds>(
  (ref) => FeedPuzzleSounds(
    isSilent: () {
      // The Feed's speaker toggle, and the board's own Sound setting.
      final sfx = ref.read(feedSfxProvider);
      return sfx.muted || !sfx.boardSoundEnabled;
    },
    onSounded: () => ref.read(feedSfxProvider).noteSounded(),
  ),
);

enum _Phase {
  /// Showing the position before the opponent's setup move.
  intro,

  /// The solver's turn.
  solving,

  /// A right move landed; the opponent answers shortly.
  replying,

  /// A wrong move is on the board; it goes back shortly.
  wrong,
  solved,

  /// The answer is playing out.
  revealing,
  revealed,
}

enum _Feedback { none, correct, wrong }

/// One Feed page: a playable puzzle.
///
/// The board is the board screen's interactive chessground board in the
/// viewer's theme, tap-to-move like the board screen (so it never fights the
/// Feed's vertical swipe), turned to the solver. The opponent's setup move
/// plays first; then a right move lands with the "best" sound and landing
/// (the finishing move with "brilliant") and the opponent answers; a wrong
/// move lands with the "mistake" sound and slides back. No engine runs here.
///
/// Anything timed (setup move, replies, the answer playing out) only runs
/// while the page is [isCurrent] and the Feed [isVisible], and picks up where
/// it stopped when it is seen again.
class FeedPuzzlePage extends ConsumerStatefulWidget {
  const FeedPuzzlePage({
    super.key,
    required this.puzzle,
    required this.isCurrent,
    required this.isVisible,
    required this.onRequestNext,
  });

  final FeedPuzzle puzzle;
  final bool isCurrent;
  final bool isVisible;
  final VoidCallback onRequestNext;

  @override
  ConsumerState<FeedPuzzlePage> createState() => _FeedPuzzlePageState();
}

class _FeedPuzzlePageState extends ConsumerState<FeedPuzzlePage> {
  static const Duration _setupDelay = Duration(milliseconds: 650);
  static const Duration _replyDelay = Duration(milliseconds: 450);
  static const Duration _wrongHold = Duration(milliseconds: 520);
  static const Duration _revealStep = Duration(milliseconds: 750);

  PuzzleSession? _session;
  ChessboardController? _board;
  _Phase _phase = _Phase.intro;
  _Feedback _feedback = _Feedback.none;
  Timer? _timer;

  /// The piece the hint points at.
  Square? _hint;

  /// Moves the viewer found before the answer was shown.
  int _found = 0;

  /// A wrong try or a hint came before the solve; it counts for less.
  bool _assisted = false;

  // The classified move on the board: badge + landing.
  Square? _markSquare;
  MoveClass? _markClass;
  int _markSeq = 0;

  /// Whether Feed is seen this instant ([FeedSeen]); null outside a Feed.
  ValueListenable<bool>? _seen;

  bool get _active =>
      widget.isCurrent && widget.isVisible && (_seen?.value ?? true);

  bool get _canMove =>
      _active && _phase == _Phase.solving && (_session?.isSolverTurn ?? false);

  @override
  void initState() {
    super.initState();
    // Listened to, so leaving Feed stops a reply or the answer playing out
    // before its timer fires, not at the next frame.
    _seen = FeedSeen.maybeOf(context)?..addListener(_onSeenChanged);
    _load();
    _syncActive();
  }

  void _onSeenChanged() {
    if (!mounted) return;
    _syncActive();
    _pushBoard(animate: false);
  }

  @override
  void didUpdateWidget(covariant FeedPuzzlePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final puzzleChanged = oldWidget.puzzle != widget.puzzle;
    if (puzzleChanged) {
      _timer?.cancel();
      _timer = null;
      _board?.dispose();
      _board = null;
      _load();
    }
    if (puzzleChanged ||
        oldWidget.isCurrent != widget.isCurrent ||
        oldWidget.isVisible != widget.isVisible) {
      _syncActive();
      // Interactivity follows visibility: no moves on a page nobody sees.
      _pushBoard(animate: false);
    }
  }

  @override
  void dispose() {
    _seen?.removeListener(_onSeenChanged);
    _timer?.cancel();
    _board?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- setup

  void _load() {
    _phase = _Phase.intro;
    _feedback = _Feedback.none;
    _hint = null;
    _found = 0;
    _assisted = false;
    _clearMark();
    try {
      _session = PuzzleSession(widget.puzzle);
    } on FormatException catch (error) {
      debugPrint('[FeedPuzzles] unplayable ${widget.puzzle.id}: $error');
      _session = null;
      return;
    }
    final s = _session!;

    // Finished earlier in this session: show it finished, not fresh.
    final outcome = ref
        .read(feedPuzzleRepositoryProvider)
        .outcomeOf(widget.puzzle.id);
    if (outcome != null) {
      s.finish(solved: outcome == FeedPuzzleOutcome.solved);
      _phase = outcome == FeedPuzzleOutcome.solved
          ? _Phase.solved
          : _Phase.revealed;
      _found = outcome == FeedPuzzleOutcome.solved ? s.solverMoveCount : 0;
      _feedback = _Feedback.none;
    } else if (s.setupMove == null) {
      _phase = _Phase.solving;
    }

    final showsSetup = _phase == _Phase.intro;
    _board = ChessboardController(
      game: _data(
        showsSetup ? s.setupPosition : s.position,
        showsSetup ? null : s.lastMove,
        interactive: !showsSetup && _canMove,
      ),
    );
  }

  GameData _data(Position pos, Move? lastMove, {required bool interactive}) {
    final side = _session?.solver ?? Side.white;
    return GameData(
      fen: pos.fen,
      playerSide: interactive
          ? (side == Side.white ? PlayerSide.white : PlayerSide.black)
          : PlayerSide.none,
      sideToMove: pos.turn,
      validMoves: interactive ? makeLegalMoves(pos) : const {},
      lastMove: lastMove,
      kingSquareInCheck: pos.isCheck ? pos.board.kingOf(pos.turn) : null,
    );
  }

  /// Shows the session's position on the board (animated from wherever the
  /// board is), interactive only when it is the solver's turn and seen.
  void _pushBoard({bool animate = true}) {
    final s = _session;
    final board = _board;
    if (s == null || board == null) return;
    if (_phase == _Phase.intro) {
      board.updatePosition(
        _data(s.setupPosition, null, interactive: false),
        animate: animate,
      );
      return;
    }
    if (_phase == _Phase.wrong) return; // the wrong move stays until it goes
    board.updatePosition(
      _data(s.position, s.lastMove, interactive: _canMove),
      animate: animate,
    );
  }

  // --------------------------------------------------------------- timing

  void _schedule(Duration delay, VoidCallback run) {
    _timer?.cancel();
    _timer = Timer(delay, () {
      _timer = null;
      if (mounted && _active) run();
    });
  }

  /// Starts (or resumes) whatever is due for the current phase while the
  /// page is seen, and stops it while it is not.
  void _syncActive() {
    if (!_active) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (_timer != null) return;
    switch (_phase) {
      case _Phase.intro:
        _schedule(_setupDelay, _playSetup);
      case _Phase.replying:
        _schedule(_replyDelay, _playReply);
      case _Phase.wrong:
        _schedule(_wrongHold, _takeBack);
      case _Phase.revealing:
        _schedule(_revealStep, _revealNext);
      case _Phase.solving:
      case _Phase.solved:
      case _Phase.revealed:
        break;
    }
  }

  void _playSetup() {
    final s = _session;
    if (s == null || _phase != _Phase.intro) return;
    setState(() => _phase = _Phase.solving);
    _pushBoard();
    final san = s.setupSan;
    if (san != null) _sound(san);
  }

  void _playReply() {
    final s = _session;
    if (s == null || _phase != _Phase.replying) return;
    final step = s.advance();
    setState(() {
      _clearMark();
      _phase = s.isComplete ? _Phase.solved : _Phase.solving;
    });
    _pushBoard();
    if (step != null) _sound(step.san);
    if (_phase == _Phase.solved) _finished(FeedPuzzleOutcome.solved);
  }

  void _takeBack() {
    if (_phase != _Phase.wrong) return;
    setState(() {
      _clearMark();
      _phase = _Phase.solving;
    });
    // The board still shows the wrong move; this slides the piece home.
    _pushBoard();
  }

  // ---------------------------------------------------------------- moves

  void _onMove(Move move, {bool? viaDragAndDrop}) {
    final s = _session;
    final board = _board;
    if (s == null || board == null || !_canMove) return;
    final attempt = s.play(move);
    if (attempt == null) return;
    _hint = null;

    switch (attempt.verdict) {
      case PuzzleVerdict.wrong:
        board.updatePosition(
          _data(attempt.after, attempt.move, interactive: false),
        );
        setState(() {
          _mark(attempt.move.to, MoveClass.mistake);
          _feedback = _Feedback.wrong;
          _phase = _Phase.wrong;
          _assisted = true;
        });
        _sound(attempt.san, MoveClass.mistake);
        unawaited(HapticFeedbackService.medium());
        _schedule(_wrongHold, _takeBack);
      case PuzzleVerdict.correct:
        setState(() {
          _found = s.solverMovesPlayed;
          _mark(attempt.move.to, MoveClass.best);
          _feedback = _Feedback.correct;
          _phase = _Phase.replying;
        });
        _pushBoard();
        _sound(attempt.san, MoveClass.best);
        unawaited(HapticFeedbackService.light());
        _schedule(_replyDelay, _playReply);
      case PuzzleVerdict.solved:
        setState(() {
          _found = s.solverMoveCount;
          _mark(attempt.move.to, MoveClass.brilliant);
          _feedback = _Feedback.none;
          _phase = _Phase.solved;
        });
        _pushBoard();
        _sound(attempt.san, MoveClass.brilliant);
        unawaited(HapticFeedbackService.success());
        _finished(FeedPuzzleOutcome.solved);
    }
  }

  void _mark(Square square, MoveClass moveClass) {
    _markSquare = square;
    _markClass = moveClass;
    _markSeq++;
  }

  void _clearMark() {
    _markSquare = null;
    _markClass = null;
  }

  // -------------------------------------------------------------- actions

  void _showHint() {
    final hint = _session?.hint;
    if (hint == null || _phase != _Phase.solving) return;
    unawaited(HapticFeedbackService.buttonPress());
    setState(() {
      _hint = hint.from;
      _assisted = true;
    });
  }

  void _retry() {
    final s = _session;
    if (s == null) return;
    unawaited(HapticFeedbackService.buttonPress());
    _timer?.cancel();
    _timer = null;
    s.reset();
    setState(() {
      _phase = s.setupMove == null ? _Phase.solving : _Phase.intro;
      _feedback = _Feedback.none;
      _hint = null;
      _found = 0;
      _assisted = false;
      _clearMark();
    });
    // Back to the position before the setup move, which then plays again.
    _pushBoard(animate: false);
    _syncActive();
  }

  void _showSolution() {
    final s = _session;
    if (s == null ||
        !(_phase == _Phase.solving ||
            _phase == _Phase.wrong ||
            _phase == _Phase.replying)) {
      return;
    }
    unawaited(HapticFeedbackService.buttonPress());
    _timer?.cancel();
    _timer = null;
    s.beginReveal();
    setState(() {
      _phase = _Phase.revealing;
      _feedback = _Feedback.none;
      _hint = null;
      _clearMark();
    });
    _pushBoard(); // a wrong move on the board slides home first
    _finished(FeedPuzzleOutcome.revealed);
    _schedule(_revealStep, _revealNext);
  }

  void _revealNext() {
    final s = _session;
    if (s == null || _phase != _Phase.revealing) return;
    final step = s.advance();
    final done = step == null || s.isComplete;
    setState(() {
      if (done) _phase = _Phase.revealed;
    });
    _pushBoard();
    if (step != null) _sound(step.san);
    if (!done) _schedule(_revealStep, _revealNext);
  }

  void _finished(FeedPuzzleOutcome outcome) {
    final repo = ref.read(feedPuzzleRepositoryProvider);
    unawaited(
      repo
          .markFinished(
            widget.puzzle.id,
            outcome,
            rating: widget.puzzle.rating,
            assisted: _assisted,
          )
          .catchError((Object e) {
            debugPrint('[FeedPuzzles] could not record finish: $e');
          }),
    );
  }

  void _next() {
    unawaited(HapticFeedbackService.buttonPress());
    widget.onRequestNext();
  }

  void _sound(String san, [MoveClass? moveClass]) {
    try {
      ref.read(feedPuzzleSoundsProvider).move(san: san, moveClass: moveClass);
    } catch (error) {
      debugPrint('[FeedPuzzles] sound failed: $error');
    }
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final s = _session;
    final board = _board;
    if (s == null || board == null) {
      return FeedMessage(
        title: "This puzzle can't be played",
        body: "Its moves didn't check out.",
        actionLabel: 'Next',
        onAction: widget.onRequestNext,
      );
    }

    final settings =
        ref.watch(boardSettingsProviderNew).valueOrNull ??
        const BoardSettingsNew();
    final colors = context.colors;
    final solver = s.solver;
    final puzzle = widget.puzzle;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final shown = s.solverMovesPlayed;

    return LayoutBuilder(
      builder: (context, constraints) {
        final l = FeedLayout.resolve(
          constraints,
          MediaQuery.textScalerOf(context),
          evalWidth: 20.w,
        );

        // The board column: rail, board and the player rows.
        Widget content(Widget child) => Padding(
          padding: EdgeInsets.only(left: l.contentLeft),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(width: l.contentWidth, child: child),
          ),
        );

        // The text rows (header, status, buttons) keep the page gutter, as
        // on the game pages, so a height-bound board never shrinks a label.
        Widget fullRow(Widget child) => Padding(
          padding: const EdgeInsets.only(left: FeedLayout.sidePadding),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(width: l.rowWidth, child: child),
          ),
        );

        final opponent = solver == Side.white ? Side.black : Side.white;
        FeedPuzzlePlayer? playerOf(Side side) =>
            side == Side.white ? puzzle.white : puzzle.black;

        final markSquare = _markSquare;
        final markClass = _markClass;
        final boardStack = SizedBox.square(
          key: const ValueKey('feed_puzzle_board'),
          dimension: l.board,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Chessboard(
                size: l.board,
                controller: board,
                orientation: solver,
                settings: ChessboardSettings(
                  enableCoordinates: settings.showCoordinates,
                  animationDuration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 200),
                  dragFeedbackScale: 1,
                  dragTargetKind: DragTargetKind.none,
                  pieceShiftMethod: PieceShiftMethod.tapTwoSquares,
                  autoQueenPromotionOnPremove: false,
                  enablePremoves: false,
                  pieceOrientationBehavior: PieceOrientationBehavior.facingUser,
                  colorScheme: settings.colorScheme,
                  pieceAssets: settings.pieceAssets,
                ),
                shapes: {
                  if (_hint != null)
                    Circle(
                      color: colors.brand.withValues(alpha: 0.9),
                      orig: _hint!,
                    ),
                },
                // The judged move's piece settles on its square, keyed like
                // the [ClassificationLanding] overlay below.
                landingSquare: markClass != null ? markSquare : null,
                landingKey: markClass != null ? _markSeq : null,
                onMove: _onMove,
              ),
              if (markSquare != null && markClass != null)
                PuzzleMoveBadge(
                  square: markSquare,
                  moveClass: markClass,
                  boardSize: l.board,
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
            ],
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: l.scrublessTop),
            fullRow(_Meta(puzzle: puzzle, height: l.metaHeight)),
            const SizedBox(height: FeedLayout.gap),
            content(
              PuzzlePlayerRow(
                player: playerOf(opponent),
                side: opponent,
                pieceAssets: settings.pieceAssets,
                height: l.rowHeight,
              ),
            ),
            const SizedBox(height: FeedLayout.gap),
            content(
              Row(
                children: [
                  PuzzleProgressRail(
                    total: s.solverMoveCount,
                    found: _found,
                    shown: shown < _found ? _found : shown,
                    height: l.board,
                    width: l.evalWidth,
                  ),
                  boardStack,
                ],
              ),
            ),
            const SizedBox(height: FeedLayout.gap),
            content(
              PuzzlePlayerRow(
                player: playerOf(solver),
                side: solver,
                pieceAssets: settings.pieceAssets,
                height: l.rowHeight,
                isSolver: true,
              ),
            ),
            SizedBox(height: l.scrublessInfoSpace),
            fullRow(
              _Status(
                phase: _phase,
                feedback: _feedback,
                solver: solver,
                height: l.infoHeight,
              ),
            ),
            SizedBox(height: l.scrublessActionsSpace),
            fullRow(SizedBox(height: l.actionsHeight, child: _actions())),
            // The game pages' scrub line has no counterpart here; its room
            // is spread through the page ([FeedLayout.scrublessTop]), so the
            // puzzle is composed on its own frame and ends where a game
            // post does, with no idle band under the buttons.
          ],
        );
      },
    );
  }

  /// Hint · Retry · Solution · Next, in the game posts' action row: the
  /// same glyph-over-word columns at the same height, so a puzzle reads as
  /// one more post in the stream. All four always hold their place; one that
  /// does nothing right now is dimmed rather than removed, so nothing shifts
  /// under the thumb as the puzzle moves on.
  Widget _actions() {
    final colors = context.colors;
    final solving = _phase == _Phase.solving;
    final canReveal =
        solving || _phase == _Phase.wrong || _phase == _Phase.replying;
    final finished = _phase == _Phase.solved || _phase == _Phase.revealed;
    final triedSomething =
        finished || (_session?.step ?? 0) > 0 || _feedback != _Feedback.none;

    Widget action({
      required String key,
      required String label,
      required String glyph,
      required VoidCallback? onTap,
      String? hint,
    }) {
      final enabled = onTap != null;
      return Expanded(
        child: FeedPressable(
          key: ValueKey(key),
          semanticsLabel: label,
          semanticsHint: hint,
          onTap: onTap,
          child: Opacity(
            opacity: enabled ? 1 : 0.32,
            child: FeedActionLabel(
              label: label,
              icon: FeedGlyph(
                glyph,
                width: 22,
                height: 22,
                color: colors.textPrimary,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        action(
          key: 'feed_puzzle_hint',
          label: 'Hint',
          glyph: FeedGlyphs.hint,
          hint: 'Show which piece to move',
          onTap: solving && _hint == null ? _showHint : null,
        ),
        action(
          key: 'feed_puzzle_retry',
          label: 'Retry',
          glyph: FeedGlyphs.retry,
          hint: 'Start the puzzle again',
          onTap: triedSomething && _phase != _Phase.revealing ? _retry : null,
        ),
        action(
          key: 'feed_puzzle_solution',
          label: 'Solution',
          glyph: FeedGlyphs.solution,
          hint: 'Show the solution',
          onTap: canReveal ? _showSolution : null,
        ),
        action(
          key: 'feed_puzzle_next',
          label: 'Next',
          glyph: FeedGlyphs.next,
          hint: 'Next puzzle',
          onTap: _next,
        ),
      ],
    );
  }
}

/// The one line above the board, in the game pages' header slot: that this
/// is a puzzle, its rating, the opening it came from (or, for puzzles cached
/// before the puzzle service, the source game's speed), and on the right the
/// difficulty the viewer picked, which opens the difficulty sheet.
class _Meta extends ConsumerWidget {
  const _Meta({required this.puzzle, required this.height});

  final FeedPuzzle puzzle;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final range = ref.watch(puzzleRatingRangeProvider);
    final rating = puzzle.rating;
    final perf = puzzle.perfName?.trim() ?? '';
    final opening = puzzleOpeningName(puzzle.openingTags);
    final source = perf.isNotEmpty ? '$perf game' : opening;
    final difficulty = range.preset?.label ?? '${range.min}\u2013${range.max}';
    final hasSource = source != null && source.isNotEmpty;
    final ratingAt = rating == null ? null : 1;
    final sourceAt = hasSource ? (rating == null ? 1 : 2) : null;
    return Semantics(
      header: true,
      child: FeedPostHeader(
        key: const ValueKey('feed_puzzle_header'),
        height: height,
        parts: [
          const FeedHeaderPart(
            id: 'kind',
            pieces: [
              FeedHeaderPiece.text('Puzzle', tone: FeedHeaderTone.strong),
            ],
          ),
          if (rating != null)
            FeedHeaderPart(
              id: 'rating',
              pieces: [FeedHeaderPiece.text('Rating $rating')],
              compact: [FeedHeaderPiece.text('$rating')],
            ),
          if (hasSource)
            FeedHeaderPart(
              id: 'source',
              pieces: [
                FeedHeaderPiece.text(source, tone: FeedHeaderTone.secondary),
              ],
              shrinkable: true,
            ),
        ],
        compactOrder: [?ratingAt],
        shrinkOrder: [?sourceAt],
        // The difficulty on the right outlasts everything but its own
        // label: the board already says this is a puzzle.
        dropOrder: [?sourceAt, ?ratingAt, 0],
        trailing: FeedHeaderPart(
          id: 'difficulty',
          pieces: [
            FeedHeaderPiece.text(difficulty, tone: FeedHeaderTone.secondary),
            const FeedHeaderPiece.gap(4),
            FeedHeaderPiece.glyph(
              FeedGlyph(
                FeedGlyphs.chevronDown,
                width: 10,
                height: 10,
                color: colors.textSecondary,
              ),
              width: 10,
            ),
          ],
          onTap: () => unawaited(showPuzzleDifficultySheet(context, ref)),
          // A custom range is its own name, so it is read once.
          semanticsLabel: range.preset == null
              ? 'Puzzle difficulty, ${range.min} to ${range.max}'
              : 'Puzzle difficulty, $difficulty, ${range.min} to ${range.max}',
        ),
      ),
    );
  }
}

/// The one line that talks to the solver, in the game pages' move-info slot.
class _Status extends StatelessWidget {
  const _Status({
    required this.phase,
    required this.feedback,
    required this.solver,
    required this.height,
  });

  final _Phase phase;
  final _Feedback feedback;
  final Side solver;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final side = solver == Side.white ? 'White' : 'Black';
    final opponent = solver == Side.white ? 'Black' : 'White';
    final (String lead, String rest, Color? badgeTint) = switch (phase) {
      _Phase.solved => ('Solved', '', PuzzleMoveBadge.colorOf(MoveClass.best)),
      _Phase.revealing || _Phase.revealed => ('Solution', '', null),
      // The opponent's setup move has not played yet; the board is not the
      // solver's to touch, so do not prompt them.
      _Phase.intro => ('Watch the move', ' · $opponent to play', null),
      _ when feedback == _Feedback.wrong => (
        'Not quite',
        ' · try again',
        PuzzleMoveBadge.colorOf(MoveClass.mistake),
      ),
      _ when feedback == _Feedback.correct => (
        'Best move',
        ' · keep going',
        PuzzleMoveBadge.colorOf(MoveClass.best),
      ),
      _ => ('Your move', ' · $side to play', null),
    };
    // The verdict wears the badge's hue, walked until it reads as text on
    // the page in either theme.
    final tint = badgeTint == null
        ? null
        : feedReadableOn(badgeTint, colors.background);
    final base = AppTypography.textLgBold.copyWith(
      fontSize: 18,
      height: 24 / 18,
      color: colors.textPrimary,
    );
    return SizedBox(
      height: height,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          liveRegion: true,
          // Shrinks rather than cutting the line at large text sizes.
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
    );
  }
}
