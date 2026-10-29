import 'package:chessever2/main.dart' show routeObserver;
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/repository/supabase/chess_player/chess_player_repository.dart';
import 'package:chessever2/screens/library/providers/gamebase_database_games_provider.dart';
import 'package:chessever2/screens/library/providers/twic_event_aggregates_provider.dart';
import 'package:chessever2/screens/library/twic_contents_screen.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sqflite/sqflite.dart';

// The reported flow on the ChessEver database screen, against the answers
// production gave on 2026-10-29 (before gamebase 1.12.13): search "carlsen",
// read the chips, tap "Serbian Super League 2026". It used to show "No games
// found"; the chip said 2.
void main() {
  testWidgets('search, then tap a tournament chip: it opens with its games', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(393 * 3, 852 * 3);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    _inMemorySqlite();
    final server = _ProductionAnswers();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gamebaseRepositoryProvider.overrideWithValue(
            GamebaseRepository(server.dio, apiKey: 'test'),
          ),
          chessPlayerRepositoryProvider.overrideWithValue(_NoEnrichment()),
          twicDatabaseTotalGamesProvider.overrideWith((ref) async => 0),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          navigatorObservers: [routeObserver],
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return const TwicContentsScreen();
            },
          ),
        ),
      ),
    );
    await _frames(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TwicContentsScreen)),
    );

    // Search "carlsen".
    await tester.enterText(find.byType(EditableText).first, 'carlsen');
    await _frames(tester);
    expect(container.read(librarySearchQueryProvider), 'carlsen');

    // The chips read as counts: most matching games first, whatever order
    // the server answered in, each with its number.
    final chipOrder = [
      '2026 Freestyle Friday October 16',
      'Ganja Open 2026',
      'Serbian Super League 2026',
      'KazChess Masters Almaty 2026',
    ];
    expect(
      container
          .read(twicEventAggregatesPaginatedProvider)
          .events
          .map((e) => e.event),
      chipOrder,
    );
    // First after "All Events" on screen: the one with the most games.
    expect(find.text(chipOrder.first), findsOneWidget);

    final chipRow = find
        .ancestor(
          of: find.text(chipOrder.first),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Serbian Super League 2026'),
      120,
      scrollable: chipRow,
    );
    expect(
      find.descendant(
        of: find
            .ancestor(
              of: find.text('Serbian Super League 2026'),
              matching: find.byType(Row),
            )
            .first,
        matching: find.text('2'),
      ),
      findsOneWidget,
    );

    // Tap the tournament chip.
    await _frames(tester);
    await tester.tap(
      find.text('Serbian Super League 2026'),
      warnIfMissed: true,
    );
    await _frames(tester);

    final games = container.read(gamebaseDatabaseGamesPaginatedProvider);
    expect(
      container.read(twicSelectedEventProvider),
      'Serbian Super League 2026',
    );
    expect(games.games, hasLength(2));
    expect(find.text('No games found'), findsNothing);
    expect(find.textContaining('Atalik'), findsWidgets);
    expect(find.textContaining('Alimpic'), findsWidgets);
    expect(find.textContaining('Gaponenko'), findsNothing);

    // A trailing space is the same search: the chip and its games stay.
    await tester.enterText(find.byType(EditableText).first, 'carlsen ');
    await _frames(tester);
    expect(
      container.read(twicSelectedEventProvider),
      'Serbian Super League 2026',
    );
    expect(
      container.read(gamebaseDatabaseGamesPaginatedProvider).games,
      hasLength(2),
    );

    // Unmount inside the fake clock so no timer outlives the test.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 61));
  });
}

/// Game cards read their swipe-hint flag from SQLite; answer it in memory.
void _inMemorySqlite() {
  const channel = MethodChannel('com.tekartik.sqflite');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'getDatabasesPath':
            return '/twic-chip-tap-flow-test';
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

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Card enrichment reads Supabase, which tests do not start.
class _NoEnrichment implements ChessPlayerRepository {
  @override
  Future<Map<int, ChessPlayer>> getPlayersByFideIds(
    Iterable<int> fideIds,
  ) async => const {};

  @override
  Future<List<ChessPlayer>> searchPlayersByNameWords({
    required String query,
    int limit = 8,
    int offset = 0,
  }) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Production's answers for this flow, trimmed. Anything else is empty.
class _ProductionAnswers {
  late final Dio dio = Dio()
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (r, h) => h.resolve(
          Response(requestOptions: r, statusCode: 200, data: _answer(r)),
        ),
      ),
    );

  Map<String, dynamic> _answer(RequestOptions r) {
    final path = r.path;
    if (path.endsWith('/api/search/events')) return _carlsenChips;
    if (path.endsWith('/api/event') &&
        r.queryParameters['name'] == 'Serbian Super League 2026') {
      return _serbianLeagueView;
    }
    if (path.endsWith('/api/event')) {
      return {'status': 'error', 'error': 'Event not found', 'data': null};
    }
    // GET /api/search: `carlsen event:"Serbian Super League 2026"` found
    // nothing on production; other searches are not under test.
    return {
      'status': 'success',
      'data': {
        'results': const [],
        'metadata': {
          'pageNumber': 1,
          'pageSize': 20,
          'totalCount': 0,
          'totalCountIsEstimate': false,
          'hasMore': false,
        },
      },
    };
  }
}

/// `GET /api/search/events?q=carlsen`, newest first as production sends it.
const _carlsenChips = <String, Object>{
  'status': 'success',
  'data': {
    'events': [
      {
        'id': 'event_a',
        'event': 'KazChess Masters Almaty 2026',
        'gameCount': 1,
        'endDate': '2026-10-26T00:00:00.000Z',
      },
      {
        'id': 'event_b',
        'event': 'Ganja Open 2026',
        'gameCount': 3,
        'endDate': '2026-10-17T00:00:00.000Z',
      },
      {
        'id': 'event_c',
        'event': '2026 Freestyle Friday October 16',
        'gameCount': 6,
        'endDate': '2026-10-16T00:00:00.000Z',
      },
      {
        'id': 'event_d',
        'event': 'Serbian Super League 2026',
        'gameCount': 2,
        'endDate': '2026-10-13T00:00:00.000Z',
      },
    ],
    'metadata': {'pageNumber': 1, 'pageSize': 20, 'hasMore': false},
  },
};

/// `GET /api/event?name=Serbian Super League 2026`, three of its 614 games.
const _serbianLeagueView = <String, Object>{
  'status': 'success',
  'data': <String, Object?>{
    'event': 'Serbian Super League 2026',
    'site':
        'https://lichess.org/broadcast/serbian-super-league-2026-women/round-3/0OH4UhHT/L63dvPSi',
    'truncated': false,
    'games': [
      {
        'id': '1fec7945-7eaa-5dbd-84d5-fb80ae8d4a74',
        'round': '1.15',
        'white': {
          'name': 'Atalik, Suat',
          'fideId': '14401487',
          'title': 'GM',
          'elo': 2371,
          'fed': 'SRB',
        },
        'black': {
          'name': 'Klukin, Kirill',
          'fideId': '24199273',
          'title': 'IM',
          'elo': 2382,
          'fed': 'SRB',
        },
        'result': '1/2-1/2',
        'date': '2026-10-04T00:00:00.000Z',
        'eco': 'D35',
        'opening':
            "Queen's Gambit Declined: Exchange Variation, Carlsen Variation",
      },
      {
        'id': '18a3377c-94aa-52dd-9da3-e684b955b59e',
        'round': '10.26',
        'white': {
          'name': 'Alimpic, Aleksa',
          'fideId': '974323',
          'title': 'FM',
          'elo': 2247,
          'fed': 'SRB',
        },
        'black': {
          'name': 'Radovic, Luka',
          'fideId': '911569',
          'title': 'FM',
          'elo': 2283,
          'fed': 'SRB',
        },
        'result': '1-0',
        'date': '2026-10-13T00:00:00.000Z',
        'eco': 'D35',
        'opening':
            "Queen's Gambit Declined: Exchange Variation, Carlsen Variation",
      },
      {
        'id': '009c5180-fdba-57b9-b5ff-94ccaba906ba',
        'round': '3.1',
        'white': {
          'name': 'Gaponenko, Inna',
          'fideId': '14101181',
          'title': 'IM',
          'elo': 2308,
          'fed': 'UKR',
        },
        'black': {
          'name': 'Injac, Teodora',
          'fideId': '932400',
          'title': 'IM',
          'elo': 2405,
          'fed': 'SRB',
        },
        'result': '1/2-1/2',
        'date': '2026-09-26T00:00:00.000Z',
        'eco': 'C47',
        'opening': 'Four Knights Game: Scotch Variation Accepted',
      },
    ],
  },
};
