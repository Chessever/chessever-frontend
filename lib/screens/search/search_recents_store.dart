import 'dart:async';
import 'dart:convert';

import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/collections/collections_data.dart'
    show Collection, CollectionKind;
import 'package:chessever2/screens/feed/news/news_models.dart' show FeedNews;
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart'
    show SmartEventRequest;
import 'package:chessever2/screens/search/search_feeds.dart'
    show searchSmartEventRequests;
import 'package:chessever2/widgets/search/opening_search_suggestion.dart';
import 'package:chessever2/widgets/search/recent_searches_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// The Search tab's own recent searches, as X keeps them: the things the
// reader opened from Search (a row of their faces, logos and plates) and the
// queries they committed (submitted, or typed and then opened a result).
// Kept on the device behind [SearchRecentsStorage], so the same history
// could move to the account later without the page changing. Works for
// guests: nothing here needs a session.

/// At most this many opened things are kept, newest first.
const int searchRecentPickLimit = 12;

/// At most this many committed queries are kept, newest first.
const int searchRecentQueryLimit = 10;

/// What an opened thing is.
enum SearchRecentKind { player, event, opening, smartEvent, collection, news }

/// One thing the reader opened from Search, with what it takes to draw its
/// compact face and to open it again exactly as its card does.
///
/// Players, events and openings carry the [RecentSearchEntry] the app has
/// always stored for them (its identity and its restore rules); collections
/// and news carry the fields their cards read; a built-in smart event is
/// named by its criteria.
@immutable
class SearchRecentPick {
  const SearchRecentPick._({
    required this.kind,
    required this.id,
    required this.name,
    this.data = const {},
  });

  factory SearchRecentPick.player(SearchPlayer player) =>
      SearchRecentPick._fromEntry(RecentSearchEntry.player(player));

  factory SearchRecentPick.event(GroupEventCardModel event) =>
      SearchRecentPick._fromEntry(RecentSearchEntry.tournament(event));

  factory SearchRecentPick.opening(OpeningSearchSelection opening) =>
      SearchRecentPick._fromEntry(RecentSearchEntry.openingSelection(opening));

  /// A recent search kept before the Search tab had its own history.
  factory SearchRecentPick.fromEntry(RecentSearchEntry entry) =>
      SearchRecentPick._fromEntry(entry);

  factory SearchRecentPick._fromEntry(RecentSearchEntry entry) {
    final kind = switch (entry.kind) {
      RecentSearchKind.player => SearchRecentKind.player,
      RecentSearchKind.tournament => SearchRecentKind.event,
      RecentSearchKind.opening => SearchRecentKind.opening,
    };
    return SearchRecentPick._(
      kind: kind,
      // The entry's own identity: a Memorial player stays one player
      // however their row was keyed.
      id: entry.identity,
      name: entry.title,
      data: {'entry': entry.toJson()},
    );
  }

  factory SearchRecentPick.smartEvent(SmartEventRequest request) =>
      SearchRecentPick._(
        kind: SearchRecentKind.smartEvent,
        id: request.criteriaKey,
        name: request.displayName,
        data: {'tierLabel': request.tierLabel},
      );

  factory SearchRecentPick.collection(Collection collection) =>
      SearchRecentPick._(
        kind: SearchRecentKind.collection,
        id: collection.slug,
        name: collection.title,
        data: {
          'id': collection.id,
          'slug': collection.slug,
          'kind': collection.kind.apiValue,
          'title': collection.title,
          'subtitle': ?collection.subtitle,
          'author': ?collection.author,
          'annotator': ?collection.annotator,
          'coverUrl': ?collection.coverUrl,
          'location': ?collection.location,
          'publishedYear': ?collection.publishedYear,
          'gameCount': collection.gameCount,
          'eventCount': collection.eventCount,
          'viewCount': collection.viewCount,
          'starCount': collection.starCount,
          'access': collection.access.name,
        },
      );

  factory SearchRecentPick.news(FeedNews news) => SearchRecentPick._(
    kind: SearchRecentKind.news,
    id: news.key,
    name: news.title,
    data: {'news': news.toJson()},
  );

  /// Null for a damaged or unknown row, which is then skipped.
  static SearchRecentPick? fromJson(Object? json) {
    if (json is! Map) return null;
    final kindName = json['kind']?.toString();
    final kind = SearchRecentKind.values
        .where((value) => value.name == kindName)
        .firstOrNull;
    final id = json['id']?.toString().trim() ?? '';
    final name = json['name']?.toString().trim() ?? '';
    if (kind == null || id.isEmpty || name.isEmpty) return null;
    final raw = json['data'];
    final pick = SearchRecentPick._(
      kind: kind,
      id: id,
      name: name,
      data: raw is Map
          ? raw.map((key, value) => MapEntry(key.toString(), value))
          : const {},
    );
    return pick.isOpenable ? pick : null;
  }

  final SearchRecentKind kind;
  final String id;

  /// The full name, as its card names it.
  final String name;
  final Map<String, dynamic> data;

  /// One per thing: opening it again moves it to the front.
  String get identity => '${kind.name}|$id';

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'id': id,
    'name': name,
    if (data.isNotEmpty) 'data': data,
  };

  /// The player, event or opening entry this pick was made from.
  RecentSearchEntry? get entry {
    final raw = data['entry'];
    if (raw is! Map) return null;
    try {
      return RecentSearchEntry.fromJson(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
    } on FormatException {
      return null;
    }
  }

  SearchPlayer? get player =>
      kind == SearchRecentKind.player ? entry?.toPlayer() : null;

  GroupEventCardModel? get event =>
      kind == SearchRecentKind.event ? entry?.toTournament() : null;

  OpeningSearchSelection? get opening =>
      kind == SearchRecentKind.opening ? entry?.toOpeningSelection() : null;

  /// The built-in smart event this names; null once it is no longer one.
  SmartEventRequest? get smartEvent {
    if (kind != SearchRecentKind.smartEvent) return null;
    for (final request in searchSmartEventRequests) {
      if (request.criteriaKey == id) return request;
    }
    return null;
  }

  Collection? get collection {
    if (kind != SearchRecentKind.collection) return null;
    final slug = data['slug']?.toString().trim() ?? '';
    if (slug.isEmpty) return null;
    final title = data['title']?.toString().trim();
    try {
      return Collection.fromJson({
        ...data,
        'id': data['id']?.toString() ?? slug,
        'slug': slug,
        'kind': CollectionKind.parse(data['kind']).apiValue,
        'title': title == null || title.isEmpty ? name : title,
      });
    } catch (_) {
      return null;
    }
  }

  FeedNews? get news =>
      kind == SearchRecentKind.news ? FeedNews.fromJson(data['news']) : null;

  /// Whether it can still be drawn and opened.
  bool get isOpenable => switch (kind) {
    SearchRecentKind.player => player != null,
    SearchRecentKind.event => event != null,
    SearchRecentKind.opening => opening != null,
    SearchRecentKind.smartEvent => smartEvent != null,
    SearchRecentKind.collection => collection != null,
    SearchRecentKind.news => news != null,
  };
}

/// The Search tab's history: [picks] and [queries], newest first.
@immutable
class SearchRecents {
  const SearchRecents({
    this.picks = const [],
    this.queries = const [],
    this.loaded = false,
  });

  final List<SearchRecentPick> picks;
  final List<String> queries;

  /// The device's copy has been read.
  final bool loaded;

  bool get isEmpty => picks.isEmpty && queries.isEmpty;

  SearchRecents copyWith({
    List<SearchRecentPick>? picks,
    List<String>? queries,
    bool? loaded,
  }) => SearchRecents(
    picks: picks ?? this.picks,
    queries: queries ?? this.queries,
    loaded: loaded ?? this.loaded,
  );

  Map<String, dynamic> toJson() => {
    'v': 1,
    'picks': [for (final pick in picks) pick.toJson()],
    'queries': queries,
  };

  /// What [raw] holds; anything damaged in it is skipped, never fatal.
  static SearchRecents fromJson(Object? raw) {
    if (raw is! Map) return const SearchRecents(loaded: true);
    final rawPicks = raw['picks'];
    final rawQueries = raw['queries'];
    final seen = <String>{};
    final picks = <SearchRecentPick>[
      if (rawPicks is List)
        for (final item in rawPicks)
          if (SearchRecentPick.fromJson(item) case final pick?)
            if (seen.add(pick.identity)) pick,
    ];
    final seenQueries = <String>{};
    final queries = <String>[
      if (rawQueries is List)
        for (final item in rawQueries)
          if (searchRecentQueryText(item?.toString() ?? '') case final query?)
            if (seenQueries.add(query.toLowerCase())) query,
    ];
    return SearchRecents(
      picks: picks.take(searchRecentPickLimit).toList(growable: false),
      queries: queries.take(searchRecentQueryLimit).toList(growable: false),
      loaded: true,
    );
  }
}

/// [raw] as a query worth keeping: trimmed, inner runs of space folded to
/// one; null when nothing is left.
String? searchRecentQueryText(String raw) {
  final text = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  return text.isEmpty ? null : text;
}

/// Where the history is kept. The device by default
/// ([AppDatabaseSearchRecentsStorage]); a server copy would implement the
/// same two calls.
abstract interface class SearchRecentsStorage {
  Future<String?> read();
  Future<void> write(String value);
}

/// The device's key-value store (SQLite), as the app's other local state.
class AppDatabaseSearchRecentsStorage implements SearchRecentsStorage {
  const AppDatabaseSearchRecentsStorage(this.database);

  static const String key = 'search_tab_recents_v1';

  final AppDatabase database;

  @override
  Future<String?> read() => database.getString(key);

  @override
  Future<void> write(String value) => database.setString(key, value);
}

final searchRecentsStorageProvider = Provider<SearchRecentsStorage>(
  (ref) => AppDatabaseSearchRecentsStorage(ref.watch(appDatabaseProvider)),
);

/// The Search tab's history. Read from the device the first time it is
/// asked for; every change is written back at once.
final searchRecentsProvider =
    NotifierProvider<SearchRecentsNotifier, SearchRecents>(
      SearchRecentsNotifier.new,
    );

class SearchRecentsNotifier extends Notifier<SearchRecents> {
  late SearchRecentsStorage _storage;
  Future<void>? _loading;

  /// Clear all was pressed before the device's copy was read: that copy is
  /// dropped when it lands instead of merged back.
  bool _clearedBeforeLoad = false;

  @override
  SearchRecents build() {
    _storage = ref.watch(searchRecentsStorageProvider);
    _loading = null;
    _clearedBeforeLoad = false;
    scheduleMicrotask(() => unawaited(_ensureLoaded()));
    return const SearchRecents();
  }

  Future<void> _ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    SearchRecents read;
    var imported = false;
    try {
      final raw = await _storage.read();
      if (raw == null) {
        read = await _fromEarlierHistory();
        imported = true;
      } else {
        read = SearchRecents.fromJson(jsonDecode(raw));
      }
    } catch (error) {
      debugPrint('[SearchRecents] read failed: $error');
      read = const SearchRecents(loaded: true);
    }
    if (_clearedBeforeLoad) read = const SearchRecents(loaded: true);
    // Anything recorded while the read was out stays in front of it.
    final now = state;
    state = SearchRecents(
      picks: _merge(
        now.picks,
        read.picks,
        (pick) => pick.identity,
      ).take(searchRecentPickLimit).toList(growable: false),
      queries: _merge(
        now.queries,
        read.queries,
        (q) => q.toLowerCase(),
      ).take(searchRecentQueryLimit).toList(growable: false),
      loaded: true,
    );
    // The earlier history is imported once: written straight to the device
    // (not through [_persist], which waits on this load) so the next launch
    // reads the Search tab's own copy.
    if (imported) {
      try {
        await _storage.write(jsonEncode(state.toJson()));
      } catch (error) {
        debugPrint('[SearchRecents] write failed: $error');
      }
    }
  }

  /// The first time: the recent searches the Search tab showed before it had
  /// its own history (shared with the Events page's field), so nobody
  /// arrives to an empty Recent after updating.
  Future<SearchRecents> _fromEarlierHistory() async {
    try {
      final raw = await ref.read(recentSearchStorageProvider).read();
      if (raw == null || raw.trim().isEmpty) {
        return const SearchRecents(loaded: true);
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const SearchRecents(loaded: true);
      final picks = <SearchRecentPick>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          final entry = RecentSearchEntry.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          );
          final pick = SearchRecentPick.fromEntry(entry);
          if (pick.isOpenable) picks.add(pick);
        } on FormatException {
          // A damaged row never hides the rest.
        }
      }
      return SearchRecents(picks: picks, loaded: true);
    } catch (_) {
      return const SearchRecents(loaded: true);
    }
  }

  static List<T> _merge<T>(
    List<T> first,
    List<T> second,
    Object Function(T item) identity,
  ) {
    final seen = <Object>{};
    return [
      for (final item in [...first, ...second])
        if (seen.add(identity(item))) item,
    ];
  }

  /// Puts [pick] in front, once.
  Future<void> recordPick(SearchRecentPick pick) async {
    if (!pick.isOpenable) return;
    _apply(
      state.copyWith(
        picks: [
          pick,
          ...state.picks.where((item) => item.identity != pick.identity),
        ].take(searchRecentPickLimit).toList(growable: false),
      ),
    );
    await _persist();
  }

  /// Puts [raw] in front of the queries, once (case aside).
  Future<void> recordQuery(String raw) async {
    final query = searchRecentQueryText(raw);
    if (query == null) return;
    final key = query.toLowerCase();
    _apply(
      state.copyWith(
        queries: [
          query,
          ...state.queries.where((item) => item.toLowerCase() != key),
        ].take(searchRecentQueryLimit).toList(growable: false),
      ),
    );
    await _persist();
  }

  /// Forgets everything; returns what was there, for Undo ([restore]).
  Future<SearchRecents> clear() async {
    final before = state;
    if (!state.loaded) _clearedBeforeLoad = true;
    _apply(state.copyWith(picks: const [], queries: const []));
    await _persist();
    return before;
  }

  /// Brings back [previous] (a [clear] undone), ahead of anything recorded
  /// since.
  Future<void> restore(SearchRecents previous) async {
    _apply(
      state.copyWith(
        picks: _merge(
          state.picks,
          previous.picks,
          (pick) => pick.identity,
        ).take(searchRecentPickLimit).toList(growable: false),
        queries: _merge(
          state.queries,
          previous.queries,
          (q) => q.toLowerCase(),
        ).take(searchRecentQueryLimit).toList(growable: false),
      ),
    );
    await _persist();
  }

  void _apply(SearchRecents next) => state = next;

  Future<void> _persist() async {
    // The device's copy is read before the first write, so a change made
    // before it landed never writes over the older history.
    await _ensureLoaded();
    try {
      await _storage.write(jsonEncode(state.toJson()));
    } catch (error) {
      // The history still works for this session.
      debugPrint('[SearchRecents] write failed: $error');
    }
  }
}
