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

  const EvaluationBarWidget({
    required this.width,
    required this.height,
    required this.isFlipped,
    required this.evaluation,
    required this.mate,
    required this.isEvaluating,
    this.isWhiteToMove = true,
    this.positionKey,
    super.key,
  });

  @override
  State<EvaluationBarWidget> createState() => _EvaluationBarWidgetState();
}

class _EvaluationBarWidgetState extends State<EvaluationBarWidget> {
  double? _lastEval;
  int? _lastMate;
  bool _awaitingNewEvaluation = false;
  double _whiteRatioTarget = 0.5;
  String? _lastPositionKey;

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
    final displayText =
        showLoading
            ? '...'
            : !hasEval
            ? ''
            : (displayEval.abs() >= 10.0 && displayMate != 0)
            ? '#$displayMate'
            : _formatSignedEval(displayEval);

    return SingleMotionBuilder(
      motion: const CupertinoMotion.smooth(),
      value: _whiteRatioTarget,
      builder: (context, animatedRatio, _) {
        final whiteRatio = animatedRatio.clamp(0.0, 1.0).toDouble();
        final blackRatio = 1.0 - whiteRatio;
        final whiteHeight = whiteRatio * widget.height;
        final blackHeight = blackRatio * widget.height;

        final topHeight = widget.isFlipped ? whiteHeight : blackHeight;
        final bottomHeight = widget.isFlipped ? blackHeight : whiteHeight;
        final topColor = widget.isFlipped ? kWhiteColor : kPopUpColor;
        final bottomColor = widget.isFlipped ? kPopUpColor : kWhiteColor;

        return SizedBox(
          width: widget.width,
          height: widget.height,
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: Container(
                  width: widget.width,
                  height: topHeight,
                  color: topColor,
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: widget.width,
                  height: bottomHeight,
                  color: bottomColor,
                ),
              ),
              // Evaluation text positioned at the meeting point of black/white
              Positioned(
                left: 0,
                right: 0,
                // Position at the edge where black and white meet, clamped to stay within bounds
                top: (topHeight - 10.h).clamp(0.0, widget.height - 20.h),
                child: Container(
                  width: widget.width,
                  color: kPrimaryColor,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      displayText,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: AppTypography.textSmRegular.copyWith(
                        color: Colors.white,
                        fontSize: 3.5.f,
                        fontWeight: FontWeight.w600,
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

  const EvaluationBarWidgetForGames({
    required this.width,
    required this.height,
    required this.fen,
    required this.playerView,
    this.isFlipped = false,
    this.allowStockfishFallback = true,
    super.key,
  });

  @override
  ConsumerState<EvaluationBarWidgetForGames> createState() =>
      _EvaluationBarWidgetForGamesState();
}

class _EvaluationBarWidgetForGamesState
    extends ConsumerState<EvaluationBarWidgetForGames> {
  _EvalBarDisplay? _lastDisplay;

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
      ).build(widget);
    }

    if (widget.fen.isEmpty) {
      return _EvalBarDisplay.neutral(hasEvaluationData: false).build(widget);
    }

    // Uses depth-aware cache/server reuse first, then low-priority Stockfish.
    // Auto-disposes when card scrolls out of view.
    final evalAsync =
        widget.allowStockfishFallback
            ? ref.watch(gameCardEvalWithStockfishFallbackProvider(widget.fen))
            : ref.watch(gameCardEvalCacheOnlyProvider(widget.fen));

    final display = evalAsync.when(
      loading:
          () =>
              _lastDisplay?.retainedWhileLoading() ??
              _EvalBarDisplay.neutral(
                isEvaluating: true,
                hasEvaluationData: false,
              ),
      error:
          (_, __) =>
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

    return display.build(widget);
  }

  _EvalBarDisplay _remember(_EvalBarDisplay display) {
    _lastDisplay = display;
    return display;
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

  Widget build(EvaluationBarWidgetForGames widget) {
    return _Bars(
      width: widget.width,
      height: widget.height,
      whiteHeight: _getWhiteHeight(evaluation, widget.height),
      blackHeight: _getBlackHeight(evaluation, widget.height),
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

  double _getWhiteHeight(double eval, double totalHeight) {
    final ratio = _normalizedEvalToRatio(eval);
    return ratio * totalHeight;
  }

  double _getBlackHeight(double eval, double totalHeight) {
    return totalHeight - _getWhiteHeight(eval, totalHeight);
  }
}

class _Bars extends StatelessWidget {
  final double width;
  final double height;
  final double whiteHeight;
  final double blackHeight;
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
    required this.whiteHeight,
    required this.blackHeight,
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
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: Container(
              width: width,
              height: isFlipped ? whiteHeight : blackHeight,
              color: isFlipped ? kWhiteColor : kPopUpColor,
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: width,
              height: isFlipped ? blackHeight : whiteHeight,
              color: isFlipped ? kPopUpColor : kWhiteColor,
            ),
          ),
          // Evaluation text positioned at the meeting point of black/white
          Positioned(
            left: 0,
            right: 0,
            // Position at the edge where black and white meet, clamped to stay within bounds
            top: ((isFlipped ? whiteHeight : blackHeight) -
                    (playerView == PlayerView.gridView ? 6.h : 10.h))
                .clamp(
                  0.0,
                  height - (playerView == PlayerView.gridView ? 12.h : 20.h),
                ),
            child: Container(
              width: width,
              color: kPrimaryColor,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  isEvaluating && !hasEvaluationData
                      ? '...'
                      : !hasEvaluationData
                      ? ''
                      : isCheckmate
                      ? '#'
                      : (isMate && mate != 0)
                      ? '#$mate'
                      : _formatSignedEval(evaluation),
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: AppTypography.textSmRegular.copyWith(
                    color: Colors.white,
                    fontSize: playerView == PlayerView.gridView ? 0.2.f : 1.5.f,
                    fontWeight:
                        playerView == PlayerView.gridView
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
  final double effectiveEval =
      mate != 0 ? (mate > 0 ? 10.0 : -10.0) : evaluation;
  return _normalizedEvalToRatio(effectiveEval);
}
