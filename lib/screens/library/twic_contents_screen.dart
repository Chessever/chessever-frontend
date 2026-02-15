import 'dart:async';

import 'package:chessever2/utils/number_format_utils.dart';
import 'package:chessever2/screens/library/providers/gamebase_database_games_provider.dart';
import 'package:chessever2/screens/library/providers/gamebase_filter_provider.dart';
import 'package:chessever2/screens/library/widgets/add_to_folder_sheet.dart';
import 'package:chessever2/screens/library/widgets/gamebase_search_game_card.dart';
import 'package:chessever2/screens/library/widgets/library_gamebase_filter_dialog.dart';
import 'package:chessever2/screens/library/widgets/library_search_bar.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// TWIC book contents screen.
///
/// Queries the gamebase (4M+ games) with search, filters, and pagination.
/// Uses [gamebaseDatabaseGamesPaginatedProvider] directly for a focused
/// game-only experience with infinite scroll.
class TwicContentsScreen extends ConsumerStatefulWidget {
  const TwicContentsScreen({super.key});

  @override
  ConsumerState<TwicContentsScreen> createState() => _TwicContentsScreenState();
}

class _TwicContentsScreenState extends ConsumerState<TwicContentsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  Timer? _debounceTimer;
  static const _debounceDuration = Duration(milliseconds: 350);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Reset global search query when entering TWIC
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(librarySearchQueryProvider.notifier).state = '';
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final state = ref.read(gamebaseDatabaseGamesPaginatedProvider);
      if (!state.isLoading && state.hasMore) {
        ref
            .read(gamebaseDatabaseGamesPaginatedProvider.notifier)
            .loadNextPage();
      }
    }
  }

  void _onSearchChanged(String query) {
    final trimmed = query.trim();
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () {
      if (mounted) {
        ref.read(librarySearchQueryProvider.notifier).state = trimmed;
      }
    });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: ScreenWrapper(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth:
                  ResponsiveHelper.isTablet
                      ? ResponsiveHelper.contentMaxWidth
                      : double.infinity,
            ),
            child: Column(
              children: [_buildTopArea(), Expanded(child: _buildContent())],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header & Search
  // ---------------------------------------------------------------------------

  Widget _buildTopArea() {
    final topPadding = MediaQuery.of(context).viewPadding.top;

    return Container(
      padding: EdgeInsets.only(top: topPadding + 8.h, bottom: 6.h),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [kBlackColor, kBackgroundColor],
        ),
      ),
      child: Column(children: [_buildHeader(), _buildSearchRow()]),
    );
  }

  Widget _buildHeader() {
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 8.w,
      tablet: 16.w,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        0,
        horizontalPadding,
        8.h,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: () {
                HapticFeedbackService.light();
                Navigator.of(context).pop();
              },
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: kWhiteColor.withValues(alpha: 0.7),
                size: 20.ic,
              ),
            ),
          ),
          Opacity(
            opacity: 0.8,
            child: Text(
              'TWIC Database',
              style: AppTypography.textMdMedium.copyWith(
                fontWeight: FontWeight.w600,
                color: kWhiteColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchRow() {
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 24.w,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        0,
        horizontalPadding,
        8.h,
      ),
      child: LibrarySearchBar(
        controller: _searchController,
        focusNode: _searchFocusNode,
        enableOverlay: false,
        hintText: 'Search games',
        hintPhrases: const [
          'Search players...',
          'Search openings...',
          'Search among millions...',
        ],
        onChanged: _onSearchChanged,
        onFilterTap: _openFilters,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Content
  // ---------------------------------------------------------------------------

  Widget _buildContent() {
    final paginationState = ref.watch(gamebaseDatabaseGamesPaginatedProvider);
    final games = paginationState.games;

    // Loading state (no games yet)
    if (games.isEmpty && paginationState.isLoading) {
      return const Center(child: CircularProgressIndicator(color: kWhiteColor));
    }

    // Error state
    if (paginationState.error != null && games.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 40.sp,
                color: kWhiteColor.withValues(alpha: 0.3),
              ),
              SizedBox(height: 12.h),
              Text(
                'Search failed',
                style: AppTypography.textSmRegular.copyWith(
                  color: const Color(0xFFA1A1AA),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // No results state
    if (games.isEmpty) {
      return Center(
        child: Text(
          'No games found',
          style: AppTypography.textSmRegular.copyWith(
            color: const Color(0xFFA1A1AA),
          ),
        ),
      );
    }

    // Game list with infinite scroll
    final itemCount = games.length + (paginationState.hasMore ? 1 : 0);
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 24.w,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Result count
        if (paginationState.totalCount > 0)
          Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              4.h,
              horizontalPadding,
              8.h,
            ),
            child: Text(
              '${formatCompactCount(paginationState.totalCount)} games',
              style: AppTypography.textXsRegular.copyWith(
                color: kWhiteColor.withValues(alpha: 0.5),
              ),
            ),
          ),

        // Games list
        Expanded(
          child: ListView.separated(
            controller: _scrollController,
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              0,
              horizontalPadding,
              100.h,
            ),
            itemCount: itemCount,
            separatorBuilder: (_, __) => SizedBox(height: 12.h),
            itemBuilder: (context, index) {
              // Load-more indicator at the end
              if (index >= games.length) {
                return Padding(
                  padding: EdgeInsets.symmetric(vertical: 16.h),
                  child: const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: kWhiteColor,
                        strokeWidth: 2,
                      ),
                    ),
                  ),
                );
              }

              final game = games[index];
              return GamebaseSearchGameCard(
                game: game,
                allGames: games,
                gameIndex: index,
                animationIndex: index,
                onAdd: () => showAddToFolderSheet(context: context, game: game),
                showSwipeHint: index == 0,
                hideEventInfo: true,
              );
            },
          ),
        ),
      ],
    );
  }
}
