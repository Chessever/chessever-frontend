import 'package:chessever2/repository/gamebase/collections/collection_search_query.dart';
import 'package:chessever2/screens/collections/collections_data.dart'
    show Collection, collectionsRepositoryProvider;
import 'package:chessever2/screens/feed/news/news_models.dart' show FeedNews;
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart'
    show SmartEventRequest;
import 'package:chessever2/screens/search/search_feeds.dart';
import 'package:chessever2/screens/search/search_landing.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// What a typed search finds in each of the landing's sections beyond the
// players, events and openings the app-wide search returns: the events the
// landing already holds (Coming up), the built-in smart events, the
// collections (the catalog's own search) and the news the landing has read
// (no server search: filtered here, capped).

/// At most this many collections a search lists.
const int searchCollectionResultLimit = 6;

/// At most this many stories a search lists.
const int searchNewsResultLimit = 8;

/// At most this many events a search adds from the landing's own lists.
const int searchLocalEventLimit = 12;

final RegExp _separators = RegExp(r'[\s\-_/.,:;|()]+');

/// The accented Latin letters a name is often written with, and the letter
/// a reader types for each.
const Map<String, String> _plainLetters = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a', //
  'ă': 'a', 'ą': 'a', 'ç': 'c', 'ć': 'c', 'č': 'c', 'ď': 'd', 'è': 'e', //
  'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ė': 'e', 'ę': 'e', 'ě': 'e', //
  'ğ': 'g', 'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i', 'į': 'i', //
  'ı': 'i', 'ľ': 'l', 'ł': 'l', 'ñ': 'n', 'ń': 'n', 'ň': 'n', 'ò': 'o', //
  'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o', 'ő': 'o', //
  'ŕ': 'r', 'ř': 'r', 'ś': 's', 'š': 's', 'ş': 's', 'ť': 't', 'ù': 'u', //
  'ú': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u', 'ů': 'u', 'ű': 'u', 'ų': 'u', //
  'ý': 'y', 'ÿ': 'y', 'ź': 'z', 'ż': 'z', 'ž': 'z',
};

/// [text] folded for matching: lower case, the common Latin accents
/// dropped, so "reti" finds Réti.
String searchFold(String text) {
  final buffer = StringBuffer();
  for (final rune in text.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    buffer.write(_plainLetters[char] ?? char);
  }
  return buffer.toString();
}

/// The words of [query] worth matching on.
List<String> searchQueryWords(String query) => [
  for (final word in searchFold(query).split(_separators))
    if (word.isNotEmpty) word,
];

/// Whether every word of [query] starts a word of [texts] (or, for a word
/// of three letters or more, sits inside one: "dorf" finds Najdorf).
bool searchTextMatches(String query, Iterable<String?> texts) {
  final words = searchQueryWords(query);
  if (words.isEmpty) return false;
  final haystack = [
    for (final text in texts)
      if (text != null && text.trim().isNotEmpty)
        ...searchFold(text).split(_separators).where((w) => w.isNotEmpty),
  ];
  if (haystack.isEmpty) return false;
  return words.every(
    (word) => haystack.any(
      (candidate) =>
          candidate.startsWith(word) ||
          (word.length >= 3 && candidate.contains(word)),
    ),
  );
}

/// Of [events], the ones [query] names (title, location, search terms), each
/// once, in their order, at most [limit].
List<GroupEventCardModel> searchEventMatches(
  String query,
  Iterable<GroupEventCardModel> events, {
  int limit = searchLocalEventLimit,
}) {
  final seen = <String>{};
  final found = <GroupEventCardModel>[];
  for (final event in events) {
    if (found.length >= limit) break;
    if (event.id.trim().isEmpty || !seen.add(event.id)) continue;
    if (searchTextMatches(query, [
      event.title,
      event.location,
      ...event.searchTerms,
    ])) {
      found.add(event);
    }
  }
  return found;
}

/// The events of one search: not started (Coming up, as the landing has
/// it) and the rest (Events), the events in play leading the rest.
@immutable
class SearchEventGroups {
  const SearchEventGroups({this.upcoming = const [], this.events = const []});

  final List<GroupEventCardModel> upcoming;

  /// Every event found that is not coming up, in play first (each reading
  /// LIVE on its card), then the rest in the search's order.
  final List<GroupEventCardModel> events;

  bool get isEmpty => upcoming.isEmpty && events.isEmpty;
}

/// [found] (the app-wide search's events) and the landing's [comingUp]
/// events [query] names, each once: not started under Coming up, the rest
/// under Events. There is no group of events in play: an event in play by
/// [liveIds] (by its own category before the live set is known) leads
/// Events and reads LIVE.
SearchEventGroups searchEventGroups(
  String query, {
  required List<GroupEventCardModel> found,
  Iterable<GroupEventCardModel> comingUp = const [],
  List<String> liveIds = const [],
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final byId = <String, GroupEventCardModel>{};
  for (final event in found) {
    if (event.id.trim().isEmpty) continue;
    byId.putIfAbsent(event.id, () => event);
  }
  for (final event in searchEventMatches(query, comingUp)) {
    byId.putIfAbsent(event.id, () => event);
  }
  final live = <GroupEventCardModel>[];
  final upcoming = <GroupEventCardModel>[];
  final rest = <GroupEventCardModel>[];
  for (final event in byId.values) {
    // The live set is the truth once it is known; before, the event's own
    // category.
    final inPlay = liveIds.isEmpty
        ? event.tourEventCategory == TourEventCategory.live
        : searchEventIsLive(event, liveIds);
    if (inPlay) {
      live.add(liveIds.isEmpty ? event : event.withLiveIds(liveIds));
      continue;
    }
    final start = event.startDate;
    final notStarted = start != null && at.isBefore(start);
    if (notStarted || event.tourEventCategory == TourEventCategory.upcoming) {
      upcoming.add(event);
      continue;
    }
    rest.add(event);
  }
  return SearchEventGroups(upcoming: upcoming, events: [...live, ...rest]);
}

/// The built-in smart events [query] names (its level or time control, its
/// title, its line), in the landing's order.
List<SmartEventRequest> searchSmartEventMatches(
  String query, {
  List<SmartEventRequest>? requests,
}) => [
  for (final request in requests ?? searchSmartEventRequests)
    if (searchTextMatches(query, [
      request.tierLabel,
      request.titleSuffix,
      request.displayName,
      request.caption,
      ...request.formatsAndStates,
      if (request.minElo > 0) '${request.minElo}',
      _levelWords(request.tierLabel),
    ]))
      request,
];

/// The spelled-out names a level goes by, so "grandmaster" finds GM.
String? _levelWords(String tierLabel) {
  final words = <String>[
    for (final part in tierLabel.split(_separators))
      switch (part.toUpperCase()) {
        'GM' => 'grandmaster',
        'IM' => 'international master',
        'FM' => 'fide master',
        'CM' => 'candidate master',
        _ => '',
      },
  ].where((word) => word.isNotEmpty);
  return words.isEmpty ? null : words.join(' ');
}

/// The stories of [news] (what the landing has read) [query] names, title
/// first, then the summary, at most [limit].
List<FeedNews> searchNewsMatches(
  String query,
  Iterable<FeedNews> news, {
  int limit = searchNewsResultLimit,
}) {
  final byTitle = <FeedNews>[];
  final bySummary = <FeedNews>[];
  final seen = <String>{};
  for (final story in news) {
    if (!seen.add(story.key)) continue;
    if (searchTextMatches(query, [story.title])) {
      byTitle.add(story);
    } else if (searchTextMatches(query, [story.summary])) {
      bySummary.add(story);
    }
  }
  return [...byTitle, ...bySummary].take(limit).toList(growable: false);
}

/// The collections [query] finds: the catalog's own search (the books, as
/// the landing lists them), at most [searchCollectionResultLimit]. When the
/// catalog cannot be reached, the books the landing has read, filtered here.
final searchCollectionResultsProvider = FutureProvider.autoDispose
    .family<List<Collection>, String>((ref, query) async {
      final words = query.trim();
      if (words.isEmpty) return const <Collection>[];
      try {
        // No retries: the next keystroke is the retry.
        final page = await ref
            .read(collectionsRepositoryProvider)
            .searchBooks(CollectionSearchQuery(text: words), 0);
        return page.items
            .take(searchCollectionResultLimit)
            .toList(growable: false);
      } catch (error) {
        debugPrint('[Search] collections search failed: $error');
        final loaded = ref.read(searchCollectionsFeedProvider).items;
        return [
          for (final collection in loaded)
            if (searchTextMatches(words, [
              collection.title,
              collection.subtitle,
              collection.author,
              collection.annotator,
              collection.location,
            ]))
              collection,
        ].take(searchCollectionResultLimit).toList(growable: false);
      }
    });
