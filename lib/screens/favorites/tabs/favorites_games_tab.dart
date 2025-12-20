import 'dart:async';

import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/screens/favorites/favorite_players_provider.dart';
import 'package:chessever2/screens/favorites/player_games/provider/favorites_combined_games_provider.dart';
import 'package:chessever2/screens/library/widgets/add_to_folder_sheet.dart';
import 'package:chessever2/screens/library/widgets/gamebase_search_game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

class FavoritesGamesTab extends ConsumerStatefulWidget {
  const FavoritesGamesTab({super.key});

  @override
  ConsumerState<FavoritesGamesTab> createState() => _FavoritesGamesTabState();
}

class _FavoritesGamesTabState extends ConsumerState<FavoritesGamesTab>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounceTimer;

  /// Track expanded state for date sections
  final Set<String> _collapsedDates = {};

  /// Selected player IDs for filtering - empty means show all
  final Set<String> _selectedPlayerIds = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _loadMoreDays() {
    HapticFeedback.mediumImpact();
    final state = ref.read(favoritesCombinedGamesProvider);
    if (state.isSearching) {
      ref.read(favoritesCombinedGamesProvider.notifier).loadMoreSearchResults();
    } else {
      ref.read(favoritesCombinedGamesProvider.notifier).loadMoreGames();
    }
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      ref.read(favoritesCombinedGamesProvider.notifier).searchGames(value);
    });
  }

  void _clearSearch() {
    HapticFeedback.lightImpact();
    _debounceTimer?.cancel();
    _searchController.clear();
    _searchFocusNode.unfocus();
    ref.read(favoritesCombinedGamesProvider.notifier).clearSearch();
  }

  /// Group games by date
  Map<String, List<GamesTourModel>> _groupGamesByDate(List<GamesTourModel> games) {
    final grouped = <String, List<GamesTourModel>>{};

    for (final game in games) {
      final date = game.lastMoveTime ?? DateTime.now();
      final dateKey = DateFormat('yyyy-MM-dd').format(date);
      grouped.putIfAbsent(dateKey, () => []).add(game);
    }

    // Sort keys by date descending (most recent first)
    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return Map.fromEntries(
      sortedKeys.map((key) => MapEntry(key, grouped[key]!)),
    );
  }

  String _formatDateHeader(String dateKey) {
    final date = DateTime.parse(dateKey);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final gameDate = DateTime(date.year, date.month, date.day);

    if (gameDate == today) {
      return 'Today';
    } else if (gameDate == yesterday) {
      return 'Yesterday';
    } else {
      return DateFormat('EEEE, MMM d').format(date);
    }
  }

  void _toggleDateSection(String dateKey) {
    HapticFeedback.lightImpact();
    setState(() {
      if (_collapsedDates.contains(dateKey)) {
        _collapsedDates.remove(dateKey);
      } else {
        _collapsedDates.add(dateKey);
      }
    });
  }

  List<GamesTourModel> _filterGames(
    List<GamesTourModel> games,
    List<FavoritePlayer> favorites,
  ) {
    var filtered = games;

    if (_selectedPlayerIds.isNotEmpty) {
      // Get selected favorites
      final selectedFavorites = favorites
          .where((f) => _selectedPlayerIds.contains(f.id))
          .toList();

      // Build FIDE ID set for fast lookup (most reliable matching)
      final selectedFideIds = selectedFavorites
          .where((f) => f.fideId != null && f.fideId!.isNotEmpty)
          .map((f) => f.fideId!)
          .toSet();

      // Build normalized last names for fallback matching
      final selectedLastNames = selectedFavorites
          .map((f) => _extractLastName(f.playerName))
          .where((name) => name.isNotEmpty)
          .toSet();

      filtered = filtered.where((game) {
        final whiteFideId = game.whitePlayer.fideId ?? '';
        final blackFideId = game.blackPlayer.fideId ?? '';

        // First try FIDE ID matching (most reliable)
        if (selectedFideIds.contains(whiteFideId) ||
            selectedFideIds.contains(blackFideId)) {
          return true;
        }

        // Fallback to last name matching
        final whiteLastName = _extractLastName(game.whitePlayer.name);
        final blackLastName = _extractLastName(game.blackPlayer.name);

        return selectedLastNames.contains(whiteLastName) ||
            selectedLastNames.contains(blackLastName);
      }).toList();
    }

    return filtered;
  }

  /// Extract and normalize last name from various name formats
  /// Handles: "Carlsen, Magnus", "Magnus Carlsen", "Carlsen, M."
  String _extractLastName(String fullName) {
    final normalized = fullName.toLowerCase().trim();

    // Handle "Last, First" format
    if (normalized.contains(',')) {
      final parts = normalized.split(',');
      return parts[0].trim();
    }

    // Handle "First Last" format - take last word
    final parts = normalized.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isNotEmpty) {
      return parts.last;
    }

    return normalized;
  }

  void _togglePlayerFilter(String playerId) {
    HapticFeedback.lightImpact();
    setState(() {
      if (_selectedPlayerIds.contains(playerId)) {
        _selectedPlayerIds.remove(playerId);
      } else {
        _selectedPlayerIds.add(playerId);
      }
    });
  }

  void _clearAllFilters() {
    HapticFeedback.mediumImpact();
    setState(() {
      _selectedPlayerIds.clear();
    });
  }

  String? _extractFederation(FavoritePlayer player) {
    final metadata = player.metadata;
    if (metadata.containsKey('federation')) {
      return metadata['federation']?.toString();
    }
    if (metadata.containsKey('fed')) {
      return metadata['fed']?.toString();
    }
    if (metadata.containsKey('country')) {
      return metadata['country']?.toString();
    }
    if (metadata.containsKey('countryCode')) {
      return metadata['countryCode']?.toString();
    }
    return null;
  }

  String _getDisplayName(String fullName) {
    final parts = fullName.split(',');
    if (parts.length > 1) {
      return parts[0].trim();
    }
    final words = fullName.trim().split(' ');
    if (words.length > 1) {
      return words.last;
    }
    return fullName.length > 12 ? '${fullName.substring(0, 10)}...' : fullName;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final state = ref.watch(favoritesCombinedGamesProvider);
    // Watch the notifier provider for optimistic updates when favorites change
    final favoritesState = ref.watch(favoritePlayersNotifierProvider);
    final playerModels = favoritesState.valueOrNull?.players ?? [];

    // Convert PlayerStandingModel to FavoritePlayer for chip display
    final now = DateTime.now();
    final favorites = playerModels.map((p) => FavoritePlayer(
      id: p.fideId?.toString() ?? p.name,
      userId: '', // Not needed for display
      playerName: p.name,
      fideId: p.fideId?.toString(),
      metadata: {'countryCode': p.countryCode, 'federation': p.countryCode},
      createdAt: now,
      updatedAt: now,
    )).toList();

    // Refresh games when favorites list changes
    ref.listen(favoritePlayersNotifierProvider, (prev, next) {
      final prevCount = prev?.valueOrNull?.players.length ?? 0;
      final nextCount = next.valueOrNull?.players.length ?? 0;
      if (prevCount != nextCount) {
        // Favorites changed, refresh games
        Future.microtask(() {
          ref.read(favoritesCombinedGamesProvider.notifier).refreshGames();
        });
      }
    });

    return RefreshIndicator(
      onRefresh: () async {
        HapticFeedbackService.medium();
        await ref.read(favoritesCombinedGamesProvider.notifier).refreshGames();
      },
      color: kWhiteColor,
      backgroundColor: kBlack2Color,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          // Search bar
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
              child: _buildSearchBar(state),
            ),
          ),

          // Filter chips (only show when not searching)
          if (favorites.length > 1 && !state.isSearching)
            SliverToBoxAdapter(
              child: _buildFilterChips(favorites),
            ),

          // Content
          _buildContentSliver(state, favorites),

          // Bottom padding
          SliverToBoxAdapter(child: SizedBox(height: 24.h)),
        ],
      ),
    );
  }

  Widget _buildSearchBar(FavoritesCombinedGamesState state) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF09090B),
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(color: const Color(0xFF27272A)),
      ),
      child: Row(
        children: [
          SizedBox(width: 12.w),
          Icon(
            Icons.search,
            size: 20.sp,
            color: const Color(0xFFA1A1AA),
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              style: AppTypography.textSmRegular.copyWith(
                color: const Color(0xFFFAFAFA),
              ),
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search games',
                hintStyle: AppTypography.textSmRegular.copyWith(
                  color: const Color(0xFFA1A1AA),
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14.h),
              ),
            ),
          ),
          if (_searchController.text.isNotEmpty || state.isSearching) ...[
            GestureDetector(
              onTap: _clearSearch,
              child: Icon(
                Icons.close,
                size: 20.sp,
                color: const Color(0xFFA1A1AA),
              ),
            ),
            SizedBox(width: 8.w),
          ],
          SizedBox(width: 8.w),
        ],
      ),
    );
  }

  Widget _buildFilterChips(List<FavoritePlayer> favorites) {
    final hasSelection = _selectedPlayerIds.isNotEmpty;

    return SizedBox(
      height: 48.h,
      child: ShaderMask(
        shaderCallback: (Rect bounds) {
          return LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Colors.transparent,
              Colors.white,
              Colors.white,
              Colors.transparent,
            ],
            stops: const [0.0, 0.03, 0.97, 1.0],
          ).createShader(bounds);
        },
        blendMode: BlendMode.dstIn,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 6.h),
          itemCount: favorites.length + (hasSelection ? 1 : 0),
          itemBuilder: (context, index) {
            if (hasSelection && index == favorites.length) {
              return Padding(
                padding: EdgeInsets.only(right: 8.w),
                child: GestureDetector(
                  onTap: _clearAllFilters,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                    decoration: BoxDecoration(
                      color: const Color(0xFF27272A),
                      borderRadius: BorderRadius.circular(16.br),
                      border: Border.all(
                        color: const Color(0xFF3F3F46),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.close_rounded,
                          size: 14.sp,
                          color: const Color(0xFFA1A1AA),
                        ),
                        SizedBox(width: 4.w),
                        Text(
                          'Clear',
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFFA1A1AA),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final player = favorites[index];
            final isSelected = _selectedPlayerIds.contains(player.id);
            final federation = _extractFederation(player);
            final displayName = _getDisplayName(player.playerName);

            return Padding(
              padding: EdgeInsets.only(right: 8.w),
              child: GestureDetector(
                onTap: () => _togglePlayerFilter(player.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF27272A),
                    borderRadius: BorderRadius.circular(16.br),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF3F3F46),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FederationFlag(
                        federation: federation,
                        width: 16.w,
                        height: 12.h,
                        borderRadius: BorderRadius.circular(2.br),
                      ),
                      SizedBox(width: 6.w),
                      Text(
                        displayName,
                        style: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: kWhiteColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildContentSliver(
    FavoritesCombinedGamesState state,
    List<FavoritePlayer> favorites,
  ) {
    if (state.isLoading && state.games.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildLoadingState(),
      );
    }

    if (state.error != null && state.games.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildErrorState(state.error!),
      );
    }

    if (state.games.isEmpty) {
      if (state.isSearching) {
        return SliverFillRemaining(
          hasScrollBody: false,
          child: _buildNoSearchResultsState(),
        );
      }
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildEmptyState(),
      );
    }

    final filteredGames = state.isSearching
        ? state.games
        : _filterGames(state.games, favorites);

    if (filteredGames.isEmpty && _selectedPlayerIds.isNotEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildNoSearchResultsState(),
      );
    }

    // Group games by date
    final gamesByDate = _groupGamesByDate(filteredGames);

    // Build list items: date headers + games
    final items = <Widget>[];

    for (final entry in gamesByDate.entries) {
      final dateKey = entry.key;
      final dateGames = entry.value;
      final isCollapsed = _collapsedDates.contains(dateKey);

      // Date header
      items.add(
        Padding(
          padding: EdgeInsets.only(bottom: 12.h),
          child: _DateHeader(
            dateLabel: _formatDateHeader(dateKey),
            gameCount: dateGames.length,
            isExpanded: !isCollapsed,
            onToggle: () => _toggleDateSection(dateKey),
          ),
        ),
      );

      // Games under this date (only if expanded)
      if (!isCollapsed) {
        for (int i = 0; i < dateGames.length; i++) {
          final game = dateGames[i];
          final isLast = i == dateGames.length - 1;
          items.add(
            Padding(
              padding: EdgeInsets.only(bottom: isLast ? 16.h : 12.h),
              child: GamebaseSearchGameCard(
                game: game,
                allGames: filteredGames,
                gameIndex: filteredGames.indexOf(game),
                animationIndex: items.length,
                showRound: false,
                onAdd: () => _showAddToFolderSheet(context, game),
              ),
            ),
          );
        }
      }
    }

    // Load More button or end message
    if (state.hasMore && !state.isLoading) {
      items.add(
        Padding(
          padding: EdgeInsets.symmetric(vertical: 16.h),
          child: Center(
            child: GestureDetector(
              onTap: _loadMoreDays,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 14.h),
                decoration: BoxDecoration(
                  color: kDarkGreyColor,
                  borderRadius: BorderRadius.circular(12.br),
                  border: Border.all(color: kWhiteColor.withValues(alpha: 0.15)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_rounded,
                      color: kWhiteColor,
                      size: 22.sp,
                    ),
                    SizedBox(width: 8.w),
                    Text(
                      'Load More Days',
                      style: AppTypography.textSmMedium.copyWith(
                        color: kWhiteColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    } else if (state.isLoading && state.games.isNotEmpty) {
      items.add(
        Padding(
          padding: EdgeInsets.symmetric(vertical: 24.h),
          child: Center(
            child: SizedBox(
              width: 24.w,
              height: 24.h,
              child: const CircularProgressIndicator(
                color: kWhiteColor,
                strokeWidth: 2,
              ),
            ),
          ),
        ),
      );
    } else if (!state.hasMore && state.games.isNotEmpty) {
      items.add(
        Padding(
          padding: EdgeInsets.symmetric(vertical: 16.h),
          child: Center(
            child: Text(
              'No more games',
              style: AppTypography.textXsRegular.copyWith(
                color: const Color(0xFF52525B),
              ),
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => items[index],
          childCount: items.length,
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 48.w,
            height: 48.h,
            child: const CircularProgressIndicator(
              color: kWhiteColor,
              strokeWidth: 2.5,
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            'Loading games...',
            style: AppTypography.textSmRegular.copyWith(
              color: const Color(0xFFA1A1AA),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64.w,
            height: 64.h,
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16.br),
            ),
            child: Icon(
              Icons.error_outline_rounded,
              color: const Color(0xFFEF4444),
              size: 32.ic,
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            'Failed to load games',
            style: AppTypography.textMdMedium.copyWith(color: kWhiteColor),
          ),
          SizedBox(height: 8.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 32.w),
            child: Text(
              error,
              style: AppTypography.textSmRegular.copyWith(
                color: const Color(0xFFA1A1AA),
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(height: 24.h),
          TextButton(
            onPressed: () => ref
                .read(favoritesCombinedGamesProvider.notifier)
                .refreshGames(),
            style: TextButton.styleFrom(
              backgroundColor: kWhiteColor.withValues(alpha: 0.1),
              padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.br),
              ),
            ),
            child: Text(
              'Retry',
              style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80.w,
            height: 80.h,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  kWhiteColor.withValues(alpha: 0.15),
                  kWhiteColor.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(20.br),
            ),
            child: Icon(
              Icons.sports_esports_outlined,
              color: kWhiteColor.withValues(alpha: 0.7),
              size: 40.ic,
            ),
          ),
          SizedBox(height: 20.h),
          Text(
            'No games found',
            style: AppTypography.textMdMedium.copyWith(color: kWhiteColor),
          ),
          SizedBox(height: 8.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 40.w),
            child: Text(
              'Your favorite players haven\'t played any games yet.',
              style: AppTypography.textSmRegular.copyWith(
                color: const Color(0xFFA1A1AA),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).scale(begin: const Offset(0.95, 0.95));
  }

  Widget _buildNoSearchResultsState() {
    return Center(
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
              color: kWhiteColor.withValues(alpha: 0.85),
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            'Try a different filter',
            style: AppTypography.textSmRegular.copyWith(
              color: kWhiteColor.withValues(alpha: 0.55),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  void _showAddToFolderSheet(BuildContext context, GamesTourModel game) {
    showAddToFolderSheet(context: context, game: game);
  }
}

/// Date section header - similar to RoundHeader
class _DateHeader extends StatelessWidget {
  final String dateLabel;
  final int gameCount;
  final bool isExpanded;
  final VoidCallback? onToggle;

  const _DateHeader({
    required this.dateLabel,
    required this.gameCount,
    required this.isExpanded,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(12.br),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 14.sp),
        decoration: BoxDecoration(
          color: kDarkGreyColor,
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(color: kWhiteColor.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 4.w,
              height: 20.h,
              decoration: BoxDecoration(
                color: kPrimaryColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                '$dateLabel • $gameCount ${gameCount == 1 ? 'game' : 'games'}',
                style: TextStyle(
                  color: kWhiteColor,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onToggle != null) ...[
              SizedBox(width: 12.w),
              Icon(
                isExpanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: kWhiteColor.withValues(alpha: 0.5),
                size: 20.sp,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
