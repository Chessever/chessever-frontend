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

    return Scaffold(
      backgroundColor: context.colors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth:
                ResponsiveHelper.isTablet
                    ? ResponsiveHelper.contentMaxWidth
                    : double.infinity,
          ),
          child: Column(
            children: [
              _buildGlassHeader(context, displayTitle),
              Expanded(child: _buildBody(state)),
            ],
          ),
        ),
      ),
    );
  }

  /// Floating liquid-glass header — replaces the sticky AppBar. Back button
  /// plus the player's title/name and federation, over a top-fading gradient
  /// so games scroll beneath it (matches the library detail pages).
  Widget _buildGlassHeader(BuildContext context, String displayTitle) {
    final topPadding = MediaQuery.of(context).viewPadding.top;
    return Container(
      padding: EdgeInsets.only(top: topPadding + 8.h, bottom: 6.h),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            context.colors.background,
            context.colors.background.withValues(alpha: 0),
          ],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(8.w, 0, 8.w, 4.h),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const GlassBackButton(),
            SizedBox(width: 8.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (displayTitle.isNotEmpty) ...[
                        Text(
                          displayTitle,
                          style: AppTypography.textSmBold.copyWith(
                            color: const Color(0xFFA1A1AA), // Zinc 400
                          ),
                        ),
                        SizedBox(width: 6.w),
                      ],
                      Flexible(
                        child: Text(
                          widget.player.name,
                          style: AppTypography.textMdBold.copyWith(
                            color: context.colors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (widget.player.fed.trim().isNotEmpty) ...[
                    SizedBox(height: 2.h),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FederationFlag(
                          federation: widget.player.fed,
                          width: 16.w,
                          height: 12.h,
                          borderRadius: BorderRadius.circular(2.br),
                        ),
                        SizedBox(width: 6.w),
                        Text(
                          widget.player.fed,
                          style: AppTypography.textXsRegular.copyWith(
                            color: const Color(0xFFA1A1AA),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(GamebasePlayerGamesState state) {
    if (state.isLoading && state.games.isEmpty) {
      return  Center(child: CircularProgressIndicator(color: context.colors.textPrimary));
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
              style: AppTypography.textMdMedium.copyWith(color: context.colors.textPrimary),
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
              child: Text(
                'Retry',
                style: AppTypography.textSmMedium.copyWith(color: context.colors.textPrimary),
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
              color: const Color(0xFFA1A1AA),
              size: 48.sp,
            ),
            SizedBox(height: 16.h),
            Text(
              'No games found',
              style: AppTypography.textMdMedium.copyWith(color: context.colors.textPrimary),
            ),
            SizedBox(height: 4.h),
            Text(
              'This player has no recorded games',
              style: AppTypography.textSmRegular.copyWith(
                color: const Color(0xFFA1A1AA),
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
              child:  Center(
                child: CircularProgressIndicator(color: context.colors.textPrimary),
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
