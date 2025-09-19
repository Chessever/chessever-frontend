import 'dart:math' as math; // ADD
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/search/enhanced_group_broadcast_local_storage.dart';
import 'package:chessever2/widgets/search/search_result_model.dart';
import 'package:chessever2/widgets/search/widgets/search_result_title.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/group_event/providers/supabase_combined_search_provider.dart';

class SearchOverlay extends ConsumerWidget {
  final String query;
  final Function(GroupEventCardModel) onTournamentTap;
  final Function(SearchPlayer)? onPlayerTap;

  const SearchOverlay({
    super.key,
    required this.query,
    required this.onTournamentTap,
    this.onPlayerTap,
  });

  // Compute a responsive max height that avoids the keyboard
  double _computeMaxHeight(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenH = mq.size.height;
    final keyboard = mq.viewInsets.bottom;
    final topSafe = mq.padding.top;

    // Reserve some space for UI above overlay (search bar, margins)
    final reservedAbove = 120.h;

    final available = screenH - topSafe - keyboard - reservedAbove;
    final cap = screenH * 0.39; // don’t let overlay exceed 40% of screen
    // Ensure reasonable lower bound to avoid collapsing too small
    return available.clamp(120.h, cap);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queries = ref.watch(searchQueryProvider);
    final maxH = _computeMaxHeight(context);

    return Container(
      decoration: BoxDecoration(
        color: kDarkGreyColor,
        borderRadius: BorderRadius.circular(16.br),
        border: Border.all(color: kWhiteColor.withOpacity(0.1)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: ref
              .watch(supabaseCombinedSearchProvider(queries))
              .when(
                loading: () => _buildLoadingState(maxH),
                error: (e, _) => _buildErrorState(e.toString(), maxH),
                data: (searchResult) {
                  if (searchResult.isEmpty) return _buildEmptyState(maxH);
                  return _buildSearchResults(searchResult);
                },
              ),
        ),
      ),
    );
  }

  Widget _buildSearchResults(EnhancedSearchResult searchResult) {
    final hasTournaments = searchResult.tournamentResults.isNotEmpty;
    final hasPlayers = searchResult.playerResults.isNotEmpty;

    // Parent already constrains maxHeight; this column will flex inside it.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeader(searchResult, hasTournaments, hasPlayers),
        Flexible(
          child:
              hasTournaments && hasPlayers
                  ? _buildTwoColumnLayout(searchResult)
                  : _buildSingleColumnLayout(searchResult, hasTournaments),
        ),
      ],
    );
  }

  Widget _buildTwoColumnLayout(EnhancedSearchResult searchResult) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: _buildResultColumn(
            title: 'Events',
            count: searchResult.tournamentResults.length,
            results: searchResult.tournamentResults,
            icon: Icons.emoji_events,
            isPlayerSection: false,
          ),
        ),
        Container(
          width: 1,
          color: kWhiteColor.withOpacity(0.1),
          margin: EdgeInsets.symmetric(vertical: 8.h),
        ),
        Flexible(
          child: _buildResultColumn(
            title: 'Players',
            count: searchResult.playerResults.length,
            results: searchResult.playerResults,
            icon: Icons.person,
            isPlayerSection: true,
          ),
        ),
      ],
    );
  }

  Widget _buildSingleColumnLayout(
    EnhancedSearchResult searchResult,
    bool hasTournaments,
  ) {
    final results =
        hasTournaments
            ? searchResult.tournamentResults
            : searchResult.playerResults;
    final title = hasTournaments ? 'Events' : 'Players';
    final icon = hasTournaments ? Icons.emoji_events : Icons.person;

    return _buildResultColumn(
      title: title,
      count: results.length,
      results: results,
      icon: icon,
      isFullWidth: true,
      isPlayerSection: !hasTournaments,
    );
  }

  Widget _buildResultColumn({
    required String title,
    required int count,
    required List<SearchResult> results,
    required IconData icon,
    bool isFullWidth = false,
    bool isPlayerSection = false,
  }) {
    final filteredResults =
        isPlayerSection
            ? results
                .where((result) => result.player != null)
                .fold<Map<String, SearchResult>>({}, (map, result) {
                  final name = result.player!.name.toLowerCase();
                  if (!map.containsKey(name)) {
                    map[name] = result;
                  }
                  return map;
                })
                .values
                .toList()
            : results;

    if (filteredResults.isEmpty) {
      return Center(
        child: Text(
          'No $title found',
          style: TextStyle(color: Colors.grey[400], fontSize: 14),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.all(12.sp),
          child: Row(
            children: [
              Icon(icon, size: 16.ic, color: kDarkBlue),
              SizedBox(width: 8.w),
              Text(
                '$title (${filteredResults.length})',
                style: TextStyle(
                  color: kWhiteColor,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: filteredResults.length,
            itemBuilder: (context, index) {
              final result = filteredResults[index];
              return SearchResultTile(
                result: result,
                onTap:
                    isPlayerSection
                        ? () => onPlayerTap?.call(result.player!)
                        : () => onTournamentTap(result.tournament),
                isPlayerResult: isPlayerSection,
                isFullWidth: isFullWidth,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(
    EnhancedSearchResult searchResult,
    bool hasTournaments,
    bool hasPlayers,
  ) {
    final totalResults =
        searchResult.tournamentResults.length +
        searchResult.playerResults.length;

    return Container(
      padding: EdgeInsets.all(8.sp),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: kWhiteColor.withOpacity(0.1))),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 16.ic, color: kDarkBlue),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              '$totalResults result${totalResults != 1 ? 's' : ''} for "$query"',
              style: TextStyle(
                color: kWhiteColor,
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(double maxHeight) {
    final h = math.min(maxHeight, 200.h);
    return SizedBox(
      height: h,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
              strokeWidth: 2,
            ),
            SizedBox(height: 16.h),
            Text(
              'Searching...',
              style: TextStyle(color: Colors.white70, fontSize: 14.sp),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error, double maxHeight) {
    final h = math.min(maxHeight, 200.h);
    return SizedBox(
      height: h,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48.ic, color: kRedColor),
            SizedBox(height: 16.h),
            Text(
              'Search failed',
              style: TextStyle(
                color: kWhiteColor,
                fontSize: 16.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              error,
              style: TextStyle(color: kBoardLightGrey, fontSize: 12.sp),
              textAlign: TextAlign.center,
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(double maxHeight) {
    final h = math.min(maxHeight, 200.h);
    return SizedBox(
      height: h,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 48.ic, color: Colors.grey[600]),
            SizedBox(height: 16.h),
            Text(
              'No results found',
              style: TextStyle(
                color: kWhiteColor,
                fontSize: 16.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Try different keywords for "$query"',
              style: TextStyle(color: kBoardLightGrey, fontSize: 14.sp),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
