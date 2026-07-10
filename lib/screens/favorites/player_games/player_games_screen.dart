import 'package:chessever2/screens/favorites/player_games/provider/player_games_provider.dart';
import 'package:chessever2/screens/favorites/player_games/view_model/player_games_state.dart';
import 'package:chessever2/screens/favorites/player_games/models/player_identifier.dart';
import 'package:chessever2/screens/favorites/player_games/widgets/tournament_group_header.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/widgets/liquid_glass/glass_back_button.dart';
import 'package:chessever2/widgets/liquid_glass/glass_full_screen_page.dart';
import 'package:chessever2/widgets/liquid_glass/glass_island_top_bar.dart';
import 'package:chessever2/widgets/liquid_glass/glass_title_chip.dart';

class PlayerGamesScreen extends ConsumerStatefulWidget {
  final String? fideId;
  final String playerName;
  final String? playerTitle;
  final String? countryCode;

  const PlayerGamesScreen({
    super.key,
    this.fideId,
    required this.playerName,
    this.playerTitle,
    this.countryCode,
  });

  @override
  ConsumerState<PlayerGamesScreen> createState() => _PlayerGamesScreenState();
}

class _PlayerGamesScreenState extends ConsumerState<PlayerGamesScreen> {
  final ScrollController _scrollController = ScrollController();
  late final PlayerIdentifier _playerIdentifier;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    // Create player identifier
    _playerIdentifier =
        widget.fideId != null && widget.fideId!.isNotEmpty
            ? PlayerIdentifier.fromFideId(widget.fideId!, widget.playerName)
            : PlayerIdentifier.fromName(widget.playerName);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Check if user scrolled to 80% of the list
    final scrollPosition = _scrollController.position;
    if (scrollPosition.pixels >= scrollPosition.maxScrollExtent * 0.8) {
      // Load more games
      ref.read(playerGamesProvider(_playerIdentifier).notifier).loadMoreGames();
    }
  }

  @override
  Widget build(BuildContext context) {
    final playerGamesAsync = ref.watch(playerGamesProvider(_playerIdentifier));
    final controlExtent = _controlExtent(context);
    final topContentInset =
        MediaQuery.viewPaddingOf(context).top + 4 + controlExtent + 6 + 8;

    return GlassFullScreenPage(
      backgroundColor: context.colors.background,
      includeContentSafeArea: false,
      topOverlayPadding: const EdgeInsets.only(top: 4),
      topOverlay: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth:
                ResponsiveHelper.isTablet
                    ? ResponsiveHelper.contentMaxWidth
                    : double.infinity,
          ),
          child: _buildHeader(controlExtent),
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
          child: playerGamesAsync.when(
            data:
                (playerGamesState) =>
                    _buildContent(playerGamesState, topContentInset),
            loading: () => _buildLoadingState(topContentInset),
            error: (error, stack) {
              debugPrint('===== PlayerGamesScreen AsyncValue error =====');
              debugPrint('Error type: ${error.runtimeType}');
              debugPrint('Error: $error');
              debugPrint('Stack: $stack');
              return Padding(
                padding: EdgeInsets.only(top: topContentInset),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const _PlayerGamesErrorHeading(),
                      SizedBox(height: 16.h),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 32.sp),
                        child: Text(
                          userFacingError(error),
                          style: AppTypography.textSmRegular.copyWith(
                            color: context.colors.textPrimary.withValues(
                              alpha: 0.7,
                            ),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  double _controlExtent(BuildContext context) {
    final scaledLabelHeight = MediaQuery.textScalerOf(context).scale(16);
    final dynamicExtent = scaledLabelHeight + 28;
    return dynamicExtent < 48 ? 48 : dynamicExtent;
  }

  Widget _buildHeader(double controlExtent) {
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 20.sp,
      tablet: 32.sp,
    );
    final title =
        widget.playerTitle?.isNotEmpty == true
            ? '${widget.playerTitle} ${widget.playerName}'
            : widget.playerName;
    return GlassIslandTopBar(
      horizontalPadding: horizontalPadding,
      topPadding: 0,
      height: controlExtent,
      leading: const GlassBackButton(),
      title: GlassTitleChip(
        label: title,
        height: controlExtent,
        maxWidth: 220.w,
      ),
    );
  }

  Widget _buildContent(
    PlayerGamesState playerGamesState,
    double topContentInset,
  ) {
    final tournamentGroups = playerGamesState.tournamentGroups;
    final isLoading = playerGamesState.isLoading;
    final error = playerGamesState.error;

    // Error state
    if (error != null && tournamentGroups.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(top: topContentInset),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _PlayerGamesErrorHeading(),
              SizedBox(height: 16.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 32.sp),
                child: Text(
                  error,
                  style: AppTypography.textSmRegular.copyWith(
                    color: context.colors.textPrimary.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Empty state (no loading, no groups)
    if (!isLoading && tournamentGroups.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(top: topContentInset),
        child: _buildEmptyState(),
      );
    }

    // Has data
    return RefreshIndicator(
      onRefresh: () async {
        HapticFeedbackService.medium();
        await ref
            .read(playerGamesProvider(_playerIdentifier).notifier)
            .refreshGames();
      },
      color: context.colors.textPrimaryMuted,
      backgroundColor: context.colors.surfaceRecessed,
      edgeOffset: topContentInset,
      child: ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.only(
          left: 20.sp,
          right: 20.sp,
          top: topContentInset + 8.h,
          bottom: MediaQuery.of(context).viewPadding.bottom + 20.sp,
        ),
        itemCount: _calculateItemCount(tournamentGroups, isLoading),
        itemBuilder: (context, index) {
          return _buildListItem(index, tournamentGroups, isLoading);
        },
      ),
    );
  }

  int _calculateItemCount(
    List<TournamentGamesGroup> tournamentGroups,
    bool isLoading,
  ) {
    int count = 0;
    for (final group in tournamentGroups) {
      count++; // Header
      count += group.games.length; // Games
    }
    if (isLoading) count++; // Loading indicator
    return count;
  }

  Widget _buildListItem(
    int index,
    List<TournamentGamesGroup> tournamentGroups,
    bool isLoadingMore,
  ) {
    int currentIndex = 0;

    // Iterate through tournament groups
    for (final group in tournamentGroups) {
      // Tournament header
      if (currentIndex == index) {
        return TournamentGroupHeader(tournamentGroup: group);
      }
      currentIndex++;

      // Games in this tournament
      for (int gameIdx = 0; gameIdx < group.games.length; gameIdx++) {
        if (currentIndex == index) {
          final game = group.games[gameIdx];

          // Create a GamesScreenModel with just this tournament's games
          final gamesData = GamesScreenModel(
            gamesTourModels: group.games,
            pinnedGamedIs: [],
            isSearchMode: false,
          );

          return Padding(
            padding: EdgeInsets.only(bottom: 12.sp),
            child: GameCardWrapperWidget(
              game: game,
              gamesData: gamesData,
              gameIndex: gameIdx,
              isChessBoardVisible: false,
              onReturnFromChessboard: (returnedIndex) {},
            ),
          );
        }
        currentIndex++;
      }
    }

    // Loading indicator at the end
    if (isLoadingMore) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 20.sp),
        child: Center(child: CircularProgressIndicator(color: kPrimaryColor)),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.sports_esports_outlined,
            size: 48.ic,
            color: context.colors.textPrimary.withValues(alpha: 0.5),
          ),
          SizedBox(height: 16.h),
          Text(
            'No games found',
            style: AppTypography.textMdMedium.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.7),
            ),
          ),
          SizedBox(height: 8.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 32.sp),
            child: Text(
              'This player has not played any games yet',
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textPrimary.withValues(alpha: 0.5),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(double topContentInset) {
    return SkeletonWidget(
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(
          20.sp,
          topContentInset + 8.h,
          20.sp,
          MediaQuery.viewPaddingOf(context).bottom + 20.h,
        ),
        itemCount: 3,
        itemBuilder:
            (context, index) => Column(
              children: [
                Container(
                  height: 70.h,
                  decoration: BoxDecoration(
                    color: context.colors.surface,
                    borderRadius: BorderRadius.circular(8.br),
                  ),
                ),
                SizedBox(height: 12.h),
                ...List.generate(
                  2,
                  (i) => Padding(
                    padding: EdgeInsets.only(bottom: 12.sp),
                    child: Container(
                      height: 84.h,
                      decoration: BoxDecoration(
                        color: context.colors.surface,
                        borderRadius: BorderRadius.circular(12.br),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 20.h),
              ],
            ),
      ),
    );
  }
}

class _PlayerGamesErrorHeading extends StatelessWidget {
  const _PlayerGamesErrorHeading();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.error_outline_rounded,
          size: 40,
          color: context.colors.iconSecondary,
        ),
        SizedBox(height: 8.h),
        Text(
          'Something went wrong',
          textAlign: TextAlign.center,
          style: AppTypography.textSmMedium.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
      ],
    );
  }
}
