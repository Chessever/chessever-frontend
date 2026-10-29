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

/// Published news for the Feed, ChessEver's own (`news`) and its partners'
/// (`partner_news`), merged newest first: Supabase for truth, SQLite for an
/// instant first paint, memory so a rebuild hands back the very same item
/// instances (Feed pages keyed on them do not remount on refresh).
class FeedNewsRepository {
  /// [fetchStamps] reads the same rows as [fetchRows] without their bodies,
  /// for the cheap change check; with a custom [fetchRows] and no
  /// [fetchStamps] there is no check and every refresh fetches in full.
  /// [fetchPartnerRows] and [fetchPartnerStamps] are the same for
  /// `partner_news`; a custom [fetchRows] reads no partners unless given
  /// them.
  FeedNewsRepository({
    NewsRowsFetcher? fetchRows,
    NewsRowsFetcher? fetchStamps,
    NewsRowsFetcher? fetchPartnerRows,
    NewsRowsFetcher? fetchPartnerStamps,
    NewsCacheStore? cache,
    DateTime Function()? clock,
  }) : _fetchRows = fetchRows ?? _fetchPublishedNewsRows,
       _fetchStamps =
           fetchStamps ??
           (fetchRows == null ? _fetchPublishedNewsStamps : null),
       _fetchPartnerRows =
           fetchPartnerRows ??
           (fetchRows == null ? _fetchPartnerNewsRows : null),
       _fetchPartnerStamps =
           fetchPartnerStamps ??
           (fetchRows == null && fetchPartnerRows == null
               ? _fetchPartnerNewsStamps
               : null),
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

  /// Newest articles read from each table.
  static const int limit = 20;
  static const String cacheKey = 'feed_news_v1';

  final NewsRowsFetcher _fetchRows;
  final NewsRowsFetcher? _fetchStamps;
  final NewsRowsFetcher? _fetchPartnerRows;
  final NewsRowsFetcher? _fetchPartnerStamps;
  final NewsCacheStore _cache;
  final DateTime Function() _clock;

  FeedNewsSnapshot? _memory;
  Future<FeedNewsSnapshot?>? _inFlight;

  /// [_newsStampsOf] the rows behind [_memory], and when they were fetched
  /// in full; null until a full fetch in this process.
  String? _stamps;
  DateTime? _fullAt;

  /// [_partnerStampsOf] the partner rows behind [_memory]; null until they
  /// were fetched in full, and again after a partner fetch failed.
  String? _partnerStamps;

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
  /// flavour) is an empty list, not a failure. Partner articles are extra:
  /// when only they fail, the ones already shown stay and the refresh still
  /// succeeds.
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

    final partners = await _fetchPartners();
    final partnerItems =
        partners?.items ??
        [...?previous?.items.where((item) => item.publisher.isPartner)];

    final snapshot = FeedNewsSnapshot(
      _reuse(mergeFeedNews(items, partnerItems)),
      now(),
    );
    _memory = snapshot;
    _stamps = _stampsOrNull(rows);
    _partnerStamps = partners?.stamps;
    _fullAt = snapshot.fetchedAt;
    unawaited(_write(snapshot.items));
    return snapshot;
  }

  /// The partners' articles and their stamps; null when they could not be
  /// read. No partner fetcher (a custom [_fetchRows] alone) is no partners.
  Future<({List<FeedNews> items, String? stamps})?> _fetchPartners() async {
    final fetch = _fetchPartnerRows;
    if (fetch == null) return (items: const <FeedNews>[], stamps: null);
    try {
      final rows = await fetch(limit);
      return (
        items: [
          for (final row in rows)
            if (normalizePartnerNewsRow(row) case final FeedNews item) item,
        ],
        stamps: _partnerStampsOrNull(rows),
      );
    } on PostgrestException catch (error) {
      if (_isMissingTable(error)) {
        return (items: const <FeedNews>[], stamps: _partnerStampsOf(const []));
      }
      debugPrint('[FeedNews] partner fetch failed: ${error.code}');
      return null;
    } catch (error) {
      debugPrint('[FeedNews] partner fetch failed: $error');
      return null;
    }
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
      if (_newsStampsOf(await fetchStamps(limit)) != stamps) return false;
    } on PostgrestException catch (error) {
      if (!_isMissingTable(error)) {
        debugPrint('[FeedNews] change check failed: ${error.code}');
        return false;
      }
      if (stamps != _newsStampsOf(const [])) return false;
    } catch (error) {
      debugPrint('[FeedNews] change check failed: $error');
      return false;
    }
    return _partnersUnchanged();
  }

  Future<bool> _partnersUnchanged() async {
    if (_fetchPartnerRows == null) return true;
    final fetchStamps = _fetchPartnerStamps;
    final stamps = _partnerStamps;
    if (fetchStamps == null || stamps == null) return false;
    try {
      return _partnerStampsOf(await fetchStamps(limit)) == stamps;
    } on PostgrestException catch (error) {
      if (_isMissingTable(error)) return stamps == _partnerStampsOf(const []);
      debugPrint('[FeedNews] partner change check failed: ${error.code}');
      return false;
    } catch (error) {
      debugPrint('[FeedNews] partner change check failed: $error');
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

  static String? _partnerStampsOrNull(List<Map<String, dynamic>> rows) {
    try {
      return _partnerStampsOf(rows);
    } catch (error) {
      debugPrint('[FeedNews] partner stamps unavailable: $error');
      return null;
    }
  }

  /// Keeps the previous instances for unchanged items, and the previous list
  /// itself when nothing changed at all.
  List<FeedNews> _reuse(List<FeedNews> fresh) {
    final previous = _memory?.items;
    if (previous == null) return List.unmodifiable(fresh);
    if (listEquals(previous, fresh)) return previous;
    final byKey = {for (final item in previous) item.key: item};
    return List.unmodifiable([
      for (final item in fresh)
        if (byKey[item.key] case final FeedNews old when old == item)
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

/// [own] and [partners] as one list, newest first; on an equal date
/// ChessEver's article leads. Each list keeps its own order otherwise.
List<FeedNews> mergeFeedNews(List<FeedNews> own, List<FeedNews> partners) {
  if (partners.isEmpty) return own;
  final indexed = [
    for (var i = 0; i < own.length; i++) (item: own[i], rank: i),
    for (var i = 0; i < partners.length; i++)
      (item: partners[i], rank: own.length + i),
  ];
  indexed.sort((a, b) {
    final byDate = b.item.publishedAt.compareTo(a.item.publishedAt);
    return byDate != 0 ? byDate : a.rank.compareTo(b.rank);
  });
  return [for (final entry in indexed) entry.item];
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
  int limit, {
  int offset = 0,
}) async {
  final rows = await Supabase.instance.client
      .from('news')
      .select(columns)
      .eq('status', 'published')
      .order('published_at', ascending: false, nullsFirst: false)
      .order('created_at', ascending: false)
      .order('id', ascending: false)
      .range(offset, offset + limit - 1)
      .timeout(const Duration(seconds: 12));
  return List<Map<String, dynamic>>.from(rows);
}

/// Every `partner_news` column the Feed reads except the bodies.
const String _partnerStampColumns =
    'id,source_id,url,title,summary,image_url,published_at,updated_at';

Future<List<Map<String, dynamic>>> _fetchPartnerNewsRows(int limit) =>
    _selectPartnerNews('$_partnerStampColumns,content', limit);

Future<List<Map<String, dynamic>>> _fetchPartnerNewsStamps(int limit) =>
    _selectPartnerNews(_partnerStampColumns, limit);

String _partnerStampsOf(List<Map<String, dynamic>> rows) {
  final columns = _partnerStampColumns.split(',');
  return jsonEncode([
    for (final row in rows) [for (final column in columns) row[column]],
  ]);
}

/// Published articles of the partners this build can brand
/// ([NewsPublisher.partnerSourceIds]); row-level security also hides a
/// disabled partner's.
Future<List<Map<String, dynamic>>> _selectPartnerNews(
  String columns,
  int limit, {
  int offset = 0,
}) async {
  final rows = await Supabase.instance.client
      .from('partner_news')
      .select(columns)
      .eq('status', 'published')
      .inFilter('source_id', NewsPublisher.partnerSourceIds)
      .order('published_at', ascending: false)
      .order('id', ascending: false)
      .range(offset, offset + limit - 1)
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

typedef NewsPageRowsFetcher =
    Future<List<Map<String, dynamic>>> Function(int offset, int limit);

class NewsCatalogPage {
  const NewsCatalogPage({required this.items, required this.hasMore});

  final List<FeedNews> items;
  final bool hasMore;
}

/// A browsing session over both publishers. Each source has its own cursor
/// and unread buffer: fetching equal offsets and simply merging each batch
/// would put old partner stories ahead of newer ChessEver stories on page 2.
/// Failed reads commit no cursors, so retrying cannot skip an article.
class NewsCatalogRepository {
  NewsCatalogRepository({
    NewsPageRowsFetcher? fetchOwn,
    NewsPageRowsFetcher? fetchPartners,
    this.pageSize = 12,
  }) : assert(pageSize > 0),
       _fetchOwn =
           fetchOwn ??
           ((offset, limit) => _selectPublishedNews(
             '$_newsStampColumns,content',
             limit,
             offset: offset,
           )),
       _fetchPartners =
           fetchPartners ??
           ((offset, limit) => _selectPartnerNews(
             '$_partnerStampColumns,content',
             limit,
             offset: offset,
           ));

  final int pageSize;
  final NewsPageRowsFetcher _fetchOwn;
  final NewsPageRowsFetcher _fetchPartners;
  List<FeedNews> _own = [];
  List<FeedNews> _partners = [];
  int _ownOffset = 0;
  int _partnerOffset = 0;
  bool _ownMore = true;
  bool _partnerMore = true;
  final Set<String> _seen = {};
  Future<NewsCatalogPage>? _inFlight;

  Future<NewsCatalogPage> loadNext() =>
      _inFlight ??= _loadNext().whenComplete(() => _inFlight = null);

  Future<NewsCatalogPage> _loadNext() async {
    final own = [..._own];
    final partners = [..._partners];
    var ownOffset = _ownOffset;
    var partnerOffset = _partnerOffset;
    var ownMore = _ownMore;
    var partnerMore = _partnerMore;
    final seen = {..._seen};
    final items = <FeedNews>[];

    while (items.length < pageSize) {
      // Refill both heads before choosing the next article. Bodies already
      // in the buffers are reused when a publisher dominates several pages.
      final batches = await Future.wait([
        if (own.isEmpty && ownMore)
          _fetchOwn(ownOffset, pageSize)
        else
          Future.value(<Map<String, dynamic>>[]),
        if (partners.isEmpty && partnerMore)
          _fetchPartners(partnerOffset, pageSize)
        else
          Future.value(<Map<String, dynamic>>[]),
      ]);
      if (own.isEmpty && ownMore) {
        final rows = batches[0];
        ownOffset += rows.length;
        ownMore = rows.length == pageSize;
        own.addAll([
          for (final row in rows)
            if (normalizeNewsRow(row) case final FeedNews item) item,
        ]);
      }
      if (partners.isEmpty && partnerMore) {
        final rows = batches[1];
        partnerOffset += rows.length;
        partnerMore = rows.length == pageSize;
        partners.addAll([
          for (final row in rows)
            if (normalizePartnerNewsRow(row) case final FeedNews item) item,
        ]);
      }
      // Invalid rows may leave an empty head while more rows still exist.
      if ((own.isEmpty && ownMore) || (partners.isEmpty && partnerMore)) {
        continue;
      }
      if (own.isEmpty && partners.isEmpty) break;
      final useOwn =
          partners.isEmpty ||
          (own.isNotEmpty &&
              !own.first.publishedAt.isBefore(partners.first.publishedAt));
      final next = (useOwn ? own : partners).removeAt(0);
      if (seen.add(next.key)) items.add(next);
    }

    _own = own;
    _partners = partners;
    _ownOffset = ownOffset;
    _partnerOffset = partnerOffset;
    _ownMore = ownMore;
    _partnerMore = partnerMore;
    _seen.addAll(seen);
    return NewsCatalogPage(
      items: List.unmodifiable(items),
      hasMore: own.isNotEmpty || partners.isNotEmpty || ownMore || partnerMore,
    );
  }
}

/// A fresh cursor per News screen (and per pull-to-refresh).
final newsCatalogFactoryProvider = Provider<NewsCatalogRepository Function()>(
  (ref) =>
      () => NewsCatalogRepository(),
);
