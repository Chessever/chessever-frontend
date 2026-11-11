// Duo audit for Prep (lib/screens/my_prep/**): every Prep screen, tab, sheet
// and dialog in each of the four iPhone Duo window states at 1.0x and 1.3x
// text, with state carried across the fold.
import 'dart:async';
import 'dart:io';

import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/supabase/chess_player/chess_player_repository.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/screens/favorites/rankings/ranking_filters.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/my_prep_home_screen.dart';
import 'package:chessever2/screens/my_prep/prep_access.dart';
import 'package:chessever2/screens/my_prep/prep_profile_screen.dart';
import 'package:chessever2/screens/my_prep/prep_sources_screen.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/services/prep_analysis.dart';
import 'package:chessever2/screens/my_prep/services/prep_pgn_player.dart';
import 'package:chessever2/screens/my_prep/services/prep_repository.dart';
import 'package:chessever2/screens/my_prep/services/prep_watch.dart';
import 'package:chessever2/screens/my_prep/tabs/prep_games_tab.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_dialogs.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_filter_dialog.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_filters.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_import_dialog.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_options_dialog.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_source_dialog.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_source_picker.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/adaptive_window.dart';
import 'package:chessever2/widgets/window_orientation_scope.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import 'fixtures/duo_window_matrix.dart';

class _Repository extends PrepRepository {
  _Repository()
    : super(
        GamebaseRepository(
          Dio(),
          baseUrl: 'https://example.test',
          apiKey: 'fixture',
        ),
      );

  @override
  Future<List<GamebasePlayer>> searchPlayers(String query) async => const [];

  @override
  Future<PrepAccount> lookup(PrepSource source, String username) async =>
      PrepAccount(
        source: source,
        username: username,
        displayName: 'Club Player',
        ratings: const {'bullet': 1800, 'rapid': 2000, 'blitz': 1900},
      );

  @override
  Future<PrepAccount> sync(
    PrepAccount account, {
    bool forceRefresh = false,
    bool frequent = false,
    PrepProgress? onProgress,
    CancelToken? cancelToken,
    bool reinstall = false,
  }) async => account;
}

class _Rankings implements ChessPlayerRepository {
  @override
  Future<List<ChessPlayer>> getRankedPlayers({
    required RankingFilters filters,
    String? countryCode,
    String searchQuery = '',
    int limit = 30,
    int offset = 0,
    DateTime? now,
  }) async => offset > 0
      ? []
      : const [
          ChessPlayer(
            fideid: 1503014,
            name: 'Carlsen, Magnus',
            title: 'GM',
            rating: 2823,
            country: 'NOR',
          ),
          ChessPlayer(
            fideid: 2020009,
            name: 'Caruana, Fabiano',
            title: 'GM',
            rating: 2795,
            country: 'USA',
          ),
        ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Follows extends FavoritePlayersNotifierNew {
  @override
  Future<List<FavoritePlayer>> build() async => const [];
}

class _SpaceShortcuts extends SpaceShortcutsNotifier {
  @override
  Future<List<SpaceShortcut>> build() async => const [];
}

class _WatchRemote extends PrepWatchRemote {
  @override
  Future<bool> watch(PrepProfile profile) async => true;

  @override
  Future<bool> unwatch(String profileId) async => true;
}

const _lichess = PrepAccount(
  source: PrepSource.lichess,
  username: 'ClubPlayerWithALongHandle',
  gameCount: 40,
  lastSyncAtMs: 1,
  ratings: {'bullet': 1800, 'rapid': 2000, 'blitz': 1900},
);
const _chesscom = PrepAccount(
  source: PrepSource.chesscom,
  username: 'SecondAccountOnChessCom',
  gameCount: 12,
  lastSyncAtMs: 1,
  ratings: {'bullet': 1750, 'rapid': 1950, 'blitz': 1850},
);

/// A long name, so the top bar has to share its row with the star.
const _name = 'Alexandra Konstantinopoulou-Vasquez';

List<PrepGame> _games(PrepAccount account) => [
  for (var i = 0; i < 40; i++)
    PrepGame(
      index: i,
      source: account.source,
      sourcePath: PrepRepository.gamesFileName(account),
      white: i.isEven ? account.username : 'Opponent number $i',
      black: i.isEven ? 'Opponent number $i' : account.username,
      result: switch (i % 3) {
        0 => '1-0',
        1 => '0-1',
        _ => '1/2-1/2',
      },
      plies: 40 + i,
      whiteElo: 1900 + i,
      blackElo: 1950 - i,
      date: DateTime(2026, 10, 1).subtract(Duration(days: i)),
      speed: PrepTimeControl.values[i % PrepTimeControl.values.length],
      eco: ['B90', 'C42', 'D37', 'E60'][i % 4],
      opening: [
        'Sicilian Defense: Najdorf Variation, English Attack',
        'Petrov Defense',
        "Queen's Gambit Declined",
        "King's Indian Defense",
      ][i % 4],
      playerIsWhite: i.isEven,
      event: 'Titled Arena',
    ),
];

const _sqflite = MethodChannel('com.tekartik.sqflite');

/// A downloaded Lichess file of [count] games for [account].
String _pgn(PrepAccount account, int count) => [
  for (var i = 0; i < count; i++)
    '''
[Event "Titled Arena with a long tournament name, round $i"]
[Site "https://lichess.org/duoFixture$i"]
[Date "2026.10.${(i % 28 + 1).toString().padLeft(2, '0')}"]
[White "${i.isEven ? account.username : 'Opponent number $i'}"]
[Black "${i.isEven ? 'Opponent number $i' : account.username}"]
[Result "${i % 3 == 0 ? '1-0' : '0-1'}"]
[WhiteElo "2100"]
[BlackElo "2000"]
[TimeControl "180+0"]
[ECO "B90"]
[Opening "Sicilian Defense: Najdorf Variation, English Attack"]

1. e4 c5 2. Nf3 d6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 a6 ${i % 3 == 0 ? '1-0' : '0-1'}
''',
].join('\n');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late _Repository repo;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('duo_prep_');
    repo = _Repository();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => directory.path,
    );
    messenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (_) async => null,
    );
    // An in-memory stand-in for the app's key-value table (card hints).
    final values = <String, String>{};
    messenger.setMockMethodCallHandler(_sqflite, (call) async {
      final args = call.arguments as Map?;
      switch (call.method) {
        case 'getDatabasesPath':
          return directory.path;
        case 'openDatabase':
          return <String, Object>{'id': 1};
        case 'query':
          if ((args!['sql'] as String).contains('user_version')) {
            return [
              {'user_version': 1},
            ];
          }
          final arguments = args['arguments'] as List? ?? const [];
          final key = arguments.isEmpty ? null : arguments.first;
          return [
            if (values[key] case final value?) {'value': value},
          ];
        case 'insert':
          final arguments = args!['arguments'] as List;
          values[arguments[0] as String] = '${arguments[1]}';
          return 1;
        default:
          return null;
      }
    });
    SqflitePlugin.registerWith();
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    messenger.setMockMethodCallHandler(_sqflite, null);
    repo.dispose();
    directory.deleteSync(recursive: true);
  });

  Future<void> loaded(ProviderContainer container) async {
    final ready = Completer<void>();
    final sub = container.listen(prepProfilesProvider, (_, state) {
      if (!state.isLoading && !ready.isCompleted) ready.complete();
    }, fireImmediately: true);
    await ready.future;
    sub.close();
  }

  /// Pumps [home] at [window] under the app's real root scopes, with the
  /// profiles [seed] puts in the store.
  Future<ProviderContainer> pump(
    WidgetTester tester,
    DuoWindowCase window,
    double scale,
    Widget home, {
    void Function(PrepProfilesNotifier profiles)? seed,
    Future<PrepAnalysis> Function(String id)? analysis,
    bool realAnalysis = false,
    List<Override> overrides = const [],
  }) async {
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    applyDuoWindow(tester, window);
    final container = ProviderContainer(
      overrides: [
        prepRepositoryProvider.overrideWithValue(repo),
        premiumAccessProvider.overrideWithValue(true),
        prepUnlimitedProvider.overrideWithValue(true),
        prepPremiumPromptProvider.overrideWithValue(
          (_, _, {required rewarded}) async => true,
        ),
        prepWatchRemoteProvider.overrideWithValue(_WatchRemote()),
        favoritePlayersProviderNew.overrideWith(_Follows.new),
        spaceShortcutsProvider.overrideWith(_SpaceShortcuts.new),
        chessPlayerRepositoryProvider.overrideWithValue(_Rankings()),
        if (!realAnalysis)
          prepAnalysisProvider.overrideWith(
            (ref, id) =>
                analysis?.call(id) ??
                Future.value(
                  PrepAnalysis(profileId: id, games: _games(_lichess)),
                ),
          ),
        ...overrides,
      ],
    );
    addTearDown(container.dispose);
    await tester.runAsync(() async {
      await loaded(container);
      if (seed != null) {
        seed(container.read(prepProfilesProvider.notifier));
        await container.read(prepProfilesProvider.notifier).debugDrainWrites();
      }
      if (realAnalysis) {
        // Indexed before the screen opens, and kept while it is open.
        final id = container
            .read(prepProfilesOfKindProvider(PrepKind.opponent))!
            .first
            .id;
        container.listen(prepAnalysisProvider(id), (_, _) {});
        await container.read(prepAnalysisProvider(id).future);
      }
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          builder: (context, child) => MediaQuery.withClampedTextScaling(
            minScaleFactor: scale,
            maxScaleFactor: scale,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: WindowOrientationScope(
                child: AdaptiveWindowScope(child: child!),
              ),
            ),
          ),
          home: home,
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    return container;
  }

  /// Moves the window and settles; the screen must not throw on the way.
  Future<void> move(
    WidgetTester tester,
    DuoWindowCase window, {
    bool mirror = false,
  }) async {
    applyDuoWindow(tester, window, mirrorInsets: mirror);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: window.name);
  }

  /// [target] can be brought on screen and receives a tap at its centre.
  Future<void> expectHittable(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    expect(target.hitTestable(), findsWidgets, reason: '$target');
  }

  String opponentId(ProviderContainer container) =>
      container.read(prepProfilesOfKindProvider(PrepKind.opponent))!.first.id;

  void seedOpponent(PrepProfilesNotifier profiles, {bool two = false}) {
    profiles.create(
      kind: PrepKind.opponent,
      name: _name,
      accounts: [_lichess, if (two) _chesscom],
    );
  }

  const scales = [1.0, 1.3];

  // ------------------------------------------------------------ home screen

  group('Prep home', () {
    for (final window in duoWindowCases) {
      for (final scale in scales) {
        testWidgets(
          'empty Games and Profiles fit ${window.name} at ${scale}x',
          (tester) async {
            await pump(tester, window, scale, const MyPrepHomeScreen());
            expect(tester.takeException(), isNull);
            expect(find.text('Attach your own usernames'), findsOneWidget);
            await expectHittable(tester, find.text('Attach your username'));
            expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
            await tester.tap(find.text('Profiles'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(find.text('Prepare for your next opponent'), findsOneWidget);
            await expectHittable(tester, find.text('Add opponent'));
            expect(tester.takeException(), isNull);
          },
        );

        testWidgets('populated Profiles, fab and Players fit ${window.name} '
            'at ${scale}x', (tester) async {
          await pump(
            tester,
            window,
            scale,
            const MyPrepHomeScreen(initialTab: 1),
            seed: (p) {
              seedOpponent(p, two: true);
              p.create(
                kind: PrepKind.mine,
                name: 'Me',
                accounts: const [
                  PrepAccount(source: PrepSource.lichess, username: 'MeMyself'),
                ],
              );
            },
          );
          expect(tester.takeException(), isNull);
          expect(find.text(_name), findsWidgets);
          final fab = find.byKey(const ValueKey('prep_add_floating'));
          await expectHittable(tester, fab);
          await tester.tap(fab);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Chess.com').hitTestable(), findsWidgets);
          // The root keeps the app inside the safe area: tap just inside it.
          await tester.tapAt(Offset(window.landscape ? 70 : 8, 300));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Players'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.textContaining('Carlsen'), findsWidgets);
          await tester.tap(find.text('Games'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }

    for (final transition in duoWindowTransitions) {
      testWidgets('home tab and unfolded card survive ${transition.from.name} '
          '-> ${transition.to.name}', (tester) async {
        await pump(
          tester,
          transition.from,
          1.3,
          const MyPrepHomeScreen(initialTab: 1),
          seed: (p) => seedOpponent(p, two: true),
        );
        await tester.tap(find.byTooltip('Show sources').first);
        await tester.pumpAndSettle();
        expect(find.byTooltip('Hide sources'), findsOneWidget);
        final state = tester.state(find.byType(MyPrepHomeScreen));
        await move(tester, transition.to, mirror: true);
        expect(tester.state(find.byType(MyPrepHomeScreen)), same(state));
        expect(find.byTooltip('Hide sources'), findsOneWidget);
        // Still on Profiles: the opponent card, not the empty Games tab.
        expect(find.text(_name), findsWidgets);
        expect(find.text('Attach your own usernames'), findsNothing);
        await expectHittable(
          tester,
          find.byKey(const ValueKey('prep_add_floating')),
        );
        await move(tester, transition.from);
        expect(find.text(_name), findsWidgets);
        expect(find.byTooltip('Hide sources'), findsOneWidget);
      });
    }
  });

  // --------------------------------------------------------- profile screen

  group('Prep profile', () {
    for (final window in duoWindowCases) {
      for (final scale in scales) {
        testWidgets('header, star and About, Games, Build Tree fit '
            '${window.name} at ${scale}x', (tester) async {
          late String id;
          final container = await pump(
            tester,
            window,
            scale,
            Consumer(
              builder: (context, ref, _) {
                final profiles = ref.watch(
                  prepProfilesOfKindProvider(PrepKind.opponent),
                );
                if (profiles == null || profiles.isEmpty) {
                  return const SizedBox.shrink();
                }
                id = profiles.first.id;
                return PrepProfileScreen(profileId: id);
              },
            ),
            seed: (p) => seedOpponent(p, two: true),
            overrides: [
              prepSourceAnalysisProvider.overrideWith(
                (ref, key) async => PrepAnalysis(
                  profileId: key.profileId,
                  games: _games(_lichess),
                ),
              ),
            ],
          );
          expect(tester.takeException(), isNull);
          // The star sits in the top bar beside the name.
          final star = find.bySemanticsLabel('Star $_name');
          expect(star.hitTestable(), findsOneWidget);
          expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
          await tester.tap(star);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(container.read(prepProfileProvider(id))?.watching, isTrue);
          await tester.pump(const Duration(seconds: 5));
          await tester.pumpAndSettle();
          expect(
            find.bySemanticsLabel('Unstar $_name').hitTestable(),
            findsOneWidget,
          );
          expect(find.text('Games analyzed'), findsOneWidget);
          await expectHittable(tester, find.text('Games analyzed'));

          for (final tab in ['Games', 'Build Tree', 'About']) {
            await tester.tap(find.text(tab).first);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: tab);
          }
          await tester.tap(find.text('Games').first);
          await tester.pumpAndSettle();
          expect(find.byType(PrepGamesTab), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('Build Tree').first);
          await tester.pumpAndSettle();
          expect(find.text('Opening trees'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });

        testWidgets('empty and failed states fit ${window.name} at ${scale}x', (
          tester,
        ) async {
          await pump(
            tester,
            window,
            scale,
            Consumer(
              builder: (context, ref, _) {
                final profiles = ref.watch(
                  prepProfilesOfKindProvider(PrepKind.opponent),
                );
                if (profiles == null || profiles.isEmpty) {
                  return const SizedBox.shrink();
                }
                return PrepProfileScreen(profileId: profiles.first.id);
              },
            ),
            seed: (p) => p.create(
              kind: PrepKind.opponent,
              name: _name,
              accounts: const [],
            ),
            analysis: (id) async => PrepAnalysis.empty(id),
          );
          expect(tester.takeException(), isNull);
          expect(find.text('No games yet'), findsOneWidget);
          await expectHittable(tester, find.text('Manage sources'));
          await tester.tap(find.text('Games').first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await expectHittable(tester, find.text('Manage sources'));
        });

        testWidgets(
          'a failed read offers Retry in ${window.name} at ${scale}x',
          (tester) async {
            await pump(
              tester,
              window,
              scale,
              Consumer(
                builder: (context, ref, _) {
                  final profiles = ref.watch(
                    prepProfilesOfKindProvider(PrepKind.opponent),
                  );
                  if (profiles == null || profiles.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return PrepProfileScreen(profileId: profiles.first.id);
                },
              ),
              seed: seedOpponent,
              analysis: (_) async => throw StateError('fixture failure'),
            );
            expect(tester.takeException(), isNull);
            expect(find.text('Could not read these games'), findsOneWidget);
            await expectHittable(tester, find.text('Retry'));
            await tester.tap(find.text('Games').first);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(find.text('Could not read games'), findsOneWidget);
            await expectHittable(tester, find.text('Retry'));
          },
        );
      }
    }

    for (final window in duoWindowCases) {
      for (final scale in scales) {
        testWidgets('About statistics panels open in ${window.name} at '
            '${scale}x', (tester) async {
          await pump(
            tester,
            window,
            scale,
            Consumer(
              builder: (context, ref, _) {
                final profiles = ref.watch(
                  prepProfilesOfKindProvider(PrepKind.opponent),
                );
                if (profiles == null || profiles.isEmpty) {
                  return const SizedBox.shrink();
                }
                return PrepProfileScreen(profileId: profiles.first.id);
              },
            ),
            seed: (p) => seedOpponent(p, two: true),
            overrides: [
              prepSourceAnalysisProvider.overrideWith(
                (ref, key) async => PrepAnalysis(
                  profileId: key.profileId,
                  games: _games(_lichess),
                ),
              ),
            ],
          );
          for (final panel in [
            'Performance by colour',
            'Opening repertoire',
            'Time controls',
            'More statistics',
          ]) {
            final title = find.text(panel);
            await expectHittable(tester, title);
            await tester.tap(title);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: panel);
          }
          // A choice in an open panel still reaches the tab bar's cue.
          final white = find.text('As White').first;
          await expectHittable(tester, white);
          await tester.tap(white);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.textContaining('Games '), findsWidgets);
          // Scroll About to its end.
          await tester.drag(
            find.text('Games analyzed'),
            const Offset(0, -3000),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }

    for (final window in duoWindowCases) {
      for (final scale in scales) {
        for (final mode in GamesListViewMode.values) {
          group(
            'Games ${mode.name} in ${window.name} at ${scale}x',
            () => testWidgets('fits', (tester) async {
              await tester.runAsync(() async {
                await File(
                  '${directory.path}/${PrepRepository.gamesFileName(_lichess)}',
                ).create(recursive: true);
                final file = await repo.gamesFile(_lichess);
                await file.writeAsString(_pgn(_lichess, 12));
              });
              await pump(
                tester,
                window,
                scale,
                Consumer(
                  builder: (context, ref, _) {
                    final profiles = ref.watch(
                      prepProfilesOfKindProvider(PrepKind.opponent),
                    );
                    if (profiles == null || profiles.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return PrepProfileScreen(
                      profileId: profiles.first.id,
                      initialTab: prepProfileGamesTab,
                    );
                  },
                ),
                seed: seedOpponent,
                realAnalysis: true,
                overrides: [gamesListViewModeProvider.overrideWithValue(mode)],
              );
              await tester.pump(const Duration(seconds: 1));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              expect(find.byType(PrepGamesTab), findsOneWidget);
              final kind = switch (mode) {
                GamesListViewMode.gamesCard => 'card',
                GamesListViewMode.chessBoardGrid => 'grid',
                GamesListViewMode.chessBoard => 'board',
              };
              final cards = find.byWidgetPredicate(
                (w) =>
                    w.key is ValueKey<String> &&
                    (w.key! as ValueKey<String>).value.startsWith(
                      'prep_${kind}_',
                    ),
              );
              expect(cards, findsWidgets);
              await expectHittable(tester, cards.first);
              // The list scrolls to its end without anything overflowing.
              await tester.drag(
                find.byType(PrepGamesTab),
                const Offset(0, -2000),
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              // Board cards leave engine and eval timers behind: let them run.
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pump(const Duration(minutes: 1));
            }),
          );
        }
      }
    }

    for (final transition in duoWindowTransitions) {
      testWidgets('selected tab and filter survive ${transition.from.name} '
          '-> ${transition.to.name}', (tester) async {
        await pump(
          tester,
          transition.from,
          1.3,
          Consumer(
            builder: (context, ref, _) {
              final profiles = ref.watch(
                prepProfilesOfKindProvider(PrepKind.opponent),
              );
              if (profiles == null || profiles.isEmpty) {
                return const SizedBox.shrink();
              }
              return PrepProfileScreen(profileId: profiles.first.id);
            },
          ),
          seed: seedOpponent,
        );
        // A choice on About narrows the games; then open Games.
        await tester.tap(find.text('Wins').first);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('prep_filter_banner')), findsWidgets);
        await tester.tap(find.textContaining('Games ').first);
        await tester.pumpAndSettle();
        expect(find.byType(PrepGamesTab), findsOneWidget);
        final state = tester.state(find.byType(PrepProfileScreen));
        await move(tester, transition.to, mirror: true);
        expect(tester.state(find.byType(PrepProfileScreen)), same(state));
        expect(find.byType(PrepGamesTab), findsOneWidget);
        expect(
          tester.widget<PrepGamesTab>(find.byType(PrepGamesTab)).filter.narrows,
          isTrue,
        );
        expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
        await move(tester, transition.from);
        expect(find.byType(PrepGamesTab), findsOneWidget);
      });
    }
  });

  // --------------------------------------------------------- sources screen

  group('Prep sources', () {
    for (final window in duoWindowCases) {
      for (final scale in scales) {
        testWidgets('list, add menu and source popup fit ${window.name} at '
            '${scale}x', (tester) async {
          final container = await pump(
            tester,
            window,
            scale,
            Consumer(
              builder: (context, ref, _) {
                final profiles = ref.watch(
                  prepProfilesOfKindProvider(PrepKind.opponent),
                );
                if (profiles == null || profiles.isEmpty) {
                  return const SizedBox.shrink();
                }
                return PrepSourcesScreen(profileId: profiles.first.id);
              },
            ),
            seed: (p) => seedOpponent(p, two: true),
          );
          expect(tester.takeException(), isNull);
          final add = find.byKey(const ValueKey('prep_add_source'));
          expect(add.hitTestable(), findsOneWidget);
          await tester.tap(add);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await expectHittable(
            tester,
            find.byKey(const ValueKey('prep_attach_chesscom')),
          );
          await tester.tapAt(Offset(window.landscape ? 70 : 8, 200));
          await tester.pumpAndSettle();

          final row = find.byKey(ValueKey('prep_account_${_chesscom.key}'));
          await expectHittable(tester, row);
          await tester.tap(row);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await expectHittable(tester, find.text('Go to profile'));
          await expectHittable(tester, find.byTooltip('Close'));
          await tester.tap(find.byTooltip('Close'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(opponentId(container), isNotEmpty);
        });
      }
    }

    for (final transition in duoWindowTransitions) {
      testWidgets('source popup page survives ${transition.from.name} -> '
          '${transition.to.name}', (tester) async {
        await pump(
          tester,
          transition.from,
          1.3,
          Consumer(
            builder: (context, ref, _) {
              final profiles = ref.watch(
                prepProfilesOfKindProvider(PrepKind.opponent),
              );
              if (profiles == null || profiles.isEmpty) {
                return const SizedBox.shrink();
              }
              return PrepSourcesScreen(profileId: profiles.first.id);
            },
          ),
          seed: (p) => seedOpponent(p, two: true),
        );
        await tester.tap(find.byKey(ValueKey('prep_account_${_chesscom.key}')));
        await tester.pumpAndSettle();
        final scope = find.byKey(const ValueKey('prep_download_scope'));
        await tester.ensureVisible(scope);
        await tester.pumpAndSettle();
        await tester.tap(scope);
        await tester.pumpAndSettle();
        expect(find.text('Download options'), findsOneWidget);
        await move(tester, transition.to, mirror: true);
        expect(find.text('Download options'), findsOneWidget);
        await expectHittable(tester, find.text('Save'));
        await move(tester, transition.from);
        expect(find.text('Download options'), findsOneWidget);
        await expectHittable(tester, find.text('Save'));
      });
    }
  });

  // ------------------------------------------------------- dialogs & sheets

  Widget launcher(Future<void> Function(BuildContext context) open) => Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: TextButton(
          onPressed: () => open(context),
          child: const Text('Open'),
        ),
      ),
    ),
  );

  group('Prep dialogs', () {
    for (final window in duoWindowCases) {
      for (final scale in scales) {
        testWidgets('rename keeps its text and Save in ${window.name} at '
            '${scale}x', (tester) async {
          String? renamed;
          await pump(
            tester,
            window,
            scale,
            launcher(
              (c) async => renamed = await showPrepRenameDialog(c, _name),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
          applyDuoWindow(tester, window);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.enterText(find.byType(TextField), 'Renamed opponent');
          await tester.pumpAndSettle();
          await expectHittable(tester, find.text('Save'));
          await tester.tap(find.text('Save'));
          await tester.pumpAndSettle();
          expect(renamed, 'Renamed opponent');
          expect(tester.takeException(), isNull);
        });

        testWidgets('download options fit ${window.name} at ${scale}x', (
          tester,
        ) async {
          PrepDownloadPreferences? picked;
          var closed = false;
          await pump(
            tester,
            window,
            scale,
            launcher((c) async {
              picked = await showPrepDownloadOptionsDialog(
                c,
                account: _lichess,
                others: const [_chesscom],
                download: true,
              );
              closed = true;
            }),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Time controls'), findsOneWidget);
          await expectHittable(tester, find.text('Download'));
          await tester.tap(find.text('Download'));
          await tester.pumpAndSettle();
          expect(closed, isTrue);
          expect(picked, isNotNull);
          expect(tester.takeException(), isNull);
        });

        testWidgets('filter popup fits ${window.name} at ${scale}x', (
          tester,
        ) async {
          PrepFilter? chosen;
          const profile = PrepProfile(
            id: 'p',
            kind: PrepKind.opponent,
            name: _name,
            createdAtMs: 1,
            accounts: [_lichess, _chesscom],
          );
          await pump(
            tester,
            window,
            scale,
            launcher(
              (c) async => chosen = await showPrepFilterDialog(
                context: c,
                profile: profile,
                currentFilter: const PrepFilter(),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await expectHittable(tester, find.byTooltip('Close filters'));
          await expectHittable(tester, find.text('More game filters'));
          await expectHittable(tester, find.text('Apply'));
          await tester.tap(find.text('Apply'));
          await tester.pumpAndSettle();
          expect(chosen, isNotNull);
          expect(tester.takeException(), isNull);
        });

        testWidgets('PGN import fits ${window.name} at ${scale}x', (
          tester,
        ) async {
          await pump(
            tester,
            window,
            scale,
            PrepImportDialog(
              pickFiles: () async => null,
              onImport: (inputs, {player}) async => const PrepPgnReading(
                candidates: [
                  PrepPgnCandidate('Carlsen, Magnus', 14),
                  PrepPgnCandidate('Nepomniachtchi, Ian', 14),
                ],
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          await expectHittable(tester, find.text('Choose files'));
          await tester.enterText(
            find.byKey(const ValueKey('prep_import_pgn')),
            '[White "A"]',
          );
          await tester.pumpAndSettle();
          await expectHittable(tester, find.text('Import'));
          await tester.tap(find.text('Import'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Whose games are these?'), findsOneWidget);
          await expectHittable(tester, find.text('Nepomniachtchi, Ian'));
        });

        testWidgets('add-opponent sheet fits ${window.name} at ${scale}x', (
          tester,
        ) async {
          await pump(
            tester,
            window,
            scale,
            launcher((c) => showPrepSourcePicker(c, kind: PrepKind.opponent)),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Add an opponent'), findsOneWidget);
          await expectHittable(tester, find.text('Chess.com'));
          await expectHittable(
            tester,
            find.byKey(const ValueKey('prep_source_cancel')),
          );
          await tester.tap(find.text('Chess.com'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await expectHittable(
            tester,
            find.byKey(const ValueKey('prep_source_query')),
          );
        });
      }
    }

    for (final transition in duoWindowTransitions) {
      testWidgets('source dialog page survives ${transition.from.name} -> '
          '${transition.to.name}', (tester) async {
        final container = await pump(
          tester,
          transition.from,
          1.3,
          launcher((_) async {}),
          seed: (p) => seedOpponent(p, two: true),
        );
        final id = opponentId(container);
        final context = tester.element(find.text('Open'));
        unawaited(
          showPrepSourceDialog(
            context,
            profileId: id,
            accountKey: _lichess.key,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Go to profile'), findsWidgets);
        await move(tester, transition.to, mirror: true);
        await expectHittable(tester, find.text('Go to profile'));
        await move(tester, transition.from);
        await expectHittable(tester, find.byTooltip('Close'));
      });
    }
  });
}
