import 'dart:async';

import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/favorites/favorites_tab_screen.dart';
import 'package:chessever2/screens/favorites/provider/favorites_mode_provider.dart';
import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart'
    show kDiscoverySmartPresets;
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart'
    show DiscoveryAction;
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart'
    show SmartEventRequest;
import 'package:chessever2/screens/group_event/widget/player_search_cards.dart';
import 'package:chessever2/screens/search/search_landing.dart';
import 'package:chessever2/screens/search/search_page_sections.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/event_card/smart_event_request_card.dart';
import 'package:chessever2/widgets/search/opening_search_suggestion.dart';
import 'package:chessever2/widgets/search/recent_searches_provider.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The Search tab before anything is typed: what is worth opening right now,
/// each in the card the app draws it in everywhere else, so a tap opens it
/// and a long-press offers what it offers there (My Space for events and
/// smart events).
///
/// In order: the recent searches, the events in play, the top of the world
/// ranking, the main openings and the built-in smart events (both as smart
/// events), the strongest events coming up. A section with nothing to list
/// is simply not there; nothing explains itself in prose.
///
/// Each section listens to its own source, so a live event starting does not
/// rebuild the recent searches. The sources are kept warm by the tab
/// (`SearchTabScreen`), so clearing a search brings this back at once.
class SearchPageLanding extends StatelessWidget {
  const SearchPageLanding({super.key, required this.picks});

  final SearchPicks picks;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      key: const ValueKey('search_landing'),
      // The Search tab's controller: a re-tap of the tab takes it to its top.
      primary: true,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        _RecentSection(picks: picks),
        _LiveNowSection(picks: picks),
        _TopPlayersSection(picks: picks),
        _OpeningsSection(picks: picks),
        const _SmartEventsSection(),
        _ComingUpSection(picks: picks),
        SliverToBoxAdapter(child: SizedBox(height: 24.h)),
      ],
    );
  }
}

const Widget _none = SliverToBoxAdapter(child: SizedBox.shrink());

/// Opens a recent search the way its result opens.
Future<void> openSearchRecent(
  RecentSearchEntry entry,
  SearchPicks picks,
) async {
  switch (entry.kind) {
    case RecentSearchKind.tournament:
      final tournament = entry.toTournament();
      if (tournament != null) picks.event(tournament);
    case RecentSearchKind.player:
      final player = await resolveRecentSearchPlayer(entry);
      if (player != null) picks.player?.call(player);
    case RecentSearchKind.opening:
      final opening = entry.toOpeningSelection();
      if (opening != null) picks.opening?.call(opening);
  }
}

/// The recent searches, each in its own kind's card: an event card (its
/// status read again now), the player's card, the opening's smart event.
/// A swipe removes one. Edit, as My Space's Edit, holds the cards still and
/// puts a remove button after each, with Clear all and Done in the heading.
class _RecentSection extends ConsumerStatefulWidget {
  const _RecentSection({required this.picks});

  final SearchPicks picks;

  @override
  ConsumerState<_RecentSection> createState() => _RecentSectionState();
}

class _RecentSectionState extends ConsumerState<_RecentSection> {
  /// Removed and not yet gone from the stored list: a removed card must
  /// leave the tree in the same frame.
  final _gone = <String>{};
  bool _editing = false;

  void _setEditing(bool editing) {
    if (_editing == editing) return;
    HapticFeedbackService.selection();
    setState(() => _editing = editing);
  }

  void _remove(RecentSearchEntry entry, int left) {
    setState(() {
      _gone.add(entry.identity);
      // The last one gone ends Edit: the section is gone with it.
      if (left <= 1) _editing = false;
    });
    unawaited(ref.read(recentSearchesProvider.notifier).remove(entry));
  }

  void _clear() {
    setState(() {
      _gone.clear();
      _editing = false;
    });
    unawaited(ref.read(recentSearchesProvider.notifier).clear());
  }

  Widget _card(RecentSearchEntry entry, List<String> liveIds) {
    void open() => unawaited(openSearchRecent(entry, widget.picks));
    switch (entry.kind) {
      case RecentSearchKind.tournament:
        final saved = entry.toTournament();
        if (saved == null) return const SizedBox.shrink();
        return EventCard(
          tourEventCardModel: searchRecentEvent(saved, liveIds),
          forceCompactLayout: true,
          heroTagSuffix: 'search-recent-${saved.id}',
          favoritePlayersSource: EventFavoritePlayersSource.cacheOnly,
          onTap: open,
        );
      case RecentSearchKind.player:
        final player = entry.toPlayer();
        if (player == null) return const SizedBox.shrink();
        return PlayerSearchCards(
          players: [player],
          animateIn: false,
          bottomPadding: 0,
          onOpen: (_) => open(),
        );
      case RecentSearchKind.opening:
        final selection = entry.toOpeningSelection();
        if (selection == null) return const SizedBox.shrink();
        return SmartEventRequestCard(
          request: SmartEventRequest.forOpeningSelection(selection),
          onTap: widget.picks.opening == null ? null : open,
        );
    }
  }

  Widget _actions() {
    if (!_editing) {
      return DiscoveryAction(
        key: const ValueKey('search-recent-edit'),
        label: 'Edit',
        semanticsLabel: 'Edit recent searches',
        onTap: () => _setEditing(true),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DiscoveryAction(
          key: const ValueKey('search-recent-clear'),
          label: 'Clear all',
          semanticsLabel: 'Clear all recent searches',
          onTap: _clear,
        ),
        SizedBox(width: 16.w),
        DiscoveryAction(
          key: const ValueKey('search-recent-done'),
          label: 'Done',
          semanticsLabel: 'Done editing recent searches',
          onTap: () => _setEditing(false),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final stored =
        ref.watch(recentSearchesProvider).valueOrNull ??
        const <RecentSearchEntry>[];
    _gone.retainWhere((id) => stored.any((e) => e.identity == id));
    final entries = [
      for (final entry in stored)
        if (!_gone.contains(entry.identity)) entry,
    ].take(searchLandingRecentLimit).toList(growable: false);
    if (entries.isEmpty) return _none;
    final key = ref.watch(searchLiveIdsKeyProvider);
    final liveIds = key.isEmpty ? const <String>[] : key.split('\n');
    return SearchSection(
      title: 'Recent searches',
      trailing: _actions(),
      body: SliverList.builder(
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          return Padding(
            key: ValueKey('search-recent-${entry.identity}'),
            padding: EdgeInsets.only(
              bottom: index == entries.length - 1 ? 0 : searchCardGap,
            ),
            child: SearchRecentItem(
              identity: entry.identity,
              title: entry.title,
              editing: _editing,
              onRemove: () => _remove(entry, entries.length),
              child: _card(entry, liveIds),
            ),
          );
        },
      ),
    );
  }
}

/// Live now: an event card per event in play, as the Events list draws it.
/// Events still being looked up arrive into room already held for them
/// ([SearchLiveNow.pending]), so nothing below moves down when they land.
class _LiveNowSection extends ConsumerWidget {
  const _LiveNowSection({required this.picks});

  final SearchPicks picks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(searchLiveNowProvider);
    if (live.isEmpty) return _none;
    return SearchSection(
      title: 'Live now',
      body: SearchEventCards(
        events: live.events,
        pending: live.pending,
        keyPrefix: 'search-live',
        onOpen: picks.event,
      ),
    );
  }
}

/// Top players: the head of the world ranking as the player cards (photo
/// and flag), with the way on to the whole ranking. A failed read leaves no
/// trace; a slow one holds the cards' room with one quiet spinner.
class _TopPlayersSection extends ConsumerWidget {
  const _TopPlayersSection({required this.picks});

  final SearchPicks picks;

  /// Nameless stand-ins, only ever laid out: they ask for no photo.
  static final _placeholders = List<SearchPlayer>.unmodifiable([
    for (var i = 0; i < searchLandingPlayerCount; i++)
      SearchPlayer(
        id: 'search-pending-$i',
        name: '\u00A0',
        tournamentId: '',
        tournamentName: '',
      ),
  ]);

  void _openRankings(BuildContext context) {
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            const FavoritesTabScreen(initialMode: FavoritesScreenMode.players),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(searchTopPlayersProvider);
    final players = state.valueOrNull;
    if (players == null ? state.hasError : players.isEmpty) return _none;
    final Widget cards;
    if (players == null) {
      cards = ExcludeSemantics(
        key: const ValueKey('search-top-players-pending'),
        child: Stack(
          alignment: Alignment.center,
          children: [
            IgnorePointer(
              child: Visibility(
                visible: false,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: PlayerSearchCards(
                  players: _placeholders,
                  animateIn: false,
                  bottomPadding: 0,
                ),
              ),
            ),
            SizedBox.square(
              dimension: 18.ic,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.colors.textSecondary,
              ),
            ),
          ],
        ),
      );
    } else {
      cards = PlayerSearchCards(
        key: const ValueKey('search-top-players'),
        players: players.take(searchLandingPlayerCount).toList(),
        animateIn: false,
        bottomPadding: 0,
        onOpen: picks.player,
      );
    }
    return SearchSection(
      title: 'Top players',
      onTitleTap: () => _openRankings(context),
      trailing: DiscoveryAction(
        label: 'See all',
        arrow: true,
        semanticsLabel: 'See all in Rankings',
        onTap: () => _openRankings(context),
      ),
      body: SliverToBoxAdapter(child: cards),
    );
  }
}

/// The main openings, each as the smart event its search result opens: the
/// games of every current event played in it.
class _OpeningsSection extends ConsumerWidget {
  const _OpeningsSection({required this.picks});

  final SearchPicks picks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(searchLandingOpeningsProvider);
    final resolved = state.valueOrNull;
    if (resolved == null && !state.hasError) {
      // Resolved off the UI isolate, a moment after the page: its room is
      // held, so the sections under it never move down when it lands.
      return SearchSection(
        title: 'Openings',
        body: SliverToBoxAdapter(
          child: ExcludeSemantics(
            key: const ValueKey('search-openings-pending'),
            child: IgnorePointer(
              child: Visibility(
                visible: false,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: SearchSmartEventGrid(
                  requests: List.filled(
                    searchLandingOpeningQueries.length,
                    kDiscoverySmartPresets.first,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    final openings = searchOpeningSmartEvents(
      resolved ?? const <OpeningSearchSuggestion>[],
      limit: searchLandingOpeningQueries.length,
    );
    if (openings.isEmpty) return _none;
    return SearchSection(
      title: 'Openings',
      body: SliverToBoxAdapter(
        child: searchOpeningGrid(openings, picks.opening),
      ),
    );
  }
}

/// One opening per smart event, in [openings]' order, at most [limit] (all
/// of them without one).
///
/// Named lines that share an ECO code are one smart event (its criteria are
/// the code), so the best-ranked line stands for the rest instead of the
/// same card repeating under different names.
List<OpeningSearchSuggestion> searchOpeningSmartEvents(
  List<OpeningSearchSuggestion> openings, {
  int? limit,
}) {
  final seen = <String>{};
  final distinct = [
    for (final opening in openings)
      if (seen.add(opening.filter.code ?? opening.id)) opening,
  ];
  if (limit == null || distinct.length <= limit) return distinct;
  return distinct.take(limit).toList(growable: false);
}

/// [openings] as their smart events, each slot keyed `opening-result-<id>`
/// and opening through [onOpening] (which remembers the pick) when given.
/// Already one per smart event ([searchOpeningSmartEvents]).
Widget searchOpeningGrid(
  List<OpeningSearchSuggestion> openings,
  ValueChanged<OpeningSearchSelection>? onOpening,
) {
  return SearchSmartEventGrid(
    requests: [
      for (final opening in openings)
        SmartEventRequest.forOpeningSelection(opening.selection),
    ],
    keyFor: (index) => ValueKey('opening-result-${openings[index].id}'),
    onTap: onOpening == null
        ? null
        : (index) =>
              () => onOpening(openings[index].selection),
  );
}

/// The built-in smart events (every game averaging GM and IM level), as My
/// Space shows a saved one: star it to hear about its games, long-press to
/// keep it in My Space.
class _SmartEventsSection extends StatelessWidget {
  const _SmartEventsSection();

  @override
  Widget build(BuildContext context) {
    return SearchSection(
      title: 'Smart events',
      body: SliverToBoxAdapter(
        child: SearchSmartEventGrid(
          requests: kDiscoverySmartPresets,
          keyFor: (index) => ValueKey(
            'search-smart-${kDiscoverySmartPresets[index].tierLabel}',
          ),
        ),
      ),
    );
  }
}

/// Coming up: the strongest events not started yet, as the Events list's
/// Upcoming draws them. One that starts leaves at once (it is under Live
/// now), and the next strongest takes its place ([searchComingUpProvider]).
class _ComingUpSection extends ConsumerWidget {
  const _ComingUpSection({required this.picks});

  final SearchPicks picks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upcoming = ref.watch(searchComingUpProvider);
    if (upcoming == null || upcoming.isEmpty) return _none;
    return SearchSection(
      title: 'Coming up',
      body: SearchEventCards(
        events: upcoming,
        keyPrefix: 'search-upcoming',
        onOpen: picks.event,
      ),
    );
  }
}
