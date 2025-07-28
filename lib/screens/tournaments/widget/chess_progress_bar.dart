import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ChessProgressBar extends ConsumerStatefulWidget {
  const ChessProgressBar({
    required this.fen,
    super.key,
  });

  final String fen;

  @override
  ConsumerState<ChessProgressBar> createState() => _ChessProgressBarState();
}

class _ChessProgressBarState extends ConsumerState<ChessProgressBar> {
  /// Returns a valid FEN or the standard start position.
  String _validFenOrStart(String? fen) {
    const start = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
    if (fen == null || fen.isEmpty) return start;

    // Must contain exactly 7 slashes (8 ranks)
    final slashCount = fen.split('/').length - 1;
    if (slashCount != 7) return start;

    return fen;
  }

  @override
  Widget build(BuildContext context) {
    final evalAsync = ref.watch(
      cascadeEvalProvider(_validFenOrStart(widget.fen)),
    );

    final evaluation = evalAsync.when(
      loading: () => 0.0,
      error: (_, __) => 0.0,
      data: (cloud) {
        final pv = cloud.pvs.firstOrNull;
        print(pv?.cp ?? 0);
        return pv == null ? 0.0 : (pv.cp * 10 / 100).clamp(-10, 10) / 10;
      },
    );

    return SizedBox(
      width: 48.w,
      height: 12.h,
      child: Stack(
        children: [
          // Background container
          Container(
            width: 48.w,
            height: 12.h,
            decoration: BoxDecoration(
              color: kBlack2Color,
              borderRadius: BorderRadius.all(Radius.circular(4.br)),
            ),
          ),
          // Progress container
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            width: (48.w * evaluation).clamp(0.0, 48.w),
            height: 12.h,
            decoration: BoxDecoration(
              color: kWhiteColor,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(4.br),
                bottomLeft: Radius.circular(4.br),
                topRight:
                    evaluation >= 0.99 ? Radius.circular(4.br) : Radius.zero,
                bottomRight:
                    evaluation >= 0.99 ? Radius.circular(4.br) : Radius.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
