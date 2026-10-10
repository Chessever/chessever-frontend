import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/supabase/chess_player/chess_player_repository.dart';
import 'package:chessever2/screens/favorites/rankings/ranking_filters.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/my_prep_home_screen.dart';
import 'package:chessever2/screens/my_prep/prep_profile_screen.dart';
import 'package:chessever2/screens/my_prep/prep_actions.dart';
import 'package:chessever2/screens/my_prep/prep_source_actions.dart';
import 'package:chessever2/screens/my_prep/prep_sources_screen.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/services/prep_analysis.dart';
import 'package:chessever2/screens/my_prep/services/prep_repository.dart';
import 'package:chessever2/screens/my_prep/tabs/prep_overview_tab.dart';
import 'package:chessever2/screens/my_prep/tabs/prep_trees_tab.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_common.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_dialogs.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_profile_card.dart';
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
import 'package:chessever2/widgets/popover_add_fab.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:dio/dio.dart';

import 'my_prep_sources_test.dart' show databasePlayer, sourceGame;

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
  setUp(() {
    directory = Directory.systemTemp.createTempSync('prep_flow_');
    repo = _PickerRepository();
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
    List<Override> overrides = const [],
  }) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(
      overrides: [
        prepRepositoryProvider.overrideWithValue(repo),
        premiumAccessProvider.overrideWithValue(premium),
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
      ('My games', 'Attach your username', 'Attach your usernames'),
      ('Opponents', 'Add opponent', 'Add an opponent'),
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
    // Favorites is a fixed ranking: no floating button and no in-page add.
    await tester.tap(find.text('Favorites'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('prep_add_floating')), findsNothing);
    expect(find.byKey(const ValueKey('prep_add_empty')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a ranked favorite joins Opponents through the add sheet with '
      'its known accounts chosen, and keeps its ranking slot', (tester) async {
    final container = await pump(
      tester,
      const MyPrepHomeScreen(),
      premium: true,
      overrides: [
        chessPlayerRepositoryProvider.overrideWithValue(_RankingRepository()),
      ],
    );
    await tester.tap(find.text('Favorites'));
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

  testWidgets('the + on a Favorites row adds the whole player to Opponents in '
      'one tap, as the add sheet would with nothing changed', (tester) async {
    final container = await pump(
      tester,
      const MyPrepHomeScreen(),
      premium: true,
      overrides: [
        chessPlayerRepositoryProvider.overrideWithValue(_RankingRepository()),
      ],
    );
    await tester.tap(find.text('Favorites'));
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    // No sheet and no profile screen: the player is simply in Opponents.
    expect(find.text('Add an opponent'), findsNothing);
    expect(find.byType(PrepProfileScreen), findsNothing);
    final profile = container.read(prepProfilesProvider).requireValue.single;
    expect(profile.kind, PrepKind.opponent);
    expect(profile.favoriteId, 'carlsen');
    expect(profile.fideId, '1503014');
    expect(profile.accounts.map((a) => a.source), [
      PrepSource.chessever,
      PrepSource.chesscom,
      PrepSource.lichess,
    ]);
    // Each account carries what the sheet's scope page would have proposed.
    for (final account in profile.accounts) {
      final proposed = PrepDownloadPreferences.initialFor(account.source);
      expect(account.preferences.timeControls, proposed.timeControls);
      expect(account.preferences.range, proposed.range);
    }
    expect(repo.syncCalls, 3);
    expect(find.text('${profile.name} added to Opponents'), findsOneWidget);
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
    expect(find.bySemanticsLabel(RegExp('In Opponents')), findsOneWidget);

    // A player ChessEver cannot resolve, with no known handle, adds nothing.
    await tester.tap(add('Unknown, Handle'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(container.read(prepProfilesProvider).requireValue, hasLength(1));
    expect(add('Unknown, Handle'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('My games attaches own usernames from both online sites', (
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
          body: PrepIdentity(profile: profile, onRating: (_, _) {}),
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

        await tester.tap(find.text('1900'));
        await tester.pumpAndSettle();
        final tab = tester.widget<PrepGamesTab>(find.byType(PrepGamesTab));
        expect(tab.games, hasLength(1));
        expect(tab.filter.accountKey, online.key);
        expect(tab.filter.speed, PrepTimeControl.rapid);
        // The Games row is the player profile's: search, filters, layout.
        expect(
          find.byTooltip('Filter and sort games').hitTestable(),
          findsOneWidget,
        );

        await tester.tap(find.byTooltip('Filter and sort games'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Lichess · ClubPlayer').last);
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
        await tester.tap(find.byTooltip('Manage sources'));
        await tester.pumpAndSettle();
        expect(find.byType(PrepSourcesScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

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

  testWidgets('result statistics open a correctly scoped games filter', (
    tester,
  ) async {
    final stats = PrepStats.of([
      const PrepGame(
        index: 0,
        source: PrepSource.lichess,
        white: 'ClubPlayer',
        black: 'Opponent',
        result: '1-0',
        plies: 4,
        playerIsWhite: true,
        whiteElo: 1900,
        blackElo: 1800,
      ),
    ]);
    PrepFilter? selected;
    await pump(
      tester,
      Scaffold(
        body: PrepOverviewTab(
          profile: const PrepProfile(
            id: 'p',
            kind: PrepKind.opponent,
            name: 'ClubPlayer',
            createdAtMs: 1,
          ),
          stats: stats,
          filter: const PrepFilter(source: PrepSource.lichess),
          onOpenGames: (filter) => selected = filter,
        ),
      ),
      scale: 2,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Their White'), findsNothing);
    await tester.tap(find.text('Wins'));
    expect(selected?.outcome, PrepOutcome.win);
    expect(selected?.source, PrepSource.lichess);
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
