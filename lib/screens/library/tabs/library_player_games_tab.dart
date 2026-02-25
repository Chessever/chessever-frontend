import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/library/providers/library_player_profile_provider.dart';
import 'package:chessever2/screens/library/widgets/add_to_folder_sheet.dart';
import 'package:chessever2/screens/library/widgets/gamebase_search_game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Games tab for library player profile
/// Displays games from gamebase (historical chess database)
class LibraryPlayerGamesTab extends ConsumerStatefulWidget {
  const LibraryPlayerGamesTab({
    super.key,
    required this.playerKey,
    required this.player,
  });

  final LibraryPlayerProfileKey playerKey;
  final GamebasePlayer player;

  @override
  ConsumerState<LibraryPlayerGamesTab> createState() =>
      _LibraryPlayerGamesTabState();
}

class _LibraryPlayerGamesTabState extends ConsumerState<LibraryPlayerGamesTab>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

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
          .read(libraryPlayerGamesProvider(widget.playerKey).notifier)
          .loadMoreGames();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(libraryPlayerGamesProvider(widget.playerKey));

    return _buildBody(state);
  }

  Widget _buildBody(LibraryPlayerGamesState state) {
    if (state.isLoading && state.games.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: kWhiteColor));
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
              style: AppTypography.textMdMedium.copyWith(color: kWhiteColor),
            ),
            SizedBox(height: 8.h),
            TextButton(
              onPressed:
                  () =>
                      ref
                          .read(
                            libraryPlayerGamesProvider(
                              widget.playerKey,
                            ).notifier,
                          )
                          .refreshGames(),
              child: Text(
                'Retry',
                style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
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
              style: AppTypography.textMdMedium.copyWith(color: kWhiteColor),
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
                  .read(libraryPlayerGamesProvider(widget.playerKey).notifier)
                  .refreshGames(),
      color: kWhiteColor,
      backgroundColor: kBlack2Color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Games count header
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
            child: Text(
              '${state.games.length} games',
              style: AppTypography.textSmMedium.copyWith(
                color: kWhiteColor.withValues(alpha: 0.7),
              ),
            ),
          ),

          // Games list
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              itemCount: state.games.length + (state.hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= state.games.length) {
                  return Padding(
                    padding: EdgeInsets.symmetric(vertical: 24.h),
                    child: const Center(
                      child: CircularProgressIndicator(color: kWhiteColor),
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
                    hideEventInfo: false,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showAddToFolderSheet(BuildContext context, GamesTourModel game) {
    showAddToFolderSheet(context: context, game: game);
  }
}
