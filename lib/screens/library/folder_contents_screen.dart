import 'dart:async';

import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/library/providers/book_games_search_provider.dart';
import 'package:chessever2/screens/library/widgets/book_games_filter_dialog.dart';
import 'package:chessever2/screens/library/widgets/book_saved_game_card.dart';
import 'package:chessever2/screens/library/widgets/gamebase_search_game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Book (folder) screen.
///
/// - When search is empty, shows saved games in the book.
/// - When search has content, queries the Gamebase/TWIC database and lets the
///   user add results into the book.
class FolderContentsScreen extends ConsumerStatefulWidget {
  const FolderContentsScreen({
    super.key,
    required this.folder,
  });

  final LibraryFolder folder;

  @override
  ConsumerState<FolderContentsScreen> createState() =>
      _FolderContentsScreenState();
}

class _FolderContentsScreenState extends ConsumerState<FolderContentsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _debounceTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onScroll() {
    final searchState = ref.read(bookGamesSearchProvider).valueOrNull;
    if (searchState == null ||
        searchState.query.isEmpty ||
        !searchState.hasMore ||
        searchState.isLoadingMore) {
      return;
    }

    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(bookGamesSearchProvider.notifier).loadMore();
    }
  }

  void _handleSearchInput(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 220), () {
      ref.read(bookGamesSearchProvider.notifier).setQuery(value);
      setState(() {});
    });
  }

  void _clearSearch() {
    _searchController.clear();
    ref.read(bookGamesSearchProvider.notifier).setQuery('');
    _searchFocusNode.unfocus();
    setState(() {});
  }

  Future<void> _openFilters() async {
    HapticFeedbackService.buttonPress();
    final current =
        ref.read(bookGamesSearchProvider).valueOrNull?.filter ??
        BookGamesFilter.defaultFilter();

    final newFilter = await showBookGamesFilterDialog(
      context: context,
      currentFilter: current,
    );

    if (newFilter != null && mounted) {
      await ref.read(bookGamesSearchProvider.notifier).applyFilter(newFilter);
    }
  }

  Future<void> _addGameToBook(
    GamesTourModel game,
    List<SavedAnalysis> existingAnalyses,
  ) async {
    try {
      final alreadyAdded = existingAnalyses.any(
        (a) => a.sourceGameId == game.gameId,
      );
      if (alreadyAdded) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Game already in this book',
              style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
            ),
            backgroundColor: kBlack2Color.withValues(alpha: 0.95),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final gameRepository = ref.read(gameRepositoryProvider);
      final pgn = await gameRepository.getGamePgn(game.gameId);
      if (pgn == null || pgn.isEmpty) {
        throw Exception('PGN not available');
      }

      final chessGame = ChessGame.fromPgn(game.gameId, pgn);
      final whiteName =
          chessGame.metadata['White'] as String? ?? game.whitePlayer.name;
      final blackName =
          chessGame.metadata['Black'] as String? ?? game.blackPlayer.name;

      final userId =
          ref.read(libraryRepositoryProvider).supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      final analysis = SavedAnalysis(
        id: '',
        userId: userId,
        folderId: widget.folder.id,
        title: '$whiteName vs $blackName',
        sourceGameId: game.gameId,
        sourceTournamentId: game.tourId,
        chessGame: chessGame,
        analysisState: const {},
        variationComments: const {},
        lastViewedPosition: -1,
        tags: const [],
        notes: null,
        isFavorite: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await ref.read(libraryRepositoryProvider).createSavedAnalysis(analysis);
      ref.invalidate(_folderAnalysesProvider(widget.folder.id));

      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Added to "${widget.folder.name}"',
            style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
          ),
          backgroundColor: kBlack2Color.withValues(alpha: 0.95),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to add game: $e',
            style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
          ),
          backgroundColor: kRedColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final analysesAsync = ref.watch(_folderAnalysesProvider(widget.folder.id));
    final searchAsync = ref.watch(bookGamesSearchProvider);
    final searchState = searchAsync.valueOrNull;
    final isSearching = searchState?.query.isNotEmpty == true;

    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: ScreenWrapper(
        child: Column(
          children: [
            _buildHeader(context),
            _buildSearchRow(isSearching),
            Expanded(
              child: isSearching
                  ? _buildDatabaseResults(searchAsync, analysesAsync)
                  : _buildSavedGames(analysesAsync),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).viewPadding.top + 8.h,
        left: 8.w,
        right: 16.w,
        bottom: 8.h,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).pop();
            },
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: kWhiteColor,
              size: 20.ic,
            ),
          ),
          SizedBox(width: 6.w),
          Expanded(
            child: Text(
              widget.folder.name,
              style: AppTypography.textLgBold.copyWith(color: kWhiteColor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchRow(bool isSearching) {
    final filter = ref.watch(bookGamesSearchProvider).valueOrNull?.filter ??
        BookGamesFilter.defaultFilter();

    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 8.h),
      child: Row(
        children: [
          Expanded(child: _buildSearchField()),
          SizedBox(width: 10.w),
          _SquareIconButton(
            icon: Icons.tune_rounded,
            onTap: _openFilters,
            isActive: filter.hasActiveFilters,
          ),
          if (isSearching) ...[
            SizedBox(width: 8.w),
            _SquareIconButton(
              icon: Icons.close_rounded,
              onTap: _clearSearch,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: kBlack2Color,
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(color: kWhiteColor.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Icon(Icons.search, color: kWhiteColor.withValues(alpha: 0.7)),
          SizedBox(width: 10.w),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              style: AppTypography.textSmRegular.copyWith(color: kWhiteColor),
              onChanged: _handleSearchInput,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search games, players, events, openings...',
                hintStyle: AppTypography.textSmRegular.copyWith(
                  color: kWhiteColor.withValues(alpha: 0.5),
                ),
                border: InputBorder.none,
              ),
            ),
          ),
          if (_searchController.text.isNotEmpty)
            GestureDetector(
              onTap: _clearSearch,
              child: Container(
                padding: EdgeInsets.all(6.sp),
                decoration: BoxDecoration(
                  color: kWhiteColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.close,
                  size: 14.sp,
                  color: kWhiteColor.withValues(alpha: 0.7),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSavedGames(AsyncValue<List<SavedAnalysis>> analysesAsync) {
    return RefreshIndicator(
      onRefresh: () async {
        HapticFeedbackService.medium();
        ref.invalidate(_folderAnalysesProvider(widget.folder.id));
      },
      color: kPrimaryColor,
      backgroundColor: kBlack2Color,
      child: analysesAsync.when(
        data: (analyses) {
          if (analyses.isEmpty) return _buildEmptySavedState();
          return ListView.separated(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
            itemCount: analyses.length,
            separatorBuilder: (_, __) => SizedBox(height: 10.h),
            itemBuilder: (context, index) {
              return BookSavedGameCard(analysis: analyses[index]);
            },
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: kPrimaryColor),
        ),
        error: (error, _) => _buildErrorState(error.toString()),
      ),
    );
  }

  Widget _buildDatabaseResults(
    AsyncValue<BookGamesSearchState> searchAsync,
    AsyncValue<List<SavedAnalysis>> analysesAsync,
  ) {
    return analysesAsync.when(
      data: (existingAnalyses) {
        return searchAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: kPrimaryColor),
          ),
          error: (error, _) => _buildErrorState(error.toString()),
          data: (state) {
            if (state.games.isEmpty) {
              return _buildEmptySearchState();
            }
            return RefreshIndicator(
              onRefresh: () async {
                HapticFeedbackService.medium();
                await ref.read(bookGamesSearchProvider.notifier).refresh();
              },
              color: kPrimaryColor,
              backgroundColor: kBlack2Color,
              child: ListView.builder(
                controller: _scrollController,
                padding: EdgeInsets.all(16.sp),
                itemCount: state.games.length + (state.isLoadingMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == state.games.length) {
                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: 16.h),
                      child: Center(
                        child: SizedBox(
                          width: 24.sp,
                          height: 24.sp,
                          child: const CircularProgressIndicator(
                            color: kPrimaryColor,
                            strokeWidth: 2,
                          ),
                        ),
                      ),
                    );
                  }

                  final game = state.games[index];
                  return GamebaseSearchGameCard(
                    game: game,
                    allGames: state.games,
                    gameIndex: index,
                    animationIndex: index,
                    onAdd: () => _addGameToBook(game, existingAnalyses),
                  );
                },
              ),
            );
          },
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: kPrimaryColor),
      ),
      error: (error, _) => _buildErrorState(error.toString()),
    );
  }

  Widget _buildEmptySavedState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.sp),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: 64.sp,
              color: kWhiteColor.withValues(alpha: 0.35),
            ),
            SizedBox(height: 12.h),
            Text(
              'No games in this book',
              style: AppTypography.textMdMedium.copyWith(
                color: kWhiteColor.withValues(alpha: 0.8),
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              'Search the database to add your first game.',
              style: AppTypography.textSmRegular.copyWith(
                color: kWhiteColor.withValues(alpha: 0.55),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySearchState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.sp),
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
              'No results',
              style: AppTypography.textMdMedium.copyWith(
                color: kWhiteColor.withValues(alpha: 0.8),
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              'Try a different search or adjust filters.',
              style: AppTypography.textSmRegular.copyWith(
                color: kWhiteColor.withValues(alpha: 0.55),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.sp),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 56.sp,
              color: kRedColor.withValues(alpha: 0.8),
            ),
            SizedBox(height: 12.h),
            Text(
              'Something went wrong',
              style: AppTypography.textMdMedium.copyWith(color: kWhiteColor),
            ),
            SizedBox(height: 6.h),
            Text(
              error,
              style: AppTypography.textSmRegular.copyWith(
                color: kWhiteColor.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _SquareIconButton extends StatelessWidget {
  const _SquareIconButton({
    required this.icon,
    required this.onTap,
    this.isActive = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42.w,
        height: 42.h,
        decoration: BoxDecoration(
          color: kBlack2Color,
          borderRadius: BorderRadius.circular(10.br),
          border: Border.all(
            color:
                isActive
                    ? kPrimaryColor.withValues(alpha: 0.7)
                    : kWhiteColor.withValues(alpha: 0.08),
          ),
        ),
        child: Icon(
          icon,
          color: isActive ? kPrimaryColor : kWhiteColor,
          size: 20.ic,
        ),
      ),
    );
  }
}

// Stream provider for folder analyses
final _folderAnalysesProvider =
    StreamProvider.family.autoDispose<List<SavedAnalysis>, String>(
  (ref, folderId) {
    final repository = ref.watch(libraryRepositoryProvider);
    return repository.subscribeAnalyses(folderId: folderId);
  },
);
