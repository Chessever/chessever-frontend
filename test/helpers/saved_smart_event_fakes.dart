import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';

import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_shortcut.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/utils/confirmed_saved_row_edit.dart';
import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final fixtureStamp = DateTime.utc(2026, 1, 1);
const fixtureOwner = 'fixture-owner';

void installSavedEventFixtureCache() {
  const channel = MethodChannel('com.tekartik.sqflite');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'getDatabasesPath':
            return '/fixture-smart-events';
          case 'openDatabase':
            return <String, Object>{'id': 1};
          case 'query':
            final sql = ((call.arguments as Map?)?['sql'] as String?) ?? '';
            return sql.contains('user_version')
                ? [
                    {'user_version': 1},
                  ]
                : <Object>[];
          case 'insert':
          case 'update':
            return 1;
          default:
            return null;
        }
      });
  SqflitePlugin.registerWith();
  addTearDown(() async {
    await AppDatabase.instance.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}

SmartEventRequest fixtureRequest() => SmartEventRequest(
  source: SmartEventSource.forYou,
  tierLabel: 'FM',
  titleSuffix: 'Games',
  minElo: 2300,
  maxElo: 3200,
  caption: 'From your 2300+ filter',
  countSingular: 'event',
  countPlural: 'events',
  events: const [],
  savedAt: fixtureStamp,
);

FavoriteEvent fixtureFavorite(
  SmartEventRequest request, {
  String? eventId,
  String? name,
}) => FavoriteEvent(
  id: eventId ?? request.favoriteEventId,
  userId: fixtureOwner,
  eventId: eventId ?? request.favoriteEventId,
  eventName: name ?? request.displayName,
  metadata: {...request.toFavoriteMetadata(), 'customFlag': 'kept'},
  createdAt: fixtureStamp,
  updatedAt: fixtureStamp,
);

SpaceShortcut fixturePin(SmartEventRequest request) =>
    smartEventSpaceDraft(request).copyWith(
      id: 'local:fixture-card',
      sortIndex: 8,
      openCount: 4,
      lastOpenedAt: fixtureStamp,
      params: {...smartEventSpaceDraft(request).params, 'customFlag': 'kept'},
    );

/// Only the HTTP boundary is replaced. The real Supabase query builder and
/// guarded compare/write/readback helper run, including lost-reply behavior.
class SavedRowsTransport {
  SavedRowsTransport(List<FavoriteEvent> favorites) {
    tables['user_favorite_events'] = [
      for (final f in favorites) f.toSupabase(),
    ];
    client = SupabaseClient(
      'https://saved-fixture.test',
      'fixture-public-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(handle),
    );
  }
  final tables = <String, List<Map<String, dynamic>>>{};
  late final SupabaseClient client;
  final writes = <String>[];
  Future<void> Function(http.Request)? beforeWrite;
  Future<void> Function(http.Request)? afterWrite;

  Future<http.Response> handle(http.Request request) async {
    final table = request.url.pathSegments.last;
    final rows = tables.putIfAbsent(table, () => []);
    final filters = request.url.queryParameters;
    bool matches(Map<String, dynamic> row) => filters.entries.every((e) {
      if (e.key == 'select' || e.key == 'order') return true;
      if (e.value == 'is.null') return row[e.key] == null;
      if (!e.value.startsWith('eq.')) {
        throw StateError('Unsupported fixture filter');
      }
      final raw = e.value.substring(3);
      if (row[e.key] is Map || row[e.key] is List) {
        return const DeepCollectionEquality().equals(
          row[e.key],
          jsonDecode(raw),
        );
      }
      if (e.key.endsWith('_at') && row[e.key] is String) {
        return DateTime.tryParse(row[e.key] as String) ==
            DateTime.tryParse(raw);
      }
      return row[e.key].toString() == raw;
    });
    if (request.method != 'GET') {
      await beforeWrite?.call(request);
      writes.add('${request.method}:$table');
    }
    var result = rows.where(matches).toList();
    if (request.method == 'POST') {
      final inserted = Map<String, dynamic>.from(
        jsonDecode(request.body) as Map,
      );
      final key = table == 'user_favorite_events'
          ? ['event_id']
          : ['kind', 'target_id'];
      if (rows.any(
        (r) =>
            r['user_id'] == inserted['user_id'] &&
            key.every((k) => r[k] == inserted[k]),
      )) {
        return http.Response(
          jsonEncode({'code': '23505', 'message': 'Fixture duplicate'}),
          409,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }
      inserted.putIfAbsent('id', () => 'fixture-row-${rows.length}');
      inserted.putIfAbsent('created_at', () => fixtureStamp.toIso8601String());
      inserted.putIfAbsent('updated_at', () => fixtureStamp.toIso8601String());
      rows.add(inserted);
      result = [inserted];
    } else if (request.method == 'PATCH') {
      final patch = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
      for (final row in result) {
        row.addAll(patch);
      }
    } else if (request.method == 'DELETE') {
      rows.removeWhere(matches);
    }
    if (request.method != 'GET') await afterWrite?.call(request);
    return http.Response(
      jsonEncode(result),
      200,
      request: request,
      headers: {'content-type': 'application/json'},
    );
  }

  List<FavoriteEvent> get favorites => [
    for (final row in tables['user_favorite_events']!)
      FavoriteEvent.fromSupabase(row),
  ];
}

class FixtureFavorites extends FavoriteEventsNotifier {
  FixtureFavorites(this.transport);
  final SavedRowsTransport transport;
  String? actor = fixtureOwner;
  @override
  String? get smartEventEditUserId => actor;
  Completer<void>? ready;
  @override
  Future<List<FavoriteEvent>> build() async {
    await ready?.future;
    return transport.favorites;
  }

  @override
  void beginConfirmedSmartEventEdit() {}
  @override
  void endConfirmedSmartEventEdit() {}
  @override
  Future<List<FavoriteEvent>> readForSmartEventEdit() async {
    await future;
    state = AsyncData(transport.favorites);
    return transport.favorites;
  }

  @override
  Future<void> writeSmartEventEdit(
    FavoriteEvent? before,
    FavoriteEvent? after,
  ) async {
    Map<String, dynamic>? fields(FavoriteEvent? row) => row == null
        ? null
        : {
            'event_id': row.eventId,
            'event_name': row.eventName,
            'metadata': row.metadata,
          };
    await writeConfirmedSavedRow(
      client: transport.client,
      userId: fixtureOwner,
      table: 'user_favorite_events',
      keyColumns: const ['event_id'],
      before: fields(before),
      after: fields(after),
    );
    state = AsyncData(transport.favorites);
  }

  @override
  Future<void> removeFavorite(String eventId, {String? eventName}) =>
      writeSmartEventEdit(
        transport.favorites.firstWhere((r) => r.eventId == eventId),
        null,
      );
}

/// Real local shortcut edit/add/remove/Undo implementation, only initial reads
/// and optional fault injection replaced. There is no real remote account.
class FixturePins extends SpaceShortcutsNotifier {
  FixturePins(this.initial);
  final List<SpaceShortcut> initial;
  Completer<void>? ready;
  Future<void> Function(SpaceShortcut?, SpaceShortcut?)? beforeWrite;
  Future<void> Function(SpaceShortcut?, SpaceShortcut?)? afterWrite;
  @override
  Future<List<SpaceShortcut>> build() async {
    await ready?.future;
    return initial;
  }

  @override
  Future<void> writeSmartEventEdit(
    SpaceShortcut? before,
    SpaceShortcut? after,
  ) async {
    await beforeWrite?.call(before, after);
    await super.writeSmartEventEdit(before, after);
    await afterWrite?.call(before, after);
  }
}
