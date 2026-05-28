import 'dart:async';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/library/folder_contents_screen.dart';
import 'package:chessever2/screens/library/providers/gamebase_database_games_provider.dart';
import 'package:chessever2/screens/library/providers/gamebase_filter_provider.dart';
import 'package:chessever2/screens/library/providers/library_combined_search_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/screens/library/utils/create_empty_game.dart';
import 'package:chessever2/screens/library/utils/gamebase_game_to_games_tour_model.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/library/utils/load_saved_analysis.dart';
import 'package:chessever2/screens/library/widgets/library_gamebase_filter_dialog.dart';
import 'package:chessever2/screens/library/widgets/create_folder_dialog.dart';
import 'package:chessever2/screens/library/widgets/folder_card.dart';
import 'package:chessever2/screens/library/widgets/library_search_bar.dart';
import 'package:chessever2/screens/library/widgets/library_search_results_view.dart';
import 'package:chessever2/screens/library/library_player_profile_screen.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
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
import 'package:motor/motor.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';
  bool _isSearchFocused = false;

  // Debounce timer for API calls
  Timer? _debounceTimer;
  static const _debounceDuration = Duration(milliseconds: 350);

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_onSearchFocusChange);
  }

  void _onSearchFocusChange() {
    setState(() {
      _isSearchFocused = _searchFocusNode.hasFocus;
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchFocusNode.removeListener(_onSearchFocusChange);
    _searchFocusNode.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
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
              showGamebaseButton: false,
              disableGamebaseOverlayByDefault: true,
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
        final shouldFocusSearch = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => FolderContentsScreen(folder: newFolder),
          ),
        );
        if (shouldFocusSearch == true && mounted) {
          _searchFocusNode.requestFocus();
        }
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
    ref.listen<BottomNavBarReTapRequest>(bottomNavBarReTapRequestProvider, (
      previous,
      next,
    ) {
      if (next.item == BottomNavBarItem.library) {
        _scrollToTop();
      }
    });

    return ScreenWrapper(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.contentMaxWidth,
          ),
          child: Column(
            children: [_buildTopBar(), Expanded(child: _buildContent())],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final topPadding = MediaQuery.of(context).viewPadding.top;
    final filtersActive = ref.watch(hasActiveGamebaseFiltersProvider);
    // Only show filter button when user has entered a search query
    // because Gamebase /api/search requires 'q' parameter
    final showFilterButton = _searchQuery.isNotEmpty;

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
      child: SingleMotionBuilder(
        motion: CupertinoMotion.snappy(),
        value: _isSearchFocused ? 1.0 : 0.0,
        builder: (context, value, child) {
          // value goes from 0 (unfocused) to 1 (focused)
          // Clamp all values to avoid negative width constraints
          final clampedValue = value.clamp(0.0, 1.0);
          final buttonWidth = (44.h * (1 - clampedValue)).clamp(0.0, 44.h);
          final filterGap = (10.w * (1 - clampedValue)).clamp(0.0, 10.w);
          final buttonGap = (8.w * (1 - clampedValue)).clamp(0.0, 8.w);
          final opacity = (1 - clampedValue).clamp(0.0, 1.0);

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Search bar - expands to full width when focused
              Expanded(child: _buildSearchField()),
              // Filter button gap - only when filter button is shown
              if (showFilterButton) SizedBox(width: filterGap),
              // Filter button - only shown when search query exists
              if (showFilterButton)
                Opacity(
                  opacity: opacity,
                  child: SizedBox(
                    width: buttonWidth,
                    child:
                        buttonWidth > 1
                            ? _FilterButton(
                              isActive: filtersActive,
                              onTap: _openFilters,
                            )
                            : const SizedBox.shrink(),
                  ),
                ),

              // Empty board button gap
              SizedBox(width: buttonGap),
              // Empty board button
              Opacity(
                opacity: opacity,
                child: SizedBox(
                  width: buttonWidth,
                  child:
                      buttonWidth > 1
                          ? _SquareIconButton(
                            icon: Icons.grid_on_rounded,
                            onTap: _navigateToEmptyBoard,
                          )
                          : const SizedBox.shrink(),
                ),
              ),
              // Add folder button gap
              SizedBox(width: buttonGap),
              // Add folder button
              Opacity(
                opacity: opacity,
                child: SizedBox(
                  width: buttonWidth,
                  child:
                      buttonWidth > 1
                          ? _SquareIconButton(
                            icon: Icons.add,
                            onTap: _handleCreateFolder,
                            isPrimary: true,
                          )
                          : const SizedBox.shrink(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchField() {
    return LibrarySearchBar(
      controller: _searchController,
      focusNode: _searchFocusNode,
      enableOverlay: true,
      hintText: 'Search',
      onChanged: (query) {
        final trimmed = query.trim();
        // Update local state immediately for UI responsiveness
        setState(() => _searchQuery = trimmed.toLowerCase());

        // Debounce the provider update to avoid excessive API calls
        _debounceTimer?.cancel();
        _debounceTimer = Timer(_debounceDuration, () {
          if (mounted) {
            ref.read(librarySearchQueryProvider.notifier).state = trimmed;
          }
        });
      },
      onFolderTap: (folder) async {
        final shouldFocusSearch = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => FolderContentsScreen(folder: folder),
          ),
        );
        if (shouldFocusSearch == true && mounted) {
          _searchFocusNode.requestFocus();
        }
      },
      onAnalysisTap: (analysis) {
        loadSavedAnalysis(context, analysis);
      },
      onPlayerTap: (player) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => LibraryPlayerProfileScreen(player: player),
          ),
        );
      },
      onGameTap: (gameRow) {
        _openGame(gameRow);
      },
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
              showGamebaseButton: false,
              disableGamebaseOverlayByDefault: true,
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
    final event =
        row['event']?.toString() ?? row['Event']?.toString() ?? 'Gamebase';
    final site = row['site']?.toString() ?? row['Site']?.toString();
    final date =
        row['date'] != null ? DateTime.tryParse(row['date'].toString()) : null;

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
      tourId: event,
      pgn: buildHeaderOnlyPgn(
        whiteName: whiteName,
        blackName: blackName,
        result: result,
        event: event,
        site: site,
        date: date,
        eco: row['eco']?.toString() ?? row['ECO']?.toString(),
        opening: row['opening']?.toString() ?? row['Opening']?.toString(),
        variation: row['variation']?.toString() ?? row['Variation']?.toString(),
      ),
      lastMoveTime: date,
    );
  }

  Future<void> _openFilters() async {
    HapticFeedbackService.light();

    final currentFilter = ref.read(gamebaseFilterProvider);
    final newFilter = await showLibraryGamebaseFilterDialog(
      context: context,
      currentFilter: currentFilter,
    );

    if (newFilter != null) {
      ref.read(gamebaseFilterProvider.notifier).state = newFilter;
    }
  }

  Widget _buildContent() {
    final filtersActive = ref.watch(hasActiveGamebaseFiltersProvider);
    final isSearchMode = _searchQuery.isNotEmpty || filtersActive;
    final viewMode = ref.watch(gamesListViewModeProvider);

    if (isSearchMode) {
      final searchResultsAsync = ref.watch(
        libraryCombinedSearchProvider(_searchQuery),
      );

      final databaseGamesAsync =
          filtersActive ? ref.watch(gamebaseDatabaseGamesProvider) : null;

      return searchResultsAsync.when(
        data:
            (results) => LibrarySearchResultsView(
              results: results,
              databaseGamesAsync: databaseGamesAsync,
              viewMode: viewMode,
              scrollController: _scrollController,
              onFolderTap: (folder) async {
                final shouldFocusSearch = await Navigator.of(
                  context,
                ).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => FolderContentsScreen(folder: folder),
                  ),
                );
                if (shouldFocusSearch == true && mounted) {
                  _searchFocusNode.requestFocus();
                }
              },
              onAnalysisTap: (analysis) => loadSavedAnalysis(context, analysis),
              onPlayerTap: (player) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LibraryPlayerProfileScreen(player: player),
                  ),
                );
              },
              onPlayerFilter: (player) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LibraryPlayerProfileScreen(player: player),
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
                          showGamebaseButton: false,
                          disableGamebaseOverlayByDefault: true,
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

    // Check if we have folders to show background decoration
    final hasFolders = foldersAsync.valueOrNull?.isNotEmpty ?? false;

    return Stack(
      children: [
        // Subtle background decoration - only when folders exist
        if (hasFolders)
          const Positioned.fill(child: _LibraryBackgroundDecoration()),
        // Main content
        RefreshIndicator(
          onRefresh: () async {
            HapticFeedbackService.medium();
            ref.invalidate(libraryFoldersStreamProvider);
          },
          color: kWhiteColor,
          backgroundColor: kBlack2Color,
          child: CustomScrollView(
            controller: _scrollController,
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
        ),
      ],
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

    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 24.w,
    );

    // Use grid layout for tablets
    if (ResponsiveHelper.isTablet) {
      final crossAxisCount = ResponsiveHelper.tabletGridColumns.clamp(2, 3);
      return SliverPadding(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: 8.h,
        ),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16.sp,
            mainAxisSpacing: 16.sp,
            childAspectRatio: ResponsiveHelper.isLandscape ? 2.5 : 2.0,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => FolderCard(
              folder: filteredFolders[index],
              isExpanded: true,
              onTap: () async {
                HapticFeedback.mediumImpact();
                final shouldFocusSearch = await Navigator.of(
                  context,
                ).push<bool>(
                  MaterialPageRoute(
                    builder:
                        (_) => FolderContentsScreen(
                          folder: filteredFolders[index],
                        ),
                  ),
                );
                if (shouldFocusSearch == true && mounted) {
                  _searchFocusNode.requestFocus();
                }
              },
            ),
            childCount: filteredFolders.length,
          ),
        ),
      );
    }

    // Phone layout: single column list
    return SliverPadding(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 8.h,
      ),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => Padding(
            padding: EdgeInsets.only(bottom: 12.h),
            child: FolderCard(
              folder: filteredFolders[index],
              isExpanded: true,
              onTap: () async {
                HapticFeedback.mediumImpact();
                final shouldFocusSearch = await Navigator.of(
                  context,
                ).push<bool>(
                  MaterialPageRoute(
                    builder:
                        (_) => FolderContentsScreen(
                          folder: filteredFolders[index],
                        ),
                  ),
                );
                if (shouldFocusSearch == true && mounted) {
                  _searchFocusNode.requestFocus();
                }
              },
            ),
          ),
          childCount: filteredFolders.length,
        ),
      ),
    );
  }

  Widget _buildLibraryEmptyState() {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: _LibraryEmptyStateContent(
        onSearchTap: () {
          _searchController.clear();
          FocusScope.of(context).requestFocus(FocusNode());
          // Trigger search field focus by tapping on search bar area
          setState(() => _searchQuery = '');
        },
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
    const double size = 44;
    final dimension = size.h;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: dimension,
        height: dimension,
        decoration: BoxDecoration(
          color: isPrimary ? const Color(0xFFFAFAFA) : const Color(0xFF09090B),
          borderRadius: BorderRadius.circular(10.br),
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
                size: 20.sp,
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

/// Filter button styled to match the search bar island
class _FilterButton extends StatelessWidget {
  final bool isActive;
  final VoidCallback onTap;

  const _FilterButton({required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const double size = 44;
    final dimension = size.h;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: dimension,
        height: dimension,
        decoration: BoxDecoration(
          color: const Color(0xFF09090B), // Zinc 950
          borderRadius: BorderRadius.circular(10.br),
          border: Border.all(
            color:
                isActive
                    ? const Color(0xFF52525B) // Zinc 600 when active
                    : const Color(0xFF27272A), // Zinc 800
          ),
        ),
        child: Center(
          child: Icon(
            Icons.tune_rounded,
            size: 20.sp,
            color: const Color(0xFFFAFAFA),
          ),
        ),
      ),
    );
  }
}

/// A visually striking empty state that highlights access to millions of chess games
class _LibraryEmptyStateContent extends StatelessWidget {
  final VoidCallback onSearchTap;

  const _LibraryEmptyStateContent({required this.onSearchTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.w),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Decorative chess pattern grid
          _buildChessPatternVisual(),
          SizedBox(height: 32.h),

          // Main headline
          Text(
            'Millions of games',
            style: AppTypography.displayXsMedium.copyWith(
              color: kWhiteColor,
              letterSpacing: -0.5,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            'at your fingertips',
            style: AppTypography.displayXsMedium.copyWith(
              color: kWhiteColor.withValues(alpha: 0.75),
              letterSpacing: -0.5,
            ),
          ),

          SizedBox(height: 20.h),

          // Description
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: Text(
              'Search any player, opening, or tournament. Save games to your personal books for study.',
              style: AppTypography.textSmRegular.copyWith(
                color: kWhiteColor.withValues(alpha: 0.55),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          SizedBox(height: 32.h),

          // Subtle hint about the search bar
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search_rounded,
                size: 16.sp,
                color: kPrimaryColor.withValues(alpha: 0.8),
              ),
              SizedBox(width: 8.w),
              Text(
                'Use the search bar above to explore',
                style: AppTypography.textXsMedium.copyWith(
                  color: kPrimaryColor.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),

          SizedBox(height: 80.h), // Bottom breathing room
        ],
      ),
    );
  }

  Widget _buildChessPatternVisual() {
    // A stylized 4x4 chess pattern with fading opacity to create depth
    const gridSize = 4;
    final squareSize = 28.w;
    final totalSize = squareSize * gridSize;

    return SizedBox(
      width: totalSize,
      height: totalSize,
      child: Stack(
        children: [
          // Chess grid
          for (int row = 0; row < gridSize; row++)
            for (int col = 0; col < gridSize; col++)
              Positioned(
                left: col * squareSize,
                top: row * squareSize,
                child: _buildSquare(
                  row: row,
                  col: col,
                  size: squareSize,
                  gridSize: gridSize,
                ),
              ),
          // Overlay gradient for depth effect
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8.br),
                gradient: RadialGradient(
                  colors: [
                    Colors.transparent,
                    kBackgroundColor.withValues(alpha: 0.3),
                    kBackgroundColor.withValues(alpha: 0.7),
                  ],
                  stops: const [0.0, 0.6, 1.0],
                  radius: 0.9,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSquare({
    required int row,
    required int col,
    required double size,
    required int gridSize,
  }) {
    final isLight = (row + col) % 2 == 0;

    // Calculate distance from center for opacity falloff
    final centerRow = (gridSize - 1) / 2;
    final centerCol = (gridSize - 1) / 2;
    final distance =
        ((row - centerRow).abs() + (col - centerCol).abs()) / gridSize;
    final opacity = (1.0 - distance * 0.4).clamp(0.3, 1.0);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color:
            isLight
                ? const Color(0xFF3F3F46).withValues(alpha: opacity * 0.6)
                : const Color(0xFF27272A).withValues(alpha: opacity * 0.8),
        borderRadius: _getCornerRadius(row, col, gridSize, 6.br),
      ),
    );
  }

  BorderRadius _getCornerRadius(int row, int col, int gridSize, double radius) {
    final isTopLeft = row == 0 && col == 0;
    final isTopRight = row == 0 && col == gridSize - 1;
    final isBottomLeft = row == gridSize - 1 && col == 0;
    final isBottomRight = row == gridSize - 1 && col == gridSize - 1;

    return BorderRadius.only(
      topLeft: isTopLeft ? Radius.circular(radius) : Radius.zero,
      topRight: isTopRight ? Radius.circular(radius) : Radius.zero,
      bottomLeft: isBottomLeft ? Radius.circular(radius) : Radius.zero,
      bottomRight: isBottomRight ? Radius.circular(radius) : Radius.zero,
    );
  }
}

/// Subtle background decoration shown behind folder cards
/// Displays a ghosted version of the empty state messaging
class _LibraryBackgroundDecoration extends StatelessWidget {
  const _LibraryBackgroundDecoration();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: 0.25,
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Decorative chess pattern - larger for background presence
                _buildChessPatternVisual(),
                SizedBox(height: 32.h),

                // Main headline
                Text(
                  'Millions of games',
                  style: AppTypography.displayXsMedium.copyWith(
                    color: kWhiteColor,
                    letterSpacing: -0.5,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  'at your fingertips',
                  style: AppTypography.displayXsMedium.copyWith(
                    color: kWhiteColor,
                    letterSpacing: -0.5,
                  ),
                ),

                SizedBox(height: 20.h),

                // Description
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20.w),
                  child: Text(
                    'Search any player, opening, or tournament. Save games to your personal books for study.',
                    style: AppTypography.textSmRegular.copyWith(
                      color: kWhiteColor,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChessPatternVisual() {
    const gridSize = 4;
    final squareSize = 28.w;
    final totalSize = squareSize * gridSize;

    return SizedBox(
      width: totalSize,
      height: totalSize,
      child: Stack(
        children: [
          for (int row = 0; row < gridSize; row++)
            for (int col = 0; col < gridSize; col++)
              Positioned(
                left: col * squareSize,
                top: row * squareSize,
                child: _buildSquare(
                  row: row,
                  col: col,
                  size: squareSize,
                  gridSize: gridSize,
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildSquare({
    required int row,
    required int col,
    required double size,
    required int gridSize,
  }) {
    final isLight = (row + col) % 2 == 0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isLight ? const Color(0xFF3F3F46) : const Color(0xFF27272A),
        borderRadius: _getCornerRadius(row, col, gridSize, 6.br),
      ),
    );
  }

  BorderRadius _getCornerRadius(int row, int col, int gridSize, double radius) {
    final isTopLeft = row == 0 && col == 0;
    final isTopRight = row == 0 && col == gridSize - 1;
    final isBottomLeft = row == gridSize - 1 && col == 0;
    final isBottomRight = row == gridSize - 1 && col == gridSize - 1;

    return BorderRadius.only(
      topLeft: isTopLeft ? Radius.circular(radius) : Radius.zero,
      topRight: isTopRight ? Radius.circular(radius) : Radius.zero,
      bottomLeft: isBottomLeft ? Radius.circular(radius) : Radius.zero,
      bottomRight: isBottomRight ? Radius.circular(radius) : Radius.zero,
    );
  }
}
