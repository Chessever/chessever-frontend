import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

/// Evaluation bar shown beside the active chess board.
/// It reflects the evaluation managed by the board provider and keeps the last
/// known value while the engine continues deepening.
class EvaluationBarWidget extends StatefulWidget {
  final double width;
  final double height;
  final bool isFlipped;
  final double? evaluation;
  final int? mate;
  final bool isEvaluating;
  final bool isWhiteToMove;
  final String? positionKey;

  /// The position is checkmate: the label reads "#", as the game cards' bar
  /// does, instead of the pawn count the caller fills the bar with.
  final bool isCheckmate;

  const EvaluationBarWidget({
    required this.width,
    required this.height,
    required this.isFlipped,
    required this.evaluation,
    required this.mate,
    required this.isEvaluating,
    this.isWhiteToMove = true,
    this.positionKey,
    this.isCheckmate = false,
    super.key,
  });

  @override
  State<EvaluationBarWidget> createState() => _EvaluationBarWidgetState();
}

class _EvaluationBarWidgetState extends State<EvaluationBarWidget>
    with SingleTickerProviderStateMixin {
  double? _lastEval;
  int? _lastMate;
  bool _awaitingNewEvaluation = false;
  double _whiteRatioTarget = 0.5;
  String? _lastPositionKey;

  /// White's share of the bar, sprung toward [_whiteRatioTarget].
  ///
  /// It reaches the screen through paint only ([_EvalBarPainter] and
  /// [_EvalChipFlow] repaint from it): no widget rebuilds and nothing is laid
  /// out on a tick. The board bar sits inside the board's LayoutBuilder, where
  /// any widget rebuilt by a tick schedules that LayoutBuilder's layout, which
  /// reaches the page and repaints the app bar, the player rows and the engine
  /// lines on every frame of the spring, past this bar's RepaintBoundary.
  late final SingleMotionController _ratio;
  late double _sprungTo;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _lastEval = widget.evaluation;
    _lastMate = widget.mate;
    _lastPositionKey = widget.positionKey;
    _awaitingNewEvaluation = (widget.evaluation == null && widget.mate == null);
    final initialEval = widget.evaluation ?? 0.0;
    final initialMate = widget.mate ?? 0;
    _whiteRatioTarget = _ratioForEval(initialEval, initialMate);
    _sprungTo = _whiteRatioTarget;
    _ratio = SingleMotionController(
      motion: _evalBarMotion,
      vsync: this,
      initialValue: _whiteRatioTarget,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  @override
  void dispose() {
    _ratio.dispose();
    super.dispose();
  }

  /// Springs the bar to [_whiteRatioTarget], or jumps there when the reader
  /// turned animations off.
  void _moveRatio() {
    if (_whiteRatioTarget == _sprungTo) return;
    _sprungTo = _whiteRatioTarget;
    if (_reduceMotion) {
      _ratio
        ..stop()
        ..value = _whiteRatioTarget;
    } else {
      _ratio.animateTo(_whiteRatioTarget);
    }
  }

  @override
  void didUpdateWidget(covariant EvaluationBarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    bool changed = false;
    final positionChanged = widget.positionKey != _lastPositionKey;
    final hasIncomingData = widget.evaluation != null || widget.mate != null;
    final mateChanged = widget.mate != _lastMate;
    final evalChanged =
        widget.evaluation != null &&
        (widget.evaluation != _lastEval || positionChanged);

    // Position changed but no evaluation ever arrived for it (cancelled/timeout).
    // Stop waiting so the UI doesn't stay on "..." indefinitely.
    if (_awaitingNewEvaluation && !widget.isEvaluating && !hasIncomingData) {
      _awaitingNewEvaluation = false;
      _lastEval = null;
      _lastMate = null;
      _whiteRatioTarget = 0.5;
      changed = true;
    }

    if (positionChanged) {
      _lastPositionKey = widget.positionKey;
      _awaitingNewEvaluation = true;
      changed = true;
    }

    if (mateChanged) {
      _lastMate = widget.mate;
    }
    if (evalChanged) {
      _lastEval = widget.evaluation;
    }
    if (positionChanged && widget.evaluation != null && !evalChanged) {
      // Same numeric eval for a new position still represents fresh data
      _lastEval = widget.evaluation;
    }

    final shouldUpdateRatio =
        mateChanged ||
        evalChanged ||
        (positionChanged && hasIncomingData) ||
        (_awaitingNewEvaluation && hasIncomingData);

    if (shouldUpdateRatio) {
      _awaitingNewEvaluation = false;
      final effectiveEval = _effectiveEval(_lastEval, _lastMate);
      final newRatio = _whiteRatio(effectiveEval);
      if ((newRatio - _whiteRatioTarget).abs() > 0.0005 || positionChanged) {
        _whiteRatioTarget = newRatio.clamp(0.0, 1.0).toDouble();
      }
      changed = true;
    }

    if (changed) {
      _moveRatio();
      setState(() {});
    }
  }

  double _whiteRatio(double eval) => _normalizedEvalToRatio(eval);

  double _effectiveEval(double? eval, int? mate) {
    final effectiveMate = mate ?? _lastMate;
    if (effectiveMate != null && effectiveMate != 0) {
      return effectiveMate > 0 ? 10.0 : -10.0;
    }
    return eval ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final rawEval = widget.evaluation ?? _lastEval ?? 0.0;
    final rawMate = widget.mate ?? _lastMate ?? 0;

    // CRITICAL FIX: Chess evaluations are ALWAYS from White's perspective
    // Positive = White advantage, Negative = Black advantage
    // This should NEVER be negated based on whose turn it is
    final displayEval = rawEval;
    final displayMate = rawMate;
    final awaitingNewPositionData = _awaitingNewEvaluation;
    final hasEval =
        !awaitingNewPositionData &&
        ((widget.evaluation != null || _lastEval != null) || displayMate != 0);
    final showLoading =
        awaitingNewPositionData || (widget.isEvaluating && !hasEval);
    final displayText = showLoading
        ? '...'
        : !hasEval
        ? ''
        : widget.isCheckmate
        ? '#'
        : (displayEval.abs() >= 10.0 && displayMate != 0)
        ? '#$displayMate'
        : _formatSignedEval(displayEval);

    // White/black shares are chess-semantic, but the *paints* come from
    // AppColors so light mode can use the broadcast mint-grey rail instead of
    // a leftover near-black slab.
    final whitePieceColor = context.colors.evalWhite;
    final blackPieceColor = context.colors.evalBlack;

    // The spring moves the bar and its chip through paint only (see [_ratio]);
    // this layer keeps those repaints to the bar itself.
    return RepaintBoundary(
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: CustomPaint(
          painter: _EvalBarPainter(
            ratio: _ratio,
            isFlipped: widget.isFlipped,
            whiteColor: whitePieceColor,
            blackColor: blackPieceColor,
          ),
          // Evaluation text at the meeting point of black and white. No
          // number (e.g. Feed autoplay cache miss) means no chip: an empty
          // cyan block reads as a leftover, not a state.
          child: displayText.isEmpty
              ? null
              : Flow(
                  delegate: _EvalChipFlow(
                    ratio: _ratio,
                    isFlipped: widget.isFlipped,
                    lift: 10.h,
                    floor: 20.h,
                  ),
                  children: [
                    Container(
                      width: widget.width,
                      color: kPrimaryColor,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          displayText,
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          style: AppTypography.textSmRegular.copyWith(
                            // Light takes dark ink on the cyan chip (8.2:1);
                            // dark keeps its shipped white label unchanged.
                            color: context.isLightTheme
                                ? context.colors.inkOnAccent
                                : Colors.white,
                            fontSize: 3.5.f,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// The bar's spring: smooth, no bounce.
const Motion _evalBarMotion = CupertinoMotion.smooth();

/// Height of the bar's top fill (black's share, or white's when flipped) for
/// white's share [whiteRatio] of a bar [height] tall.
double _evalBarTopHeight(double whiteRatio, double height, bool isFlipped) {
  final white = whiteRatio.clamp(0.0, 1.0).toDouble();
  return (isFlipped ? white : 1.0 - white) * height;
}

/// The two fills of the evaluation bar, split where [ratio] says.
class _EvalBarPainter extends CustomPainter {
  _EvalBarPainter({
    required this.ratio,
    required this.isFlipped,
    required this.whiteColor,
    required this.blackColor,
  }) : super(repaint: ratio);

  final Animation<double> ratio;
  final bool isFlipped;
  final Color whiteColor;
  final Color blackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final topHeight = _evalBarTopHeight(ratio.value, size.height, isFlipped);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, topHeight),
      Paint()..color = isFlipped ? whiteColor : blackColor,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, topHeight, size.width, size.height - topHeight),
      Paint()..color = isFlipped ? blackColor : whiteColor,
    );
  }

  @override
  bool shouldRepaint(_EvalBarPainter oldDelegate) =>
      oldDelegate.ratio != ratio ||
      oldDelegate.isFlipped != isFlipped ||
      oldDelegate.whiteColor != whiteColor ||
      oldDelegate.blackColor != blackColor;
}

/// Places the evaluation chip on the line where the fills meet, [lift] above
/// it, kept inside the bar ([floor] from the bottom). Moves by paint only.
class _EvalChipFlow extends FlowDelegate {
  _EvalChipFlow({
    required this.ratio,
    required this.isFlipped,
    required this.lift,
    required this.floor,
  }) : super(repaint: ratio);

  final Animation<double> ratio;
  final bool isFlipped;
  final double lift;
  final double floor;

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) =>
      BoxConstraints.tightFor(width: constraints.maxWidth);

  @override
  void paintChildren(FlowPaintingContext context) {
    final height = context.size.height;
    final topHeight = _evalBarTopHeight(ratio.value, height, isFlipped);
    final top = (topHeight - lift)
        .clamp(0.0, math.max(0.0, height - floor))
        .toDouble();
    context.paintChild(0, transform: Matrix4.translationValues(0, top, 0));
  }

  @override
  bool shouldRepaint(_EvalChipFlow oldDelegate) =>
      oldDelegate.ratio != ratio ||
      oldDelegate.isFlipped != isFlipped ||
      oldDelegate.lift != lift ||
      oldDelegate.floor != floor;
}

/// Provider to cache checkmate detection results to avoid expensive calculations during scroll
final _checkmateCacheProvider = Provider.autoDispose.family<bool?, String>((
  ref,
  fen,
) {
  // Delay disposal by 3 seconds to prevent thrashing during fast scrolling
  final link = ref.keepAlive();
  final timer = Timer(const Duration(seconds: 3), () {
    link.close();
  });
  ref.onDispose(() => timer.cancel());

  if (fen.isEmpty) return null;
  try {
    final setup = Setup.parseFen(fen);
    final position = Chess.fromSetup(setup);

    // Fast path: if king is not in check, it cannot be checkmate.
    if (!position.isCheck) return null;

    if (position.isCheckmate) {
      // The side to move is the one that got checkmated
      // If it's black's turn and checkmate, white won (true)
      return setup.turn == Side.black;
    }
    return null;
  } catch (_) {
    return null;
  }
});

/// Evaluation widget used on game cards.
/// Uses depth-aware local/Gamebase reuse first, then low-priority Stockfish.
/// Auto-disposes when card scrolls out of view (only evaluates visible boards).
class EvaluationBarWidgetForGames extends ConsumerStatefulWidget {
  final double width;
  final double height;
  final String fen;
  final PlayerView playerView;
  final bool isFlipped;
  final bool allowStockfishFallback;

  /// What the game's own record says of [fen] ([recordedEvalAt]). When set,
  /// the bar shows it and asks neither the caches nor the engine.
  final CloudEval? recordedEval;

  const EvaluationBarWidgetForGames({
    required this.width,
    required this.height,
    required this.fen,
    required this.playerView,
    this.isFlipped = false,
    this.allowStockfishFallback = true,
    this.recordedEval,
    super.key,
  });

  @override
  ConsumerState<EvaluationBarWidgetForGames> createState() =>
      _EvaluationBarWidgetForGamesState();
}

class _EvaluationBarWidgetForGamesState
    extends ConsumerState<EvaluationBarWidgetForGames> {
  _EvalBarDisplay? _lastDisplay;

  /// White fill ratio target — retained across FEN changes so geometry eases
  /// like the main board bar instead of snapping to neutral 0.5 while loading.
  double _whiteRatioTarget = 0.5;

  /// When the card FEN changes, hide the previous score label until fresh data
  /// arrives (main-board `_awaitingNewEvaluation` semantics).
  bool _awaitingNewPosition = false;

  @override
  void didUpdateWidget(covariant EvaluationBarWidgetForGames oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep scroll/rebuild stability only for the same position. Archive cards
    // can hydrate from a temporary starting FEN to the real final FEN, where
    // retaining the old *score text* would show the starting-position evaluation.
    // Geometry keeps [_whiteRatioTarget] so the bar does not jump to 0.5.
    if (oldWidget.fen != widget.fen) {
      _lastDisplay = null;
      _awaitingNewPosition = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    // First, check if position is checkmate - handle immediately without external eval
    // Uses the cached provider for better scroll performance
    final checkmateResult = ref.watch(_checkmateCacheProvider(widget.fen));
    if (checkmateResult != null) {
      // Checkmate detected - show definitive result
      // whiteWon = true means white delivered checkmate (eval +10.0)
      // whiteWon = false means black delivered checkmate (eval -10.0)
      final eval = checkmateResult ? 10.0 : -10.0;
      return _remember(
        _EvalBarDisplay(
          evaluation: eval,
          isCheckmate: true,
          hasEvaluationData: true,
        ),
      ).build(widget, whiteRatioTarget: _whiteRatioTarget);
    }

    if (widget.fen.isEmpty) {
      return _EvalBarDisplay.neutral(
        hasEvaluationData: false,
      ).build(widget, whiteRatioTarget: _whiteRatioTarget);
    }

    // Uses depth-aware cache/server reuse first, then low-priority Stockfish.
    // Auto-disposes when card scrolls out of view.
    final recorded = widget.recordedEval;
    final evalAsync = recorded != null
        ? AsyncValue.data(recorded)
        : widget.allowStockfishFallback
        ? ref.watch(gameCardEvalWithStockfishFallbackProvider(widget.fen))
        : ref.watch(gameCardEvalCacheOnlyProvider(widget.fen));

    final display = evalAsync.when(
      loading: () {
        // Same-position scroll: keep previous settled score.
        // New FEN: show "..." but keep prior fill ratio (main board style).
        if (_lastDisplay != null && !_awaitingNewPosition) {
          return _lastDisplay!.retainedWhileLoading();
        }
        return _EvalBarDisplay.neutral(
          isEvaluating: true,
          hasEvaluationData: false,
        );
      },
      error: (_, __) =>
          _lastDisplay ?? _EvalBarDisplay.neutral(hasEvaluationData: false),
      data: (cloud) {
        final pv = cloud.pvs.firstOrNull;
        if (pv == null) {
          return _lastDisplay ??
              _EvalBarDisplay.neutral(hasEvaluationData: false);
        }

        final normalized = _normalizePvToWhitePerspective(pv);
        return _remember(
          _EvalBarDisplay(
            evaluation: normalized.eval,
            isMate: normalized.isMate,
            mate: normalized.mate,
            hasEvaluationData: true,
          ),
        );
      },
    );

    // FEN just changed and we still hold no settled data for the new position:
    // force loading text even if AsyncValue briefly reports something else.
    final paintDisplay = _awaitingNewPosition && !display.hasEvaluationData
        ? _EvalBarDisplay.neutral(isEvaluating: true, hasEvaluationData: false)
        : display;

    return paintDisplay.build(widget, whiteRatioTarget: _whiteRatioTarget);
  }

  _EvalBarDisplay _remember(_EvalBarDisplay display) {
    _lastDisplay = display;
    _awaitingNewPosition = false;
    if (display.hasEvaluationData) {
      final newRatio = _ratioFromDisplay(display);
      if ((newRatio - _whiteRatioTarget).abs() > 0.0005) {
        _whiteRatioTarget = newRatio.clamp(0.0, 1.0);
      }
    }
    return display;
  }

  double _ratioFromDisplay(_EvalBarDisplay display) {
    if (display.isMate && display.mate != 0) {
      return _ratioForEval(display.evaluation, display.mate);
    }
    return _ratioForEval(display.evaluation, 0);
  }
}

class _EvalBarDisplay {
  const _EvalBarDisplay({
    required this.evaluation,
    this.isEvaluating = false,
    this.isMate = false,
    this.mate = 0,
    this.isCheckmate = false,
    this.hasEvaluationData = true,
  });

  factory _EvalBarDisplay.neutral({
    bool isEvaluating = false,
    bool hasEvaluationData = true,
  }) {
    return _EvalBarDisplay(
      evaluation: 0.0,
      isEvaluating: isEvaluating,
      hasEvaluationData: hasEvaluationData,
    );
  }

  final double evaluation;
  final bool isEvaluating;
  final bool isMate;
  final int mate;
  final bool isCheckmate;
  final bool hasEvaluationData;

  _EvalBarDisplay retainedWhileLoading() {
    return _EvalBarDisplay(
      evaluation: evaluation,
      isEvaluating: isEvaluating,
      isMate: isMate,
      mate: mate,
      isCheckmate: isCheckmate,
      hasEvaluationData: hasEvaluationData,
    );
  }

  Widget build(
    EvaluationBarWidgetForGames widget, {
    required double whiteRatioTarget,
  }) {
    return _Bars(
      width: widget.width,
      height: widget.height,
      whiteRatioTarget: whiteRatioTarget,
      evaluation: evaluation,
      isEvaluating: isEvaluating,
      isMate: isMate,
      mate: mate,
      isCheckmate: isCheckmate,
      hasEvaluationData: hasEvaluationData,
      playerView: widget.playerView,
      isFlipped: widget.isFlipped,
    );
  }
}

/// Game-card eval bar paint: same smooth ratio motion as [EvaluationBarWidget].
class _Bars extends StatelessWidget {
  final double width;
  final double height;
  final double whiteRatioTarget;
  final double evaluation;
  final PlayerView playerView;
  final bool isFlipped;
  final bool isEvaluating;
  final bool isMate;
  final int mate;
  final bool isCheckmate;
  final bool hasEvaluationData;

  const _Bars({
    required this.width,
    required this.height,
    required this.whiteRatioTarget,
    required this.evaluation,
    required this.playerView,
    required this.isFlipped,
    this.isEvaluating = false,
    this.isMate = false,
    this.mate = 0,
    this.isCheckmate = false,
    this.hasEvaluationData = true,
  });

  @override
  Widget build(BuildContext context) {
    final whitePieceColor = context.colors.evalWhite;
    final blackPieceColor = context.colors.evalBlack;

    final labelInset = playerView == PlayerView.gridView ? 6.h : 10.h;
    // A bar shorter than its label (a card mid-collapse, a 0-height first
    // layout) would make the upper bound negative, and `clamp` throws when
    // upper < lower: once per animation frame (Sentry CHESSEVER-27D).
    final labelClampMax = math.max(
      0.0,
      height - (playerView == PlayerView.gridView ? 12.h : 20.h),
    );

    final displayText = isEvaluating && !hasEvaluationData
        ? '...'
        : !hasEvaluationData
        ? ''
        : isCheckmate
        ? '#'
        : (isMate && mate != 0)
        ? '#$mate'
        : _formatSignedEval(evaluation);

    return SingleMotionBuilder(
      motion: const CupertinoMotion.smooth(),
      value: whiteRatioTarget,
      builder: (context, animatedRatio, _) {
        final whiteRatio = animatedRatio.clamp(0.0, 1.0).toDouble();
        final blackRatio = 1.0 - whiteRatio;
        final whiteHeight = whiteRatio * height;
        final blackHeight = blackRatio * height;
        final topHeight = isFlipped ? whiteHeight : blackHeight;
        final bottomHeight = isFlipped ? blackHeight : whiteHeight;
        final topColor = isFlipped ? whitePieceColor : blackPieceColor;
        final bottomColor = isFlipped ? blackPieceColor : whitePieceColor;

        return SizedBox(
          width: width,
          height: height,
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: Container(
                  width: width,
                  height: topHeight,
                  color: topColor,
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: width,
                  height: bottomHeight,
                  color: bottomColor,
                ),
              ),
              // Evaluation text positioned at the meeting point of black/white.
              // Skip the chip when there is nothing to say.
              if (displayText.isNotEmpty)
                Positioned(
                  left: 0,
                  right: 0,
                  top: (topHeight - labelInset).clamp(0.0, labelClampMax),
                  child: Container(
                    width: width,
                    color: kPrimaryColor,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        displayText,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        style: AppTypography.textSmRegular.copyWith(
                          // Light takes dark ink on the cyan chip (8.2:1);
                          // dark keeps its shipped white label unchanged.
                          color: context.isLightTheme
                              ? context.colors.inkOnAccent
                              : Colors.white,
                          fontSize: playerView == PlayerView.gridView
                              ? 0.2.f
                              : 1.5.f,
                          fontWeight: playerView == PlayerView.gridView
                              ? FontWeight.w300
                              : FontWeight.w600,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

({double eval, bool isMate, int mate}) _normalizePvToWhitePerspective(Pv pv) {
  final sign = pv.whitePerspective ? 1 : -1;
  final isMate = pv.isMate && pv.mate != null;
  final normalizedMate = (pv.mate ?? 0) * sign;
  final normalizedEval = (pv.cp * sign) / 100.0;
  return (eval: normalizedEval, isMate: isMate, mate: normalizedMate);
}

String _formatSignedEval(double evaluation) {
  final value = evaluation.abs() < 0.05 ? 0.0 : evaluation;
  if (value == 0.0) {
    return '0.0';
  }
  final formatted = value.toStringAsFixed(1);
  return value > 0 ? '+$formatted' : formatted;
}

double _normalizedEvalToRatio(double eval) {
  const double scale = 3.0;
  const double minRatio = 0.02;
  const double maxRatio = 0.98;
  final double clampedEval = eval.clamp(-20.0, 20.0);
  final double logistic = 1.0 / (1.0 + math.exp(-clampedEval / scale));
  return logistic.clamp(minRatio, maxRatio);
}

double _ratioForEval(double evaluation, int mate) {
  final double effectiveEval = mate != 0
      ? (mate > 0 ? 10.0 : -10.0)
      : evaluation;
  return _normalizedEvalToRatio(effectiveEval);
}
