import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/screens/feed/models/feed_collection.dart';
import 'package:chessever2/screens/feed/models/feed_short.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

typedef BoardFeedPosition = ({String sessionId, String pageId});
typedef BoardFeedCard = ({
  String id,
  bool isAd,
  int? articleCount,
  FeedShort? short,
  FeedCollection? collection,
});

class BoardFeedUnavailable implements Exception {
  const BoardFeedUnavailable(this.status);

  final int status;
}

class BoardFeedPage {
  BoardFeedPage(Map<String, dynamic> body)
    : position = (
        sessionId: body['sessionId'] as String,
        pageId: body['pageId'] as String,
      ),
      cards = _cards(body),
      nextCursor = body['nextCursor'] as String?;

  final BoardFeedPosition position;
  final List<BoardFeedCard> cards;

  static List<BoardFeedCard> _cards(Map<String, dynamic> body) {
    final items = body['items'];
    if (items is! List) {
      return [
        for (final id in List<String>.from(body['gameIds'] as List))
          (
            id: id,
            isAd: false,
            articleCount: null,
            short: null,
            collection: null,
          ),
      ];
    }
    return [
      for (final item in items)
        if (item case {'type': 'board', 'id': final String id})
          (
            id: id,
            isAd: false,
            articleCount: null,
            short: null,
            collection: null,
          )
        else if (item case {
          'type': 'ad',
          'id': final String id,
        } when id.startsWith('ad:') && id.length > 3)
          (
            id: id,
            isAd: true,
            articleCount: null,
            short: null,
            collection: null,
          )
        else if (item case {
          'type': 'news',
          'id': final String id,
          'articleCount': final int count,
        })
          (
            id: id,
            isAd: false,
            articleCount: count,
            short: null,
            collection: null,
          )
        else if (FeedShort.fromJson(item) case final FeedShort short)
          (
            id: short.id,
            isAd: false,
            articleCount: null,
            short: short,
            collection: null,
          )
        else if (FeedCollection.fromJson(item)
            case final FeedCollection collection)
          (
            id: collection.collection.id,
            isAd: false,
            articleCount: null,
            short: null,
            collection: collection,
          ),
    ];
  }

  final String? nextCursor;
}

/// The internal feed uses the signed-in account's existing Supabase session.
class BoardFeedClient {
  BoardFeedClient(this.base, this.userId, this.auth);

  static const endpoint = String.fromEnvironment(
    'BOARD_FEED_URL',
    defaultValue: String.fromEnvironment('INTERNAL_BOARD_FEED_URL'),
  );
  static final _random = Random.secure();

  final Uri base;
  final String userId;
  final GoTrueClient auth;

  String get _cacheKey => 'internal_board_feed_pending:${base.origin}';
  final _pending = <Map<String, dynamic>>[];
  final _pendingCompletions = <String>{};
  Future<void>? _restored;
  Future<void>? _flushing;
  Timer? _retry;

  bool completedLocally(String id) => _pendingCompletions.contains(id);

  static BoardFeedClient? forCurrentUser() {
    if (endpoint.isEmpty) return null;
    final base = Uri.tryParse(endpoint);
    if (base == null || !base.hasAuthority || base.userInfo.isNotEmpty) {
      return null;
    }
    final loopback = const {'localhost', '127.0.0.1', '10.0.2.2', '::1'};
    if (base.scheme != 'https' &&
        !(base.scheme == 'http' && loopback.contains(base.host))) {
      return null;
    }
    final auth = Supabase.instance.client.auth;
    final session = auth.currentSession;
    if (session == null || session.user.isAnonymous) return null;
    return BoardFeedClient(base, session.user.id, auth);
  }

  String newRequestId() {
    final bytes = List.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<BoardFeedPage> start(
    String requestId, {
    String? country,
    List<String> languages = const [],
  }) async {
    await flush();
    return BoardFeedPage(
      await _request(
        '/v1/feed/sessions',
        body: {
          'requestId': requestId,
          if (country != null) 'country': country,
          'languages': languages,
        },
      ),
    );
  }

  Future<BoardFeedPage> next(String cursor) async {
    await flush();
    return BoardFeedPage(
      await _request('/v1/feed/pages', query: {'cursor': cursor}),
    );
  }

  Future<CollectionCheckpoint?> loadCollectionProgress(String id) async {
    final result = await _request(
      '/v1/feed/collection-progress',
      query: {'collectionId': id},
    );
    return collectionCheckpointFromJson(result['progress']);
  }

  Future<CollectionCheckpoint> saveCollectionProgress(
    String id,
    CollectionCheckpoint checkpoint,
    DateTime observedAt,
  ) async {
    final result = await _request(
      '/v1/feed/collection-progress',
      body: {
        'collectionId': id,
        'gameId': checkpoint.gameId,
        'moveIndex': checkpoint.moveIndex,
        'observedAt': observedAt.toUtc().toIso8601String(),
      },
    );
    final progress = collectionCheckpointFromJson(result['progress']);
    if (progress == null) {
      throw const FormatException('Invalid collection progress');
    }
    return progress;
  }

  void record(BoardFeedPosition position, String id, String kind) {
    if (kind == 'complete' && !_pendingCompletions.add(id)) return;
    _record(position, 'gameId', id, kind);
  }

  void recordNews(BoardFeedPosition position, int id, String kind) {
    _record(position, 'newsId', id.toString(), kind);
  }

  void recordShort(BoardFeedPosition position, String id, String kind) {
    _record(position, 'videoId', id, kind);
  }

  void recordCollectionGame(
    BoardFeedPosition position,
    String collectionId,
    String gameId,
    String kind,
  ) {
    _record(
      position,
      'collectionGameId',
      gameId,
      kind,
      collectionId: collectionId,
    );
  }

  void _record(
    BoardFeedPosition position,
    String type,
    String id,
    String kind, {
    String? collectionId,
  }) {
    _pending.add({
      'eventId': newRequestId(),
      'sessionId': position.sessionId,
      'pageId': position.pageId,
      type: id,
      if (collectionId != null) 'collectionId': collectionId,
      'kind': kind,
    });
    unawaited(flush());
  }

  Future<void> flush() {
    final existing = _flushing;
    if (existing != null) return existing;
    _retry?.cancel();
    final run = _drain();
    _flushing = run;
    unawaited(run.whenComplete(() => _flushing = null));
    return run;
  }

  Future<void> _restore() async {
    try {
      final saved = await AppDatabase.instance.getCache(
        key: _cacheKey,
        userId: userId,
        maxAge: const Duration(days: 7),
      );
      if (saved == null) return;
      final events = List<Map<String, dynamic>>.from(
        jsonDecode(saved.value) as List,
      );
      _pending.insertAll(0, events);
      _pendingCompletions.addAll([
        for (final event in events)
          if (event['kind'] == 'complete') event['gameId'] as String,
      ]);
    } catch (_) {
      // A missing local cache does not prevent loading the feed.
    }
  }

  Future<void> _persist() async {
    try {
      await AppDatabase.instance.setCache(
        key: _cacheKey,
        userId: userId,
        value: jsonEncode(_pending),
      );
    } catch (_) {
      // The in-memory queue can still send feedback.
    }
  }

  Future<void> _drain() async {
    await (_restored ??= _restore());
    while (_pending.isNotEmpty) {
      await _persist();
      if (auth.currentSession?.user.id != userId) return;
      try {
        final batch = _pending.take(25).toList();
        final response = await _request(
          '/v1/feed/events',
          body: {'events': batch},
        );
        final accepted = Set<String>.from(response['accepted'] as List);
        final rejected = Set<String>.from(response['rejected'] as List);
        var removed = false;
        for (final event in batch) {
          final id = event['eventId'];
          if (accepted.contains(id) || rejected.contains(id)) {
            removed = _pending.remove(event) || removed;
            if (rejected.contains(id) && event['kind'] == 'complete') {
              _pendingCompletions.remove(event['gameId']);
            }
          }
        }
        if (!removed) throw const FormatException('No feedback acknowledgment');
        await _persist();
      } catch (error) {
        if (error is! BoardFeedUnavailable || error.status != 404) {
          _retry = Timer(const Duration(seconds: 10), () => unawaited(flush()));
        }
        return;
      }
    }
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    Map<String, String>? query,
    Map<String, Object>? body,
  }) async {
    final session = auth.currentSession;
    if (session?.user.id != userId) throw const BoardFeedUnavailable(401);
    final uri = base.replace(path: path, queryParameters: query);
    final headers = {
      'authorization': 'Bearer ${session!.accessToken}',
      'x-feed-format': 'collection-games',
      if (body != null) 'content-type': 'application/json',
    };
    final request = http.Request(body == null ? 'GET' : 'POST', uri)
      ..followRedirects = false
      ..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);
    final client = http.Client();
    try {
      final response = await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw BoardFeedUnavailable(response.statusCode);
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }
}
