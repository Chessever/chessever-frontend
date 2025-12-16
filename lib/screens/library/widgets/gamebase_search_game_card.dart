import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/library/utils/gamebase_game_to_games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

class GamebaseSearchGameCard extends ConsumerWidget {
  const GamebaseSearchGameCard({
    super.key,
    required this.game,
    required this.allGames,
    required this.gameIndex,
    required this.onAdd,
    this.animationIndex = 0,
  });

  final GamesTourModel game;
  final List<GamesTourModel> allGames;
  final int gameIndex;
  final VoidCallback onAdd;
  final int animationIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventName = _formatEventName(game.tourSlug ?? game.tourId);
    final formatCode = _formatCode(game.roundSlug);
    final date = _formatDate(game.lastMoveTime);
    final timeControlIcon = _getTimeControlIcon(
      eventName: eventName,
      timeControl: game.roundSlug,
    );

    return GestureDetector(
      onTap: () => _handleTap(context, ref),
      onLongPress: () {
        HapticFeedbackService.buttonPress();
        onAdd();
      },
      child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF18181B), // Zinc 900
              borderRadius: BorderRadius.circular(12.br),
              border: Border.all(color: const Color(0xFF27272A)), // Zinc 800
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: EdgeInsets.fromLTRB(14.w, 10.h, 14.w, 10.h),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE4E4E7), // Zinc 200
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(12.br),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: _PlayerInfoColumn(
                          player: game.whitePlayer,
                          alignment: CrossAxisAlignment.start,
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10.w),
                        child: _ResultBadge(status: game.gameStatus),
                      ),
                      Expanded(
                        child: _PlayerInfoColumn(
                          player: game.blackPlayer,
                          alignment: CrossAxisAlignment.end,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 12.w,
                    vertical: 8.h,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF09090B), // Zinc 950
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(12.br),
                    ),
                    border: Border(
                      top: BorderSide(
                        color: kWhiteColor.withValues(alpha: 0.06),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 6,
                        child: Row(
                          children: [
                            Image.asset(
                              timeControlIcon,
                              width: 14.sp,
                              height: 14.sp,
                            ),
                            SizedBox(width: 8.w),
                            Expanded(
                              child: Text(
                                eventName,
                                style: AppTypography.textXsRegular.copyWith(
                                  color: const Color(0xFFA1A1AA), // Zinc 400
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Center(
                          child: Text(
                            formatCode,
                            style: AppTypography.textXsMedium.copyWith(
                              color: const Color(0xFFA1A1AA), // Zinc 400
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            date,
                            style: AppTypography.textXsRegular.copyWith(
                              color: const Color(0xFF71717A), // Zinc 500
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
          .animate()
          .fadeIn(
            duration: 200.ms,
            delay: Duration(milliseconds: (animationIndex % 10) * 40),
          )
          .slideY(begin: 0.05, end: 0, duration: 200.ms, curve: Curves.easeOut),
    );
  }

  void _handleTap(BuildContext context, WidgetRef ref) {
    HapticFeedbackService.cardTap();
    ref.read(chessboardViewFromProviderNew.notifier).state =
        ChessboardView.tour;

    final needsPgn = game.pgn == null || game.pgn!.trim().isEmpty;
    if (!needsPgn) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => ChessBoardScreenNew(
                games: allGames,
                currentIndex: gameIndex,
                showGamebaseButton: true,
              ),
        ),
      );
      return;
    }

    // Fallback: fetch full game from Gamebase to build a usable PGN.
    (() async {
      final repo = ref.read(gamebaseRepositoryProvider);
      final full = await repo.getGameById(game.gameId);
      final resolved =
          full != null ? mapGamebaseGameToGamesTourModel(full) : game;

      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => ChessBoardScreenNew(
                games: [resolved],
                currentIndex: 0,
                showGamebaseButton: true,
              ),
        ),
      );
    })();
  }
}

class _PlayerInfoColumn extends StatelessWidget {
  const _PlayerInfoColumn({required this.player, required this.alignment});

  final PlayerCard player;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final rank = [
      if (player.title.isNotEmpty) player.title,
      if (player.rating > 0) player.rating.toString(),
    ].join(' ');

    return Column(
      crossAxisAlignment: alignment,
      children: [
        Text(
          player.name,
          style: AppTypography.textSmMedium.copyWith(
            color: kBlackColor,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign:
              alignment == CrossAxisAlignment.end
                  ? TextAlign.right
                  : TextAlign.left,
        ),
        SizedBox(height: 2.h),
        Text(
          rank,
          style: AppTypography.textXsRegular.copyWith(
            color: kBlack2Color.withValues(alpha: 0.7),
            fontSize: 12.sp,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign:
              alignment == CrossAxisAlignment.end
                  ? TextAlign.right
                  : TextAlign.left,
        ),
      ],
    );
  }
}

class _ResultBadge extends StatelessWidget {
  const _ResultBadge({required this.status});

  final GameStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: kBlackColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6.br),
        border: Border.all(color: kBlackColor.withValues(alpha: 0.06)),
      ),
      child: Text(
        status.toResultString(),
        style: AppTypography.textSmMedium.copyWith(
          color: kBlackColor,
          fontWeight: FontWeight.w700,
          fontSize: 12.sp,
        ),
      ),
    );
  }
}

String _formatEventName(String rawName) {
  final cleaned = rawName.replaceAll('-', ' ').replaceAll('_', ' ').trim();
  if (cleaned.isEmpty || cleaned == 'gamebase' || cleaned == 'search') {
    return 'Gamebase';
  }
  return cleaned;
}

extension GameStatusExtension on GameStatus {
  String toResultString() {
    switch (this) {
      case GameStatus.whiteWins:
        return '1 - 0';
      case GameStatus.blackWins:
        return '0 - 1';
      case GameStatus.draw:
        return '½ - ½';
      default:
        return '*';
    }
  }
}

String _formatCode(String? raw) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) return '';
  if (value.toLowerCase() == 'search' || value.toLowerCase() == 'gamebase') {
    return '';
  }
  return value;
}

String _formatDate(DateTime? dateTime) {
  if (dateTime == null) return '';
  return DateFormat('dd/MM/yyyy').format(dateTime);
}

String _getTimeControlIcon({
  required String eventName,
  required String? timeControl,
}) {
  final event = eventName.toLowerCase();
  final tc = (timeControl ?? '').toLowerCase();

  if (event.contains('blitz') || tc.contains('blitz')) {
    return PngAsset.blitzIcon;
  }
  if (event.contains('rapid') || tc.contains('rapid')) {
    return PngAsset.rapidIcon;
  }
  if (tc.contains('classical') || tc.contains('standard')) {
    return PngAsset.classicalIcon;
  }
  return PngAsset.classicalIcon;
}
