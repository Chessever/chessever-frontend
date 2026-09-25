import 'dart:async';
import 'dart:convert';

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/feed/race/race_controller.dart';
import 'package:chessever2/screens/feed/race/race_flames.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/my_profile/chess_accounts.dart';
import 'package:chessever2/screens/my_profile/my_profile_screen.dart';
import 'package:chessever2/screens/my_profile/race_stats_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'puzzle_race_fakes.dart';

// ---------------------------------------------------------------- doubles

/// Subscription double without RevenueCat's constructor side effects.
class _Subscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _Subscription(bool subscribed)
    : super(SubscriptionState(isSubscribed: subscribed));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

User _supabaseUser(Map<String, dynamic> metadata, {bool anonymous = false}) {
  return User(
    id: 'user-1',
    appMetadata: const {},
    userMetadata: metadata,
    aud: 'authenticated',
    email: anonymous ? null : 'magnus@example.com',
    createdAt: '2026-01-02T03:04:05.000Z',
    isAnonymous: anonymous,
  );
}

/// Site double: answers per path, records every request.
class _Sites {
  _Sites(this.answers);

  /// Path → (status, body). Unknown paths answer 404.
  final Map<String, (int, Object?)> answers;
  final List<Uri> requests = [];

  http.Client get client => MockClient((request) async {
    requests.add(request.url);
    final answer = answers[request.url.path] ?? (404, null);
    return http.Response(
      answer.$2 == null ? '' : jsonEncode(answer.$2),
      answer.$1,
    );
  });
}

/// Metadata writer double: records every write, echoes it back merged.
class _Writes {
  final List<Map<String, dynamic>> calls = [];
  Map<String, dynamic> stored = {'full_name': 'Magnus Carlsen'};

  Future<User?> call(Map<String, dynamic> data) async {
    calls.add(Map.of(data));
    stored = {...stored};
    data.forEach((key, value) {
      if (value == null) {
        stored.remove(key);
      } else {
        stored[key] = value;
      }
    });
    return _supabaseUser(stored);
  }
}

// ---------------------------------------------------------------- pump

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  bool guest = false,
  LinkedChessAccounts linked = (lichess: null, chesscom: null),
  RaceStats stats = RaceStats.empty,
  ChessAccountsService? service,
  void Function()? onStatsRead,
  List<Override> extraOverrides = const [],
  RaceServerStats? kept,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = const Size(393, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      subscriptionProvider.overrideWith((ref) => _Subscription(false)),
      currentUserProvider.overrideWithValue(
        AppUser(
          id: 'user-1',
          email: guest ? null : 'magnus@example.com',
          displayName: guest ? 'Guest' : 'Magnus Carlsen',
          createdAt: DateTime(2026),
          isAnonymous: guest,
        ),
      ),
      myProfileIdentityProvider.overrideWith(
        (ref) => (
          displayName: guest ? 'Guest' : 'Magnus Carlsen',
          email: guest ? null : 'magnus@example.com',
          isGuest: guest,
        ),
      ),
      linkedChessAccountsProvider.overrideWithValue(linked),
      raceStatsProvider.overrideWith((ref) async {
        onStatsRead?.call();
        return stats;
      }),
      raceServerStatsSourceProvider.overrideWithValue(
        FakeRaceServerStatsSource(kept),
      ),
      chessAccountsServiceProvider.overrideWithValue(
        service ??
            ChessAccountsService(
              client: _Sites(const {}).client,
              writeMetadata: _Writes().call,
            ),
      ),
      ...extraOverrides,
    ],
  );
  addTearDown(container.dispose);
  // Keep the tab selection alive the way the home shell does.
  container.listen(selectedBottomNavBarItemProvider, (_, _) {});

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: theme ?? AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const MyProfileScreen(),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await _settle(tester);
  return container;
}

/// Springs settle on their own time; step frames instead of pumpAndSettle.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('username format', () {
    test('Lichess takes 2 to 30 of letters, digits, - and _', () {
      expect(validateChessUsername(ChessSite.lichess, ''), isNull);
      expect(validateChessUsername(ChessSite.lichess, 'a'), isNotNull);
      expect(validateChessUsername(ChessSite.lichess, 'ab'), isNull);
      expect(
        validateChessUsername(ChessSite.lichess, 'Dr-Nykter_stein'),
        isNull,
      );
      expect(validateChessUsername(ChessSite.lichess, 'a' * 30), isNull);
      expect(validateChessUsername(ChessSite.lichess, 'a' * 31), isNotNull);
      expect(validateChessUsername(ChessSite.lichess, 'bad name'), isNotNull);
      expect(validateChessUsername(ChessSite.lichess, 'mägnus'), isNotNull);
    });

    test('Chess.com takes 3 to 25 of letters, digits, - and _', () {
      expect(validateChessUsername(ChessSite.chesscom, ''), isNull);
      expect(validateChessUsername(ChessSite.chesscom, 'ab'), isNotNull);
      expect(validateChessUsername(ChessSite.chesscom, 'abc'), isNull);
      expect(validateChessUsername(ChessSite.chesscom, 'a' * 25), isNull);
      expect(validateChessUsername(ChessSite.chesscom, 'a' * 26), isNotNull);
      expect(validateChessUsername(ChessSite.chesscom, 'hikaru.n'), isNotNull);
    });

    test('pasted names and profile addresses reduce to the bare name', () {
      expect(normalizeChessUsername('  @DrNykterstein '), 'DrNykterstein');
      expect(
        normalizeChessUsername('https://lichess.org/@/DrNykterstein'),
        'DrNykterstein',
      );
      expect(
        normalizeChessUsername('lichess.org/@/DrNykterstein/all'),
        'DrNykterstein',
      );
      expect(
        normalizeChessUsername('https://www.chess.com/member/Hikaru?ref=x'),
        'Hikaru',
      );
      expect(normalizeChessUsername('lichess.org/@/'), '');
      // Not an address: left alone for the format check to reject.
      expect(normalizeChessUsername('a#b'), 'a#b');
    });
  });

  group('AppUser metadata', () {
    test('reads linked usernames from user_metadata, trimmed', () {
      final user = AppUser.fromSupabaseUser(
        _supabaseUser({
          'full_name': 'Magnus Carlsen',
          'lichess_username': ' DrNykterstein ',
          'chesscom_username': 'MagnusCarlsen',
        }),
      );
      expect(user.displayName, 'Magnus Carlsen');
      expect(user.lichessUsername, 'DrNykterstein');
      expect(user.chesscomUsername, 'MagnusCarlsen');
    });

    test('missing, blank or non-text values read as not linked', () {
      final none = AppUser.fromSupabaseUser(_supabaseUser({}));
      expect(none.lichessUsername, isNull);
      expect(none.chesscomUsername, isNull);

      final odd = AppUser.fromSupabaseUser(
        _supabaseUser({'lichess_username': '   ', 'chesscom_username': 42}),
      );
      expect(odd.lichessUsername, isNull);
      expect(odd.chesscomUsername, isNull);
    });

    test('copyWith carries the usernames', () {
      final user = AppUser.fromSupabaseUser(
        _supabaseUser({'lichess_username': 'DrNykterstein'}),
      );
      final renamed = user.copyWith(displayName: 'Magnus');
      expect(renamed.lichessUsername, 'DrNykterstein');
      expect(
        renamed.copyWith(chesscomUsername: 'MagnusCarlsen').chesscomUsername,
        'MagnusCarlsen',
      );
    });
  });

  group('ChessAccountsService', () {
    test('lookup reads found, closed, missing and unreachable', () async {
      final sites = _Sites({
        '/api/user/drnykterstein': (200, {'username': 'DrNykterstein'}),
        '/api/user/gone': (200, {'username': 'Gone', 'disabled': true}),
        '/api/user/busy': (429, null),
        '/pub/player/hikaru': (
          200,
          {'username': 'hikaru', 'status': 'premium'},
        ),
        '/pub/player/cheater': (200, {'status': 'closed:fair_play_violations'}),
      });
      final service = ChessAccountsService(client: sites.client);

      final found = await service.lookup(ChessSite.lichess, 'drnykterstein');
      expect(found.status, UsernameLookupStatus.found);
      expect(found.canonicalUsername, 'DrNykterstein');

      expect(
        (await service.lookup(ChessSite.lichess, 'gone')).status,
        UsernameLookupStatus.closed,
      );
      expect(
        (await service.lookup(ChessSite.lichess, 'nobody')).status,
        UsernameLookupStatus.notFound,
      );
      expect(
        (await service.lookup(ChessSite.lichess, 'busy')).status,
        UsernameLookupStatus.unreachable,
      );
      // Chess.com's API is keyed on the lowercase name.
      expect(
        (await service.lookup(ChessSite.chesscom, 'Hikaru')).status,
        UsernameLookupStatus.found,
      );
      expect(sites.requests.last.path, '/pub/player/hikaru');
      expect(
        (await service.lookup(ChessSite.chesscom, 'cheater')).status,
        UsernameLookupStatus.closed,
      );
    });

    test('a check that never answers is unreachable, not an error', () async {
      final service = ChessAccountsService(
        client: MockClient((_) => Completer<http.Response>().future),
        timeout: const Duration(milliseconds: 10),
      );
      final result = await service.lookup(ChessSite.lichess, 'slow');
      expect(result.status, UsernameLookupStatus.unreachable);
    });

    test(
      'save writes the changed keys, null to unlink, and returns what is stored',
      () async {
        final writes = _Writes();
        final service = ChessAccountsService(writeMetadata: writes.call);
        final stored = await service.save((
          lichess: 'DrNykterstein',
          chesscom: null,
        ), sites: ChessSite.values);
        expect(writes.calls.single, {
          'lichess_username': 'DrNykterstein',
          'chesscom_username': null,
        });
        expect(stored, (lichess: 'DrNykterstein', chesscom: null));
        // The merge keeps everything else in user_metadata.
        expect(writes.stored['full_name'], 'Magnus Carlsen');
      },
    );

    test('save never sends a site the user did not change', () async {
      // Another device linked Chess.com after this session was cached.
      final writes = _Writes()
        ..stored = {
          'full_name': 'Magnus Carlsen',
          'chesscom_username': 'MagnusCarlsen',
        };
      final service = ChessAccountsService(writeMetadata: writes.call);
      final stored = await service.save(
        (lichess: 'DrNykterstein', chesscom: null),
        sites: const [ChessSite.lichess],
      );
      expect(writes.calls.single, {'lichess_username': 'DrNykterstein'});
      expect(stored, (lichess: 'DrNykterstein', chesscom: 'MagnusCarlsen'));
    });
  });

  group('RaceStats', () {
    test('decodes the cached JSON, forgiving shape and bad values', () {
      expect(RaceStats.decode(null), RaceStats.empty);
      expect(RaceStats.decode('not json'), RaceStats.empty);
      expect(RaceStats.decode('[1,2]'), RaceStats.empty);
      expect(
        RaceStats.decode(
          '{"survivalBest":31,"infiniteBest":118.0,"racesPlayed":12,'
          '"bestStreak":9}',
        ),
        const RaceStats(
          survivalBest: 31,
          infiniteBest: 118,
          racesPlayed: 12,
          bestStreak: 9,
        ),
      );
      expect(
        RaceStats.decode('{"survival_best":"7","races_played":-3}'),
        const RaceStats(survivalBest: 7),
      );
    });

    test('recordPuzzleRace folds a race into what is stored', () async {
      SharedPreferences.setMockInitialValues({});
      await recordPuzzleRace(
        mode: PuzzleRaceMode.survival,
        score: 20,
        streak: 6,
      );
      final after = await recordPuzzleRace(
        mode: PuzzleRaceMode.infinite,
        score: 55,
        streak: 4,
      );
      expect(
        after,
        const RaceStats(
          survivalBest: 20,
          infiniteBest: 55,
          racesPlayed: 2,
          bestStreak: 6,
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(RaceStats.decode(prefs.getString(kRaceStatsPrefsKey)), after);
    });

    test('flames ride along: read, added up, and written back', () async {
      expect(RaceStats.decode('{"flames": 30}').flames, 30);
      expect(RaceStats.decode('{"flames": -4}').flames, 0);
      // A count alone is something to show.
      expect(const RaceStats(flames: 3).isEmpty, isFalse);
      SharedPreferences.setMockInitialValues({
        kRaceStatsPrefsKey: jsonEncode({'flames': 10, 'future': 'kept'}),
      });
      final after = await recordPuzzleRace(
        mode: PuzzleRaceMode.survival,
        score: 4,
        streak: 2,
        flames: 6,
      );
      expect(after.flames, 16);
      final prefs = await SharedPreferences.getInstance();
      final stored =
          jsonDecode(prefs.getString(kRaceStatsPrefsKey)!) as Map;
      expect(stored['flames'], 16);
      expect(stored['future'], 'kept');
    });
  });

  group('My Profile screen', () {
    testWidgets('signed in: identity and plan, no chess accounts or '
        'Puzzle Race', (tester) async {
      await _pump(tester, linked: (lichess: 'DrNykterstein', chesscom: null));

      expect(find.text('Magnus Carlsen'), findsOneWidget);
      expect(find.text('MC'), findsOneWidget);
      expect(find.text('magnus@example.com'), findsOneWidget);
      expect(find.text('Free plan'), findsOneWidget);
      expect(find.text('Chess accounts'), findsNothing);
      expect(find.text('lichess.org/@/'), findsNothing);
      expect(find.text('Puzzle Race'), findsNothing);
      expect(find.text('Start a Puzzle Race'), findsNothing);
      expect(tester.takeException(), isNull);
    });

  });
}
