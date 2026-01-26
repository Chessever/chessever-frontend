import 'dart:math' as math;

import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
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
    if (mate != null && mate != 0) {
      return mate > 0 ? 10.0 : -10.0;
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
              Center(
                child: Container(
                  width: widget.width,
                  height: 2,
                  color: kRedColor,
                ),
              ),
              Center(
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 1.w,
                    vertical: 0.5.h,
                  ),
                  decoration: BoxDecoration(
                    color: kPrimaryColor,
                    borderRadius: BorderRadius.circular(2.br),
                  ),
                  child: Text(
                    showLoading
                        ? '...'
                        : (displayEval.abs() >= 10.0 && displayMate != 0)
                        ? '#${displayMate.abs()}'
                        : displayEval.abs().toStringAsFixed(1),
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: AppTypography.textSmRegular.copyWith(
                      color: Colors.white,
                      fontSize: 3.5.f,
                      fontWeight: FontWeight.w600,
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

/// Evaluation widget used on game cards.
/// Uses cascade (local → Supabase → Lichess) with Stockfish depth 8 as fallback.
/// Auto-disposes when card scrolls out of view (only evaluates visible boards).
class EvaluationBarWidgetForGames extends ConsumerWidget {
  final double width;
  final double height;
  final String fen;
  final PlayerView playerView;

  const EvaluationBarWidgetForGames({
    required this.width,
    required this.height,
    required this.fen,
    required this.playerView,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // First, check if position is checkmate - handle immediately without external eval
    final checkmateResult = _detectCheckmate(fen);
    if (checkmateResult != null) {
      // Checkmate detected - show definitive result
      // whiteWon = true means white delivered checkmate (eval +10.0)
      // whiteWon = false means black delivered checkmate (eval -10.0)
      final eval = checkmateResult ? 10.0 : -10.0;
      return _Bars(
        width: width,
        height: height,
        whiteHeight: _getWhiteHeight(eval, height),
        blackHeight: _getBlackHeight(eval, height),
        evaluation: eval,
        isCheckmate: true,
        playerView: playerView,
        isFlipped: false,
      );
    }

    // Uses cascade (local → Supabase → Lichess) with Stockfish depth 8 fallback
    // Auto-disposes when card scrolls out of view
    return ref
        .watch(gameCardEvalWithStockfishFallbackProvider(fen))
        .when(
          loading: () {
            return SkeletonWidget(
              child: _Bars(
                width: width,
                height: height,
                whiteHeight: height * 0.5,
                blackHeight: height * 0.5,
                evaluation: 0.0,
                isEvaluating: true,
                playerView: playerView,
                isFlipped: false,
              ),
            );
          },
          error: (_, __) {
            return SkeletonWidget(
              child: _Bars(
                width: width,
                height: height,
                whiteHeight: height * 0.5,
                blackHeight: height * 0.5,
                evaluation: 0.0,
                playerView: playerView,
                isFlipped: false,
              ),
            );
          },
          data: (cloud) {
            final pv = cloud.pvs.firstOrNull;
            if (pv == null) {
              return SkeletonWidget(
                child: _Bars(
                  width: width,
                  height: height,
                  whiteHeight: height * 0.5,
                  blackHeight: height * 0.5,
                  evaluation: 0.0,
                  playerView: playerView,
                  isFlipped: false,
                ),
              );
            }

            final eval = pv.cp / 100.0;
            final isMate = pv.isMate && pv.mate != null;
            final mate = pv.mate ?? 0;

            return _Bars(
              width: width,
              height: height,
              whiteHeight: _getWhiteHeight(eval, height),
              blackHeight: _getBlackHeight(eval, height),
              evaluation: eval,
              isMate: isMate,
              mate: mate,
              playerView: playerView,
              isFlipped: false,
            );
          },
        );
  }

  /// Detects if the FEN position is checkmate.
  /// Returns: true if white won (delivered checkmate), false if black won, null if not checkmate
  bool? _detectCheckmate(String fen) {
    if (fen.isEmpty) return null;
    try {
      final setup = Setup.parseFen(fen);
      final position = Chess.fromSetup(setup);
      if (position.isCheckmate) {
        // The side to move is the one that got checkmated
        // So if it's white's turn and checkmate, black won (delivered checkmate)
        // If it's black's turn and checkmate, white won (delivered checkmate)
        return setup.turn == Side.black; // true = white won
      }
      return null;
    } catch (e) {
      return null;
    }
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
          Center(child: Container(width: width, height: 2, color: kRedColor)),
          Center(
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 1.w, vertical: 0.5.h),
              decoration: BoxDecoration(
                color: kPrimaryColor,
                borderRadius: BorderRadius.circular(2.br),
              ),
              child: Text(
                isEvaluating && evaluation == 0.0
                    ? '...'
                    : isCheckmate
                    ? '#'
                    : (isMate && mate != 0)
                    ? '#${mate.abs()}'
                    : evaluation.round().abs().toString(),
                maxLines: 1,
                textAlign: TextAlign.center,
                style: AppTypography.textSmRegular.copyWith(
                  color: Colors.white,
                  fontSize: playerView == PlayerView.gridView ? 0.2.f : 1.5.f,
                  fontWeight:
                      playerView == PlayerView.gridView
                          ? FontWeight.w300
                          : FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
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
