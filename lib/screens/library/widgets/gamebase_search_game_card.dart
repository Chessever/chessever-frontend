import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
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
    return Stack(
      children: [
        GestureDetector(
              onTap: () => _handleTap(context, ref),
              child: Container(
                margin: EdgeInsets.only(bottom: 10.sp),
                decoration: BoxDecoration(
                  color: const Color(0xFF252525), // Dark grey background
                  borderRadius: BorderRadius.circular(12.br),
                  border: Border.all(
                    color: kWhiteColor.withValues(alpha: 0.05),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        14.sp,
                        12.sp,
                        36.sp,
                        12.sp,
                      ), // Right padding for Add button
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: _PlayerInfo(
                              player: game.whitePlayer,
                              isWinner:
                                  game.effectiveGameStatus ==
                                  GameStatus.whiteWins,
                              alignment: CrossAxisAlignment.start,
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8.sp),
                            child: _ResultBadge(
                              status: game.effectiveGameStatus,
                            ),
                          ),
                          Expanded(
                            child: _PlayerInfo(
                              player: game.blackPlayer,
                              isWinner:
                                  game.effectiveGameStatus ==
                                  GameStatus.blackWins,
                              alignment: CrossAxisAlignment.end,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12.sp,
                        vertical: 8.sp,
                      ),
                      decoration: BoxDecoration(
                        color: kBlackColor.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.vertical(
                          bottom: Radius.circular(12.br),
                        ),
                        border: Border(
                          top: BorderSide(
                            color: kWhiteColor.withValues(alpha: 0.05),
                          ),
                        ),
                      ),
                      child: _MetaRow(game: game),
                    ),
                  ],
                ),
              ),
            )
            .animate()
            .fadeIn(
              duration: 200.ms,
              delay: Duration(milliseconds: (animationIndex % 10) * 40),
            )
            .slideY(
              begin: 0.05,
              end: 0,
              duration: 200.ms,
              curve: Curves.easeOut,
            ),
        Positioned(
          top: 8.sp,
          right: 8.sp,
          child: GestureDetector(
            onTap: () {
              HapticFeedbackService.buttonPress();
              onAdd();
            },
            child: Container(
              padding: EdgeInsets.all(8.sp),
              decoration: BoxDecoration(
                color: kPrimaryColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: kBlackColor.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(Icons.add_rounded, size: 20.ic, color: kBlackColor),
            ),
          ),
        ),
      ],
    );
  }

  void _handleTap(BuildContext context, WidgetRef ref) {
    HapticFeedbackService.cardTap();

    ref.read(chessboardViewFromProviderNew.notifier).state =
        ChessboardView.tour;

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
  }
}

class _PlayerInfo extends StatelessWidget {
  const _PlayerInfo({
    required this.player,
    required this.isWinner,
    required this.alignment,
  });

  final PlayerCard player;
  final bool isWinner;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignment,
      children: [
        // Name
        Text(
          player.name,
          style: AppTypography.textSmMedium.copyWith(
            color: kWhiteColor,
            fontWeight: isWinner ? FontWeight.w700 : FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: 2.sp),
        // Title + Rating
        RichText(
          text: TextSpan(
            children: [
              if (player.title.isNotEmpty)
                TextSpan(
                  text: '${player.title} ',
                  style: AppTypography.textXsRegular.copyWith(
                    color: kWhiteColor.withValues(alpha: 0.5),
                    fontSize: 12.sp,
                  ),
                ),
              TextSpan(
                text: player.displayRating,
                style: AppTypography.textXsRegular.copyWith(
                  color: kWhiteColor.withValues(alpha: 0.5),
                  fontSize: 12.sp,
                ),
              ),
            ],
          ),
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
    Color backgroundColor;
    Color textColor;
    String text;

    switch (status) {
      case GameStatus.whiteWins:
        backgroundColor = kWhiteColor.withValues(alpha: 0.1);
        textColor = kWhiteColor;
        text = '1-0';
        break;
      case GameStatus.blackWins:
        backgroundColor = kWhiteColor.withValues(alpha: 0.1);
        textColor = kWhiteColor;
        text = '0-1';
        break;
      case GameStatus.draw:
        backgroundColor = kWhiteColor.withValues(alpha: 0.05);
        textColor = kWhiteColor.withValues(alpha: 0.7);
        text = '½-½';
        break;
      case GameStatus.ongoing:
        backgroundColor = kPrimaryColor.withValues(alpha: 0.2);
        textColor = kPrimaryColor;
        text = 'LIVE';
        break;
      case GameStatus.unknown:
        backgroundColor = kWhiteColor.withValues(alpha: 0.05);
        textColor = kWhiteColor.withValues(alpha: 0.5);
        text = '-';
        break;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.sp, vertical: 4.sp),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6.br),
        border: Border.all(
          color: kWhiteColor.withValues(alpha: 0.05),
          width: 1,
        ),
      ),
      child: Text(
        text,
        style: AppTypography.textSmMedium.copyWith(
          color: textColor,
          fontWeight: FontWeight.w700,
          fontSize: 12.sp,
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.game});

  final GamesTourModel game;

  @override
  Widget build(BuildContext context) {
    final tournamentName = _formatTournamentName(game.tourSlug ?? game.tourId);
    final date = _formatDate(game.lastMoveTime);
    final timeControlIcon = _getTimeControlIcon(game);

    // Using game.gameId as logic for "Gevent Name" or similar if needed,
    // but here mapping standard meta data to the bottom row

    return Row(
      children: [
        // Time Control Icon
        Image.asset(timeControlIcon, width: 14.sp, height: 14.sp),
        SizedBox(width: 8.w),
        // Tournament / Event
        Expanded(
          child: Text(
            tournamentName,
            style: AppTypography.textXsRegular.copyWith(
              color: kWhiteColor.withValues(alpha: 0.6),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SizedBox(width: 12.sp),
        // Date
        Row(
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 10.ic,
              color: kWhiteColor.withValues(alpha: 0.4),
            ),
            SizedBox(width: 4.sp),
            Text(
              date,
              style: AppTypography.textXsRegular.copyWith(
                color: kWhiteColor.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _getTimeControlIcon(GamesTourModel game) {
    final tourId = (game.tourId).toLowerCase();
    final tourSlug = (game.tourSlug ?? '').toLowerCase();

    if (tourId.contains('blitz') || tourSlug.contains('blitz')) {
      return PngAsset.blitzIcon;
    }
    if (tourId.contains('rapid') || tourSlug.contains('rapid')) {
      return PngAsset.rapidIcon;
    }

    return PngAsset.classicalIcon;
  }

  String _formatTournamentName(String rawName) {
    // Clean up tournament slug to readable format
    return rawName
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map(
          (word) =>
              word.length > 1
                  ? '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}'
                  : word.toUpperCase(),
        )
        .join(' ')
        .trim();
  }

  String _formatDate(DateTime? dateTime) {
    if (dateTime == null) return '';

    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return DateFormat('MMM d, y').format(dateTime);
    }
  }
}
