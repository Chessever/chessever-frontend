import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/library/folder_contents_screen.dart';
import 'package:chessever2/screens/library/providers/gamebase_database_search_provider.dart';
import 'package:chessever2/screens/library/providers/gamebase_database_games_provider.dart';
import 'package:chessever2/screens/library/providers/library_combined_search_provider.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/screens/library/utils/create_empty_game.dart';
import 'package:chessever2/screens/library/utils/gamebase_game_to_games_tour_model.dart';
import 'package:chessever2/screens/library/utils/load_saved_analysis.dart';
import 'package:chessever2/screens/library/widgets/library_gamebase_filters_sheet.dart';
import 'package:chessever2/screens/library/widgets/create_folder_dialog.dart';
import 'package:chessever2/screens/library/widgets/folder_card.dart';
import 'package:chessever2/screens/library/widgets/library_search_bar.dart';
import 'package:chessever2/screens/library/widgets/library_search_results_view.dart';
import 'package:chessever2/screens/library/gamebase_player_games_screen.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _hasOpenedFilters = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Filter method - commented out as filter button is not ready yet
  // void _onFilterPressed() {
  //   HapticFeedback.selectionClick();
  //   ScaffoldMessenger.of(context).showSnackBar(
  //     SnackBar(
  //       behavior: SnackBarBehavior.floating,
  //       backgroundColor: kBlack2Color.withValues(alpha: 0.95),
  //       content: Text(
  //         'Sorting and filters coming soon',
  //         style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
  //       ),
  //     ),
  //   );
  // }

  void _navigateToEmptyBoard() {
    HapticFeedback.mediumImpact();
    ref.read(chessboardViewFromProviderNew.notifier).state =
        ChessboardView.tour;
    final emptyGame = createEmptyGame();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => ChessBoardScreenNew(
              currentIndex: 0,
              games: [emptyGame],
              hideEventInfo: true,
              showGamebaseButton: true,
            ),
      ),
    );
  }

  List<LibraryFolder> _filterFolders(List<LibraryFolder> folders) {
    if (_searchQuery.isEmpty) return folders;
    return folders
        .where((folder) => folder.name.toLowerCase().contains(_searchQuery))
        .toList();
  }

  Future<void> _handleCreateFolder() async {
    HapticFeedback.mediumImpact();
    final name = await showCreateFolderDialog(context);
    if (name == null || name.isEmpty) return;

    try {
      final repository = ref.read(libraryRepositoryProvider);
      final newFolder = await repository.createFolder(name: name);

      // Force refresh folders provider to ensure immediate UI update
      // (Supabase streams may have slight delay)
      ref.invalidate(libraryFoldersStreamProvider);
      await ref.read(libraryFoldersStreamProvider.future);

      if (mounted) {
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Book "$name" created',
              style: TextStyle(color: kWhiteColor),
            ),
            backgroundColor: kBlack2Color.withValues(alpha: 0.95),
            behavior: SnackBarBehavior.floating,
          ),
        );

        // Redirect to the book games list view after creation.
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FolderContentsScreen(folder: newFolder),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        HapticFeedback.lightImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to create book: $e',
              style: TextStyle(color: kWhiteColor),
            ),
            backgroundColor: kRedColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenWrapper(
      child: Column(
        children: [_buildTopBar(), Expanded(child: _buildContent())],
      ),
    );
  }

  Widget _buildTopBar() {
    final topPadding = MediaQuery.of(context).viewPadding.top;
    final filtersActive =
        _hasOpenedFilters &&
        (ref
                .watch(gamebaseDatabaseSearchProvider)
                .valueOrNull
                ?.hasActiveFilters ==
            true);

    return Container(
      padding: EdgeInsets.fromLTRB(16.w, topPadding + 16.h, 16.w, 12.h),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: const Color(0xFF27272A), // Zinc 800
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(child: _buildSearchField(filtersActive: filtersActive)),
          SizedBox(width: 12.w),
          _SquareIconButton(
            iconWidget: SvgWidget(
              SvgAsset.chase_grid,
              height: 18.sp,
              width: 18.sp,
            ),
            onTap: _navigateToEmptyBoard,
          ),
          SizedBox(width: 8.w),
          _SquareIconButton(
            icon: Icons.add,
            onTap: _handleCreateFolder,
            isPrimary: true,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField({required bool filtersActive}) {
    return LibrarySearchBar(
      controller: _searchController,
      enableOverlay: true,
      hintText: 'Search library',
      isFilterActive: filtersActive,
      onChanged: (query) {
        final trimmed = query.trim();
        setState(() => _searchQuery = trimmed.toLowerCase());
        if (_hasOpenedFilters) {
          ref.read(gamebaseDatabaseSearchProvider.notifier).setQuery(trimmed);
        }
      },
      onFolderTap: (folder) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FolderContentsScreen(folder: folder),
          ),
        );
      },
      onAnalysisTap: (analysis) {
        loadSavedAnalysis(context, analysis);
      },
      onPlayerTap: (player) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => GamebasePlayerGamesScreen(player: player),
          ),
        );
      },
      onGameTap: (gameRow) {
        _openGame(gameRow);
      },
      onFilterTap: _openFilters,
    );
  }

  void _openGame(Map<String, dynamic> row) async {
    final id = row['id']?.toString() ?? 'unknown';
    final gamebaseRepository = ref.read(gamebaseRepositoryProvider);
    final fullGame = await gamebaseRepository.getGameById(id);

    final gameModel =
        fullGame != null
            ? mapGamebaseGameToGamesTourModel(fullGame)
            : _toGamesTourModelFallback(id, row);

    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => ChessBoardScreenNew(
              currentIndex: 0,
              games: [gameModel],
              hideEventInfo: true,
              showGamebaseButton: true,
            ),
      ),
    );
  }

  GamesTourModel _toGamesTourModelFallback(
    String id,
    Map<String, dynamic> row,
  ) {
    final result = row['result']?.toString() ?? '*';
    final whiteName =
        row['white']?.toString() ?? row['whiteName']?.toString() ?? 'White';
    final blackName =
        row['black']?.toString() ?? row['blackName']?.toString() ?? 'Black';

    final whitePlayer = PlayerCard(
      name: whiteName,
      federation: '',
      title: '',
      rating: 0,
      countryCode: '',
      team: null,
      fideId: null,
    );

    final blackPlayer = PlayerCard(
      name: blackName,
      federation: '',
      title: '',
      rating: 0,
      countryCode: '',
      team: null,
      fideId: null,
    );

    return GamesTourModel(
      gameId: id,
      whitePlayer: whitePlayer,
      blackPlayer: blackPlayer,
      whiteTimeDisplay: '--:--',
      blackTimeDisplay: '--:--',
      whiteClockCentiseconds: 0,
      blackClockCentiseconds: 0,
      gameStatus: GameStatus.fromString(result),
      roundId: 'gamebase_search',
      tourId: 'Gamebase',
    );
  }

  Future<void> _openFilters() async {
    HapticFeedbackService.light();
    setState(() => _hasOpenedFilters = true);

    // Ensure the provider is initialized and synced to current query.
    ref
        .read(gamebaseDatabaseSearchProvider.notifier)
        .setQuery(_searchController.text.trim());

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const LibraryGamebaseFiltersSheet(),
    );
  }

  Widget _buildContent() {
    final filtersActive =
        _hasOpenedFilters &&
        (ref
                .watch(gamebaseDatabaseSearchProvider)
                .valueOrNull
                ?.hasActiveFilters ==
            true);
    final isSearchMode = _searchQuery.isNotEmpty || filtersActive;

    if (isSearchMode) {
      final searchResultsAsync = ref.watch(
        libraryCombinedSearchProvider(_searchQuery),
      );

      final databaseGamesAsync =
          _hasOpenedFilters ? ref.watch(gamebaseDatabaseGamesProvider) : null;

      return searchResultsAsync.when(
        data:
            (results) => LibrarySearchResultsView(
              results: results,
              databaseGamesAsync: databaseGamesAsync,
              onFolderTap: (folder) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FolderContentsScreen(folder: folder),
                  ),
                );
              },
              onAnalysisTap: (analysis) => loadSavedAnalysis(context, analysis),
              onPlayerTap: (player) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GamebasePlayerGamesScreen(player: player),
                  ),
                );
              },
              onGameTap: (game) async {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder:
                        (_) => ChessBoardScreenNew(
                          currentIndex: 0,
                          games: [game],
                          hideEventInfo: true,
                          showGamebaseButton: true,
                        ),
                  ),
                );
              },
            ),
        loading:
            () => const Center(
              child: CircularProgressIndicator(color: kWhiteColor),
            ),
        error:
            (e, stack) => Center(
              child: Text(
                'Search failed: $e',
                style: const TextStyle(color: kRedColor),
              ),
            ),
      );
    }

    final foldersAsync = ref.watch(libraryFoldersStreamProvider);

    return RefreshIndicator(
      onRefresh: () async {
        HapticFeedbackService.medium();
        ref.invalidate(libraryFoldersStreamProvider);
      },
      color: kWhiteColor,
      backgroundColor: kBlack2Color,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: 4.h)),
          foldersAsync.when(
            data: (folders) => _buildFoldersSliver(folders),
            loading: () => _buildLoadingSliver(),
            error: (error, _) => _buildErrorSliver(error.toString()),
          ),
          SliverToBoxAdapter(child: SizedBox(height: 24.h)),
        ],
      ),
    );
  }

  Widget _buildFoldersSliver(List<LibraryFolder> folders) {
    final filteredFolders = _filterFolders(folders);

    if (folders.isEmpty && _searchQuery.isEmpty) {
      return _buildLibraryEmptyState();
    }

    if (filteredFolders.isEmpty) {
      return _buildSearchEmptyState('No folders match your search');
    }

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => Padding(
            padding: EdgeInsets.only(bottom: 12.h),
            child: FolderCard(folder: filteredFolders[index], isExpanded: true),
          ),
          childCount: filteredFolders.length,
        ),
      ),
    );
  }

  Widget _buildLibraryEmptyState() {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: 80.sp,
              color: kWhiteColor.withValues(alpha: 0.35),
            ),
            SizedBox(height: 18.h),
            Text(
              'Nothing saved yet',
              style: AppTypography.textLgBold.copyWith(color: kWhiteColor),
            ),
            SizedBox(height: 8.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 36.w),
              child: Text(
                'Save a board position or create your first book to get started.',
                style: AppTypography.textSmRegular.copyWith(
                  color: kWhiteColor.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchEmptyState(String message) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_outlined,
              size: 56.sp,
              color: kWhiteColor.withValues(alpha: 0.4),
            ),
            SizedBox(height: 12.h),
            Text(
              message,
              style: AppTypography.textMdMedium.copyWith(
                color: kWhiteColor.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingSliver() {
    return const SliverFillRemaining(
      hasScrollBody: false,
      child: Center(child: CircularProgressIndicator(color: kWhiteColor)),
    );
  }

  Widget _buildErrorSliver(String error) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64.sp,
              color: kRedColor.withValues(alpha: 0.7),
            ),
            SizedBox(height: 16.h),
            Text(
              'Failed to load library',
              style: AppTypography.textLgMedium.copyWith(
                color: const Color(0xFFFAFAFA), // Zinc 50
              ),
            ),
            SizedBox(height: 8.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 40.w),
              child: Text(
                error,
                style: AppTypography.textSmRegular.copyWith(
                  color: const Color(0xFFA1A1AA), // Zinc 400
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SquareIconButton extends StatelessWidget {
  final IconData? icon;
  final Widget? iconWidget;
  final VoidCallback onTap;
  final bool isPrimary;

  const _SquareIconButton({
    required this.onTap,
    this.icon,
    this.iconWidget,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36.w,
        height: 36.h,
        decoration: BoxDecoration(
          color: isPrimary ? const Color(0xFFFAFAFA) : const Color(0xFF09090B),
          borderRadius: BorderRadius.circular(8.br),
          border:
              isPrimary
                  ? null
                  : Border.all(
                    color: const Color(0xFF27272A), // Zinc 800
                  ),
        ),
        child: Center(
          child:
              iconWidget ??
              Icon(
                icon,
                size: 18.sp,
                color:
                    isPrimary
                        ? const Color(0xFF09090B)
                        : const Color(0xFFFAFAFA),
              ),
        ),
      ),
    );
  }
}
