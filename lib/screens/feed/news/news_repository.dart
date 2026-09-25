import 'dart:async';
import 'dart:convert';

import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/screens/feed/news/news_content.dart';
import 'package:chessever2/screens/feed/news/news_models.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads published rows from the `news` table, newest first.
typedef NewsRowsFetcher =
    Future<List<Map<String, dynamic>>> Function(int limit);

/// A cached copy of the news list, [storedAt] being when it was fetched.
typedef NewsCacheEntry = ({String value, DateTime storedAt});

/// Where the list is persisted between launches (SQLite in the app).
abstract interface class NewsCacheStore {
  Future<NewsCacheEntry?> read(String key);
  Future<void> write(String key, String value);
}

/// The news list with the moment it was fetched from the network.
@immutable
class FeedNewsSnapshot {
  const FeedNewsSnapshot(this.items, this.fetchedAt);

  final List<FeedNews> items;
  final DateTime fetchedAt;
}

/// Published ChessEver News for the Feed: Supabase for truth, SQLite for an
/// instant first paint, memory so a rebuild hands back the very same item
/// instances (Feed pages keyed on them do not remount on refresh).
class FeedNewsRepository {
  /// [fetchStamps] reads the same rows as [fetchRows] without their bodies,
  /// for the cheap change check; with a custom [fetchRows] and no
  /// [fetchStamps] there is no check and every refresh fetches in full.
  FeedNewsRepository({
    NewsRowsFetcher? fetchRows,
    NewsRowsFetcher? fetchStamps,
    NewsCacheStore? cache,
    DateTime Function()? clock,
  }) : _fetchRows = fetchRows ?? _fetchPublishedNewsRows,
       _fetchStamps =
           fetchStamps ??
           (fetchRows == null ? _fetchPublishedNewsStamps : null),
       _cache = cache ?? const _AppDatabaseNewsCache(),
       _clock = clock ?? DateTime.now;

  /// A list older than this is refreshed from the network.
  static const Duration maxAge = Duration(minutes: 30);

  /// Wait before trying again after a failed fetch.
  static const Duration retryAfter = Duration(minutes: 5);

  /// Longest a list is kept on the strength of the change check alone. Past
  /// it the bodies are fetched again whatever the check says, so an edit to
  /// a body that did not touch `updated_at` still lands.
  static const Duration fullRefreshEvery = Duration(hours: 6);

  static const int limit = 20;
  static const String cacheKey = 'feed_news_v1';

  final NewsRowsFetcher _fetchRows;
  final NewsRowsFetcher? _fetchStamps;
  final NewsCacheStore _cache;
  final DateTime Function() _clock;

  FeedNewsSnapshot? _memory;
  Future<FeedNewsSnapshot?>? _inFlight;

  /// [_newsStampsOf] the rows behind [_memory], and when they were fetched
  /// in full; null until a full fetch in this process.
  String? _stamps;
  DateTime? _fullAt;

  DateTime now() => _clock();

  bool isFresh(FeedNewsSnapshot snapshot) =>
      now().difference(snapshot.fetchedAt) < maxAge;

  /// Time left before [snapshot] turns stale (zero once it has).
  Duration freshFor(FeedNewsSnapshot snapshot) {
    final left = maxAge - now().difference(snapshot.fetchedAt);
    return left.isNegative ? Duration.zero : left;
  }

  /// The last known list (memory, else SQLite), whatever its age.
  Future<FeedNewsSnapshot?> readCached() async {
    final memory = _memory;
    if (memory != null) return memory;
    try {
      final entry = await _cache.read(cacheKey);
      if (entry == null) return null;
      final items = decodeFeedNewsCache(entry.value);
      if (items == null) return null;
      // A refresh may have landed while SQLite was being read.
      return _memory ??= FeedNewsSnapshot(items, entry.storedAt);
    } catch (error) {
      debugPrint('[FeedNews] cache read failed: $error');
      return null;
    }
  }

  /// Fetches the latest list and stores it. Null when the fetch failed; the
  /// previous list stays in place then. A missing `news` table (the test
  /// flavour) is an empty list, not a failure.
  ///
  /// When the list was fetched in full earlier in this process, the bodies
  /// are fetched only if the rows without them changed: an unchanged list
  /// costs one small request and comes back as the very same instance.
  Future<FeedNewsSnapshot?> refresh() =>
      _inFlight ??= _refresh().whenComplete(() => _inFlight = null);

  Future<FeedNewsSnapshot?> _refresh() async {
    final previous = _memory;
    if (previous != null && await _unchanged()) {
      final snapshot = FeedNewsSnapshot(previous.items, now());
      _memory = snapshot;
      // Restamps the SQLite copy so the next launch paints it as fresh.
      unawaited(_write(snapshot.items));
      return snapshot;
    }

    List<Map<String, dynamic>> rows;
    List<FeedNews> items;
    try {
      rows = await _fetchRows(limit);
      items = [
        for (final row in rows)
          if (normalizeNewsRow(row) case final FeedNews item) item,
      ];
    } on PostgrestException catch (error) {
      if (!_isMissingTable(error)) {
        debugPrint('[FeedNews] fetch failed: ${error.code} ${error.message}');
        return null;
      }
      rows = const [];
      items = const [];
    } catch (error) {
      debugPrint('[FeedNews] fetch failed: $error');
      return null;
    }

    final snapshot = FeedNewsSnapshot(_reuse(items), now());
    _memory = snapshot;
    _stamps = _stampsOrNull(rows);
    _fullAt = snapshot.fetchedAt;
    unawaited(_write(snapshot.items));
    return snapshot;
  }

  /// Whether the rows behind [_memory] are still what the server returns,
  /// bodies aside. False whenever that cannot be told cheaply: no stamps on
  /// record, a full fetch due ([fullRefreshEvery]) or the check failing.
  Future<bool> _unchanged() async {
    final fetchStamps = _fetchStamps;
    final stamps = _stamps;
    final fullAt = _fullAt;
    if (fetchStamps == null || stamps == null || fullAt == null) return false;
    if (now().difference(fullAt) >= fullRefreshEvery) return false;
    try {
      return _newsStampsOf(await fetchStamps(limit)) == stamps;
    } on PostgrestException catch (error) {
      if (_isMissingTable(error)) return stamps == _newsStampsOf(const []);
      debugPrint('[FeedNews] change check failed: ${error.code}');
      return false;
    } catch (error) {
      debugPrint('[FeedNews] change check failed: $error');
      return false;
    }
  }

  static String? _stampsOrNull(List<Map<String, dynamic>> rows) {
    try {
      return _newsStampsOf(rows);
    } catch (error) {
      debugPrint('[FeedNews] stamps unavailable: $error');
      return null;
    }
  }

  /// Keeps the previous instances for unchanged items, and the previous list
  /// itself when nothing changed at all.
  List<FeedNews> _reuse(List<FeedNews> fresh) {
    final previous = _memory?.items;
    if (previous == null) return List.unmodifiable(fresh);
    if (listEquals(previous, fresh)) return previous;
    final byId = {for (final item in previous) item.id: item};
    return List.unmodifiable([
      for (final item in fresh)
        if (byId[item.id] case final FeedNews old when old == item)
          old
        else
          item,
    ]);
  }

  Future<void> _write(List<FeedNews> items) async {
    try {
      await _cache.write(cacheKey, encodeFeedNewsCache(items));
    } catch (error) {
      debugPrint('[FeedNews] cache write failed: $error');
    }
  }

  /// Only the missing-relation codes (Postgres `42P01`, PostgREST
  /// `PGRST205`). Never the message: a missing *column* also reads "does not
  /// exist", and schema drift must be logged and retried, not cached as an
  /// empty Feed.
  static bool _isMissingTable(PostgrestException error) =>
      error.code == '42P01' || error.code == 'PGRST205';
}

String encodeFeedNewsCache(List<FeedNews> items) =>
    jsonEncode([for (final item in items) item.toJson()]);

/// Null when [value] is not a cached list at all; invalid items are dropped.
List<FeedNews>? decodeFeedNewsCache(String value) {
  try {
    final decoded = jsonDecode(value);
    if (decoded is! List) return null;
    return List.unmodifiable([
      for (final entry in decoded)
        if (FeedNews.fromJson(entry) case final FeedNews item) item,
    ]);
  } on FormatException {
    return null;
  }
}

/// Every column the Feed reads except the article bodies. The change check
/// fetches just these and compares them with the last full fetch.
const String _newsStampColumns =
    'id,title,summary,source_url,image_url,status,published_at,created_at,'
    'updated_at';

Future<List<Map<String, dynamic>>> _fetchPublishedNewsRows(int limit) =>
    _selectPublishedNews('$_newsStampColumns,content', limit);

Future<List<Map<String, dynamic>>> _fetchPublishedNewsStamps(int limit) =>
    _selectPublishedNews(_newsStampColumns, limit);

/// What [rows] say about the list apart from the bodies: equal for the full
/// rows and the stamp rows of the same, unchanged list.
String _newsStampsOf(List<Map<String, dynamic>> rows) {
  final columns = _newsStampColumns.split(',');
  return jsonEncode([
    for (final row in rows) [for (final column in columns) row[column]],
  ]);
}

Future<List<Map<String, dynamic>>> _selectPublishedNews(
  String columns,
  int limit,
) async {
  final rows = await Supabase.instance.client
      .from('news')
      .select(columns)
      .eq('status', 'published')
      .order('published_at', ascending: false, nullsFirst: false)
      .order('created_at', ascending: false)
      .limit(limit)
      .timeout(const Duration(seconds: 12));
  return List<Map<String, dynamic>>.from(rows);
}

class _AppDatabaseNewsCache implements NewsCacheStore {
  const _AppDatabaseNewsCache();

  @override
  Future<NewsCacheEntry?> read(String key) async {
    final entry = await AppDatabase.instance.getCache(key: key);
    if (entry == null) return null;
    return (value: entry.value, storedAt: entry.cachedAt);
  }

  @override
  Future<void> write(String key, String value) =>
      AppDatabase.instance.setCache(key: key, value: value);
}

final feedNewsRepositoryProvider = Provider<FeedNewsRepository>(
  (ref) => FeedNewsRepository(),
);
