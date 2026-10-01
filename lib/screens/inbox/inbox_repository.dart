import 'dart:async';
import 'dart:convert';

import 'package:chessever2/config/app_environment.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'inbox_message.dart';

abstract interface class InboxSource {
  bool hasSession(String ownerId);
  Future<List<InboxMessage>> fetch(String ownerId);
  Future<DateTime> markRead(String ownerId, String messageId);
}

/// Uses the app's configured Supabase client; never a service key or push SDK.
class SupabaseInboxSource implements InboxSource {
  SupabaseInboxSource(this._client);
  final SupabaseClient Function() _client;
  SupabaseClient get client => _client();
  static const _requestTimeout = Duration(seconds: 15);

  @override
  bool hasSession(String ownerId) {
    try {
      return client.auth.currentSession?.user.id == ownerId;
    } catch (_) {
      return false;
    }
  }

  Session _session(SupabaseClient requestClient, String ownerId) {
    final session = requestClient.auth.currentSession;
    if (!identical(client, requestClient) ||
        session == null ||
        session.user.id != ownerId) {
      throw StateError('Inbox account changed');
    }
    return session;
  }

  Future<void> _freshSession(
    SupabaseClient requestClient,
    String ownerId,
  ) async {
    _session(requestClient, ownerId);
    // Use the same SDK-owned, de-duplicated refresh path as its HTTP client.
    // Never pin currentSession's potentially expired token before this await.
    final session = await requestClient.auth.getSession().timeout(
      _requestTimeout,
    );
    if (session == null || session.user.id != ownerId) {
      throw StateError('Inbox account changed');
    }
    _session(requestClient, ownerId);
  }

  @override
  Future<List<InboxMessage>> fetch(String ownerId) async {
    final requestClient = client;
    final messages = <InboxMessage>[];
    final seen = <String>{};
    InboxMessage? cursor;
    while (true) {
      await _freshSession(requestClient, ownerId);
      final session = _session(requestClient, ownerId);
      final rows = await requestClient
          .rpc(
            'list_editorial_inbox',
            params: {
              'p_before_published_at': cursor?.publishedAt
                  .toUtc()
                  .toIso8601String(),
              'p_before_id': cursor?.id,
              'p_limit': 100,
            },
          )
          // Keep A's credential pinned if the SDK awaits again during dispatch.
          .setHeader('Authorization', 'Bearer ${session.accessToken}')
          .timeout(_requestTimeout);
      _session(requestClient, ownerId);
      final page = (rows as List)
          .map(
            (row) =>
                InboxMessage.fromJson(Map<String, dynamic>.from(row as Map)),
          )
          .toList();
      if (page.length > 100 || page.any((m) => !seen.add(m.id))) {
        throw const FormatException('Invalid Inbox pagination');
      }
      messages.addAll(page);
      if (page.length < 100) break;
      cursor = page.last;
    }
    return messages;
  }

  @override
  Future<DateTime> markRead(String ownerId, String messageId) async {
    final requestClient = client;
    await _freshSession(requestClient, ownerId);
    final session = _session(requestClient, ownerId);
    final result = await requestClient
        .rpc('mark_editorial_inbox_read', params: {'p_message_id': messageId})
        .setHeader('Authorization', 'Bearer ${session.accessToken}')
        .timeout(_requestTimeout);
    _session(requestClient, ownerId);
    // A null/invalid acknowledgement is a failure, not permission to clear dots.
    return DateTime.parse(result as String).toUtc();
  }
}

abstract interface class InboxCache {
  Future<List<InboxMessage>?> load(String ownerId);
  Future<void> save(String ownerId, List<InboxMessage> messages);
}

/// Reuses the existing SQLite cache. Owner is part of both the key and payload;
/// no signed-out/shared fallback namespace exists. Cache never expires offline.
class SqliteInboxCache implements InboxCache {
  SqliteInboxCache(this.database);
  final AppDatabase database;
  static String get _key =>
      '${AppEnvironment.isTest ? 'test' : 'production'}_editorial_inbox_v1';
  final _writes = <String, Future<void>>{};

  @override
  Future<List<InboxMessage>?> load(String ownerId) async {
    await _writes[ownerId];
    final entry = await database.getCache(key: _key, userId: ownerId);
    if (entry == null) return null;
    final json = jsonDecode(entry.value) as Map<String, dynamic>;
    if (json['owner'] != ownerId || json['version'] != 1) {
      throw const FormatException('Invalid Inbox cache owner');
    }
    return (json['messages'] as List)
        .map(
          (row) => InboxMessage.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  @override
  Future<void> save(String ownerId, List<InboxMessage> messages) {
    final payload = jsonEncode({
      'owner': ownerId,
      'version': 1,
      'messages': messages.map((m) => m.toJson()).toList(),
    });
    final previous = _writes[ownerId] ?? Future<void>.value();
    final write = previous.then(
      (_) => database.setCache(key: _key, userId: ownerId, value: payload),
    );
    // The queue tracks completion, not success. Callers still receive failures,
    // but later reads can reach the durable last-good snapshot after a failure.
    _writes[ownerId] = write.catchError((Object _) {});
    return write;
  }
}
