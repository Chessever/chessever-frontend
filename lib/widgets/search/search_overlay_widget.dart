import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/group_event/providers/supabase_combined_search_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/search/enhanced_group_broadcast_local_storage.dart';
import 'package:chessever2/widgets/search/opening_search_suggestion.dart';
import 'package:chessever2/widgets/search/recent_searches_provider.dart';
import 'package:chessever2/widgets/search/search_result_model.dart';
import 'package:chessever2/widgets/search/widgets/search_result_title.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class SearchOverlay extends ConsumerWidget {
  const SearchOverlay({
    super.key,
    required this.onTournamentTap,
    this.onPlayerTap,
    this.onOpeningTap,
  });

  final ValueChanged<GroupEventCardModel> onTournamentTap;
  final ValueChanged<SearchPlayer>? onPlayerTap;
  final ValueChanged<GameEcoFilter>? onOpeningTap;

  double _computeMaxHeight(BuildContext context) {
    final mq = MediaQuery.of(context);
    final available =
        mq.size.height - mq.padding.top - mq.viewInsets.bottom - 120.h;
    final cap = mq.size.height * 0.48;
    return available.clamp(120.h, cap);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final maxHeight = _computeMaxHeight(context);
    final currentQuery = ref.watch(searchQueryProvider).trim();

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surfaceRecessed,
        borderRadius: BorderRadius.circular(16.br),
        border: Border.all(
          color: context.colors.textPrimary.withValues(alpha: 0.1),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16.br),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child:
              currentQuery.isEmpty
                  ? _buildRecentSearches(context, ref, maxHeight)
                  : _buildQueryResults(context, ref, currentQuery, maxHeight),
        ),
      ),
    );
  }

  Widget _buildQueryResults(
    BuildContext context,
    WidgetRef ref,
    String currentQuery,
    double maxHeight,
  ) {
    final debouncedQuery = ref.watch(debouncedSearchQueryProvider).trim();
    final openings = searchOpeningSuggestions(currentQuery);
    final isWaiting = debouncedQuery != currentQuery;

    if (isWaiting || debouncedQuery.isEmpty) {
      if (openings.isEmpty) return _buildLoadingState(maxHeight);
      return _buildSearchResults(
        context,
        query: currentQuery,
        openings: openings,
        isRemoteLoading: true,
      );
    }

    return ref
        .watch(supabaseCombinedSearchProvider(debouncedQuery))
        .when(
          loading:
              () =>
                  openings.isEmpty
                      ? _buildLoadingState(maxHeight)
                      : _buildSearchResults(
                        context,
                        query: currentQuery,
                        openings: openings,
                        isRemoteLoading: true,
                      ),
          error:
              (error, _) =>
                  openings.isEmpty
                      ? _buildErrorState(
                        context,
                        userFacingError(error),
                        maxHeight,
                      )
                      : _buildSearchResults(
                        context,
                        query: currentQuery,
                        openings: openings,
                        remoteMessage: 'Events and players are unavailable',
                      ),
          data: (searchResult) {
            if (searchResult.isEmpty && openings.isEmpty) {
              return _buildEmptyState(context, currentQuery, maxHeight);
            }
            return _buildSearchResults(
              context,
              query: currentQuery,
              openings: openings,
              searchResult: searchResult,
            );
          },
        );
  }

  Widget _buildSearchResults(
    BuildContext context, {
    required String query,
    required List<OpeningSearchSuggestion> openings,
    EnhancedSearchResult? searchResult,
    bool isRemoteLoading = false,
    String? remoteMessage,
  }) {
    final tournaments =
        searchResult?.tournamentResults ?? const <SearchResult>[];
    final players =
        searchResult?.playerResults
            .where((result) => result.player != null)
            .toList(growable: false) ??
        const <SearchResult>[];
    final total = openings.length + tournaments.length + players.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildResultsHeader(context, query, total, isRemoteLoading),
        Flexible(
          child: ListView(
            padding: EdgeInsets.only(bottom: 8.h),
            children: [
              if (openings.isNotEmpty) ...[
                _buildSectionLabel(
                  context,
                  icon: Icons.menu_book_outlined,
                  label: 'Openings',
                  count: openings.length,
                ),
                ...openings.map(
                  (opening) => _OpeningResultRow(
                    suggestion: opening,
                    onTap: () => onOpeningTap?.call(opening.filter),
                  ),
                ),
              ],
              if (tournaments.isNotEmpty) ...[
                _buildSectionLabel(
                  context,
                  icon: Icons.emoji_events_outlined,
                  label: 'Events',
                  count: tournaments.length,
                ),
                ...tournaments.map(
                  (result) => SearchResultTile(
                    result: result,
                    onTap: () => onTournamentTap(result.tournament),
                    isPlayerResult: false,
                    isFullWidth: true,
                  ),
                ),
              ],
              if (players.isNotEmpty) ...[
                _buildSectionLabel(
                  context,
                  icon: Icons.person_outline,
                  label: 'Players',
                  count: players.length,
                ),
                ...players.map(
                  (result) => SearchResultTile(
                    result: result,
                    onTap: () => onPlayerTap?.call(result.player!),
                    isPlayerResult: true,
                    isFullWidth: true,
                  ),
                ),
              ],
              if (remoteMessage != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 8.h),
                  child: Text(
                    remoteMessage,
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 11.sp,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRecentSearches(
    BuildContext context,
    WidgetRef ref,
    double maxHeight,
  ) {
    return ref
        .watch(recentSearchesProvider)
        .when(
          loading:
              () => _buildLoadingState(
                maxHeight,
                label: 'Loading recent searches',
              ),
          error: (_, __) => _buildRecentEmptyState(context, maxHeight),
          data: (entries) {
            if (entries.isEmpty) {
              return _buildRecentEmptyState(context, maxHeight);
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(14.w, 6.h, 6.w, 6.h),
                  child: Row(
                    children: [
                      Icon(
                        Icons.history,
                        size: 18.ic,
                        color: context.colors.textSecondary,
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: Text(
                          'Recent',
                          style: TextStyle(
                            color: context.colors.textPrimary,
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed:
                            () => unawaited(
                              ref.read(recentSearchesProvider.notifier).clear(),
                            ),
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    padding: EdgeInsets.only(bottom: 8.h),
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return _RecentSearchRow(
                        entry: entry,
                        onTap: () => _openRecent(entry),
                        onRemove:
                            () => unawaited(
                              ref
                                  .read(recentSearchesProvider.notifier)
                                  .remove(entry),
                            ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
  }

  void _openRecent(RecentSearchEntry entry) {
    switch (entry.kind) {
      case RecentSearchKind.tournament:
        final tournament = entry.toTournament();
        if (tournament != null) onTournamentTap(tournament);
      case RecentSearchKind.player:
        final player = entry.toPlayer();
        if (player != null) onPlayerTap?.call(player);
      case RecentSearchKind.opening:
        final opening = entry.toOpening();
        if (opening != null) onOpeningTap?.call(opening);
    }
  }

  Widget _buildResultsHeader(
    BuildContext context,
    String query,
    int total,
    bool isLoading,
  ) {
    final suffix = isLoading ? ' · searching events and players' : '';
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: context.colors.textPrimary.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 17.ic, color: context.colors.textSecondary),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              '$total result${total == 1 ? '' : 's'} for “$query”$suffix',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 12.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (isLoading)
            SizedBox.square(
              dimension: 14.ic,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: context.colors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(
    BuildContext context, {
    required IconData icon,
    required String label,
    required int count,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(14.w, 12.h, 14.w, 5.h),
      child: Row(
        children: [
          Icon(icon, size: 16.ic, color: context.colors.textSecondary),
          SizedBox(width: 8.w),
          Text(
            '$label ($count)',
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 12.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(double maxHeight, {String label = 'Searching'}) {
    return SizedBox(
      height: math.min(maxHeight, 152.h),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(height: 12.h),
            Text(
              label,
              style: TextStyle(color: kBoardLightGrey, fontSize: 12.sp),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentEmptyState(BuildContext context, double maxHeight) {
    return SizedBox(
      height: math.min(maxHeight, 130.h),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 20.w),
        child: Row(
          children: [
            Icon(
              Icons.search,
              size: 24.ic,
              color: context.colors.textSecondary,
            ),
            SizedBox(width: 14.w),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Find a chess destination',
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    'Search events, players, opening names, or ECO codes.',
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 12.sp,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(
    BuildContext context,
    String error,
    double maxHeight,
  ) {
    return SizedBox(
      height: math.min(maxHeight, 180.h),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 20.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 32.ic, color: kRedColor),
            SizedBox(height: 10.h),
            Text(
              'Search failed',
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 15.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              error,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(color: kBoardLightGrey, fontSize: 12.sp),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    String query,
    double maxHeight,
  ) {
    return SizedBox(
      height: math.min(maxHeight, 160.h),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off,
              size: 32.ic,
              color: context.colors.textSecondary,
            ),
            SizedBox(height: 10.h),
            Text(
              'No results for “$query”',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              'Try a player, event, opening name, or ECO code.',
              style: TextStyle(color: kBoardLightGrey, fontSize: 12.sp),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpeningResultRow extends StatelessWidget {
  const _OpeningResultRow({required this.suggestion, required this.onTap});

  final OpeningSearchSuggestion suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final code = suggestion.filter.code!;
    return Semantics(
      button: true,
      label: 'Open ${suggestion.title} smart event, ECO $code',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
              child: Row(
                children: [
                  SizedBox(
                    width: 40.w,
                    child: Text(
                      code,
                      style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          suggestion.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.colors.textPrimary,
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          suggestion.subtitle,
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 11.sp,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 19.ic,
                    color: context.colors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentSearchRow extends StatelessWidget {
  const _RecentSearchRow({
    required this.entry,
    required this.onTap,
    required this.onRemove,
  });

  final RecentSearchEntry entry;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  IconData get _icon => switch (entry.kind) {
    RecentSearchKind.tournament => Icons.emoji_events_outlined,
    RecentSearchKind.player => Icons.person_outline,
    RecentSearchKind.opening => Icons.menu_book_outlined,
  };

  String get _semanticKind => switch (entry.kind) {
    RecentSearchKind.tournament => 'event',
    RecentSearchKind.player => 'player',
    RecentSearchKind.opening => 'opening smart event',
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Open recent $_semanticKind ${entry.title}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: EdgeInsets.only(left: 14.w, right: 4.w),
              child: Row(
                children: [
                  Icon(_icon, size: 19.ic, color: context.colors.textSecondary),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.colors.textPrimary,
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (entry.subtitle.isNotEmpty) ...[
                          SizedBox(height: 2.h),
                          Text(
                            entry.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 11.sp,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Tooltip(
                    message: 'Remove from recent searches',
                    child: IconButton(
                      onPressed: onRemove,
                      icon: const Icon(Icons.close),
                      iconSize: 18.ic,
                      color: context.colors.textSecondary,
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
