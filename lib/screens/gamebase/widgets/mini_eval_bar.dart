import 'dart:math' as math;

import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Small horizontal eval bar for opening explorer move rows.
///
/// Uses [cascadeEvalProviderForBoard] (local cache + Supabase only, NO
/// Stockfish) so that rendering 15+ candidate moves doesn't trigger expensive
/// engine evaluations. Shows nothing when no cached eval exists.
class MiniEvalBar extends ConsumerWidget {
  const MiniEvalBar({super.key, required this.fen});

  final String? fen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (fen == null || fen!.isEmpty) return const SizedBox.shrink();

    final evalAsync = ref.watch(
      cascadeEvalProviderForBoard(CascadeEvalParams(fen: fen!, multiPV: 1)),
    );

    return evalAsync.when(
      data: (cloud) {
        final pv = cloud.pvs.firstOrNull;
        if (pv == null) return const SizedBox.shrink();

        final normalized = _normalizePvToWhitePerspective(pv);
        final eval = normalized.eval;
        final isMate = normalized.isMate;
        final mate = normalized.mate;

        final effectiveEval =
            (isMate && mate != 0) ? (mate > 0 ? 10.0 : -10.0) : eval;
        final whiteRatio = _normalizedEvalToRatio(effectiveEval);

        final evalText =
            isMate && mate != 0
                ? (mate > 0 ? '#${mate.abs()}' : '#-${mate.abs()}')
                : '${eval >= 0 ? '+' : ''}${eval.toStringAsFixed(1)}';

        return SizedBox(
          height: 16.h,
          child: Row(
            children: [
              // Eval text
              SizedBox(
                width: 26.w,
                child: Text(
                  evalText,
                  style: TextStyle(
                    color:
                        effectiveEval >= 0
                            ? kWhiteColor
                            : kWhiteColor.withValues(alpha: 0.6),
                    fontSize: 9.f,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                ),
              ),
              SizedBox(width: 4.w),
              // Mini bar
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2.br),
                  child: SizedBox(
                    height: 6.h,
                    child: Row(
                      children: [
                        Expanded(
                          flex: (whiteRatio * 100).round(),
                          child: Container(color: kWhiteColor),
                        ),
                        Expanded(
                          flex: ((1.0 - whiteRatio) * 100).round(),
                          child: Container(color: kPopUpColor),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

/// Logistic sigmoid mapping from centipawn eval to white-portion ratio.
/// Duplicated locally to avoid coupling with evaluation_bar_widget.dart.
double _normalizedEvalToRatio(double eval) {
  const double scale = 3.0;
  const double minRatio = 0.02;
  const double maxRatio = 0.98;
  final double clampedEval = eval.clamp(-20.0, 20.0);
  final double logistic = 1.0 / (1.0 + math.exp(-clampedEval / scale));
  return logistic.clamp(minRatio, maxRatio);
}

({double eval, bool isMate, int mate}) _normalizePvToWhitePerspective(Pv pv) {
  final sign = pv.whitePerspective ? 1 : -1;
  final isMate = pv.isMate && pv.mate != null;
  final normalizedMate = ((pv.mate ?? 0) * sign);
  final normalizedEval = (pv.cp * sign) / 100.0;
  return (eval: normalizedEval, isMate: isMate, mate: normalizedMate);
}
