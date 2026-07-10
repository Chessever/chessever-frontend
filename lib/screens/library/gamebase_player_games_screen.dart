import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/library/providers/gamebase_player_games_provider.dart';
import 'package:chessever2/screens/library/widgets/add_to_folder_sheet.dart';
import 'package:chessever2/screens/library/widgets/gamebase_search_game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/chess_title_utils.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:chessever2/widgets/liquid_glass/glass_back_button.dart';
import 'package:chessever2/widgets/liquid_glass/glass_full_screen_page.dart';
import 'package:chessever2/widgets/liquid_glass/glass_island_top_bar.dart';
import 'package:chessever2/widgets/liquid_glass/glass_title_chip.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class GamebasePlayerGamesScreen extends ConsumerStatefulWidget {
  final GamebasePlayer player;

  const GamebasePlayerGamesScreen({super.key, required this.player});

  @override
  ConsumerState<GamebasePlayerGamesScreen> createState() =>
      _GamebasePlayerGamesScreenState();
}

class _GamebasePlayerGamesScreenState
    extends ConsumerState<GamebasePlayerGamesScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref
          .read(gamebasePlayerGamesProvider(widget.player).notifier)
          .loadMoreGames();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gamebasePlayerGamesProvider(widget.player));
    final displayTitle = ChessTitleUtils.normalize(widget.player.title);

    final titleLabel =
        displayTitle.isNotEmpty
            ? '$displayTitle ${widget.player.name}'
            : widget.player.name;

    return GlassFullScreenPage(
      backgroundColor: context.colors.background,
      includeContentSafeArea: false,
      contentPadding: const EdgeInsets.only(top: 72, bottom: 24),
      topOverlayPadding: const EdgeInsets.only(top: 4),
      topOverlay: GlassIslandTopBar(
        topPadding: 0,
        height: 48,
        leading: const GlassBackButton(),
        title: GlassTitleChip(
          label: titleLabel,
          maxWidth: 220.w,
          icon:
              widget.player.fed.trim().isEmpty
                  ? null
                  : FederationFlag(
                    federation: widget.player.fed,
                    width: 16.w,
                    height: 12.h,
                    borderRadius: BorderRadius.circular(2.br),
                  ),
        ),
      ),
      content: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth:
                ResponsiveHelper.isTablet
                    ? ResponsiveHelper.contentMaxWidth
                    : double.infinity,
          ),
          child: _buildBody(state),
        ),
      ),
    );
  }

  Widget _buildBody(GamebasePlayerGamesState state) {
    if (state.isLoading && state.games.isEmpty) {
      return Center(
        child: CircularProgressIndicator(color: context.colors.textPrimary),
      );
    }

    if (state.error != null && state.games.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: kRedColor, size: 48.sp),
            SizedBox(height: 16.h),
            Text(
              'Failed to load games',
              style: AppTypography.textMdMedium.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
            SizedBox(height: 8.h),
            TextButton(
              onPressed:
                  () =>
                      ref
                          .read(
                            gamebasePlayerGamesProvider(widget.player).notifier,
                          )
                          .refreshGames(),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: Text(
                'Retry',
                style: AppTypography.textSmMedium.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (state.games.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.sports_esports_outlined,
              color: context.colors.iconSecondary,
              size: 48.sp,
            ),
            SizedBox(height: 16.h),
            Text(
              'No games found',
              style: AppTypography.textMdMedium.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              'This player has no recorded games',
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh:
          () =>
              ref
                  .read(gamebasePlayerGamesProvider(widget.player).notifier)
                  .refreshGames(),
      color: context.colors.textPrimary,
      backgroundColor: context.colors.surface,
      child: ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.adaptive(phone: 16.w, tablet: 24.w),
          vertical: 12.h,
        ),
        itemCount: state.games.length + (state.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= state.games.length) {
            return Padding(
              padding: EdgeInsets.symmetric(vertical: 24.h),
              child: Center(
                child: CircularProgressIndicator(
                  color: context.colors.textPrimary,
                ),
              ),
            );
          }

          final game = state.games[index];
          return Padding(
            padding: EdgeInsets.only(bottom: 12.h),
            child: GamebaseSearchGameCard(
              game: game,
              allGames: state.games,
              gameIndex: index,
              animationIndex: index,
              onAdd: () => _showAddToFolderSheet(context, game),
              hideEventInfo: true,
            ),
          );
        },
      ),
    );
  }

  void _showAddToFolderSheet(BuildContext context, GamesTourModel game) {
    showAddToFolderSheet(context: context, game: game);
  }
}
