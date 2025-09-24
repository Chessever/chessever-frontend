import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/game_fen_stream_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/game_last_move_stream_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ChessProgressBar extends ConsumerWidget {
  const ChessProgressBar({required this.gamesTourModel, super.key});

  final GamesTourModel gamesTourModel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fenAsync = ref.watch(gameFenStreamProvider(gamesTourModel.gameId));
    final lastMoveAsync = ref.watch(
      gameLastMoveStreamProvider(gamesTourModel.gameId),
    );
    return fenAsync.when(
      data: (fenData) {
        return lastMoveAsync.when(
          data: (lastMoveData) {
            final newGamesTourModel = gamesTourModel.copyWith(
              fen: fenData,
              lastMove: lastMoveData,
            );
            return _ChessProgressBar(gamesTourModel: newGamesTourModel);
          },
          error: (e, _) {
            return _ChessProgressBar(gamesTourModel: gamesTourModel);
          },
          loading: () {
            return _ChessProgressBar(gamesTourModel: gamesTourModel);
          },
        );
      },
      error: (e, _) {
        return _ChessProgressBar(gamesTourModel: gamesTourModel);
      },
      loading: () {
        return _ChessProgressBar(gamesTourModel: gamesTourModel);
      },
    );
  }
}

class _ChessProgressBar extends ConsumerStatefulWidget {
  const _ChessProgressBar({required this.gamesTourModel, super.key});

  final GamesTourModel gamesTourModel;

  @override
  ConsumerState<_ChessProgressBar> createState() => _ChessProgressBarState();
}

class _ChessProgressBarState extends ConsumerState<_ChessProgressBar> {
  var oldEvail = 0.0;
  @override
  Widget build(BuildContext context) {
    final evalAsync = ref.watch(
      cascadeEvalProvider(widget.gamesTourModel.fen ?? ''),
    );

    final evaluation = evalAsync.when(
      loading: () => oldEvail,
      error: (_, __) => oldEvail,
      data: (cloud) {
        final pv = cloud.pvs.firstOrNull;

        // Handle evaluation based on cp value
        double evaluation;
        if (pv?.cp.abs() == 100000) {
          // This is a mate score (converted from mate in X moves)
          evaluation = (pv?.cp ?? 0) > 0 ? 10.0 : -10.0;
        } else {
          // Normal centipawn score - convert to pawn units
          evaluation = (pv?.cp ?? 0) / 100.0;
        }

        // Calculate ratios (fixed to sum to 1.0)
        final normalized = (evaluation.clamp(-5.0, 5.0) + 5.0) / 10.0;
        final whiteRatio = normalized;
        return whiteRatio;
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
