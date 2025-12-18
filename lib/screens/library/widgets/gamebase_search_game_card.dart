import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/library/widgets/swipe_action_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/chess_title_utils.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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
    final card = _GameCardContent(
      game: game,
      onTap: () => _handleGamebaseTap(context, ref, game, allGames, gameIndex),
      onLongPress: onAdd,
    );

    final swipeCard = SwipeActionCard(
      dismissKey: ValueKey('add_${game.gameId}_$gameIndex'),
      icon: Icons.add_rounded,
      label: 'Add',
      backgroundColor: kGreenColor,
      onAction: () async {
        HapticFeedbackService.medium();
        onAdd();
      },
      child: card,
    );

    // Simple entry animation only - no slideX showcase
    final entryDelay = Duration(milliseconds: (animationIndex % 10) * 40);
    return swipeCard
        .animate()
        .fadeIn(duration: 200.ms, delay: entryDelay)
        .slideY(begin: 0.05, end: 0, duration: 200.ms, curve: Curves.easeOut);
  }

  Future<void> _handleGamebaseTap(
    BuildContext context,
    WidgetRef ref,
    GamesTourModel game,
    List<GamesTourModel> allGames,
    int gameIndex,
  ) async {
    ref.read(chessboardViewFromProviderNew.notifier).state =
        ChessboardView.tour;

    // Check if PGN has actual moves (not just headers)
    // Search results only return metadata, so we need to fetch the full game
    final hasMoves = pgnHasMoves(game.pgn);

    if (hasMoves) {
      // Already have PGN with moves, navigate directly
      _navigateToChessboard(context, allGames, gameIndex);
      return;
    }

    // Show loading indicator while fetching PGN
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: CircularProgressIndicator(color: kWhiteColor),
      ),
    );

    try {
      // Try to fetch full game with PGN from API
      final repository = ref.read(gamebaseRepositoryProvider);
      final gameWithPgn = await repository.getGameWithPgn(game.gameId);

      if (!context.mounted) return;
      Navigator.of(context).pop(); // Dismiss loading

      final patched = List<GamesTourModel>.from(allGames);
      String? pgn;

      if (gameWithPgn != null) {
        // Try to use the raw PGN first
        if (gameWithPgn.pgn != null && gameWithPgn.pgn!.trim().isNotEmpty) {
          pgn = gameWithPgn.pgn;
        } else if (gameWithPgn.data != null) {
          // Try to build PGN from the data field (contains moves)
          pgn = buildPgnFromGamebaseData(gameWithPgn.data);
        }
      }

      // Fallback to header-only PGN if we couldn't get moves
      pgn ??= buildHeaderOnlyPgn(
        whiteName: game.whitePlayer.name,
        blackName: game.blackPlayer.name,
        result: game.gameStatus.displayText,
        event: game.tourSlug?.trim().isNotEmpty == true
            ? game.tourSlug
            : game.tourId,
        eco: game.roundSlug,
        date: game.lastMoveTime,
      );

      patched[gameIndex] = game.copyWith(pgn: pgn);
      _navigateToChessboard(context, patched, gameIndex);
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop(); // Dismiss loading

      // Fallback to header-only PGN on error
      final patched = List<GamesTourModel>.from(allGames);
      final eventName = game.tourSlug?.trim().isNotEmpty == true
          ? game.tourSlug
          : game.tourId;
      final pgn = buildHeaderOnlyPgn(
        whiteName: game.whitePlayer.name,
        blackName: game.blackPlayer.name,
        result: game.gameStatus.displayText,
        event: eventName,
        eco: game.roundSlug,
        date: game.lastMoveTime,
      );
      patched[gameIndex] = game.copyWith(pgn: pgn);
      _navigateToChessboard(context, patched, gameIndex);
    }
  }

  void _navigateToChessboard(
    BuildContext context,
    List<GamesTourModel> games,
    int index,
  ) {
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChessBoardScreenNew(
          games: games,
          currentIndex: index,
          hideEventInfo: true,
          showGamebaseButton: true,
          showClock: false,
        ),
      ),
    );
  }
}

class _GameCardContent extends StatelessWidget {
  const _GameCardContent({
    required this.game,
    required this.onTap,
    required this.onLongPress,
  });

  final GamesTourModel game;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final eventName = _formatEventName(game.tourSlug ?? game.tourId);
    final timeControlIcon = _getTimeControlIcon(eventName);
    final eco = game.roundSlug ?? '';
    final date = _formatDate(game.lastMoveTime);
    final result = game.gameStatus.displayText;

    return GestureDetector(
      onTap: () {
        HapticFeedbackService.cardTap();
        onTap();
      },
      onLongPress: () {
        HapticFeedbackService.buttonPress();
        onLongPress();
      },
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF2E2E2E),
          borderRadius: BorderRadius.circular(12.br),
        ),
        child: Column(
          children: [
            // Top section - light background with player info
            Container(
              padding: EdgeInsets.fromLTRB(14.w, 10.h, 14.w, 10.h),
              decoration: BoxDecoration(
                color: const Color(0xFFE4E4E7),
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(12.br),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: _PlayerInfo(
                      name: game.whitePlayer.name,
                      title: ChessTitleUtils.normalize(game.whitePlayer.title),
                      rating: game.whitePlayer.rating > 0
                          ? game.whitePlayer.displayRating
                          : '',
                      federation: game.whitePlayer.countryCode,
                      alignment: CrossAxisAlignment.start,
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10.w),
                    child: _ResultBadge(result: result),
                  ),
                  Expanded(
                    child: _PlayerInfo(
                      name: game.blackPlayer.name,
                      title: ChessTitleUtils.normalize(game.blackPlayer.title),
                      rating: game.blackPlayer.rating > 0
                          ? game.blackPlayer.displayRating
                          : '',
                      federation: game.blackPlayer.countryCode,
                      alignment: CrossAxisAlignment.end,
                    ),
                  ),
                ],
              ),
            ),
            // Bottom section - dark background with event info
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1C),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(12.br),
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
                              color: const Color(0xFFA1A1AA),
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
                        eco,
                        style: AppTypography.textXsMedium.copyWith(
                          color: const Color(0xFFA1A1AA),
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
                          color: const Color(0xFF71717A),
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
      ),
    );
  }

  String _formatEventName(String rawName) {
    final cleaned = rawName.replaceAll('-', ' ').replaceAll('_', ' ').trim();
    if (cleaned.isEmpty || cleaned == 'gamebase' || cleaned == 'search') {
      return 'Gamebase';
    }
    return cleaned;
  }

  String _getTimeControlIcon(String eventName) {
    final event = eventName.toLowerCase();
    if (event.contains('blitz')) return PngAsset.blitzIcon;
    if (event.contains('rapid')) return PngAsset.rapidIcon;
    return PngAsset.classicalIcon;
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    return '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
  }
}

class _PlayerInfo extends StatelessWidget {
  const _PlayerInfo({
    required this.name,
    required this.title,
    required this.rating,
    required this.alignment,
    required this.federation,
  });

  final String name;
  final String title;
  final String rating;
  final CrossAxisAlignment alignment;
  final String federation;

  @override
  Widget build(BuildContext context) {
    final rank = [
      if (title.isNotEmpty) title,
      if (rating.isNotEmpty) rating,
    ].join(' ');

    return Column(
      crossAxisAlignment: alignment,
      children: [
        Row(
          mainAxisAlignment:
              alignment == CrossAxisAlignment.end
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
          children: [
            if (alignment != CrossAxisAlignment.end &&
                federation.trim().isNotEmpty) ...[
              FederationFlag(
                federation: federation,
                width: 14.sp,
                height: 10.sp,
                borderRadius: BorderRadius.circular(2.br),
              ),
              SizedBox(width: 6.w),
            ],
            Flexible(
              child: Text(
                name,
                style: AppTypography.textSmMedium.copyWith(
                  color: const Color(0xFF09090B),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign:
                    alignment == CrossAxisAlignment.end
                        ? TextAlign.right
                        : TextAlign.left,
              ),
            ),
            if (alignment == CrossAxisAlignment.end &&
                federation.trim().isNotEmpty) ...[
              SizedBox(width: 6.w),
              FederationFlag(
                federation: federation,
                width: 14.sp,
                height: 10.sp,
                borderRadius: BorderRadius.circular(2.br),
              ),
            ],
          ],
        ),
        SizedBox(height: 2.h),
        Text(
          rank,
          style: AppTypography.textXsRegular.copyWith(
            color: const Color(0xFF71717A),
            fontSize: 12.sp,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign:
              alignment == CrossAxisAlignment.end ? TextAlign.right : TextAlign.left,
        ),
      ],
    );
  }
}

class _ResultBadge extends StatelessWidget {
  const _ResultBadge({required this.result});

  final String result;

  @override
  Widget build(BuildContext context) {
    return Text(
      result,
      style: AppTypography.textSmMedium.copyWith(
        color: const Color(0xFF09090B),
        fontSize: 12.sp,
      ),
    );
  }
}
