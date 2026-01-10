import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/library/providers/gamebase_player_games_provider.dart';
import 'package:chessever2/screens/library/widgets/add_to_folder_sheet.dart';
import 'package:chessever2/screens/library/widgets/gamebase_search_game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/chess_title_utils.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/federation_flag.dart';
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
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        backgroundColor: kBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: kWhiteColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                      color: kWhiteColor,
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
        centerTitle: false,
      ),
      body: Center(
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
                            gamebasePlayerGamesProvider(widget.player).notifier,
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
                  .read(gamebasePlayerGamesProvider(widget.player).notifier)
                  .refreshGames(),
      color: kWhiteColor,
      backgroundColor: kBlack2Color,
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
