import 'package:chessever2/repository/gamebase/miniatures/miniatures_models.dart';
import 'package:chessever2/screens/library/miniatures/miniature_game_launcher.dart';
import 'package:chessever2/screens/library/providers/miniatures_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

/// Full drill-down for the record-book games behind the About tab's
/// "Shortest of them all" / "Strongest company" previews: every game in
/// [MiniatureStats.shortestGames] and [MiniatureStats.topRatedGames], each
/// one tap away from the board.
class MiniatureHallOfFameScreen extends ConsumerStatefulWidget {
  const MiniatureHallOfFameScreen({super.key, required this.window});

  final MiniatureGamesWindow window;

  @override
  ConsumerState<MiniatureHallOfFameScreen> createState() =>
      _MiniatureHallOfFameScreenState();
}

class _MiniatureHallOfFameScreenState
    extends ConsumerState<MiniatureHallOfFameScreen> {
  int _tabIndex = 0;

  Future<void> _openMiniature(GamebaseMiniature miniature) {
    HapticFeedbackService.cardTap();
    final games = <GamesTourModel>[miniature.toGamesTourModel()];
    return openMiniatureGame(
      context: context,
      ref: ref,
      games: games,
      index: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(miniatureStatsProvider(widget.window));
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 24.w,
    );

    Widget content = ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        12.h,
        horizontalPadding,
        32.h,
      ),
      children: [
        statsAsync.when(
          loading: () => const _HeaderSkeleton(),
          error: (_, __) => const SizedBox.shrink(),
          data: (stats) => _RecordHeader(stats: stats),
        ),
        SizedBox(height: 20.h),
        SegmentedSwitcher(
          options: const ['Shortest', 'Strongest'],
          currentSelection: _tabIndex,
          onSelectionChanged: (index) {
            HapticFeedbackService.selection();
            setState(() => _tabIndex = index);
          },
        ),
        SizedBox(height: 20.h),
        statsAsync.when(
          loading: () => const _ListSkeleton(),
          error:
              (error, _) => _HallOfFameError(
                onRetry:
                    () => ref.invalidate(miniatureStatsProvider(widget.window)),
              ),
          data:
              (stats) => _GamesList(
                games:
                    _tabIndex == 0 ? stats.shortestGames : stats.topRatedGames,
                showRating: _tabIndex == 1,
                onOpenGame: _openMiniature,
              ),
        ),
      ],
    );

    if (ResponsiveHelper.isTablet) {
      content = Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.contentMaxWidth,
          ),
          child: content,
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.background,
        elevation: 0,
        title: Text(
          'Hall of fame',
          style: AppTypography.textMdMedium.copyWith(
            color: context.colors.textPrimary,
          ),
        ),
      ),
      body: SafeArea(child: content),
    );
  }
}

class _RecordHeader extends StatelessWidget {
  const _RecordHeader({required this.stats});

  final MiniatureStats stats;

  @override
  Widget build(BuildContext context) {
    final clauses = <String>[];
    if (stats.minMoves != null) {
      clauses.add('Fastest ever: ${stats.minMoves} moves.');
    }
    if (stats.maxRating != null) {
      clauses.add('Strongest average rating: ${stats.maxRating}.');
    }
    if (clauses.isEmpty) return const SizedBox.shrink();

    return Text(
      clauses.join(' '),
      style: AppTypography.textXsRegular.copyWith(
        color: context.colors.textSecondary,
        height: 1.45,
      ),
    );
  }
}

class _GamesList extends StatelessWidget {
  const _GamesList({
    required this.games,
    required this.showRating,
    required this.onOpenGame,
  });

  final List<GamebaseMiniature> games;
  final bool showRating;
  final Future<void> Function(GamebaseMiniature) onOpenGame;

  @override
  Widget build(BuildContext context) {
    if (games.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 40.h),
        child: Center(
          child: Text(
            'No games in this window yet.',
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (final game in games)
          Padding(
            padding: EdgeInsets.only(bottom: 8.h),
            child: _HallOfFameGameRow(
              game: game,
              showRating: showRating,
              onTap: () => onOpenGame(game),
            ),
          ),
      ],
    );
  }
}

class _HallOfFameGameRow extends StatelessWidget {
  const _HallOfFameGameRow({
    required this.game,
    required this.showRating,
    required this.onTap,
  });

  final GamebaseMiniature game;
  final bool showRating;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final whiteWins = game.result == 'W';
    final winner = (whiteWins ? game.whiteName : game.blackName) ?? 'Unknown';
    final loser = (whiteWins ? game.blackName : game.whiteName) ?? 'Unknown';
    final hasRating = game.avgRating != null && game.avgRating! > 0;
    final badgeValue =
        showRating && hasRating
            ? '${game.avgRating}'
            : '${game.finalMoveNumber}';
    final badgeLabel = showRating && hasRating ? 'rating' : 'moves';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.br),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(12.br),
        ),
        child: Row(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  badgeValue,
                  style: AppTypography.textMdMedium.copyWith(
                    color: kPrimaryColor,
                    fontWeight: FontWeight.w600,
                    height: 1,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  badgeLabel,
                  style: AppTypography.textXsRegular.copyWith(
                    color: context.colors.textTertiary,
                    fontSize: 9.sp,
                  ),
                ),
              ],
            ),
            SizedBox(width: 14.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$winner beat $loser',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.textSmMedium.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 3.h),
                  Text(
                    _subtitle(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.textXsRegular.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 8.w),
            Icon(
              Icons.chevron_right_rounded,
              size: 20.sp,
              color: context.colors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle() {
    final parts = <String>[];
    final opening = game.openingDisplayName ?? game.eco;
    if (opening != null && opening.isNotEmpty) parts.add(opening);
    if (game.avgRating != null && game.avgRating! > 0) {
      parts.add('avg ${game.avgRating}');
    }
    if (game.date != null) {
      parts.add(DateFormat('MMM y').format(game.date!.toUtc()));
    }
    return parts.join(' · ');
  }
}

class _HeaderSkeleton extends StatelessWidget {
  const _HeaderSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonWidget(
      child: Container(
        height: 16.h,
        width: 220.w,
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(4.br),
        ),
      ),
    );
  }
}

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        6,
        (index) => Padding(
          padding: EdgeInsets.only(bottom: 8.h),
          child: SkeletonWidget(
            child: Container(
              height: 60.h,
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(12.br),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HallOfFameError extends StatelessWidget {
  const _HallOfFameError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 40.h),
      child: Column(
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 36.sp,
            color: context.colors.textSecondary,
          ),
          SizedBox(height: 14.h),
          Text(
            'Could not load the numbers',
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          SizedBox(height: 16.h),
          GestureDetector(
            onTap: onRetry,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
              decoration: BoxDecoration(
                color: context.colors.surfaceRecessed,
                borderRadius: BorderRadius.circular(10.br),
              ),
              child: Text(
                'Retry',
                style: AppTypography.textXsMedium.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
