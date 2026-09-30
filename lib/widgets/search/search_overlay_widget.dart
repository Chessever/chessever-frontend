import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/group_event/providers/supabase_combined_search_provider.dart';
import 'package:chessever2/screens/gamebase/event_view/gamebase_virtual_event_id.dart';
import 'package:chessever2/screens/gamebase/utils/space_position_draft.dart';
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/my_space/actions/space_menu_action.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/navigation/space_shortcut_navigator.dart'
    show resolveSpaceLine;
import 'package:chessever2/screens/player_profile/utils/player_menu_actions.dart';
import 'package:chessever2/screens/player_profile/widgets/lifted_row_menu.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/event_card/event_context_menu.dart'
    show eventSpaceDraft;
import 'package:chessever2/widgets/search/enhanced_group_broadcast_local_storage.dart';
import 'package:chessever2/widgets/search/opening_search_suggestion.dart';
import 'package:chessever2/widgets/search/recent_searches_provider.dart';
import 'package:chessever2/widgets/search/search_result_model.dart';
import 'package:chessever2/widgets/search/widgets/search_result_title.dart';
import 'package:chessever2/widgets/space_shortcut_drafts.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class SearchOverlay extends ConsumerWidget {
  const SearchOverlay({
    super.key,
    required this.query,
    required this.onTournamentTap,
    this.onPlayerTap,
    this.onOpeningTap,
    this.debugOnResultsBuild,
  });

  /// Kept for compatibility with the established search-bar API. Search work
  /// and result labels use the debounced provider value so raw typing never
  /// rebuilds the populated result tree.
  final String query;
  final ValueChanged<GroupEventCardModel> onTournamentTap;
  final ValueChanged<SearchPlayer>? onPlayerTap;
  final ValueChanged<OpeningSearchSelection>? onOpeningTap;

  @visibleForTesting
  final VoidCallback? debugOnResultsBuild;

  /// Deliberately built from values the software keyboard does not move.
  ///
  /// `MediaQuery.of` subscribes to the whole [MediaQueryData], so reading
  /// `viewInsets.bottom` here rebuilt this entire panel — Consumers, ListViews
  /// and all — on every frame of the keyboard slide, at exactly the moment the
  /// panel was also unrolling. `sizeOf`/`paddingOf` subscribe to one aspect
  /// each, and neither ticks while the keyboard animates.
  double _computeMaxHeight(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final available = screenHeight - MediaQuery.paddingOf(context).top - 120.h;
    final cap = screenHeight * 0.39;
    return available.clamp(120.h, cap);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debouncedQuery = ref.watch(debouncedSearchQueryProvider).trim();
    final maxHeight = _computeMaxHeight(context);

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
              debouncedQuery.isEmpty
                  ? _buildBeforeFirstSearch(context, ref, maxHeight)
                  : _buildDebouncedResults(
                    context,
                    ref,
                    debouncedQuery,
                    maxHeight,
                  ),
        ),
      ),
    );
  }

  Widget _buildBeforeFirstSearch(
    BuildContext context,
    WidgetRef ref,
    double maxHeight,
  ) {
    // This small branch is the only part of the overlay that listens to raw
    // keystrokes. Once a debounced query exists, populated results stay fully
    // detached from per-character updates.
    return Consumer(
      builder: (context, ref, _) {
        final rawQuery = ref.watch(searchQueryProvider).trim();
        if (rawQuery.isNotEmpty) return _buildLoadingState(context, maxHeight);
        return _buildRecentSearches(context, ref, maxHeight);
      },
    );
  }

  Widget _buildDebouncedResults(
    BuildContext context,
    WidgetRef ref,
    String debouncedQuery,
    double maxHeight,
  ) {
    // Preserve the established in-between typing state without letting raw
    // keystrokes rebuild the populated result tree underneath it.
    return Consumer(
      builder: (context, ref, _) {
        final rawQuery = ref.watch(searchQueryProvider).trim();
        if (rawQuery.isEmpty) {
          return _buildRecentSearches(context, ref, maxHeight);
        }
        if (rawQuery != debouncedQuery) {
          return _buildLoadingState(context, maxHeight);
        }

        final openings = searchOpeningSuggestions(debouncedQuery);
        return ref
            .watch(supabaseCombinedSearchProvider(debouncedQuery))
            .when(
              loading:
                  () =>
                      openings.isEmpty
                          ? _buildLoadingState(context, maxHeight)
                          : _buildSearchResults(
                            context,
                            query: debouncedQuery,
                            searchResult: EnhancedSearchResult.empty(),
                            openings: openings,
                            remoteLoading: true,
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
                            query: debouncedQuery,
                            searchResult: EnhancedSearchResult.empty(),
                            openings: openings,
                            remoteMessage: 'Events and players unavailable',
                          ),
              data: (searchResult) {
                if (searchResult.isEmpty && openings.isEmpty) {
                  return _buildEmptyState(context, debouncedQuery, maxHeight);
                }
                return _buildSearchResults(
                  context,
                  query: debouncedQuery,
                  searchResult: searchResult,
                  openings: openings,
                );
              },
            );
      },
    );
  }

  Widget _buildSearchResults(
    BuildContext context, {
    required String query,
    required EnhancedSearchResult searchResult,
    required List<OpeningSearchSuggestion> openings,
    bool remoteLoading = false,
    String? remoteMessage,
  }) {
    debugOnResultsBuild?.call();
    final hasTournaments = searchResult.tournamentResults.isNotEmpty;
    final hasPlayers = searchResult.playerResults.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeader(context, query, searchResult, openings.length),
        if (openings.isNotEmpty) _buildOpeningStrip(context, openings),
        if (hasTournaments || hasPlayers)
          Flexible(
            child:
                hasTournaments && hasPlayers
                    ? _buildTwoColumnLayout(context, searchResult)
                    : _buildSingleColumnLayout(
                      context,
                      searchResult,
                      hasTournaments,
                    ),
          )
        else if (remoteLoading)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 12.h),
            child: SizedBox.square(
              dimension: 18.ic,
              child: const CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (remoteMessage != null)
          Padding(
            padding: EdgeInsets.fromLTRB(12.w, 4.h, 12.w, 10.h),
            child: Text(
              remoteMessage,
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 11.sp,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildOpeningStrip(
    BuildContext context,
    List<OpeningSearchSuggestion> openings,
  ) {
    return SizedBox(
      height: math.max(132.h, 136),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(12.sp),
            child: Row(
              children: [
                Icon(
                  Icons.menu_book_outlined,
                  size: 16.ic,
                  color: searchAccentInk(context),
                ),
                SizedBox(width: 8.w),
                Text(
                  'Openings (${openings.length})',
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: 4.w),
              itemCount: openings.length,
              separatorBuilder: (_, __) => SizedBox(width: 8.w),
              itemBuilder: (context, index) {
                final opening = openings[index];
                final showsAll =
                    opening.isAggregate || openings.any(opening.isParentOf);
                return Consumer(
                  builder:
                      (context, ref, _) => _OpeningResultTile(
                        suggestion: opening,
                        showsAll: showsAll,
                        onTap: () => onOpeningTap?.call(opening.selection),
                        onLongPress:
                            (tileContext) => showLibraryContextMenu(
                              context: tileContext,
                              previewBuilder:
                                  (_) => _OpeningResultTile(
                                    suggestion: opening,
                                    showsAll: showsAll,
                                    onTap: () {},
                                  ),
                              onPreviewTap:
                                  () => onOpeningTap?.call(opening.selection),
                              actions: [
                                if (onOpeningTap != null)
                                  LibraryMenuAction(
                                    icon: Icons.menu_book_outlined,
                                    label: 'Open opening',
                                    onSelected:
                                        () => onOpeningTap?.call(
                                          opening.selection,
                                        ),
                                  ),
                                labeledSpaceMenuAction(
                                  context: tileContext,
                                  ref: ref,
                                  draft: openingSearchSpaceDraft(
                                    opening.selection,
                                    name: opening.fullTitle,
                                  ),
                                  addLabel: 'Add opening to My Space',
                                  removeLabel: 'Remove opening from My Space',
                                ),
                              ],
                            ),
                      ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTwoColumnLayout(
    BuildContext context,
    EnhancedSearchResult searchResult,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: _buildResultColumn(
            context: context,
            title: 'Events',
            results: searchResult.tournamentResults,
            icon: Icons.emoji_events,
          ),
        ),
        Container(
          width: 1,
          color: context.colors.divider,
          margin: EdgeInsets.symmetric(vertical: 8.h),
        ),
        Flexible(
          child: _buildResultColumn(
            context: context,
            title: 'Players',
            results: searchResult.playerResults,
            icon: Icons.person,
            isPlayerSection: true,
          ),
        ),
      ],
    );
  }

  Widget _buildSingleColumnLayout(
    BuildContext context,
    EnhancedSearchResult searchResult,
    bool hasTournaments,
  ) {
    return _buildResultColumn(
      context: context,
      title: hasTournaments ? 'Events' : 'Players',
      results:
          hasTournaments
              ? searchResult.tournamentResults
              : searchResult.playerResults,
      icon: hasTournaments ? Icons.emoji_events : Icons.person,
      isFullWidth: true,
      isPlayerSection: !hasTournaments,
    );
  }

  Widget _buildResultColumn({
    required BuildContext context,
    required String title,
    required List<SearchResult> results,
    required IconData icon,
    bool isFullWidth = false,
    bool isPlayerSection = false,
  }) {
    final filteredResults =
        isPlayerSection
            ? results.where((result) => result.player != null).toList()
            : results;

    if (filteredResults.isEmpty) {
      return Center(
        child: Text(
          'No $title found',
          style: TextStyle(
            color: context.colors.textSecondary,
            fontSize: 12.sp,
          ),
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
              Icon(icon, size: 16.ic, color: searchAccentInk(context)),
              SizedBox(width: 8.w),
              Text(
                '$title (${filteredResults.length})',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 12.sp,
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
              final player = isPlayerSection ? result.player : null;
              final VoidCallback onTap =
                  player != null
                      ? () => onPlayerTap?.call(player)
                      : () => onTournamentTap(result.tournament);
              final tile = SearchResultTile(
                result: result,
                onTap: onTap,
                isPlayerResult: isPlayerSection,
                isFullWidth: isFullWidth,
              );
              if (isPlayerSection && player == null) return tile;
              // Long-press lifts the row into the shared focus menu.
              return Consumer(
                builder:
                    (context, ref, child) => LiftedRowMenu(
                      surfaceColor: context.colors.surfaceRecessed,
                      onPreviewTap: onTap,
                      actions:
                          (tileContext) =>
                              player != null
                                  ? _playerActions(tileContext, ref, player)
                                  : _tournamentActions(
                                    tileContext,
                                    ref,
                                    result.tournament,
                                  ),
                      child: child!,
                    ),
                child: tile,
              );
            },
          ),
        ),
      ],
    );
  }

  /// A player result's menu: open, the two My Space rows it always had, and
  /// the profile link.
  List<LibraryMenuAction> _playerActions(
    BuildContext tileContext,
    WidgetRef ref,
    SearchPlayer player, {
    VoidCallback? onOpen,
  }) {
    final open = onPlayerTap;
    return playerMenuActions(
      tileContext,
      ref,
      playerName: player.name,
      fideId: player.fideId,
      title: player.title,
      federation: player.fed,
      rating: player.rating,
      gamebasePlayerId: player.gamebasePlayerId,
      memorialSourceIdentity: player.memorialSourceIdentity,
      memorialRouteId: player.memorialRouteId,
      onOpen: onOpen ?? (open == null ? null : () => open(player)),
    );
  }

  List<LibraryMenuAction> _tournamentActions(
    BuildContext tileContext,
    WidgetRef ref,
    GroupEventCardModel tournament,
  ) {
    final draft = searchEventSpaceDraft(tournament);
    return [
      LibraryMenuAction(
        icon: Icons.open_in_new_rounded,
        label: 'Open event',
        onSelected: () => onTournamentTap(tournament),
      ),
      if (draft != null)
        spaceMenuAction(context: tileContext, ref: ref, draft: draft),
    ];
  }

  /// A recent destination's menu: open it again, pin it, or drop it from the
  /// list (the same removal as the row's close button).
  List<LibraryMenuAction> _recentActions(
    BuildContext tileContext,
    WidgetRef ref,
    RecentSearchEntry entry,
  ) {
    void open() => unawaited(_openRecent(entry));
    final remove = LibraryMenuAction(
      icon: Icons.close_rounded,
      label: 'Remove from recent searches',
      destructive: true,
      onSelected:
          () => unawaited(ref.read(recentSearchesProvider.notifier).remove(entry)),
    );
    switch (entry.kind) {
      case RecentSearchKind.player:
        final player = entry.toPlayer();
        if (player == null) return [remove];
        return [
          // The recent entry resolves its player before opening it.
          ..._playerActions(tileContext, ref, player, onOpen: open),
          remove,
        ];
      case RecentSearchKind.tournament:
        final tournament = entry.toTournament();
        final draft =
            tournament == null ? null : searchEventSpaceDraft(tournament);
        return [
          LibraryMenuAction(
            icon: Icons.open_in_new_rounded,
            label: 'Open event',
            onSelected: open,
          ),
          if (draft != null)
            spaceMenuAction(context: tileContext, ref: ref, draft: draft),
          remove,
        ];
      case RecentSearchKind.opening:
        final selection = entry.toOpeningSelection();
        return [
          LibraryMenuAction(
            icon: Icons.menu_book_outlined,
            label: 'Open opening',
            onSelected: open,
          ),
          if (selection != null && selection.filter.code != null)
            labeledSpaceMenuAction(
              context: tileContext,
              ref: ref,
              draft: openingSearchSpaceDraft(selection, name: entry.title),
              addLabel: 'Add opening to My Space',
              removeLabel: 'Remove opening from My Space',
            ),
          remove,
        ];
    }
  }

  Widget _buildHeader(
    BuildContext context,
    String query,
    EnhancedSearchResult searchResult,
    int openingCount,
  ) {
    final totalResults = searchResult.totalResults + openingCount;
    return Container(
      padding: EdgeInsets.all(8.sp),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: context.colors.textPrimary.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 16.ic, color: searchAccentInk(context)),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              '$totalResults result${totalResults == 1 ? '' : 's'} for "$query"',
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 12.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
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
          // The resting panel has ONE height whatever the storage read is
          // doing. A taller spinner block here changed the panel's height on
          // the same frames it was unrolling, so the reveal and a shrink
          // animation fought each other — the single most visible stutter in
          // the old morph. The read is local and pre-warmed when the bar
          // mounts, so there is nothing worth showing a spinner for anyway.
          loading: () => _buildRecentEmptyState(context, maxHeight),
          error: (_, __) => _buildRecentEmptyState(context, maxHeight),
          data: (entries) {
            if (entries.isEmpty) {
              return _buildRecentEmptyState(context, maxHeight);
            }
            final recentHeight = math.min(
              maxHeight,
              56.0 + math.min(entries.length, 3) * 48.0,
            );
            return SizedBox(
              height: recentHeight,
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(12.w, 4.h, 4.w, 4.h),
                    child: Row(
                      children: [
                        Icon(
                          Icons.history,
                          size: 16.ic,
                          color: searchAccentInk(context),
                        ),
                        SizedBox(width: 8.w),
                        Expanded(
                          child: Text(
                            'Recent searches',
                            style: TextStyle(
                              color: context.colors.textPrimary,
                              fontSize: 12.sp,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 48,
                          child: TextButton(
                            onPressed:
                                () => unawaited(
                                  ref
                                      .read(recentSearchesProvider.notifier)
                                      .clear(),
                                ),
                            child: const Text('Clear'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return LiftedRowMenu(
                          surfaceColor: context.colors.surfaceRecessed,
                          onPreviewTap: () => unawaited(_openRecent(entry)),
                          actions:
                              (tileContext) =>
                                  _recentActions(tileContext, ref, entry),
                          child: _RecentSearchTile(
                            entry: entry,
                            onTap: () => unawaited(_openRecent(entry)),
                            onRemove:
                                () => unawaited(
                                  ref
                                      .read(recentSearchesProvider.notifier)
                                      .remove(entry),
                                ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
  }

  Future<void> _openRecent(RecentSearchEntry entry) async {
    switch (entry.kind) {
      case RecentSearchKind.tournament:
        final tournament = entry.toTournament();
        if (tournament != null) onTournamentTap(tournament);
      case RecentSearchKind.player:
        final player = await resolveRecentSearchPlayer(entry);
        if (player != null) onPlayerTap?.call(player);
      case RecentSearchKind.opening:
        final opening = entry.toOpeningSelection();
        if (opening != null) onOpeningTap?.call(opening);
    }
  }

  Widget _buildLoadingState(
    BuildContext context,
    double maxHeight, {
    String label = 'Searching...',
  }) {
    return SizedBox(
      height: math.min(maxHeight, 200.h),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(strokeWidth: 2),
            SizedBox(height: 16.h),
            Text(
              label,
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 12.sp,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentEmptyState(BuildContext context, double maxHeight) {
    return SizedBox(
      height: math.min(maxHeight, 118.h),
      child: Center(
        child: Text(
          'Search players, tournaments, openings, or ECO codes',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.colors.textSecondary,
            fontSize: 12.sp,
          ),
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
      height: math.min(maxHeight, 200.h),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48.ic,
              // kRedColor in dark; the deeper paper red in light.
              color: context.colors.danger,
            ),
            SizedBox(height: 16.h),
            Text(
              'Search failed',
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 16.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              error,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 12.sp,
              ),
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
      height: math.min(maxHeight, 200.h),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 48.ic,
              color: context.colors.iconSecondary,
            ),
            SizedBox(height: 16.h),
            Text(
              'No results found',
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 16.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Try different keywords for "$query"',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 12.sp,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// My Space shortcut for an opening the search offers, from a live result or
/// a recent search. Both reopen in the opening explorer.
///
/// A named line (one catalog row, e.g. "Najdorf, English Attack") is pinned
/// as the `position` its moves reach, built by the shared
/// [spacePositionDraft]: several named lines share one ECO code, so a code
/// key would make every B90 line (and the board's opening row) read as
/// pinned, and it would reopen on the code's canonical line instead of this
/// one. As a position it dedupes with the explorer and board pins of the
/// same line and reopens on exactly its moves.
///
/// Aggregate rows (a whole code, or a family range like `B90-B99`) keep the
/// bare code label as their key, shared with the board's opening row and the
/// profile repertoire rows. A named line whose moves do not replay falls
/// back to that code pin rather than saving a shallower position.
SpaceShortcut openingSearchSpaceDraft(
  OpeningSearchSelection selection, {
  required String name,
}) {
  if (!selection.isAggregate && !selection.filter.isFamily) {
    final line = resolveSpaceLine(moves: selection.movePath);
    if (line != null && line.ucis.length == selection.movePath.length) {
      final draft = spacePositionDraft(fen: line.fen, ucis: line.ucis);
      if (draft != null) return draft;
    }
  }
  return spaceOpeningDraft(
    targetId: selection.codeLabel,
    name: name,
    extraParams: {
      if (selection.filter.code != null) 'ecoCode': selection.filter.code,
      'hierarchyLabel': selection.hierarchyLabel,
      'movePath': selection.movePath,
      'isAggregate': selection.isAggregate,
    },
  );
}

/// The My Space shortcut for a searched event. Community (calendar) events
/// carry their calendar identity so the opener can route them to the calendar
/// detail. Gamebase-only virtual events have no id the opener can resolve, so
/// they offer no pin.
SpaceShortcut? searchEventSpaceDraft(GroupEventCardModel tournament) {
  if (tournament.id.trim().isEmpty || isVirtualGamebaseId(tournament.id)) {
    return null;
  }
  final draft = eventSpaceDraft(tournament);
  if (tournament.eventSource != EventSource.communityEvent) return draft;
  return draft.copyWith(
    params: {
      ...draft.params,
      'source': 'calendar',
      'calendarEventId': tournament.id,
    },
  );
}

class _OpeningResultTile extends StatelessWidget {
  const _OpeningResultTile({
    required this.suggestion,
    required this.showsAll,
    required this.onTap,
    this.onLongPress,
  });

  final OpeningSearchSuggestion suggestion;
  final bool showsAll;
  final VoidCallback onTap;

  /// Receives the tile's own context so a context menu can anchor to it.
  final void Function(BuildContext tileContext)? onLongPress;

  @override
  Widget build(BuildContext context) {
    final codeLabel = suggestion.codeLabel;
    return Semantics(
      button: true,
      label:
          'Open ${suggestion.fullTitle} smart event, ECO $codeLabel'
          '${showsAll ? ', all child variations' : ''}',
      child: InkWell(
        key: ValueKey('opening-result-${suggestion.id}'),
        onTap: onTap,
        onLongPress: onLongPress == null ? null : () => onLongPress!(context),
        borderRadius: BorderRadius.circular(8.br),
        child: Container(
          width: 230,
          height: 100,
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8.br),
            border: Border.all(
              color: context.colors.textPrimary.withValues(alpha: 0.1),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: math.max(30.h, 34),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: codeLabel,
                        style: TextStyle(
                          color: searchAccentInk(context),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (showsAll)
                        TextSpan(
                          text: '  ★ All',
                          style: TextStyle(
                            color: context.colors.accentText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      TextSpan(
                        text: '  ${suggestion.title}',
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  key: showsAll ? const ValueKey('opening-all-star') : null,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ),
              SizedBox(height: 4.h),
              Expanded(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    suggestion.subtitle,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentSearchTile extends StatelessWidget {
  const _RecentSearchTile({
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

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: EdgeInsets.only(left: 12.w, right: 2.w),
          child: Row(
            children: [
              Icon(_icon, size: 17.ic, color: searchAccentInk(context)),
              SizedBox(width: 10.w),
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
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (entry.subtitle.isNotEmpty)
                      Text(
                        entry.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 10.sp,
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox.square(
                dimension: 48,
                child: IconButton(
                  tooltip: 'Remove from recent searches',
                  onPressed: onRemove,
                  icon: const Icon(Icons.close),
                  iconSize: 17.ic,
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Search's blue accent for icons and the ECO code: [kDarkBlue] on the dark
/// overlay; on paper it is ~2.6:1, so light uses the accent-text teal.
Color searchAccentInk(BuildContext context) =>
    context.isLightTheme ? context.colors.accentText : kDarkBlue;
