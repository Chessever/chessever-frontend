import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_button.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

/// TWIC-style game card with light theme design.
/// Features a light background card on dark theme with player info,
/// result badge, tournament name, and date.
class TwicGameCard extends ConsumerWidget {
  const TwicGameCard({
    super.key,
    required this.game,
    required this.allGames,
    required this.gameIndex,
    this.animationIndex = 0,
  });

  final GamesTourModel game;
  final List<GamesTourModel> allGames;
  final int gameIndex;
  final int animationIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TappableScale(
          onTap: () => _handleTap(context, ref),
          child: Container(
            margin: EdgeInsets.only(bottom: 10.sp),
            padding: EdgeInsets.symmetric(horizontal: 14.sp, vertical: 12.sp),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(12.br),
              boxShadow: [
                BoxShadow(
                  color: kBlackColor.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Players row
                _PlayersRow(game: game),
                SizedBox(height: 10.sp),
                // Meta row: Tournament | Date
                _MetaRow(game: game),
              ],
            ),
          ),
        )
        .animate()
        .fadeIn(
          duration: 200.ms,
          delay: Duration(milliseconds: (animationIndex % 10) * 40),
        )
        .slideY(begin: 0.05, end: 0, duration: 200.ms, curve: Curves.easeOut);
  }

  Future<void> _handleTap(BuildContext context, WidgetRef ref) async {
    HapticFeedbackService.cardTap();

    final hasPremium = await requirePremiumGuard(context, ref);
    if (!hasPremium) return;
    if (!context.mounted) return;

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
              disableGamebaseOverlayByDefault: true,
            ),
      ),
    );
  }
}

class _PlayersRow extends StatelessWidget {
  const _PlayersRow({required this.game});

  final GamesTourModel game;

  @override
  Widget build(BuildContext context) {
    final white = game.whitePlayer;
    final black = game.blackPlayer;
    final status = game.effectiveGameStatus;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // White player
        Expanded(
          child: _PlayerInfo(
            player: white,
            isWinner: status == GameStatus.whiteWins,
            alignment: CrossAxisAlignment.start,
          ),
        ),
        // Result badge
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 8.sp),
          child: _ResultBadge(status: status),
        ),
        // Black player
        Expanded(
          child: _PlayerInfo(
            player: black,
            isWinner: status == GameStatus.blackWins,
            alignment: CrossAxisAlignment.end,
          ),
        ),
      ],
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
            color: isWinner ? const Color(0xFF1A1A1C) : const Color(0xFF3A3A3C),
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
                    color: const Color(0xFF666666),
                    fontSize: 12.sp,
                  ),
                ),
              TextSpan(
                text: player.displayRating,
                style: AppTypography.textXsRegular.copyWith(
                  color: const Color(0xFF666666),
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
        backgroundColor = const Color(0xFF2D2D2D);
        textColor = kWhiteColor;
        text = '1-0';
        break;
      case GameStatus.blackWins:
        backgroundColor = const Color(0xFF2D2D2D);
        textColor = kWhiteColor;
        text = '0-1';
        break;
      case GameStatus.draw:
        backgroundColor = const Color(0xFF666666);
        textColor = kWhiteColor;
        text = '½-½';
        break;
      case GameStatus.ongoing:
        backgroundColor = kPrimaryColor;
        textColor = kBlackColor;
        text = 'LIVE';
        break;
      case GameStatus.unknown:
        backgroundColor = const Color(0xFFE0E0E0);
        textColor = const Color(0xFF666666);
        text = '-';
        break;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.sp, vertical: 4.sp),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6.br),
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

    return Row(
      children: [
        // Tournament
        Expanded(
          child: Row(
            children: [
              Icon(
                Icons.emoji_events_outlined,
                size: 14.ic,
                color: const Color(0xFF888888),
              ),
              SizedBox(width: 4.sp),
              Expanded(
                child: Text(
                  tournamentName,
                  style: AppTypography.textXsRegular.copyWith(
                    color: const Color(0xFF666666),
                    fontSize: 11.sp,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: 12.sp),
        // Date
        Row(
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 12.ic,
              color: const Color(0xFF888888),
            ),
            SizedBox(width: 4.sp),
            Text(
              date,
              style: AppTypography.textXsRegular.copyWith(
                color: const Color(0xFF666666),
                fontSize: 11.sp,
              ),
            ),
          ],
        ),
      ],
    );
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
    if (dateTime == null) return 'Unknown';

    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return DateFormat('MMM d').format(dateTime);
    }
  }
}
