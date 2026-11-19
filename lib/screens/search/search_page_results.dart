import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart'
    show DiscoveryAction;
import 'package:chessever2/screens/group_event/providers/supabase_combined_search_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart'
    show SmartEventRequest;
import 'package:chessever2/screens/group_event/widget/player_search_cards.dart';
import 'package:chessever2/screens/search/search_page_landing.dart'
    show searchOpeningSmartEvents;
import 'package:chessever2/screens/search/search_page_sections.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/search/enhanced_group_broadcast_local_storage.dart';
import 'package:chessever2/widgets/search/opening_search_suggestion.dart';
import 'package:chessever2/widgets/search_no_matches.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// How many players lead the results as player cards; the rest follow as
/// Rankings rows.
const int searchResultPlayerCards = 4;

/// Rows of opening cards a search shows before Show all when openings are
/// all it found: six half cards on a phone.
const int searchOpeningRows = 3;

/// Rows of opening cards before Show all beside players or events: one, so
/// the events under them start about one card lower, not a screen lower.
const int searchOpeningRowsBesideOthers = 1;

/// The opening search's score for the weakest match that names the query:
/// the query starts a word of the line's name (a curated alias scores 5
/// less), or better (the name's start, the whole name, the ECO code).
///
/// Under it are the matches that do not: a typo-tolerant one
/// (Nimzovich-*Larsen* for "carlsen", 15,130), the query inside a word
/// (Centre-hol*ding* for "ding", 17,500), the moves (under 12,000). Pinned
/// against the catalog by `test/search_page_results_test.dart`.
const int searchOpeningStrongScore = 17995;

/// Whether [opening] names what was typed rather than resembling it.
bool searchOpeningIsStrong(OpeningSearchSuggestion opening) =>
    opening.score >= searchOpeningStrongScore;

/// The openings a search shows beside its players and events, of its
/// [openings] (one per smart event): with players or events found (or still
/// on their way, [othersPending]), only those that name the query; a player
/// search lists no lookalike lines. Alone, every match, typo-tolerant ones
/// included ("sicillian" still finds the Sicilian).
List<OpeningSearchSuggestion> searchResultOpenings(
  List<OpeningSearchSuggestion> openings, {
  required bool othersFound,
  required bool othersPending,
}) {
  if (!othersFound && !othersPending) return openings;
  return [
    for (final opening in openings)
      if (searchOpeningIsStrong(opening)) opening,
  ];
}

/// What one search shows on the Search tab's page: [query] with its result
/// and every opening that matches it, one per smart event.
@immutable
class SearchPageSnapshot {
  const SearchPageSnapshot({
    required this.query,
    required this.result,
    required this.openings,
    this.remoteLoading = false,
    this.remoteMessage,
  });

  final String query;
  final EnhancedSearchResult result;
  final List<OpeningSearchSuggestion> openings;

  /// Players and events are still on their way (the openings are local).
  final bool remoteLoading;

  /// Why players and events are missing, when the openings stand alone.
  final String? remoteMessage;
}

/// The results of the (debounced) [query] on the Search tab's page.
///
/// While the next search is out, the last one stays on screen as it was,
/// rather than the page emptying into a spinner and back on every query: a
/// first search shows the openings that name the query at once (they are
/// local) with a quiet spinner for the rest.
class SearchPageResultsLoader extends HookConsumerWidget {
  const SearchPageResultsLoader({
    super.key,
    required this.query,
    required this.picks,
    this.onResultsBuild,
  });

  final String query;
  final SearchPicks picks;
  final VoidCallback? onResultsBuild;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final last = useRef<SearchPageSnapshot?>(null);
    final openings = useMemoized(
      () => searchOpeningSmartEvents(searchOpeningSuggestions(query)),
      [query],
    );

    final async = ref.watch(supabaseCombinedSearchProvider(query));

    Widget show(SearchPageSnapshot snapshot) {
      onResultsBuild?.call();
      if (snapshot.result.isEmpty &&
          snapshot.openings.isEmpty &&
          !snapshot.remoteLoading &&
          snapshot.remoteMessage == null) {
        // Nothing matched: the app's one empty-search line, on the page's
        // gutter where the first result would have been.
        return SearchNoMatches(
          key: const ValueKey('search_no_matches'),
          query: snapshot.query,
        );
      }
      return SearchPageResults(snapshot: snapshot, picks: picks);
    }

    return async.when(
      skipLoadingOnReload: true,
      data: (result) {
        final snapshot = SearchPageSnapshot(
          query: query,
          result: result,
          openings: openings,
        );
        last.value = snapshot;
        return show(snapshot);
      },
      loading: () {
        final previous = last.value;
        if (previous != null) return show(previous);
        // While players and events are on their way only the openings that
        // name the query show: a lookalike line shown first would vanish
        // the moment a player landed.
        if (!openings.any(searchOpeningIsStrong)) {
          return const SearchPageSpinner();
        }
        return show(
          SearchPageSnapshot(
            query: query,
            result: EnhancedSearchResult.empty(),
            openings: openings,
            remoteLoading: true,
          ),
        );
      },
      error: (error, _) {
        if (openings.isEmpty) {
          return _SearchFailed(message: userFacingError(error));
        }
        return show(
          SearchPageSnapshot(
            query: query,
            result: EnhancedSearchResult.empty(),
            openings: openings,
            remoteMessage: 'Events and players unavailable',
          ),
        );
      },
    );
  }
}

/// One search's results, each kind under its own heading, in the cards the
/// app draws them in everywhere else: players first (the player cards for
/// the strongest matches, then Rankings rows), then the openings as their
/// smart events ([searchResultOpenings]: one row beside players or events,
/// the rest a Show all away), then the events as the Events list draws
/// them.
class SearchPageResults extends StatelessWidget {
  const SearchPageResults({
    super.key,
    required this.snapshot,
    required this.picks,
  });

  final SearchPageSnapshot snapshot;
  final SearchPicks picks;

  @override
  Widget build(BuildContext context) {
    final players = topSearchedPlayers(snapshot.result, limit: 1 << 20);
    final cards = players.take(searchResultPlayerCards).toList();
    final rows = players.skip(searchResultPlayerCards).toList();
    final events = [
      for (final result in snapshot.result.tournamentResults)
        if (result.tournament.id.trim().isNotEmpty) result.tournament,
    ];
    final besideOthers = players.isNotEmpty || events.isNotEmpty;
    final openings = searchResultOpenings(
      snapshot.openings,
      othersFound: besideOthers,
      othersPending: snapshot.remoteLoading,
    );
    final openPlayer = picks.player;
    final list = CustomScrollView(
      key: const ValueKey('search_results'),
      // The Search tab's controller: a re-tap of the tab takes it to its top.
      primary: true,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        if (players.isNotEmpty)
          SearchSection(
            title: 'Players',
            count: players.length,
            body: SliverMainAxisGroup(
              slivers: [
                SliverToBoxAdapter(
                  child: PlayerSearchCards(
                    players: cards,
                    animateIn: false,
                    bottomPadding: rows.isEmpty ? 0 : searchCardGap,
                    onOpen: openPlayer,
                  ),
                ),
                SliverList.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final player = rows[index];
                    return SearchPlayerRow(
                      key: ValueKey(
                        'search-player-${player.fideId ?? player.id}',
                      ),
                      player: player,
                      onOpen: openPlayer ?? (_) {},
                    );
                  },
                ),
              ],
            ),
          ),
        if (openings.isNotEmpty)
          SearchOpeningResults(
            openings: openings,
            rows: besideOthers || snapshot.remoteLoading
                ? searchOpeningRowsBesideOthers
                : searchOpeningRows,
            onOpening: picks.opening,
          ),
        if (events.isNotEmpty)
          SearchSection(
            title: 'Events',
            count: events.length,
            body: SearchEventCards(
              events: events,
              keyPrefix: 'search-event',
              onOpen: picks.event,
            ),
          ),
        if (players.isEmpty && events.isEmpty && snapshot.remoteLoading)
          const SliverToBoxAdapter(child: SearchPageSpinner(top: 0)),
        if (players.isEmpty && events.isEmpty && snapshot.remoteMessage != null)
          SliverToBoxAdapter(child: _PageNote(text: snapshot.remoteMessage!)),
        SliverToBoxAdapter(child: SizedBox(height: 24.h)),
      ],
    );
    // A new search starts at its top; the last one's scroll is not its own.
    return KeyedSubtree(
      key: ValueKey<String>('search_results_${snapshot.query}'),
      child: list,
    );
  }
}

/// The openings one search matched, as their smart events, under one
/// heading with their true count: [rows] rows of cards, and Show all for the
/// rest, opened in place (Show fewer folds them back). Built a row at a time
/// as it scrolls in, however many there are.
class SearchOpeningResults extends StatefulWidget {
  const SearchOpeningResults({
    super.key,
    required this.openings,
    required this.rows,
    this.onOpening,
  });

  /// One per smart event, best first.
  final List<OpeningSearchSuggestion> openings;
  final int rows;

  /// Opens a card in place of its own open (the tab remembers the pick).
  final ValueChanged<OpeningSearchSelection>? onOpening;

  @override
  State<SearchOpeningResults> createState() => _SearchOpeningResultsState();
}

class _SearchOpeningResultsState extends State<SearchOpeningResults> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final openings = widget.openings;
    final onOpening = widget.onOpening;
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final columns = searchSmartEventColumns(
          constraints.crossAxisExtent - searchPageGutter * 2,
        );
        final folded = openings.length == 1 ? 1 : columns * widget.rows;
        final more = openings.length > folded;
        final shown = more && !_all ? openings.take(folded).toList() : openings;
        return SearchSection(
          title: 'Openings',
          count: openings.length,
          trailing: more
              ? DiscoveryAction(
                  key: const ValueKey('search-openings-more'),
                  label: _all ? 'Show fewer' : 'Show all',
                  semanticsLabel: _all
                      ? 'Show fewer openings'
                      : 'Show all ${openings.length} openings',
                  onTap: () => setState(() => _all = !_all),
                )
              : null,
          body: SearchSmartEventRows(
            columns: columns,
            requests: [
              for (final opening in shown)
                SmartEventRequest.forOpeningSelection(opening.selection),
            ],
            keyFor: (index) => ValueKey('opening-result-${shown[index].id}'),
            onTap: onOpening == null
                ? null
                : (index) =>
                      () => onOpening(shown[index].selection),
          ),
        );
      },
    );
  }
}

/// One quiet spinner, where the first result will land.
class SearchPageSpinner extends StatelessWidget {
  const SearchPageSpinner({super.key, this.top});

  /// From the top of the page; 32 by default.
  final double? top;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.only(top: top ?? 32.h, bottom: 16.h),
        child: SizedBox.square(
          dimension: 20.ic,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: context.colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// A line of quiet text on the page's gutter.
class _PageNote extends StatelessWidget {
  const _PageNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(searchPageGutter, 8.h, searchPageGutter, 0),
      child: Text(
        text,
        style: AppTypography.textSmRegular.copyWith(
          color: context.colors.textSecondary,
        ),
      ),
    );
  }
}

/// The search itself failed and nothing local matched.
class _SearchFailed extends StatelessWidget {
  const _SearchFailed({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          searchPageGutter,
          20.h,
          searchPageGutter,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Search failed',
              style: AppTypography.textMdMedium.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
