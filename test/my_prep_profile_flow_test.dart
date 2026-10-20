import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/revenue_cat_service/offline_premium_cache.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/supabase/chess_player/chess_player_repository.dart';
import 'package:chessever2/screens/favorites/rankings/ranking_filters.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/my_prep_home_screen.dart';
import 'package:chessever2/screens/my_prep/library/prep_library.dart';
import 'package:chessever2/screens/my_prep/prep_access.dart';
import 'package:chessever2/screens/my_prep/prep_profile_screen.dart';
import 'package:chessever2/screens/my_prep/prep_actions.dart';
import 'package:chessever2/screens/my_prep/prep_source_actions.dart';
import 'package:chessever2/screens/my_prep/prep_sources_screen.dart';
import 'package:chessever2/screens/my_prep/providers/prep_known_accounts_provider.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/services/prep_analysis.dart';
import 'package:chessever2/screens/my_prep/services/prep_repository.dart';
import 'package:chessever2/screens/my_prep/services/prep_watch.dart';
import 'package:chessever2/services/deep_link_service.dart';
import 'package:chessever2/screens/my_prep/tabs/prep_overview_tab.dart';
import 'package:chessever2/screens/my_prep/tabs/prep_trees_tab.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_account_switch.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_common.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_dialogs.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_profile_card.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_import_dialog.dart';
import 'package:chessever2/screens/my_prep/tabs/prep_games_tab.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/game_filter/game_filter_dialog.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_explorer_state.dart';
import 'package:chessever2/widgets/game_tree/build_tree_button.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_filters.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_filter_dialog.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_filter_popup.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_identity.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_source_picker.dart';
import 'package:chessever2/screens/player_profile/widgets/player_games_toolbar.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:chessever2/widgets/card_context_menu.dart'
    show CardActionButton, CardMoreButton;
import 'package:chessever2/widgets/figma_player_card.dart';
import 'package:chessever2/widgets/popover_add_fab.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:dio/dio.dart';

import 'my_prep_sources_test.dart' show databasePlayer, sourceGame;
import 'support/offline_premium_fakes.dart';

class _PickerRepository extends PrepRepository {
  _PickerRepository()
    : super(
        GamebaseRepository(
          Dio(),
          baseUrl: 'https://example.test',
          apiKey: 'fixture',
        ),
      );
  @override
  Future<List<GamebasePlayer>> searchPlayers(String query) async =>
      query == 'unlisted'
      ? []
      : [databasePlayer.copyWith(fideId: query == '1503014' ? query : '0')];
  @override
  Future<PrepAccount> lookup(PrepSource source, String username) async =>
      PrepAccount(
        source: source,
        username: username,
        displayName: 'Club Player',
        ratings: const {'bullet': 1800, 'rapid': 2000, 'blitz': 1900},
      );

  bool deferSync = false;
  int syncCalls = 0;

  /// What every download throws while set, as a dropped connection would.
  PrepException? syncFailure;

  /// Holds every download until completed, so overlap can be seen.
  Completer<void>? syncGate;

  /// Usernames in the order their downloads started.
  final synced = <String>[];
  final syncStarted = Completer<void>();
  @override
  Future<PrepAccount> sync(
    PrepAccount account, {
    bool forceRefresh = false,
    bool frequent = false,
    PrepProgress? onProgress,
    CancelToken? cancelToken,
    bool reinstall = false,
  }) async {
    syncCalls++;
    synced.add(account.username);
    if (syncGate case final gate?) await gate.future;
    if (syncFailure case final failure?) throw failure;
    if (deferSync) {
      syncStarted.complete();
      throw await cancelToken!.whenCancel;
    }
    return account;
  }
}

class _RankingRepository implements ChessPlayerRepository {
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
          ChessPlayer(fideid: 99, name: 'Unknown, Handle', rating: 2600),
        ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The players the reader follows in Favorites, newest first.
class _Follows extends FavoritePlayersNotifierNew {
  _Follows(this.seed);
  final List<FavoritePlayer> seed;

  @override
  Future<List<FavoritePlayer>> build() async => seed;
}

class _SpaceShortcuts extends SpaceShortcutsNotifier {
  @override
  Future<List<SpaceShortcut>> build() async => const [];
}

/// The server's copy of starred profiles, as calls.
class _WatchRemote extends PrepWatchRemote {
  final calls = <String>[];

  @override
  Future<bool> watch(PrepProfile profile) async {
    calls.add('watch ${profile.id}');
    return true;
  }

  @override
  Future<bool> unwatch(String profileId) async {
    calls.add('unwatch $profileId');
    return true;
  }
}

FavoritePlayer _follow(String name, int fide, int rating) => FavoritePlayer(
  id: 'fav-$fide',
  userId: 'u1',
  fideId: '$fide',
  playerName: name,
  metadata: {'title': 'GM', 'rating': rating},
  createdAt: DateTime(2026, 7),
  updatedAt: DateTime(2026, 7),
);

Future<void> _loaded(ProviderContainer container) async {
  final ready = Completer<void>();
  final sub = container.listen(prepProfilesProvider, (_, state) {
    if (!state.isLoading && !ready.isCompleted) ready.complete();
  }, fireImmediately: true);
  await ready.future;
  sub.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late _PickerRepository repo;

  /// What Prep asked Premium for, with whether the ad unlock was offered,
  /// and what the stand-in sheet answers.
  late List<(String, bool)> asked;
  late bool grant;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('prep_flow_');
    repo = _PickerRepository();
    asked = [];
    grant = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    repo.dispose();
    directory.deleteSync(recursive: true);
  });

  test(
    'attachments persist, cannot be shared, and retain a detached FIDE lock',
    () async {
      final container = ProviderContainer(
        overrides: [prepRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      await _loaded(container);
      final profiles = container.read(prepProfilesProvider.notifier);
      final profile = profiles.create(
        kind: PrepKind.opponent,
        name: 'Club Player',
        accounts: [],
      );
      final database = PrepAccount.fromPlayer(databasePlayer);
      const online = PrepAccount(
        source: PrepSource.lichess,
        username: 'ClubPlayer',
      );
      profiles.attach(profile.id, [database, online]);
      final other = profiles.create(
        kind: PrepKind.opponent,
        name: 'Other',
        accounts: [],
      );
      expect(
        () => profiles.attach(other.id, [online]),
        throwsA(isA<PrepException>()),
      );
      expect(
        () => profiles.attach(profile.id, [online]),
        throwsA(isA<PrepException>()),
      );
      await profiles.removeAccount(profile.id, database);
      expect(profiles.byId(profile.id)!.accounts.single.key, online.key);
      expect(profiles.byId(profile.id)!.fideId, databasePlayer.fideId);
      final different = PrepAccount.fromPlayer(
        databasePlayer.copyWith(id: 'different', fideId: '999'),
      );
      expect(
        () => profiles.attach(profile.id, [different]),
        throwsA(isA<PrepException>()),
      );
      profiles.attach(profile.id, [database]);
      profiles.attach(profile.id, [
        const PrepAccount(
          source: PrepSource.lichess,
          username: 'SecondAccount',
        ),
      ]);
      await profiles.debugDrainWrites();
      final json = jsonDecode(
        await File('${directory.path}/prep/profiles.json').readAsString(),
      );
      final restored = (json['profiles'] as List)
          .map(PrepProfile.fromJson)
          .whereType<PrepProfile>();
      expect(
        restored.firstWhere((p) => p.id == profile.id).accounts,
        hasLength(3),
      );
    },
  );

  test(
    'detaching waits for downloads to stop and cannot resurrect the source',
    () async {
      final container = ProviderContainer(
        overrides: [prepRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      await _loaded(container);
      final profiles = container.read(prepProfilesProvider.notifier);
      const account = PrepAccount(
        source: PrepSource.lichess,
        username: 'ClubPlayer',
      );
      final profile = profiles.create(
        kind: PrepKind.opponent,
        name: 'ClubPlayer',
        accounts: [account],
      );
      final file = await repo.gamesFile(account);
      await file.writeAsString(sourceGame('ClubPlayer', 'Opponent'));
      repo.deferSync = true;
      final pending = container
          .read(prepSyncProvider.notifier)
          .syncAccount(profile.id, account);
      await repo.syncStarted.future;
      await profiles.removeAccount(profile.id, account);
      expect(await pending, isNull);
      expect(profiles.byId(profile.id)!.accounts, isEmpty);
      expect(await file.exists(), isFalse);
      expect(container.read(prepSyncProvider), isEmpty);
      await profiles.debugDrainWrites();
    },
  );

  test(
    'leaving the app mid-download pauses it and continues on return',
    () async {
      final binding = TestWidgetsFlutterBinding.instance;
      void move(List<AppLifecycleState> states) {
        for (final state in states) {
          binding.handleAppLifecycleStateChanged(state);
        }
      }

      move([AppLifecycleState.resumed]);
      final container = ProviderContainer(
        overrides: [prepRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      await _loaded(container);
      final profiles = container.read(prepProfilesProvider.notifier);
      const account = PrepAccount(
        source: PrepSource.lichess,
        username: 'ClubPlayer',
      );
      final profile = profiles.create(
        kind: PrepKind.opponent,
        name: 'ClubPlayer',
        accounts: [account],
      );
      final gate = repo.syncGate = Completer<void>();
      repo.syncFailure = const PrepException('Could not download games.');
      final pending = container
          .read(prepSyncProvider.notifier)
          .syncAccount(profile.id, account, force: true);
      // The system cuts the connection off once the app is in the background.
      move([AppLifecycleState.inactive, AppLifecycleState.hidden]);
      gate.complete();
      await pumpEventQueue();
      expect(
        container.read(prepSyncProvider)[account.key]?.message,
        startsWith('Paused'),
      );
      expect(profiles.byId(profile.id)!.accounts.single.error, isNull);
      expect(repo.syncCalls, 1);

      repo
        ..syncGate = null
        ..syncFailure = null;
      move([AppLifecycleState.inactive, AppLifecycleState.resumed]);
      expect(await pending, isNull);
      expect(repo.syncCalls, 2);
      expect(profiles.byId(profile.id)!.accounts.single.error, isNull);
      expect(container.read(prepSyncProvider), isEmpty);
      await profiles.debugDrainWrites();
    },
  );

  test(
    'source analysis retains a duplicate game removed from Combined',
    () async {
      final container = ProviderContainer(
        overrides: [prepRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      await _loaded(container);
      final profiles = container.read(prepProfilesProvider.notifier);
      const online = PrepAccount(
        source: PrepSource.lichess,
        username: 'ClubPlayer',
      );
      const imported = PrepAccount(
        source: PrepSource.manual,
        username: 'archive.pgn',
        externalId: 'import-1',
        playerAliases: ['ClubPlayer'],
      );
      final profile = profiles.create(
        kind: PrepKind.opponent,
        name: 'ClubPlayer',
        accounts: [online, imported],
      );
      final pgn = sourceGame(
        'ClubPlayer',
        'Opponent',
        site: 'https://lichess.org/duplicateFixture',
      );
      for (final account in [online, imported]) {
        await (await repo.gamesFile(account)).writeAsString(pgn);
      }
      final combined = await container.read(
        prepAnalysisProvider(profile.id).future,
      );
      final source = await container.read(
        prepSourceAnalysisProvider((
          profileId: profile.id,
          accountKey: imported.key,
        )).future,
      );
      expect(combined.games, hasLength(1));
      expect(source.games.single.source, PrepSource.manual);
      expect(source.pgnOf(source.games.single), contains('duplicateFixture'));
      expect(source.profileId, isNot(profile.id));
      // A source's cloud database uploads from the same independent index.
      final file = await repo.gamesFile(imported);
      expect(source.store!.rowsAfter(file.path, -1), hasLength(1));
      await profiles.delete(profile.id);
      await profiles.debugDrainWrites();
    },
  );

  Future<ProviderContainer> pump(
    WidgetTester tester,
    Widget child, {
    bool light = false,
    bool premium = false,
    double scale = 1,
    List<FavoritePlayer> follows = const [],
    List<Override> overrides = const [],
    GlobalKey<NavigatorState>? navigatorKey,
    RouteFactory? onGenerateRoute,
    SubscriptionNotifier Function()? subscription,
  }) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(
      overrides: [
        prepRepositoryProvider.overrideWithValue(repo),
        // A real subscription state decides Premium and the limits itself.
        if (subscription != null)
          subscriptionProvider.overrideWith((ref) => subscription())
        else ...[
          premiumAccessProvider.overrideWithValue(premium),
          // A Premium fixture is a subscriber: no limit applies either.
          prepUnlimitedProvider.overrideWithValue(premium),
        ],
        prepPremiumPromptProvider.overrideWithValue((
          _,
          feature, {
          required rewarded,
        }) async {
          asked.add((feature, rewarded));
          return grant;
        }),
        favoritePlayersProviderNew.overrideWith(() => _Follows(follows)),
        spaceShortcutsProvider.overrideWith(_SpaceShortcuts.new),
        ...overrides,
      ],
    );
    addTearDown(container.dispose);
    await tester.runAsync(() => _loaded(container));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return child!;
              },
            ),
          ),
          navigatorKey: navigatorKey,
          onGenerateRoute: onGenerateRoute,
          home: child,
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  /// Lets a running attach reach its download prompt, then confirms it.
  Future<void> confirmDownload(
    WidgetTester tester, {
    required String subtitle,
  }) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Download games'), findsOneWidget);
    expect(find.text(subtitle), findsOneWidget);
    await tester.ensureVisible(find.text('Download'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
  }

  /// Taps a control of the add dialog, scrolling its card when a short
  /// screen leaves the control below the fold.
  Future<void> tapOnPage(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(
      target,
      100,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  /// Walks the add dialog's download pages, one per chosen account.
  Future<void> confirmScopes(WidgetTester tester, int pages) async {
    for (var page = 1; page <= pages; page++) {
      expect(find.text('Download games'), findsOneWidget);
      expect(
        find.text('$page/$pages'),
        pages > 1 ? findsOneWidget : findsNothing,
      );
      await tapOnPage(tester, find.text(page < pages ? 'Next' : 'Download'));
    }
  }

  for (final light in [false, true]) {
    testWidgets(
      'source picker creates an online-only profile in ${light ? 'light' : 'dark'} theme',
      (tester) async {
        PrepAddResult? result;
        await pump(
          tester,
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showPrepSourcePicker(
                    context,
                    kind: PrepKind.opponent,
                  );
                },
                child: const Text('Start'),
              ),
            ),
          ),
          light: light,
        );
        await tester.tap(find.text('Start'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Lichess'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('prep_source_query')),
          'ClubPlayer',
        );
        await tester.pump(const Duration(milliseconds: 450));
        await tester.pump();
        await tester.tap(find.text('Club Player'));
        await tester.pump();
        expect(find.text('Create profile'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Create profile'));
        await tester.pumpAndSettle();
        expect(find.text('ClubPlayer on Lichess'), findsOneWidget);
        await confirmScopes(tester, 1);
        expect(result?.accounts.single.source, PrepSource.lichess);
        // An online account starts on blitz and rapid, a year back.
        expect(
          result?.accounts.single.preferences,
          const PrepDownloadPreferences(
            timeControls: {PrepTimeControl.blitz, PrepTimeControl.rapid},
          ),
        );
        expect(result?.accounts.single.fideId, isNull);
        expect(result?.name, 'Club Player');
      },
    );
  }

  testWidgets('the add actions follow the selected My Prep tab', (
    tester,
  ) async {
    final container = await pump(
      tester,
      const MyPrepHomeScreen(),
      premium: true,
    );
    await tester.pumpAndSettle();
    for (final (tab, label, title) in [
      ('Games', 'Attach your username', 'Attach your usernames'),
      ('Profiles', 'Add opponent', 'Add an opponent'),
    ]) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(find.text('Attach username'), findsNothing);
      expect(find.byKey(const ValueKey('prep_add_top')), findsNothing);
      // With nothing added, a tab offers its add in the page; the floating
      // button waits for the first one.
      expect(find.byKey(const ValueKey('prep_add_floating')), findsNothing);
      expect(find.text(label), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('prep_add_empty')));
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('prep_source_cancel')));
      await tester.pumpAndSettle();
    }
    await tester.runAsync(() async {
      final profiles = container.read(prepProfilesProvider.notifier);
      profiles.create(
        kind: PrepKind.opponent,
        name: 'My study player',
        accounts: [],
      );
      await profiles.debugDrainWrites();
    });
    await tester.pumpAndSettle();
    expect(find.text('My study player'), findsOneWidget);
    expect(find.byKey(const ValueKey('prep_add_empty')), findsNothing);
    // The floating button offers the three sources, then asks in a dialog.
    final fab = find.byKey(const ValueKey('prep_add_floating'));
    expect(tester.widget<PopoverAddFab<PrepSource>>(fab).label, 'Add opponent');
    await tester.tap(fab);
    await tester.pumpAndSettle();
    for (final source in PrepSource.playerSources) {
      expect(find.text(source.label), findsOneWidget);
    }
    await tester.tap(find.text('Chess.com'));
    await tester.pumpAndSettle();
    expect(find.text('Add an opponent'), findsOneWidget);
    expect(find.byKey(const ValueKey('prep_source_query')), findsOneWidget);
    expect(find.text('Lichess'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('prep_source_cancel')));
    await tester.pumpAndSettle();
    // Players is a fixed ranking: no floating button and no in-page add.
    await tester.tap(find.text('Players'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('prep_add_floating')), findsNothing);
    expect(find.byKey(const ValueKey('prep_add_empty')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a ranked favorite joins Profiles through the add sheet with '
      'its known accounts chosen, and keeps its ranking slot', (tester) async {
    final container = await pump(
      tester,
      const MyPrepHomeScreen(),
      premium: true,
      overrides: [
        chessPlayerRepositoryProvider.overrideWithValue(_RankingRepository()),
      ],
    );
    await tester.tap(find.text('Players'));
    await tester.pumpAndSettle();
    PrepSourceMarks marks(String name) => tester.widget(
      find.descendant(
        of: find.ancestor(
          of: find.text(name),
          matching: find.byType(PrepProfileCard),
        ),
        matching: find.byType(PrepSourceMarks),
      ),
    );
    expect(marks('Unknown, Handle').sources, [PrepSource.chessever]);
    expect(marks('Carlsen, Magnus').sources, [
      PrepSource.chessever,
      PrepSource.chesscom,
      PrepSource.lichess,
    ]);
    // No row carries a menu button, added or not.
    expect(find.byType(CardMoreButton), findsNothing);
    await tester.tap(find.text('Carlsen, Magnus'));
    await tester.pumpAndSettle();
    // Nothing is created until the reader confirms what to download.
    expect(container.read(prepProfilesProvider).requireValue, isEmpty);
    expect(find.text('Add an opponent'), findsOneWidget);
    for (final key in [
      'chessever:player-uuid',
      'chesscom:magnuscarlsen',
      'lichess:drnykterstein',
    ]) {
      expect(find.byKey(ValueKey('prep_pending_$key')), findsOneWidget);
    }
    // One of the known accounts is dropped before anything downloads.
    await tester.tap(find.byTooltip('Remove DrNykterstein'));
    await tester.pump();
    await tapOnPage(tester, find.text('Create profile'));
    expect(find.text('1/2'), findsOneWidget);
    await tapOnPage(tester, find.text('Next'));
    expect(find.text('2/2'), findsOneWidget);
    // The added row keeps its download indicator turning.
    await tester.tap(find.text('Download'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final profile = container.read(prepProfilesProvider).requireValue.single;
    expect(profile.kind, PrepKind.opponent);
    expect(profile.favoriteId, 'carlsen');
    expect(profile.fideId, '1503014');
    expect(profile.accounts.map((a) => a.source), [
      PrepSource.chessever,
      PrepSource.chesscom,
    ]);
    // The added player stays where the ranking put them, named as before.
    final rows = tester
        .widgetList<PrepProfileCard>(find.byType(PrepProfileCard))
        .toList();
    expect(rows.map((card) => card.name), [
      'Carlsen, Magnus',
      'Unknown, Handle',
    ]);
    expect(rows.first.preview, isFalse);
    expect(find.byType(CardMoreButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the + on a Players row asks before anything is added or '
      'downloaded, with the known usernames already chosen', (tester) async {
    final container = await pump(
      tester,
      const MyPrepHomeScreen(),
      premium: true,
      overrides: [
        chessPlayerRepositoryProvider.overrideWithValue(_RankingRepository()),
      ],
    );
    await tester.tap(find.text('Players'));
    await tester.pumpAndSettle();
    Finder row(String name) => find.ancestor(
      of: find.text(name),
      matching: find.byType(PrepProfileCard),
    );
    Finder add(String name) =>
        find.descendant(of: row(name), matching: find.byType(CardActionButton));
    // Every row ends in the same button, on a full-size target.
    expect(find.byType(CardActionButton), findsNWidgets(2));
    expect(tester.getSize(add('Carlsen, Magnus')), const Size(44, 44));
    final before = tester.getRect(row('Carlsen, Magnus'));
    final nameBefore = tester.getRect(find.text('Carlsen, Magnus'));

    await tester.tap(add('Carlsen, Magnus'));
    await tester.pumpAndSettle();
    // The same sheet Profiles adds with: nothing exists yet, nothing runs.
    expect(find.text('Add an opponent'), findsOneWidget);
    expect(container.read(prepProfilesProvider).requireValue, isEmpty);
    expect(repo.syncCalls, 0);
    for (final key in [
      'chessever:player-uuid',
      'chesscom:magnuscarlsen',
      'lichess:drnykterstein',
    ]) {
      expect(find.byKey(ValueKey('prep_pending_$key')), findsOneWidget);
    }
    // Backing out leaves the list exactly as it was.
    await tester.tap(find.byKey(const ValueKey('prep_source_cancel')));
    await tester.pumpAndSettle();
    expect(container.read(prepProfilesProvider).requireValue, isEmpty);
    expect(repo.syncCalls, 0);
    expect(tester.getRect(row('Carlsen, Magnus')), before);
    expect(add('Carlsen, Magnus'), findsOneWidget);

    // Confirmed, the reader is asked what to download for each source.
    await tester.tap(add('Carlsen, Magnus'));
    await tester.pumpAndSettle();
    await tapOnPage(tester, find.text('Create profile'));
    expect(repo.syncCalls, 0);
    // One page per source, ChessEver included.
    await confirmScopes(tester, 3);
    await tester.pump(const Duration(milliseconds: 500));
    final profile = container.read(prepProfilesProvider).requireValue.single;
    expect(profile.kind, PrepKind.opponent);
    expect(profile.favoriteId, 'carlsen');
    expect(profile.fideId, '1503014');
    expect(profile.accounts.map((a) => a.source), [
      PrepSource.chessever,
      PrepSource.chesscom,
      PrepSource.lichess,
    ]);
    expect(repo.syncCalls, 3);
    expect(find.text('${profile.name} added to Profiles'), findsOneWidget);
    // The row holds its place and size; only its end mark changes.
    expect(tester.getRect(row('Carlsen, Magnus')), before);
    expect(tester.getRect(find.text('Carlsen, Magnus')), nameBefore);
    expect(add('Carlsen, Magnus'), findsNothing);
    expect(
      find.descendant(
        of: row('Carlsen, Magnus'),
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsOneWidget,
    );
    // The row reads its state out with the rest of its text.
    expect(find.bySemanticsLabel(RegExp('In Profiles')), findsOneWidget);

    // A player ChessEver cannot resolve, with no known handle, adds nothing.
    await tester.tap(add('Unknown, Handle'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(container.read(prepProfilesProvider).requireValue, hasLength(1));
    expect(add('Unknown, Handle'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('followed players lead the Players list under a heart, and the '
      'server decides whose usernames are known', (tester) async {
    await pump(
      tester,
      const MyPrepHomeScreen(initialTab: 2),
      premium: true,
      // Lower rated than the ranking's first, and still ahead of it.
      follows: [
        _follow('Followed, Second', 4242, 2500),
        _follow('Unknown, Handle', 99, 2600),
      ],
      overrides: [
        chessPlayerRepositoryProvider.overrideWithValue(_RankingRepository()),
        // The server withdrew Carlsen's Chess.com handle, renamed his
        // Lichess one and published one for a player the app never shipped.
        prepKnownAccountsProvider.overrideWith(
          (ref) async => {
            '1503014': [(PrepSource.lichess, 'ServerHandle')],
            '4242': [(PrepSource.chesscom, 'second_one')],
          },
        ),
      ],
    );
    await tester.pumpAndSettle();
    final cards = tester
        .widgetList<PrepProfileCard>(find.byType(PrepProfileCard))
        .toList();
    // Followed players first, in the order Favorites lists them, and once:
    // the one the ranking also holds does not appear again below.
    expect(cards.map((card) => card.name), [
      'Followed, Second',
      'Unknown, Handle',
      'Carlsen, Magnus',
    ]);
    Finder row(String name) => find.ancestor(
      of: find.text(name),
      matching: find.byType(PrepProfileCard),
    );
    Finder heart(String name) =>
        find.descendant(of: row(name), matching: find.byIcon(Icons.favorite));
    Finder add(String name) =>
        find.descendant(of: row(name), matching: find.byType(CardActionButton));
    for (final name in ['Followed, Second', 'Unknown, Handle']) {
      expect(heart(name), findsOneWidget);
      // The heart says where the player already is; the + is still there.
      expect(add(name), findsOneWidget);
      expect(tester.getSize(add(name)), const Size(44, 44));
    }
    expect(heart('Carlsen, Magnus'), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp('In your favorites')),
      findsNWidgets(2),
    );
    // Every row's + stands in one column, heart or not.
    expect(
      tester.getRect(add('Followed, Second')).left,
      tester.getRect(add('Carlsen, Magnus')).left,
    );
    PrepSourceMarks marks(String name) => tester.widget(
      find.descendant(of: row(name), matching: find.byType(PrepSourceMarks)),
    );
    expect(marks('Carlsen, Magnus').sources, [
      PrepSource.chessever,
      PrepSource.lichess,
    ]);
    expect(marks('Followed, Second').sources, [
      PrepSource.chessever,
      PrepSource.chesscom,
    ]);

    // The sheet is prefilled from the server's list, not the shipped one.
    await tester.tap(add('Carlsen, Magnus'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('prep_pending_lichess:serverhandle')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prep_pending_chesscom:magnuscarlsen')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('prep_source_cancel')));
    await tester.pumpAndSettle();

    // A handle finds its player, and the followed ones answer a search too.
    await tester.enterText(find.byType(TextField), 'second');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(row('Followed, Second'), findsOneWidget);
    expect(row('Unknown, Handle'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a chosen ChessEver player offers their known usernames, one '
      'tap each, and none is added unless tapped', (tester) async {
    PrepAddResult? result;
    await pump(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showPrepSourcePicker(
                context,
                kind: PrepKind.opponent,
                multiple: true,
              );
            },
            child: const Text('Start'),
          ),
        ),
      ),
      overrides: [
        prepKnownAccountsProvider.overrideWith(
          (ref) async => {
            '1503014': [
              (PrepSource.chesscom, 'MagnusCarlsen'),
              (PrepSource.lichess, 'DrNykterstein'),
              (PrepSource.lichess, 'SecondHandle'),
            ],
          },
        ),
      ],
    );
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    const chesscom = ValueKey('prep_suggested_chesscom:magnuscarlsen');
    const lichess = ValueKey('prep_suggested_lichess:drnykterstein');
    const second = ValueKey('prep_suggested_lichess:secondhandle');
    // Nothing is offered before a player is chosen.
    expect(find.text('Known accounts'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('prep_source_query')),
      '1503014',
    );
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    await tester.tap(find.text('Local Player'));
    await tester.pumpAndSettle();
    final player = find.byKey(
      const ValueKey('prep_pending_chessever:player-uuid'),
    );
    expect(player, findsOneWidget);
    // The offers sit right under the player they belong to, several of one
    // site included.
    expect(find.text('Known accounts'), findsOneWidget);
    for (final key in [chesscom, lichess, second]) {
      expect(find.byKey(key), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(key)).dy,
        greaterThan(tester.getBottomLeft(player).dy - 1),
      );
      expect(tester.getSize(find.byKey(key)).height, greaterThanOrEqualTo(44));
    }

    await tester.tap(find.byKey(lichess));
    await tester.pumpAndSettle();
    expect(find.byKey(lichess), findsNothing);
    expect(
      find.byKey(const ValueKey('prep_pending_lichess:drnykterstein')),
      findsOneWidget,
    );
    // Taken back out, it is on offer again.
    await tester.tap(find.byTooltip('Remove DrNykterstein'));
    await tester.pumpAndSettle();
    expect(find.byKey(lichess), findsOneWidget);
    await tester.tap(find.byKey(lichess));
    await tester.pumpAndSettle();

    // Typing a username by hand still works beside the offers.
    await tester.tap(find.text('Chess.com'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('prep_source_query')),
      'TypedByHand',
    );
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    await tester.tap(find.text('Club Player'));
    await tester.pumpAndSettle();

    await tapOnPage(tester, find.text('Create profile'));
    await confirmScopes(tester, 3);
    // Only what was tapped or typed: the two offers left alone are not.
    expect(result?.accounts.map((a) => a.key), [
      'chessever:player-uuid',
      'lichess:drnykterstein',
      'chesscom:typedbyhand',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('My Games attaches own usernames from both online sites', (
    tester,
  ) async {
    PrepAddResult? result;
    await pump(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showPrepSourcePicker(
                context,
                kind: PrepKind.mine,
                multiple: true,
              );
            },
            child: const Text('Start'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(find.text('Attach your usernames'), findsOneWidget);
    expect(find.byKey(const ValueKey('prep_source_query')), findsOneWidget);
    for (final source in [PrepSource.lichess, PrepSource.chesscom]) {
      await tester.tap(find.text(source.label));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('prep_source_query')),
        'ClubPlayer',
      );
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pump();
      await tester.tap(find.text('Club Player'));
      await tester.pump();
    }
    expect(find.text('Create profile'), findsNothing);
    expect(find.text('Attach 2 accounts'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('prep_attach_accounts')));
    await tester.pumpAndSettle();
    // The first page's arrow returns to the picker with both still queued.
    expect(find.text('1/2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('prep_scope_back')));
    await tester.pumpAndSettle();
    expect(find.text('Attach 2 accounts'), findsOneWidget);
    expect(result, isNull);
    await tester.tap(find.byKey(const ValueKey('prep_attach_accounts')));
    await tester.pumpAndSettle();
    // A choice made on one page survives a visit to the next and back.
    await tester.tap(find.text('Bullet'));
    await tester.pumpAndSettle();
    await tapOnPage(tester, find.text('Next'));
    expect(find.text('2/2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('prep_scope_back')));
    await tester.pumpAndSettle();
    await confirmScopes(tester, 2);
    expect(result?.accounts.first.preferences.timeControls, {
      PrepTimeControl.bullet,
      PrepTimeControl.blitz,
      PrepTimeControl.rapid,
    });
    expect(result?.accounts.last.preferences.timeControls, {
      PrepTimeControl.blitz,
      PrepTimeControl.rapid,
    });
    expect(result?.accounts.map((a) => a.source), [
      PrepSource.lichess,
      PrepSource.chesscom,
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the add sheet asks before an account past a limit joins', (
    tester,
  ) async {
    final asks = <int>[];
    await pump(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showPrepSourcePicker(
              context,
              kind: PrepKind.mine,
              multiple: true,
              // Room for one more account only.
              mayAdd: (chosen) async {
                asks.add(chosen);
                return chosen < 1;
              },
            ),
            child: const Text('Start'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    for (final source in [PrepSource.lichess, PrepSource.chesscom]) {
      await tester.tap(find.text(source.label));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('prep_source_query')),
        'ClubPlayer',
      );
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pump();
      await tester.tap(find.text('Club Player'));
      await tester.pumpAndSettle();
    }
    expect(asks, [0, 1]);
    expect(find.text('Attach account'), findsOneWidget);
    expect(find.text('Attach 2 accounts'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the add sheet rests on the bottom edge and back steps a page', (
    tester,
  ) async {
    PrepAddResult? result;
    var closed = false;
    await pump(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showPrepSourcePicker(
                context,
                kind: PrepKind.opponent,
                only: PrepSource.lichess,
                multiple: true,
              );
              closed = true;
            },
            child: const Text('Start'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    final sheet = find.byType(PagedSheet);
    expect(tester.getRect(sheet).bottom, 640);
    expect(tester.getRect(sheet).top, greaterThan(200));
    await tester.enterText(
      find.byKey(const ValueKey('prep_source_query')),
      'ClubPlayer',
    );
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    await tester.tap(find.text('Club Player'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('prep_attach_accounts')));
    await tester.pumpAndSettle();
    expect(find.text('Download games'), findsOneWidget);
    expect(tester.getRect(sheet).bottom, 640);
    // The system back gesture returns to the picker before it closes.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Download games'), findsNothing);
    expect(find.byKey(const ValueKey('prep_attach_accounts')), findsOneWidget);
    expect(closed, isFalse);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('database no-match still allows a named profile', (tester) async {
    PrepAddResult? result;
    await pump(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showPrepSourcePicker(
                context,
                kind: PrepKind.opponent,
              );
            },
            child: const Text('Start'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('prep_source_query')),
      'unlisted',
    );
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    await tester.tap(find.text('Create a profile by name'));
    await tester.pumpAndSettle();
    expect(result?.name, 'unlisted');
    expect(result?.accounts, isEmpty);
  });

  testWidgets('the selected profile form stays scrollable above the keyboard', (
    tester,
  ) async {
    PrepAddResult? result;
    await pump(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showPrepSourcePicker(
                context,
                kind: PrepKind.opponent,
              );
            },
            child: const Text('Start'),
          ),
        ),
      ),
      scale: 1.8,
    );
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chess.com'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('prep_source_query')),
      'ClubPlayer',
    );
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    await tester.tap(find.text('Club Player'));
    await tester.pump();
    tester.view.viewInsets = FakeViewPadding(
      bottom: 300 * tester.view.devicePixelRatio,
    );
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Create profile'),
      100,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create profile'));
    await tester.pumpAndSettle();
    await confirmScopes(tester, 1);
    expect(result?.accounts.single.source, PrepSource.chesscom);
  });

  testWidgets(
    'several usernames from both platforms attach together and persist',
    (tester) async {
      late PrepProfile profile;
      Future<void>? action;
      final container = await pump(
        tester,
        Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => action = prepAddAccountTo(context, ref, profile),
              child: const Text('Start'),
            ),
          ),
        ),
        premium: true,
      );
      final profiles = container.read(prepProfilesProvider.notifier);
      profile = (await tester.runAsync(() async {
        final created = profiles.create(
          kind: PrepKind.opponent,
          name: 'Club Player',
          accounts: [PrepAccount.fromPlayer(databasePlayer)],
        );
        await profiles.debugDrainWrites();
        return created;
      }))!;
      await tester.runAsync(() => tester.tap(find.text('Start')));
      await tester.pumpAndSettle();
      for (final source in [PrepSource.lichess, PrepSource.chesscom]) {
        await tester.tap(find.text(source.label));
        await tester.pumpAndSettle();
        for (final name in ['FirstHandle', 'SecondHandle']) {
          await tester.enterText(
            find.byKey(const ValueKey('prep_source_query')),
            name,
          );
          await tester.pump(const Duration(milliseconds: 450));
          await tester.pump();
          await tester.tap(
            find.byKey(ValueKey('${source.name}:${name.toLowerCase()}')),
          );
          await tester.pumpAndSettle();
        }
      }
      // Staging never mutates the existing profile before confirmation.
      expect(profiles.byId(profile.id)!.accounts, hasLength(1));
      expect(find.text('Attach 4 accounts'), findsOneWidget);
      // Case-insensitive duplicates cannot be queued twice.
      await tester.enterText(
        find.byKey(const ValueKey('prep_source_query')),
        'FIRSTHANDLE',
      );
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pump();
      expect(find.text('Already added'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chesscom:firsthandle')));
      await tester.pumpAndSettle();
      expect(find.text('Attach 4 accounts'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('prep_attach_accounts')));
      await tester.pumpAndSettle();
      // Each of the four accounts gets its own download page.
      await confirmScopes(tester, 4);
      await tester.runAsync(() => action!);
      final attached = profiles.byId(profile.id)!;
      expect(
        attached.accounts.where((a) => a.source == PrepSource.lichess),
        hasLength(2),
      );
      expect(
        attached.accounts.where((a) => a.source == PrepSource.chesscom),
        hasLength(2),
      );
      expect(attached.databaseAccount, isNotNull);
      // The download starts by itself; the database was already attached.
      expect(repo.syncCalls, 4);
      await tester.runAsync(() => profiles.debugDrainWrites());
      final persisted = jsonDecode(
        File('${directory.path}/prep/profiles.json').readAsStringSync(),
      );
      final restored = (persisted['profiles'] as List)
          .map(PrepProfile.fromJson)
          .whereType<PrepProfile>()
          .single;
      expect(
        restored.accounts.map((a) => a.key),
        attached.accounts.map((a) => a.key),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'staged accounts can be removed and cancelled without changing the profile',
    (tester) async {
      late PrepProfile profile;
      Future<void>? action;
      final container = await pump(
        tester,
        Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => action = prepAddAccountTo(
                context,
                ref,
                profile,
                source: PrepSource.lichess,
              ),
              child: const Text('Start'),
            ),
          ),
        ),
        premium: true,
        scale: 2,
      );
      final profiles = container.read(prepProfilesProvider.notifier);
      profile = (await tester.runAsync(() async {
        final created = profiles.create(
          kind: PrepKind.opponent,
          name: 'Club Player',
          accounts: [
            const PrepAccount(
              source: PrepSource.lichess,
              username: 'ExistingHandle',
            ),
          ],
        );
        await profiles.debugDrainWrites();
        return created;
      }))!;
      await tester.runAsync(() => tester.tap(find.text('Start')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('prep_source_query')),
        'ExistingHandle',
      );
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pump();
      expect(find.text('Already attached'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('lichess:existinghandle')));
      await tester.pump();
      expect(find.byKey(const ValueKey('prep_attach_accounts')), findsNothing);
      for (final name in ['RemoveMe', 'KeepStaged']) {
        await tester.enterText(
          find.byKey(const ValueKey('prep_source_query')),
          name,
        );
        await tester.pump(const Duration(milliseconds: 450));
        await tester.pump();
        await tester.tap(find.byKey(ValueKey('lichess:${name.toLowerCase()}')));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.byTooltip('Remove RemoveMe'));
      await tester.tap(find.byTooltip('Remove RemoveMe'));
      await tester.pumpAndSettle();
      expect(find.text('Attach account'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('prep_source_cancel')));
      await tester.pumpAndSettle();
      await tester.runAsync(() => action!);
      expect(
        profiles.byId(profile.id)!.accounts.single.username,
        'ExistingHandle',
      );
      expect(tester.takeException(), isNull);
      await tester.runAsync(() => profiles.debugDrainWrites());
    },
  );

  testWidgets('changing one username still replaces only that account', (
    tester,
  ) async {
    const account = PrepAccount(
      source: PrepSource.chesscom,
      username: 'OldHandle',
    );
    late PrepProfile profile;
    Future<void>? action;
    final container = await pump(
      tester,
      Scaffold(
        body: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () =>
                action = prepChangeAccount(context, ref, profile, account),
            child: const Text('Start'),
          ),
        ),
      ),
      premium: true,
    );
    final profiles = container.read(prepProfilesProvider.notifier);
    profile = (await tester.runAsync(() async {
      final created = profiles.create(
        kind: PrepKind.opponent,
        name: 'Club Player',
        accounts: [
          account,
          const PrepAccount(
            source: PrepSource.chesscom,
            username: 'OtherHandle',
          ),
        ],
      );
      await profiles.debugDrainWrites();
      return created;
    }))!;
    await tester.runAsync(() => tester.tap(find.text('Start')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('prep_source_query')),
      'NewHandle',
    );
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chesscom:newhandle')));
    await tester.pumpAndSettle();
    expect(find.text('Attach source'), findsOneWidget);
    await tester.tap(find.text('Attach source'));
    await tester.pumpAndSettle();
    // The account it replaces was never downloaded, so this one asks.
    await confirmDownload(tester, subtitle: 'NewHandle on Chess.com');
    await tester.runAsync(() => action!);
    await tester.runAsync(() => profiles.debugDrainWrites());
    await tester.pumpAndSettle();
    expect(profiles.byId(profile.id)!.accounts.map((a) => a.username), [
      'OtherHandle',
      'NewHandle',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'source actions and profile rating columns fit narrow phones with large text',
    (tester) async {
      const profile = PrepProfile(
        id: 'p',
        kind: PrepKind.opponent,
        name: 'Club Player',
        createdAtMs: 1,
        accounts: [
          PrepAccount(
            source: PrepSource.lichess,
            username: 'ClubPlayer',
            gameCount: 12,
            ratings: {'bullet': 1800, 'rapid': 2000, 'blitz': 1900},
          ),
        ],
      );
      await pump(
        tester,
        const PrepSourcesScreen(profileId: 'p'),
        scale: 2,
        overrides: [prepProfileProvider.overrideWith((ref, id) => profile)],
      );
      expect(find.text('ClubPlayer'), findsOneWidget);
      expect(find.byKey(const ValueKey('prep_download_scope')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('prep_add_source')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('prep_attach_chessever')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('prep_attach_lichess')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(10, 600));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('prep_account_lichess:clubplayer')),
      );
      await tester.pumpAndSettle();
      // Ratings and the download scope are on the card, not behind a tap.
      expect(find.byKey(const ValueKey('prep_download_scope')), findsOneWidget);
      await tester.ensureVisible(find.text('1900'));
      expect(find.text('1900'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Both actions fit, stacked, and the popup leaves by its close button.
      await tester.ensureVisible(find.text('Go to profile'));
      expect(find.text('Download games'), findsOneWidget);
      expect(find.text('Close'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byTooltip('Close'));
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('prep_download_scope')), findsNothing);
      await pump(
        tester,
        Scaffold(
          body: PrepIdentity(profile: profile, onRating: (_) {}),
        ),
        scale: 2,
      );
      expect(find.text('1900'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a source popup steps to its download options and back in place',
    (tester) async {
      const account = PrepAccount(
        source: PrepSource.chesscom,
        username: 'SecondAccount',
      );
      const profile = PrepProfile(
        id: 'p',
        kind: PrepKind.opponent,
        name: 'Club Player',
        createdAtMs: 1,
        accounts: [account],
      );
      await pump(
        tester,
        const PrepSourcesScreen(profileId: 'p'),
        premium: true,
        overrides: [prepProfileProvider.overrideWith((ref, id) => profile)],
      );
      final scope = find.byKey(const ValueKey('prep_download_scope'));
      await tester.tap(
        find.byKey(const ValueKey('prep_account_chesscom:secondaccount')),
      );
      await tester.pumpAndSettle();
      expect(find.text('1/2'), findsOneWidget);
      // A first download offers its scope on the popup's second page.
      await tester.tap(find.text('Download games'));
      await tester.pumpAndSettle();
      expect(find.text('2/2'), findsOneWidget);
      expect(find.text('SecondAccount on Chess.com'), findsOneWidget);
      expect(find.text('Time controls'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);
      expect(scope, findsNothing);
      expect(repo.syncCalls, 0);
      // Cancel steps back to the details; the popup stays open.
      await tester.ensureVisible(find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('1/2'), findsOneWidget);
      expect(find.text('Time controls'), findsNothing);
      await tester.tap(scope);
      await tester.pumpAndSettle();
      expect(find.text('Download options'), findsOneWidget);
      expect(find.text('SecondAccount on Chess.com'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(repo.syncCalls, 0);
      await tester.tap(find.byKey(const ValueKey('prep_source_back')));
      await tester.pumpAndSettle();
      expect(scope, findsOneWidget);
      // The system back gesture steps back a page before it leaves.
      await tester.tap(scope);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(scope, findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(scope, findsNothing);
      expect(find.text('Sources'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'refreshing a source reports inside its popup, which then opens the profile',
    (tester) async {
      late PrepProfile profile;
      late PrepProfilesNotifier profiles;
      var profileOpened = 0;
      final container = await pump(
        tester,
        Consumer(
          builder: (context, ref, _) {
            final live = ref.watch(prepProfilesProvider).valueOrNull ?? [];
            return Scaffold(
              body: live.isEmpty
                  ? const SizedBox.shrink()
                  : PrepAccountRow(
                      profile: live.single,
                      account: live.single.accounts.single,
                      onOpenProfile: () => profileOpened++,
                    ),
            );
          },
        ),
        premium: true,
      );
      profiles = container.read(prepProfilesProvider.notifier);
      profile = (await tester.runAsync(() async {
        final created = profiles.create(
          kind: PrepKind.opponent,
          name: 'Club Player',
          accounts: [
            PrepAccount.fromPlayer(
              databasePlayer,
            ).copyWith(gameCount: 12, lastSyncAtMs: 1),
          ],
        );
        await profiles.debugDrainWrites();
        return created;
      }))!;
      await tester.pump();
      final account = profile.accounts.single;
      repo.deferSync = true;
      await tester.tap(find.byKey(ValueKey('prep_account_${account.key}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Refresh games'));
      // The spinner never settles: pump by hand while the download runs.
      await tester.pump();
      await tester.pump();
      // The popup stays open and carries the progress itself.
      expect(repo.syncCalls, 1);
      expect(find.text('Stop download'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('prep_source_progress')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('prep_source_primary')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Stop download'));
      await tester.pump();
      await tester.pump();
      expect(container.read(prepSyncProvider), isEmpty);
      expect(find.text('Refresh games'), findsOneWidget);
      await tester.tap(find.text('Go to profile'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Refresh games'), findsNothing);
      expect(profileOpened, 1);
      await tester.runAsync(() => profiles.debugDrainWrites());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('without a subscription Profiles holds one opponent and My '
      'Games three of your own accounts', (tester) async {
    final container = await pump(tester, const MyPrepHomeScreen());
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final profiles = container.read(prepProfilesProvider.notifier);
      profiles.create(kind: PrepKind.opponent, name: 'Rival', accounts: []);
      profiles.create(
        kind: PrepKind.mine,
        name: 'Me',
        accounts: const [
          PrepAccount(source: PrepSource.lichess, username: 'mine-one'),
          PrepAccount(source: PrepSource.lichess, username: 'mine-two'),
          PrepAccount(source: PrepSource.chesscom, username: 'mine-three'),
        ],
      );
      await profiles.debugDrainWrites();
    });
    await tester.pumpAndSettle();
    final fab = find.byKey(const ValueKey('prep_add_floating'));

    // A fourth account of your own asks for the subscription, not an ad.
    await tester.tap(fab);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lichess').last);
    await tester.pumpAndSettle();
    expect(asked, [('prep_own_accounts', false)]);
    expect(find.text('Attach your usernames'), findsNothing);

    // So does a second opponent.
    await tester.tap(find.text('Profiles'));
    await tester.pumpAndSettle();
    expect(find.text('Rival'), findsOneWidget);
    await tester.tap(fab);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chess.com').last);
    await tester.pumpAndSettle();
    expect(asked.last, ('prep_opponents', false));
    expect(find.text('Add an opponent'), findsNothing);

    // Subscribed, the sheet opens.
    grant = true;
    await tester.tap(fab);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chess.com').last);
    await tester.pumpAndSettle();
    expect(find.text('Add an opponent'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('prep_source_cancel')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a free reader watches an ad or subscribes before statistics, '
      'Games and Build Tree open', (tester) async {
    const account = PrepAccount(
      source: PrepSource.lichess,
      username: 'ClubPlayer',
    );
    const profile = PrepProfile(
      id: 'p',
      kind: PrepKind.opponent,
      name: 'Club Player',
      createdAtMs: 1,
      accounts: [account],
    );
    final games = [
      for (var i = 0; i < 3; i++)
        PrepGame(
          index: i,
          source: account.source,
          sourcePath: PrepRepository.gamesFileName(account),
          white: 'ClubPlayer',
          black: 'Opponent $i',
          result: i == 0 ? '0-1' : '1-0',
          plies: 4,
          speed: PrepTimeControl.rapid,
          playerIsWhite: true,
        ),
    ];
    await pump(
      tester,
      const PrepProfileScreen(profileId: 'p'),
      overrides: [
        prepProfileProvider.overrideWith((ref, id) => profile),
        prepAnalysisProvider.overrideWith(
          (ref, id) async => PrepAnalysis(profileId: id, games: games),
        ),
      ],
    );
    await tester.pumpAndSettle();
    // The summary is free to read.
    expect(find.text('Games analyzed'), findsOneWidget);

    // Declined, each stays as it was.
    await tester.tap(find.text('Wins'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('prep_filter_banner')), findsNothing);
    await tester.tap(find.text('Performance by colour'));
    await tester.pumpAndSettle();
    expect(find.text('Their White'), findsNothing);
    await tester.tap(find.text('Games'));
    await tester.pumpAndSettle();
    expect(find.byType(PrepGamesTab), findsNothing);
    await tester.tap(find.text('Build Tree'));
    await tester.pumpAndSettle();
    expect(find.text('Opening trees'), findsNothing);
    expect(asked, [
      ('prep_statistics', true),
      ('prep_statistics', true),
      ('prep_games', true),
      ('build_tree', true),
    ]);
    // Nor can a swipe slide Games in.
    await tester.drag(find.text('Games analyzed'), const Offset(-280, 0));
    await tester.pumpAndSettle();
    expect(find.text('Games analyzed'), findsOneWidget);
    expect(find.byType(PrepGamesTab), findsNothing);

    // An ad watched, each opens.
    grant = true;
    await tester.tap(find.text('Performance by colour'));
    await tester.pumpAndSettle();
    expect(find.text('Their White'), findsOneWidget);
    await tester.tap(find.text('Wins'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('prep_filter_banner')), findsOneWidget);
    // The tab names the two wins the choice leaves.
    await tester.tap(find.text('Games 2'));
    await tester.pumpAndSettle();
    expect(find.byType(PrepGamesTab), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a subscriber without a connection opens statistics, Games and '
      'Build Tree with no ad prompt', (tester) async {
    const account = PrepAccount(
      source: PrepSource.lichess,
      username: 'ClubPlayer',
    );
    const profile = PrepProfile(
      id: 'p',
      kind: PrepKind.opponent,
      name: 'Club Player',
      createdAtMs: 1,
      accounts: [account],
    );
    final games = [
      for (var i = 0; i < 3; i++)
        PrepGame(
          index: i,
          source: account.source,
          sourcePath: PrepRepository.gamesFileName(account),
          white: 'ClubPlayer',
          black: 'Opponent $i',
          result: i == 0 ? '0-1' : '1-0',
          plies: 4,
          speed: PrepTimeControl.rapid,
          playerIsWhite: true,
        ),
    ];
    final now = DateTime.now();
    // Neither RevenueCat nor the entitlement function answers; only the
    // Premium this device confirmed while it was last online remains.
    final container = await pump(
      tester,
      const PrepProfileScreen(profileId: 'p'),
      subscription: () => SubscriptionNotifier(
        revenueCat: OfflineRevenueCat(() async => null),
        offlineCache: MemoryPremiumCache({
          'reader': OfflinePremiumSnapshot(
            verifiedAt: now.subtract(const Duration(days: 1)),
            expiresAt: now.add(const Duration(days: 20)),
          ),
        }),
        currentUserId: () => 'reader',
      ),
      overrides: [
        prepProfileProvider.overrideWith((ref, id) => profile),
        prepAnalysisProvider.overrideWith(
          (ref, id) async => PrepAnalysis(profileId: id, games: games),
        ),
      ],
    );
    await tester.pumpAndSettle();
    expect(container.read(subscriptionProvider).isSubscribed, isTrue);

    await tester.tap(find.text('Performance by colour'));
    await tester.pumpAndSettle();
    expect(find.text('Their White'), findsOneWidget);
    await tester.tap(find.text('Wins'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('prep_filter_banner')), findsOneWidget);
    await tester.tap(find.text('Games 2'));
    await tester.pumpAndSettle();
    expect(find.byType(PrepGamesTab), findsOneWidget);
    await tester.tap(find.text('Build Tree'));
    await tester.pumpAndSettle();
    expect(find.text('Opening trees'), findsOneWidget);
    expect(asked, isEmpty);
    expect(tester.takeException(), isNull);
    // The notifier's hourly sync timer goes with the container.
    container.dispose();
  });

  group('a "new games" push opens the profile on Games', () {
    const account = PrepAccount(
      source: PrepSource.lichess,
      username: 'durarbayli',
    );
    const profile = PrepProfile(
      id: 'p',
      kind: PrepKind.opponent,
      name: 'Vasif Durarbayli',
      createdAtMs: 1,
      accounts: [account],
    );
    final games = [
      for (var i = 0; i < 2; i++)
        PrepGame(
          index: i,
          source: account.source,
          sourcePath: PrepRepository.gamesFileName(account),
          white: 'durarbayli',
          black: 'Opponent $i',
          result: '1-0',
          plies: 4,
          speed: PrepTimeControl.blitz,
          playerIsWhite: true,
        ),
    ];
    final overrides = [
      prepProfileProvider.overrideWith((ref, id) => profile),
      prepAnalysisProvider.overrideWith(
        (ref, id) async => PrepAnalysis(profileId: id, games: games),
      ),
    ];

    testWidgets('a Premium reader lands on Games at once', (tester) async {
      await pump(
        tester,
        const PrepProfileScreen(
          profileId: 'p',
          initialTab: prepProfileGamesTab,
        ),
        premium: true,
        overrides: overrides,
      );
      await tester.pumpAndSettle();
      expect(find.byType(PrepGamesTab), findsOneWidget);
      expect(asked, isEmpty);
      expect(tester.takeException(), isNull);
    });

    for (final granted in [false, true]) {
      testWidgets('a free reader is asked first, as the tab asks '
          '(${granted ? 'granted' : 'declined'})', (tester) async {
        grant = granted;
        await pump(
          tester,
          const PrepProfileScreen(
            profileId: 'p',
            initialTab: prepProfileGamesTab,
          ),
          overrides: overrides,
        );
        await tester.pumpAndSettle();
        expect(asked, [('prep_games', true)]);
        expect(
          find.byType(PrepGamesTab),
          granted ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('Games analyzed'),
          granted ? findsNothing : findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('opened any other way it starts on About', (tester) async {
      await pump(
        tester,
        const PrepProfileScreen(profileId: 'p'),
        premium: true,
        overrides: overrides,
      );
      await tester.pumpAndSettle();
      expect(find.text('Games analyzed'), findsOneWidget);
      expect(find.byType(PrepGamesTab), findsNothing);
    });
  });

  group('tapping a Prep "new games" push, through the notification router', () {
    const account = PrepAccount(
      source: PrepSource.lichess,
      username: 'durarbayli',
    );
    const player = PrepProfile(
      id: 'vasif',
      kind: PrepKind.opponent,
      name: 'Vasif Durarbayli',
      createdAtMs: 1,
      accounts: [account],
    );
    final games = [
      for (var i = 0; i < 2; i++)
        PrepGame(
          index: i,
          source: account.source,
          sourcePath: PrepRepository.gamesFileName(account),
          white: 'durarbayli',
          black: 'Opponent $i',
          result: '1-0',
          plies: 4,
          speed: PrepTimeControl.blitz,
          playerIsWhite: true,
        ),
    ];

    /// The app with [profiles] on the device, and the tap of the push
    /// onesignal-dispatch sends (FCM: every value a string).
    Future<_WatchRemote> tapPush(
      WidgetTester tester,
      List<PrepProfile> profiles,
    ) async {
      File('${directory.path}/prep/profiles.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'profiles': [for (final p in profiles) p.toJson()],
          }),
        );
      final remote = _WatchRemote();
      final navigatorKey = GlobalKey<NavigatorState>();
      late WidgetRef captured;
      DeepLinkService.instance.dispose();
      addTearDown(DeepLinkService.instance.detachNotificationRouter);
      addTearDown(DeepLinkService.instance.dispose);
      final host = Consumer(
        builder: (_, ref, _) {
          captured = ref;
          return const SizedBox.shrink();
        },
      );
      await pump(
        tester,
        host,
        premium: true,
        navigatorKey: navigatorKey,
        onGenerateRoute: (settings) =>
            MaterialPageRoute<void>(settings: settings, builder: (_) => host),
        overrides: [
          prepWatchRemoteProvider.overrideWithValue(remote),
          prepAnalysisProvider.overrideWith(
            (ref, id) async => PrepAnalysis(profileId: id, games: games),
          ),
        ],
      );
      DeepLinkService.instance.attachNotificationRouter(navigatorKey, captured);
      DeepLinkService.notifyAppReady();
      DeepLinkService.instance.ingestNotificationData(const {
        'type': 'prep_games_added',
        'prep_profile_id': 'vasif',
        'added': '7',
        // Added by the notification service on the way to the phone.
        'url': '',
        'delivery_id': '5b1c9f0e-0d1a-4c7e-9a52-0f3c6d2e8a11',
        'campaign_id': '856a94b6-a8e3-4529-9abb-b344b431c8bd',
      });
      await tester.pumpAndSettle();
      return remote;
    }

    testWidgets('a starred player opens on their Games tab', (tester) async {
      final remote = await tapPush(tester, [player.copyWith(watching: true)]);
      final screen = tester.widget<PrepProfileScreen>(
        find.byType(PrepProfileScreen),
      );
      expect(screen.profileId, 'vasif');
      expect(screen.initialTab, prepProfileGamesTab);
      expect(screen.newGames, 7);
      expect(find.byType(PrepGamesTab), findsOneWidget);
      expect(find.text('Vasif Durarbayli played 7 new games.'), findsOneWidget);
      expect(remote.calls.where((c) => c.startsWith('unwatch')), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a player no longer starred here opens My Prep and stops the '
        'pushes', (tester) async {
      final remote = await tapPush(tester, [player]);
      expect(find.byType(PrepProfileScreen), findsNothing);
      expect(find.byType(MyPrepHomeScreen), findsOneWidget);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      expect(remote.calls, contains('unwatch vasif'));
    });
  });

  testWidgets('a free reader is asked before a Prep database in the Library '
      'lists its games', (tester) async {
    const account = PrepAccount(
      source: PrepSource.lichess,
      username: 'ClubPlayer',
    );
    const profile = PrepProfile(
      id: 'p',
      kind: PrepKind.opponent,
      name: 'Club Player',
      createdAtMs: 1,
      accounts: [account],
    );
    await pump(
      tester,
      const PrepLibraryFolderScreen(profileId: 'p'),
      overrides: [
        prepProfileProvider.overrideWith((ref, id) => profile),
        prepAnalysisProvider.overrideWith(
          (ref, id) async => PrepAnalysis(profileId: id, games: const []),
        ),
      ],
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Combined'));
    await tester.pumpAndSettle();
    expect(asked, [('prep_games', true)]);
    expect(find.byType(PrepLibraryDatabaseScreen), findsNothing);

    grant = true;
    await tester.tap(find.text('Combined'));
    await tester.pumpAndSettle();
    expect(find.byType(PrepLibraryDatabaseScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Build Tree remains usable when games analysis fails', (
    tester,
  ) async {
    const profile = PrepProfile(
      id: 'p',
      kind: PrepKind.opponent,
      name: 'Unlisted Player',
      createdAtMs: 1,
    );
    await pump(
      tester,
      const PrepProfileScreen(profileId: 'p'),
      premium: true,
      overrides: [
        prepProfileProvider.overrideWith((ref, id) => profile),
        prepAnalysisProvider.overrideWith(
          (ref, id) async => throw StateError('fixture failure'),
        ),
      ],
    );
    await tester.pump();
    await tester.tap(find.text('Build Tree'));
    await tester.pumpAndSettle();
    expect(find.text('Opening trees'), findsOneWidget);
    expect(find.text('Combined'), findsOneWidget);
    expect(find.text('Attach a source'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final light in [false, true]) {
    testWidgets(
      'tree filters apply to every tree and cancel or reset in ${light ? 'light' : 'dark'} theme',
      (tester) async {
        const profile = PrepProfile(
          id: 'p',
          kind: PrepKind.opponent,
          name: 'ClubPlayer',
          createdAtMs: 1,
          accounts: [
            PrepAccount(
              source: PrepSource.lichess,
              username: 'ClubPlayer',
              gameCount: 12,
            ),
          ],
        );
        await pump(
          tester,
          Scaffold(
            body: PrepTreesTab(profile: profile, onSources: () {}),
          ),
          light: light,
          scale: 2,
          overrides: [
            gameTreeBuiltProvider.overrideWith((ref, scope) async => false),
          ],
        );
        await tester.pumpAndSettle();
        Iterable<BuildTreeButton> buttons() =>
            tester.widgetList<BuildTreeButton>(find.byType(BuildTreeButton));
        expect(buttons(), hasLength(2));
        expect(find.text('Both colours'), findsNothing);
        expect(find.text('All clocks'), findsNothing);
        expect(find.text('Sources'), findsNothing);

        await tester.tap(find.byTooltip('Filter opening trees'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Both colours'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Their Black').last);
        await tester.pumpAndSettle();
        await Scrollable.ensureVisible(
          tester.element(find.text('All clocks')),
          alignment: 0.5,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('All clocks'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Blitz').last);
        await tester.pumpAndSettle();
        expect(buttons().every((b) => b.color == null), isTrue);
        expect(buttons().every((b) => b.timeControl == null), isTrue);
        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();
        expect(
          buttons().every((b) => b.color == GamebasePlayerColor.black),
          isTrue,
        );
        expect(
          buttons().every((b) => b.timeControl == TimeControl.blitz),
          isTrue,
        );
        expect(find.text('Their Black · Blitz'), findsOneWidget);

        await tester.tap(find.byTooltip('Filter opening trees'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Their Black'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Their White').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Close filters'));
        await tester.pumpAndSettle();
        expect(
          buttons().every((b) => b.color == GamebasePlayerColor.black),
          isTrue,
        );

        await tester.tap(find.byTooltip('Filter opening trees'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reset'));
        await tester.pumpAndSettle();
        expect(buttons().every((b) => b.color == null), isTrue);
        expect(buttons().every((b) => b.timeControl == null), isTrue);
        expect(find.text('Their Black · Blitz'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'About keeps combined results after a source filter in ${light ? 'light' : 'dark'} theme',
      (tester) async {
        const online = PrepAccount(
          source: PrepSource.lichess,
          username: 'ClubPlayer',
          ratings: {'rapid': 1900},
        );
        const other = PrepAccount(
          source: PrepSource.chesscom,
          username: 'ClubPlayer',
        );
        const empty = PrepAccount(
          source: PrepSource.chesscom,
          username: 'NoGames',
        );
        const profile = PrepProfile(
          id: 'p',
          kind: PrepKind.opponent,
          name: 'Club Player',
          createdAtMs: 1,
          accounts: [online, other, empty],
        );
        final games = [
          PrepGame(
            index: 0,
            source: online.source,
            sourcePath: PrepRepository.gamesFileName(online),
            white: 'ClubPlayer',
            black: 'Opponent',
            result: '1-0',
            plies: 4,
            speed: PrepTimeControl.rapid,
            playerIsWhite: true,
          ),
          for (final i in [1, 2])
            PrepGame(
              index: i,
              source: other.source,
              sourcePath: PrepRepository.gamesFileName(other),
              white: 'ClubPlayer',
              black: 'Opponent $i',
              result: '0-1',
              plies: 4,
              speed: PrepTimeControl.blitz,
              playerIsWhite: true,
            ),
        ];
        await pump(
          tester,
          const PrepProfileScreen(profileId: 'p'),
          light: light,
          scale: 2,
          premium: true,
          overrides: [
            prepProfileProvider.overrideWith((ref, id) => profile),
            prepAnalysisProvider.overrideWith(
              (ref, id) async => PrepAnalysis(profileId: id, games: games),
            ),
            prepSourceAnalysisProvider.overrideWith(
              (ref, scope) async => PrepAnalysis(
                profileId: scope.profileId,
                games: scope.accountKey == empty.key ? [] : [games.first],
              ),
            ),
          ],
        );
        await tester.pumpAndSettle();
        expect(find.text('Overall Performance'), findsOneWidget);
        expect(find.text('3'), findsOneWidget);
        expect(find.textContaining('Ratings from'), findsNothing);
        expect(find.text('Sources'), findsNothing);
        expect(
          find.byTooltip('Filter and sort games').hitTestable(),
          findsNothing,
        );

        // A rating narrows About to its clock where it stands, and the
        // Games tab says how many games that leaves.
        await tester.tap(find.text('1900'));
        await tester.pumpAndSettle();
        expect(find.byType(PrepGamesTab), findsNothing);
        expect(find.text('Overall Performance'), findsOneWidget);
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('prep_filter_count')))
              .data,
          '1 of 3',
        );
        expect(find.text('Games 1'), findsOneWidget);

        await tester.tap(find.text('Games 1'));
        await tester.pumpAndSettle();
        final tab = tester.widget<PrepGamesTab>(find.byType(PrepGamesTab));
        expect(tab.games, hasLength(1));
        expect(tab.filter.accountKey, isNull);
        expect(tab.filter.speed, PrepTimeControl.rapid);
        // Once Games is open its tab has nothing left to announce.
        expect(find.text('Games 1'), findsNothing);
        // The Games row is the player profile's: search, filters, layout.
        expect(
          find.byTooltip('Filter and sort games').hitTestable(),
          findsOneWidget,
        );

        await tester.tap(find.byTooltip('Filter and sort games'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('All attached sources').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Chess.com · NoGames').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();
        expect(find.text('No matching games'), findsOneWidget);
        expect(
          find.byTooltip('Filter and sort games').hitTestable(),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('Filter and sort games'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reset'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<PrepGamesTab>(find.byType(PrepGamesTab)).games,
          hasLength(3),
        );

        await tester.tap(find.text('About'));
        await tester.pumpAndSettle();
        expect(find.text('3'), findsOneWidget);
        expect(
          find.byTooltip('Filter and sort games').hitTestable(),
          findsNothing,
        );
        // With several sources the marks switch between them instead.
        expect(find.byTooltip('Manage sources'), findsNothing);
        expect(find.byType(PrepAccountSwitch), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'About and Games read one source alone or all together in ${light ? 'light' : 'dark'} theme',
      (tester) async {
        const online = PrepAccount(
          source: PrepSource.lichess,
          username: 'ClubPlayer',
          ratings: {'rapid': 1900},
        );
        // Two sources of one kind: their marks alone would be alike.
        const other = PrepAccount(
          source: PrepSource.chesscom,
          username: 'ClubPlayer',
          ratings: {'rapid': 2100},
        );
        const empty = PrepAccount(
          source: PrepSource.chesscom,
          username: 'NoGames',
        );
        const slow = PrepAccount(source: PrepSource.manual, username: 'Slow');
        const profile = PrepProfile(
          id: 'p',
          kind: PrepKind.opponent,
          name: 'Club Player',
          createdAtMs: 1,
          accounts: [online, other, empty, slow],
        );
        PrepGame game(int i, PrepAccount account, String result) => PrepGame(
          index: i,
          source: account.source,
          sourcePath: PrepRepository.gamesFileName(account),
          white: 'ClubPlayer',
          black: 'Opponent $i',
          result: result,
          plies: 4,
          speed: PrepTimeControl.rapid,
          playerIsWhite: true,
        );
        final mine = {
          online.key: [game(0, online, '1-0')],
          other.key: [game(1, other, '0-1'), game(2, other, '0-1')],
          empty.key: <PrepGame>[],
          slow.key: [for (var i = 3; i < 7; i++) game(i, slow, '1-0')],
        };
        // One source's games take their time to be read.
        final read = Completer<void>();
        // A phone's status bar and home indicator: a list left to pad
        // itself would sit lower than one that is told how.
        tester.view.padding = const FakeViewPadding(top: 177, bottom: 102);
        tester.view.viewPadding = const FakeViewPadding(top: 177, bottom: 102);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);
        await pump(
          tester,
          // Opened from a source's popup, a profile starts on that source.
          PrepProfileScreen(profileId: 'p', accountKey: other.key),
          light: light,
          premium: true,
          overrides: [
            prepProfileProvider.overrideWith((ref, id) => profile),
            prepAnalysisProvider.overrideWith(
              (ref, id) async => PrepAnalysis(
                profileId: id,
                games: [for (final games in mine.values) ...games],
              ),
            ),
            prepSourceAnalysisProvider.overrideWith((ref, scope) async {
              if (scope.accountKey == slow.key) await read.future;
              return PrepAnalysis(
                profileId: scope.profileId,
                games: mine[scope.accountKey]!,
              );
            }),
          ],
        );
        // Wide enough for the whole switch, so nothing here scrolls.
        await tester.binding.setSurfaceSize(const Size(500, 900));
        await tester.pumpAndSettle();
        String caption() => tester
            .widget<Text>(find.byKey(const ValueKey('prep_switch_caption')))
            .data!;
        Finder segment(String? key) =>
            find.byKey(ValueKey('prep_switch_${key ?? 'all'}'));
        Finder named(String? key, String name) =>
            find.descendant(of: segment(key), matching: find.text(name));
        bool selected(String? key) => tester
            .getSemantics(segment(key))
            .flagsCollection
            .isSelected
            .toBoolOrNull()!;
        String analyzed() => tester
            .widget<Text>(
              find
                  .descendant(
                    of: find.ancestor(
                      of: find.text('Games analyzed'),
                      matching: find.byType(Column),
                    ),
                    matching: find.byType(Text),
                  )
                  .at(1),
            )
            .data!;
        // Everything that must hold still while sources change.
        List<Rect> placed() => [
          tester.getRect(find.byType(PrepIdentity)),
          tester.getRect(find.text('Overall Performance')),
          tester.getRect(find.byType(PrepAccountSwitch)),
        ];

        expect(caption(), 'Chess.com · ClubPlayer');
        expect(selected(other.key), isTrue);
        expect(selected(null), isFalse);
        expect(analyzed(), '2');
        // The rating columns are that source's own.
        expect(find.text('2100'), findsOneWidget);
        expect(find.text('1900'), findsNothing);
        // Two Chess.com sources are told apart by name; a kind with one
        // source is its mark alone.
        expect(named(other.key, 'ClubPlayer'), findsOneWidget);
        expect(named(empty.key, 'NoGames'), findsOneWidget);
        expect(named(online.key, 'ClubPlayer'), findsNothing);
        expect(named(slow.key, 'Slow'), findsNothing);
        // Every choice is a full tap target, and none is cut by the screen.
        for (final key in [null, online.key, other.key, empty.key, slow.key]) {
          final at = tester.getRect(segment(key));
          expect(at.height, greaterThanOrEqualTo(44));
          expect(at.left, greaterThanOrEqualTo(0));
          expect(at.right, lessThanOrEqualTo(500));
        }
        final at = placed();
        final summaryAt = tester.getRect(find.text('Games analyzed'));

        await tester.tap(segment(online.key));
        await tester.pumpAndSettle();
        expect(caption(), 'Lichess · ClubPlayer');
        expect(selected(online.key), isTrue);
        expect(selected(other.key), isFalse);
        expect(analyzed(), '1');
        expect(find.text('1900'), findsOneWidget);
        // Choosing a source moves nothing: not the identity, the heading or
        // the switch, nor the statistics that follow them.
        expect(placed(), at);
        expect(tester.getRect(find.text('Games analyzed')), summaryAt);

        // A source with nothing downloaded can still be left again.
        await tester.tap(segment(empty.key));
        await tester.pumpAndSettle();
        expect(caption(), 'Chess.com · NoGames');
        expect(find.text('No games yet'), findsOneWidget);
        expect(placed(), at);

        await tester.tap(segment(null));
        await tester.pumpAndSettle();
        expect(caption(), 'Combined · 4 sources');
        expect(selected(null), isTrue);
        expect(analyzed(), '7');
        expect(placed(), at);
        expect(tester.getRect(find.text('Games analyzed')), summaryAt);

        // While a source's games are read, the statistics on screen wait
        // where they are, out of reach, under a heading that says so.
        await tester.tap(segment(slow.key));
        await tester.pump();
        await tester.pump();
        expect(selected(slow.key), isTrue);
        expect(
          find.byKey(const ValueKey('prep_switch_progress')),
          findsOneWidget,
        );
        expect(find.text('Reading games…'), findsOneWidget);
        expect(find.byKey(const ValueKey('prep_switch_caption')), findsNothing);
        expect(analyzed(), '7');
        expect(placed(), at);
        expect(tester.getRect(find.text('Games analyzed')), summaryAt);
        const banner = ValueKey('prep_filter_banner');
        await tester.tap(find.text('Wins'), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.byKey(banner), findsNothing);
        read.complete();
        await tester.pumpAndSettle();
        expect(caption(), 'PGN · Slow');
        expect(analyzed(), '4');
        expect(placed(), at);
        expect(tester.getRect(find.text('Games analyzed')), summaryAt);

        // Games follows the source About reads, and what About narrows to
        // stays within it.
        await tester.tap(segment(online.key));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Games'));
        await tester.pumpAndSettle();
        var tab = tester.widget<PrepGamesTab>(find.byType(PrepGamesTab));
        expect(tab.filter.accountKey, online.key);
        expect(tab.games, hasLength(1));
        await tester.tap(find.text('About'));
        await tester.pumpAndSettle();
        // A result is taken on About itself: the page stays, says what it
        // is narrowed to, and the Games tab counts what that leaves.
        final identityAt = tester.getRect(find.byType(PrepIdentity));
        await tester.tap(find.text('Wins'));
        await tester.pumpAndSettle();
        expect(find.byType(PrepGamesTab), findsNothing);
        expect(find.byKey(banner), findsOneWidget);
        expect(tester.getRect(find.byType(PrepIdentity)), identityAt);
        expect(find.text('Games 1'), findsOneWidget);
        await tester.tap(find.text('Games 1'));
        await tester.pumpAndSettle();
        tab = tester.widget<PrepGamesTab>(find.byType(PrepGamesTab));
        expect(tab.filter.accountKey, online.key);
        expect(tab.filter.outcome, PrepOutcome.win);
        await tester.tap(find.text('About'));
        await tester.pumpAndSettle();
        // The second tap gives the result up again. The banner names it
        // too, above the count that is tapped.
        await tester.tap(find.text('Wins').last);
        await tester.pumpAndSettle();
        expect(find.byKey(banner), findsNothing);
        await tester.tap(segment(null));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Games'));
        await tester.pumpAndSettle();
        tab = tester.widget<PrepGamesTab>(find.byType(PrepGamesTab));
        expect(tab.filter.accountKey, isNull);
        expect(tab.filter.source, isNull);
        expect(tab.filter.outcome, isNull);

        // The marks no longer open the sources screen; the menu does.
        expect(find.byTooltip('Manage sources'), findsNothing);
        await tester.tap(find.byTooltip('More actions'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Manage sources'));
        await tester.pumpAndSettle();
        expect(find.byType(PrepSourcesScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a switch too wide for its line brings the chosen source into '
      'view', (tester) async {
    final accounts = [
      for (final name in ['First', 'Second', 'Third', 'Fourth'])
        PrepAccount(source: PrepSource.lichess, username: name),
    ];
    String? chosen = accounts.last.key;
    await pump(
      tester,
      Scaffold(
        body: Center(
          child: SizedBox(
            width: 200,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: StatefulBuilder(
                builder: (context, setState) => PrepAccountSwitch(
                  accounts: accounts,
                  selectedKey: chosen,
                  onSelected: (key) => setState(() => chosen = key),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final line = tester.getRect(find.byType(SingleChildScrollView));
    Rect at(PrepAccount account) =>
        tester.getRect(find.byKey(ValueKey('prep_switch_${account.key}')));
    // Opened on its last source, the line starts where that source shows.
    expect(
      tester.getSize(find.byType(PrepAccountSwitch)).width,
      greaterThan(200),
    );
    expect(at(accounts.last).right, lessThanOrEqualTo(line.right + 0.5));
    expect(at(accounts.first).left, lessThan(line.left));
    // Every source is named: four of one kind would be four alike marks.
    for (final account in accounts) {
      expect(find.text(account.username), findsOneWidget);
    }
    await tester.tap(find.text('Third'));
    await tester.pumpAndSettle();
    expect(chosen, accounts[2].key);
    // Already in view, so the line holds still.
    expect(at(accounts.last).right, lessThanOrEqualTo(line.right + 0.5));
    await tester.dragFrom(line.center, const Offset(400, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('prep_switch_all')));
    await tester.pumpAndSettle();
    expect(chosen, isNull);
    expect(
      tester.getRect(find.byKey(const ValueKey('prep_switch_all'))).left,
      greaterThanOrEqualTo(line.left - 0.5),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a profile unfolds its sources under the combined card and folds them away',
    (tester) async {
      final container = await pump(
        tester,
        const MyPrepHomeScreen(initialTab: 1),
        // The profile a source's popup opens has nothing to index here.
        overrides: [
          prepAnalysisProvider.overrideWith(
            (ref, id) async => PrepAnalysis.empty(id),
          ),
          prepSourceAnalysisProvider.overrideWith(
            (ref, scope) async => PrepAnalysis.empty(scope.profileId),
          ),
        ],
      );
      await tester.runAsync(() async {
        final profiles = container.read(prepProfilesProvider.notifier);
        profiles.create(
          kind: PrepKind.opponent,
          name: 'Unsourced',
          accounts: [],
        );
        profiles.create(
          kind: PrepKind.opponent,
          name: 'Club Player',
          accounts: const [
            PrepAccount(
              source: PrepSource.chesscom,
              username: 'SecondAccount',
              gameCount: 8,
              lastSyncAtMs: 1,
            ),
            PrepAccount(
              source: PrepSource.lichess,
              username: 'ClubPlayer',
              gameCount: 4,
              lastSyncAtMs: 1,
            ),
          ],
        );
        await profiles.debugDrainWrites();
      });
      await tester.pumpAndSettle();
      Finder card(String name) => find.ancestor(
        of: find.text(name),
        matching: find.byType(PrepProfileCard),
      );
      Finder more(Finder within) =>
          find.descendant(of: within, matching: find.byType(CardMoreButton));
      const lichess = ValueKey('prep_account_lichess:clubplayer');
      const chesscom = ValueKey('prep_account_chesscom:secondaccount');

      // Folded, the list is the combined cards alone.
      expect(find.text('12 games'), findsOneWidget);
      expect(find.byKey(lichess), findsNothing);
      expect(find.byType(PrepAccountRow), findsNothing);
      // A profile with no sources has nothing to unfold, but its text ends
      // where every other row's does.
      expect(find.byTooltip('Show sources'), findsOneWidget);
      expect(
        tester.getRect(more(card('Unsourced'))).left,
        tester.getRect(more(card('Club Player'))).left,
      );
      expect(
        tester.getSize(find.byTooltip('Show sources')),
        const Size(44, 44),
      );
      final cardAt = tester.getRect(card('Club Player'));
      final moreAt = tester.getRect(more(card('Club Player')));
      // One rule per profile, drawn by the list: folded, it lies along the
      // card's own bottom edge, where the card would have ruled itself.
      Finder rule(String name) => find.ancestor(
        of: card(name),
        matching: find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox && w.position == DecorationPosition.foreground,
        ),
      );
      bool selfRuled(String name) => tester
          .widget<FigmaPlayerCard>(
            find.descendant(
              of: card(name),
              matching: find.byType(FigmaPlayerCard),
            ),
          )
          .showDivider;
      for (final name in ['Unsourced', 'Club Player']) {
        expect(rule(name), findsOneWidget);
        expect(selfRuled(name), isFalse);
        expect(
          tester.getRect(rule(name)).bottom,
          tester.getRect(card(name)).bottom,
        );
      }

      await tester.tap(find.byTooltip('Show sources'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Hide sources'), findsOneWidget);
      // The combined card holds still; its sources follow in list order.
      expect(tester.getRect(card('Club Player')), cardAt);
      expect(find.text('12 games'), findsOneWidget);
      expect(find.text('4 games'), findsOneWidget);
      expect(find.text('8 games'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(lichess)).dy,
        lessThan(tester.getTopLeft(find.byKey(chesscom)).dy),
      );
      // Both more buttons stand in one column.
      expect(
        tester.getCenter(more(find.byKey(lichess))).dx,
        moreOrLessEquals(moreAt.center.dx, epsilon: 0.5),
      );
      // Still one rule, now under the sources: nothing is ruled between the
      // card and what belongs to it.
      expect(rule('Club Player'), findsOneWidget);
      expect(selfRuled('Club Player'), isFalse);
      expect(
        tester.getRect(rule('Club Player')).bottom,
        greaterThan(tester.getRect(find.byKey(chesscom)).bottom),
      );

      // The list stays as it was left across the other tabs.
      await tester.tap(find.text('Games'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profiles'));
      await tester.pumpAndSettle();
      expect(find.byType(PrepAccountRow), findsNWidgets(2));

      // A source's popup leads to that source's own profile.
      await tester.tap(find.byKey(lichess));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Go to profile'));
      await tester.tap(find.text('Go to profile'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PrepProfileScreen>(find.byType(PrepProfileScreen))
            .accountKey,
        'lichess:clubplayer',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Hide sources'));
      await tester.pumpAndSettle();
      expect(find.byType(PrepAccountRow), findsNothing);
      expect(tester.getRect(card('Club Player')), cardAt);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'profile filters stay in a popup and apply only on confirmation',
    (tester) async {
      const account = PrepAccount(
        source: PrepSource.lichess,
        username: 'ClubPlayer',
      );
      const profile = PrepProfile(
        id: 'p',
        kind: PrepKind.opponent,
        name: 'ClubPlayer',
        createdAtMs: 1,
        accounts: [account],
      );
      var filter = const PrepFilter();
      await pump(
        tester,
        Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => PrepFilterButton(
              active: filter.isActive,
              onPressed: () async {
                final next = await showPrepFilterDialog(
                  context: context,
                  profile: profile,
                  currentFilter: filter,
                );
                if (next != null) setState(() => filter = next);
              },
            ),
          ),
        ),
      );
      expect(find.text('All dates'), findsNothing);
      expect(find.text('Both'), findsNothing);
      await tester.tap(find.byTooltip('Filter and sort games'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All dates'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('30 days').last);
      await tester.pumpAndSettle();
      expect(filter.window, PrepStatsWindow.all);
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(filter.window, PrepStatsWindow.thirtyDays);
      await tester.tap(find.byTooltip('Filter and sort games'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('30 days'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 year').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close filters'));
      await tester.pumpAndSettle();
      expect(filter.window, PrepStatsWindow.thirtyDays);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'advanced filters preserve the source, exact clock, colour and player result',
    (tester) async {
      const account = PrepAccount(
        source: PrepSource.lichess,
        username: 'ClubPlayer',
      );
      const profile = PrepProfile(
        id: 'p',
        kind: PrepKind.opponent,
        name: 'ClubPlayer',
        createdAtMs: 1,
        accounts: [account],
      );
      final initial = PrepFilter(
        source: account.source,
        accountKey: account.key,
        speed: PrepTimeControl.bullet,
        side: PrepSide.black,
        outcome: PrepOutcome.win,
      );
      PrepFilter? selected;
      await pump(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => selected = await showPrepFilterDialog(
                context: context,
                profile: profile,
                currentFilter: initial,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
        scale: 2,
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(
        tester.element(find.text('More game filters')),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('More game filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply Filters').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(selected?.accountKey, account.key);
      expect(selected?.speed, PrepTimeControl.bullet);
      expect(selected?.side, PrepSide.black);
      expect(selected?.outcome, PrepOutcome.win);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a choice on About narrows it where it stands, and a second '
      'tap gives it up', (tester) async {
    PrepGame game(
      int i,
      String result, {
      required String eco,
      required String opponent,
      PrepTimeControl speed = PrepTimeControl.blitz,
    }) => PrepGame(
      index: i,
      source: PrepSource.lichess,
      white: 'ClubPlayer',
      black: opponent,
      result: result,
      plies: 60,
      playerIsWhite: true,
      whiteElo: 1900,
      blackElo: 1800,
      eco: eco,
      speed: speed,
      date: DateTime.utc(2025 - i ~/ 12, 3),
    );
    final games = [
      // A dozen openings met in blitz, each less often than the last.
      for (var line = 0; line < 12; line++)
        for (var n = 0; n < 12 - line; n++)
          game(
            line * 12 + n,
            n.isEven ? '1-0' : '0-1',
            eco: 'B${10 + line}',
            opponent: 'Rival ${line % 3}',
          ),
      // One opening alone was played at the slow clock.
      for (var n = 0; n < 2; n++)
        game(
          200 + n,
          '1/2-1/2',
          eco: 'C65',
          opponent: 'Slow Rival',
          speed: PrepTimeControl.classical,
        ),
    ];
    final facets = PrepFacets(games);
    var filter = const PrepFilter(source: PrepSource.lichess);
    await pump(
      tester,
      Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => PrepOverviewTab(
            profile: const PrepProfile(
              id: 'p',
              kind: PrepKind.opponent,
              name: 'ClubPlayer',
              createdAtMs: 1,
            ),
            stats: filter.stats(facets),
            total: games.length,
            filter: filter,
            onFilterChanged: (next) => setState(() => filter = next),
          ),
        ),
      ),
    );
    // Short enough that the lists opened below reach well past the fold.
    await tester.binding.setSurfaceSize(const Size(430, 500));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('As White'), findsNothing);
    const banner = ValueKey('prep_filter_banner');
    String count() => tester
        .widget<Text>(find.byKey(const ValueKey('prep_filter_count')))
        .data!;
    expect(find.byKey(banner), findsNothing);

    // A result is taken in place; the counts beside it stay to choose from.
    final winsAt = tester.getRect(find.text('Wins'));
    await tester.tap(find.text('Wins'));
    await tester.pumpAndSettle();
    expect(filter.outcome, PrepOutcome.win);
    expect(filter.source, PrepSource.lichess);
    expect(count(), '42 of 80');
    expect(find.text('36'), findsOneWidget);
    // The banner names the result too, above the count that was tapped.
    await tester.tap(find.text('Wins').last);
    await tester.pumpAndSettle();
    expect(filter.outcome, isNull);
    expect(find.byKey(banner), findsNothing);
    expect(tester.getRect(find.text('Wins')), winsAt);

    // With the lists open, a clock chosen below them leaves the openings
    // above it two rows instead of ten. The row tapped stays under the
    // finger all the same.
    for (final panel in ['Opening repertoire', 'Time controls']) {
      await tester.ensureVisible(find.text(panel));
      await tester.pumpAndSettle();
      await tester.tap(find.text(panel));
      await tester.pumpAndSettle();
    }
    expect(find.text('As White'), findsOneWidget);
    expect(find.textContaining('B10'), findsOneWidget);
    await tester.ensureVisible(find.text('Classical'));
    await tester.pumpAndSettle();
    final clockAt = tester.getRect(find.text('Classical'));
    await tester.tap(find.text('Classical'));
    await tester.pump();
    expect(filter.speed, PrepTimeControl.classical);
    // The banner over the statistics names the clock as well. A chosen row
    // is a hundredth larger, which is all that its text has moved.
    expect(
      tester.getRect(find.text('Classical').last).top,
      closeTo(clockAt.top, 0.5),
    );
    await tester.pumpAndSettle();
    expect(count(), '2 of 80');
    // The openings are now the slow clock's own, the other clock still
    // listed beside the chosen one.
    expect(find.textContaining('B10'), findsNothing);
    expect(find.textContaining('C65'), findsOneWidget);
    expect(find.text('Blitz'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // An opening is taken with its colour, and given up alone.
    await tester.ensureVisible(find.textContaining('C65'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('C65'));
    await tester.pumpAndSettle();
    expect(filter.eco, 'C65');
    expect(filter.side, PrepSide.white);
    await tester.tap(find.textContaining('C65').last);
    await tester.pumpAndSettle();
    expect(filter.eco, isNull);
    expect(filter.side, PrepSide.white);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rating figures of several sources name the one source whose '
      'scale they are on', (tester) async {
    const database = PrepAccount(
      source: PrepSource.chessever,
      username: 'Player, Local',
      externalId: 'player-uuid',
    );
    const first = PrepAccount(source: PrepSource.lichess, username: 'One');
    const second = PrepAccount(source: PrepSource.lichess, username: 'Two');
    const profile = PrepProfile(
      id: 'p',
      kind: PrepKind.opponent,
      name: 'Local Player',
      createdAtMs: 1,
      accounts: [database, first, second],
    );
    var index = 0;
    PrepGame game(PrepAccount account, int elo, int day) => PrepGame(
      index: index++,
      source: account.source,
      sourcePath: '/prep/${PrepRepository.gamesFileName(account)}',
      white: 'Player',
      black: 'Opponent',
      result: '1-0',
      plies: 60,
      whiteElo: elo,
      blackElo: elo - 100,
      date: DateTime.utc(2026, 3, day),
      speed: PrepTimeControl.blitz,
      playerIsWhite: true,
    );
    final games = [
      for (var day = 1; day <= 3; day++) game(database, 2600, day),
      // More games than the database, on a site's higher scale.
      for (var day = 1; day <= 5; day++) game(second, 3000, day),
      game(first, 2900, 1),
    ];
    Future<void> show(PrepStats stats) async {
      await pump(
        tester,
        Scaffold(
          body: PrepOverviewTab(
            profile: profile,
            stats: stats,
            filter: const PrepFilter(),
          ),
        ),
      );
      await tester.binding.setSurfaceSize(const Size(430, 1600));
      await tester.pumpAndSettle();
      // The panel remembers being open from one showing to the next.
      if (find.text('Game length').evaluate().isEmpty) {
        await tester.tap(find.text('More statistics'));
        await tester.pumpAndSettle();
      }
    }

    // Together they follow the profile's main source, whatever its share.
    final together = PrepStats.of(
      games,
      ratingAccount: PrepRepository.gamesFileName(database),
    );
    await show(together);
    expect(together.averageOpponent, 2500);
    expect(find.text('2600'), findsNWidgets(2));
    expect(find.textContaining('Rating history · ChessEver'), findsOneWidget);
    const scaleNote = ValueKey('prep_rating_scale');
    expect(
      tester.widget<Text>(find.byKey(scaleNote)).data,
      startsWith('Rating figures are from ChessEver games only'),
    );

    // Two usernames on one site are told apart by name.
    final site = PrepStats.of([
      for (final g in games)
        if (g.source == PrepSource.lichess) g,
    ]);
    await show(site);
    expect(site.averageOpponent, 2900);
    expect(
      find.textContaining('Rating history · Lichess · Two'),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.byKey(scaleNote)).data,
      startsWith('Rating figures are from Lichess · Two games only'),
    );

    // One source is one scale: nothing to explain.
    await show(
      PrepStats.of([
        for (final g in games)
          if (g.sourcePath.endsWith(PrepRepository.gamesFileName(first))) g,
      ]),
    );
    expect(find.byKey(scaleNote), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('freshness never starts the first game download', () async {
    final container = ProviderContainer(
      overrides: [prepRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    await _loaded(container);
    final profiles = container.read(prepProfilesProvider.notifier);
    final profile = profiles.create(
      kind: PrepKind.opponent,
      name: 'Club',
      accounts: [
        const PrepAccount(source: PrepSource.lichess, username: 'club'),
      ],
    );
    final sync = container.read(prepSyncProvider.notifier);
    sync.refreshStale([profile]);
    await Future<void>.delayed(Duration.zero);
    expect(repo.syncCalls, 0);
    profiles.edit(
      profile.id,
      (p) => p.replaceAccount(
        p.accounts.single.copyWith(lastSyncAtMs: 1, gameCount: 1),
      ),
    );
    sync.refreshStale([profiles.byId(profile.id)!]);
    await Future<void>.delayed(Duration.zero);
    expect(repo.syncCalls, 1);
    await profiles.debugDrainWrites();
  });

  test('the retry schedule grows fourfold to a day, spread by a fifth', () {
    Duration at(int failures, {double roll = 0.5}) =>
        prepRetryDelay(failures, roll: roll);
    expect(at(1), const Duration(minutes: 2));
    expect(at(2), const Duration(minutes: 8));
    expect(at(3), const Duration(minutes: 32));
    expect(at(4), const Duration(minutes: 128));
    expect(at(5), const Duration(minutes: 512));
    expect(at(6), kPrepRetryMax);
    expect(at(60), kPrepRetryMax);
    expect(at(1, roll: 0), const Duration(seconds: 96));
    expect(at(1, roll: 0.999), lessThan(const Duration(seconds: 144)));
    expect(at(6, roll: 0.999), kPrepRetryMax);
    expect(prepRetryDelay(1, permanent: true, roll: 0.5), kPrepRetryMax);
    expect(
      prepRetryDelay(1, retryAfter: const Duration(minutes: 10), roll: 0.5),
      const Duration(minutes: 10),
    );
    expect(
      prepRetryDelay(3, retryAfter: const Duration(seconds: 30), roll: 0.5),
      const Duration(minutes: 32),
    );
  });

  test('a failed background refresh never marks downloaded games as failed, '
      'waits across a restart, and recovers by itself', () async {
    var container = ProviderContainer(
      overrides: [prepRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(() => container.dispose());
    await _loaded(container);
    var profiles = container.read(prepProfilesProvider.notifier);
    var sync = container.read(prepSyncProvider.notifier);
    const offline = 'Could not reach ChessEver (offline). Try again shortly.';
    PrepAccount live(String id) => profiles.byId(id)!.accounts.single;

    // Downloaded long ago, so launch finds it stale; the connection drops.
    final mine = profiles.create(
      kind: PrepKind.mine,
      name: 'Me',
      accounts: [
        const PrepAccount(
          source: PrepSource.lichess,
          username: 'me',
          lastSyncAtMs: 1,
          gameCount: 120,
        ),
      ],
    );
    repo.syncFailure = const PrepException(offline);
    final before = DateTime.now().millisecondsSinceEpoch;
    sync.refreshStale([profiles.byId(mine.id)!]);
    await Future<void>.delayed(Duration.zero);
    expect(repo.syncCalls, 1);
    expect(live(mine.id).error, isNull);
    expect(live(mine.id).gameCount, 120);
    expect(live(mine.id).lastSyncAtMs, 1);
    expect(live(mine.id).failedAttempts, 1);
    final wait = live(mine.id).retryAtMs! - before;
    expect(
      wait,
      greaterThanOrEqualTo(const Duration(seconds: 95).inMilliseconds),
    );
    expect(
      wait,
      lessThanOrEqualTo(const Duration(seconds: 145).inMilliseconds),
    );

    // Coming back straight away, or reopening the app, waits it out.
    sync.refreshStale([profiles.byId(mine.id)!]);
    await Future<void>.delayed(Duration.zero);
    expect(repo.syncCalls, 1);
    await profiles.debugDrainWrites();
    container.dispose();
    container = ProviderContainer(
      overrides: [prepRepositoryProvider.overrideWithValue(repo)],
    );
    await _loaded(container);
    profiles = container.read(prepProfilesProvider.notifier);
    sync = container.read(prepSyncProvider.notifier);
    expect(live(mine.id).failedAttempts, 1);
    sync.refreshStale([profiles.byId(mine.id)!]);
    await Future<void>.delayed(Duration.zero);
    expect(repo.syncCalls, 1);

    // A second failure waits four times longer.
    profiles.edit(
      mine.id,
      (p) => p.replaceAccount(p.accounts.single.copyWith(retryAtMs: 1)),
    );
    sync.refreshStale([profiles.byId(mine.id)!]);
    await Future<void>.delayed(Duration.zero);
    expect(repo.syncCalls, 2);
    expect(live(mine.id).failedAttempts, 2);
    expect(
      live(mine.id).retryAtMs! - DateTime.now().millisecondsSinceEpoch,
      greaterThan(const Duration(minutes: 6).inMilliseconds),
    );

    // Once its wait is over and the server answers, it recovers by itself.
    repo.syncFailure = null;
    profiles.edit(
      mine.id,
      (p) => p.replaceAccount(p.accounts.single.copyWith(retryAtMs: 1)),
    );
    sync.refreshStale([profiles.byId(mine.id)!]);
    await Future<void>.delayed(Duration.zero);
    expect(repo.syncCalls, 3);
    expect(live(mine.id).failedAttempts, 0);
    expect(live(mine.id).retryAtMs, isNull);
    expect(live(mine.id).error, isNull);

    // An account that kept an earlier failure is retried, and a success
    // clears it.
    final earlier = profiles.create(
      kind: PrepKind.opponent,
      name: 'Rival',
      accounts: [
        const PrepAccount(
          source: PrepSource.chesscom,
          username: 'rival',
          lastSyncAtMs: 1,
          gameCount: 40,
          error: offline,
        ),
      ],
    );
    expect(live(earlier.id).downloadError, isNull);
    sync.refreshStale([profiles.byId(earlier.id)!]);
    await Future<void>.delayed(Duration.zero);
    expect(repo.syncCalls, 4);
    expect(live(earlier.id).error, isNull);
    await profiles.debugDrainWrites();
  });

  test('a download the reader starts never waits, and says why it failed; '
      'what asking again cannot fix waits a day', () async {
    final container = ProviderContainer(
      overrides: [prepRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    await _loaded(container);
    final profiles = container.read(prepProfilesProvider.notifier);
    final sync = container.read(prepSyncProvider.notifier);
    PrepAccount live(String id) => profiles.byId(id)!.accounts.single;
    final day = kPrepRetryMax.inMilliseconds;

    final rival = profiles.create(
      kind: PrepKind.opponent,
      name: 'Rival',
      accounts: [
        PrepAccount(
          source: PrepSource.lichess,
          username: 'rival',
          lastSyncAtMs: 1,
          gameCount: 40,
          failedAttempts: 3,
          retryAtMs: DateTime.now().millisecondsSinceEpoch + day,
        ),
      ],
    );
    const missing = PrepException(
      'Lichess has no account "rival".',
      permanent: true,
    );
    repo.syncFailure = missing;
    expect(
      await sync.syncAccount(rival.id, live(rival.id), force: true),
      missing.message,
    );
    expect(repo.syncCalls, 1);
    expect(live(rival.id).error, missing.message);
    expect(live(rival.id).downloadError, isNull);
    expect(live(rival.id).failedAttempts, 4);
    expect(
      live(rival.id).retryAtMs! - DateTime.now().millisecondsSinceEpoch,
      greaterThan((day * 0.75).round()),
    );

    // A busy server's own wait is honoured.
    repo.syncFailure = const PrepException(
      'Lichess is limiting downloads. Try again in a minute.',
      retryAfter: Duration(hours: 3),
    );
    final busy = profiles.create(
      kind: PrepKind.opponent,
      name: 'Busy',
      accounts: [
        const PrepAccount(
          source: PrepSource.lichess,
          username: 'busy',
          lastSyncAtMs: 1,
          gameCount: 9,
        ),
      ],
    );
    sync.refreshStale([profiles.byId(busy.id)!]);
    await Future<void>.delayed(Duration.zero);
    expect(
      live(busy.id).retryAtMs! - DateTime.now().millisecondsSinceEpoch,
      greaterThan(const Duration(minutes: 170).inMilliseconds),
    );

    // A first download with nothing to show reads as failed.
    final first = profiles.create(
      kind: PrepKind.opponent,
      name: 'New',
      accounts: [const PrepAccount(source: PrepSource.lichess, username: 'n')],
    );
    await sync.syncAccount(first.id, live(first.id));
    expect(live(first.id).downloadError, isNotNull);
    await profiles.debugDrainWrites();
  });

  test('background refreshes download one account at a time', () async {
    final container = ProviderContainer(
      overrides: [prepRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    await _loaded(container);
    final profiles = container.read(prepProfilesProvider.notifier);
    final mine = profiles.create(
      kind: PrepKind.mine,
      name: 'Me',
      accounts: [
        for (final name in ['one', 'two', 'three'])
          PrepAccount(
            source: PrepSource.lichess,
            username: name,
            lastSyncAtMs: 1,
            gameCount: 5,
          ),
      ],
    );
    final sync = container.read(prepSyncProvider.notifier);
    // Each download holds the gate that was current when it started.
    var gate = repo.syncGate = Completer<void>();
    sync.refreshStale([profiles.byId(mine.id)!]);
    for (final (i, name) in ['one', 'two', 'three'].indexed) {
      await Future<void>.delayed(Duration.zero);
      expect(repo.synced, hasLength(i + 1));
      expect(repo.synced.last, name);
      expect(container.read(prepSyncProvider), hasLength(1));
      final held = gate;
      gate = repo.syncGate = Completer<void>();
      held.complete();
    }
    await Future<void>.delayed(Duration.zero);
    expect(container.read(prepSyncProvider), isEmpty);
    expect(repo.synced, ['one', 'two', 'three']);
    await profiles.debugDrainWrites();
  });

  testWidgets('pulling the Games list down refreshes the profile', (
    tester,
  ) async {
    const game = PrepGame(
      index: 0,
      source: PrepSource.lichess,
      white: 'club',
      black: 'Opponent',
      result: '1-0',
      plies: 4,
      playerIsWhite: true,
    );
    final container = await pump(
      tester,
      Consumer(
        builder: (context, ref, _) {
          final profile = ref
              .watch(prepProfilesProvider)
              .valueOrNull
              ?.firstOrNull;
          if (profile == null) return const SizedBox.shrink();
          return Scaffold(
            body: PrepGamesTab(
              profile: profile,
              analysis: PrepAnalysis(
                profileId: profile.id,
                games: const [game],
              ),
              games: const [game],
              filter: const PrepFilter(),
              onFilterChanged: (_) {},
            ),
          );
        },
      ),
      premium: true,
    );
    final profiles = container.read(prepProfilesProvider.notifier);
    profiles.create(
      kind: PrepKind.opponent,
      name: 'Club',
      accounts: [
        const PrepAccount(
          source: PrepSource.lichess,
          username: 'club',
          lastSyncAtMs: 1,
          gameCount: 1,
        ),
      ],
    );
    await tester.pump();
    expect(find.byType(PrepGamesTab), findsOneWidget);
    expect(repo.syncCalls, 0);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 420));
    // The indicator settles into place, then asks for the refresh. No
    // pumpAndSettle here: its spinner turns for as long as the refresh runs.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(repo.syncCalls, 1, reason: 'the pull asks the source for new games');
    // The refresh then saves the profile: file calls that finish in real
    // time, each resuming on the next frame. Step both until it is done and
    // the indicator has left.
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.byType(RefreshProgressIndicator), findsNothing);
    expect(profiles.byId(profiles.state.requireValue.single.id), isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('game search and shared filters work with large text', (
    tester,
  ) async {
    PrepFilter? selected;
    await pump(
      tester,
      Scaffold(
        body: PrepGamesTab(
          analysis: PrepAnalysis.empty('p'),
          games: const [],
          filter: const PrepFilter(),
          onFilterChanged: (filter) => selected = filter,
        ),
      ),
      scale: 2,
    );
    final field = find.byType(TextField);
    // The row grows with the text, so the search line is never cut.
    expect(
      tester.getSize(find.byType(PlayerGamesSearchBar)).height,
      greaterThanOrEqualTo(48),
    );
    await tester.enterText(field, 'Sicilian');
    await tester.pump();
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    await tester.tap(find.byTooltip('Filter and sort games'));
    await tester.pumpAndSettle();
    final dialog = tester.widget<GameFilterDialog>(
      find.byType(GameFilterDialog),
    );
    expect(dialog.showOpeningFilter, isTrue);
    expect(dialog.showFinishFilter, isTrue);
    expect(dialog.showRatingRange, isTrue);
    expect(dialog.showSortSection, isTrue);
    expect(dialog.showLiveFilter, isFalse);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Apply Filters'));
    await tester.pumpAndSettle();
    expect(selected?.base, GameFilter.defaultFilter());
    expect(tester.takeException(), isNull);
  });

  testWidgets('pasted PGN remains editable after an import error', (
    tester,
  ) async {
    var calls = 0;
    (String, String, String?)? received;
    await pump(
      tester,
      PrepImportDialog(
        playerName: 'ClubPlayer',
        onImport: ({required alias, required label, pgn}) async {
          calls++;
          if (calls == 1) throw const PrepException('No matching player');
          return false;
        },
      ),
      scale: 1.8,
    );
    final labelField = find.byKey(const ValueKey('prep_import_label'));
    final pgnField = find.byKey(const ValueKey('prep_import_pgn'));
    await tester.scrollUntilVisible(
      labelField,
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(labelField, 'Club games');
    await tester.scrollUntilVisible(
      pgnField,
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(pgnField, '[White "ClubPlayer"]');
    await tester.pump();
    await tester.ensureVisible(find.text('Attach pasted games'));
    await tester.tap(find.text('Attach pasted games'));
    await tester.pump();
    expect(find.text('No matching player'), findsOneWidget);
    expect(
      tester.widget<TextField>(pgnField).controller!.text,
      '[White "ClubPlayer"]',
    );
    expect(tester.takeException(), isNull);
    await pump(
      tester,
      PrepImportDialog(
        key: const ValueKey('second-import'),
        playerName: 'ClubPlayer',
        onImport: ({required alias, required label, pgn}) async {
          received = (alias, label, pgn);
          return false;
        },
      ),
      scale: 1.8,
    );
    await tester.scrollUntilVisible(
      labelField,
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(labelField, 'Club games');
    await tester.scrollUntilVisible(
      pgnField,
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(pgnField, '[White "ClubPlayer"]');
    await tester.pump();
    await tester.ensureVisible(find.text('Attach pasted games'));
    await tester.tap(find.text('Attach pasted games'));
    await tester.pump();
    expect(received, ('ClubPlayer', 'Club games', '[White "ClubPlayer"]'));
    expect(tester.takeException(), isNull);
  });
}
