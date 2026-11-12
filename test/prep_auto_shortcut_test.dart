import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/prep_access.dart';
import 'package:chessever2/screens/my_prep/prep_actions.dart';
import 'package:chessever2/screens/my_prep/prep_profile_screen.dart';
import 'package:chessever2/screens/my_prep/prep_source_actions.dart';
import 'package:chessever2/screens/my_prep/prep_space_shortcut.dart';
import 'package:chessever2/screens/my_prep/providers/prep_known_accounts_provider.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/services/prep_repository.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_dialogs.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_import_dialog.dart';
import 'package:chessever2/screens/my_space/actions/space_shortcut_removal.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/navigation/space_shortcut_navigator.dart';
import 'package:chessever2/screens/my_space/providers/space_auto_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _Repository extends PrepRepository {
  _Repository()
    : super(
        GamebaseRepository(
          Dio(),
          baseUrl: 'https://example.test',
          apiKey: 'test',
        ),
      );

  final synced = <String>[];
  bool failDownload = false;
  Completer<void>? importStarted;
  Completer<void>? importReleased;
  Completer<void>? deleteStarted;
  Completer<void>? deleteReleased;

  @override
  Future<File> gamesFile(PrepAccount account) async {
    if (account.source == PrepSource.manual && importReleased != null) {
      if (!(importStarted?.isCompleted ?? true)) importStarted!.complete();
      await importReleased!.future;
    }
    return super.gamesFile(account);
  }

  @override
  Future<void> deleteGames(PrepAccount account) async {
    if (deleteReleased != null) {
      if (!(deleteStarted?.isCompleted ?? true)) deleteStarted!.complete();
      await deleteReleased!.future;
    }
    await super.deleteGames(account);
  }

  @override
  Future<PrepAccount> refreshDetails(PrepAccount account) async => account;

  @override
  Future<PrepAccount> sync(
    PrepAccount account, {
    bool forceRefresh = false,
    bool frequent = false,
    PrepProgress? onProgress,
    CancelToken? cancelToken,
    bool reinstall = false,
  }) async {
    synced.add(account.key);
    if (failDownload) throw const PrepException('Offline');
    return account;
  }
}

/// Only initialization is replaced. Adds, dedupe and removals use the real
/// shortcut store in guest/local mode; no Supabase writes are made.
class _Store extends SpaceShortcutsNotifier {
  late Completer<List<SpaceShortcut>> ready;
  final attempts = <SpaceShortcut>[];
  bool failAdd = false;

  @override
  Future<List<SpaceShortcut>> build() => ready.future;

  @override
  Future<bool> add(SpaceShortcut draft) {
    attempts.add(draft);
    if (failAdd) throw StateError('Test shortcut failure');
    return super.add(draft);
  }
}

class _Hidden extends SpaceHiddenAutoKeys {
  @override
  Set<String> build() => {};

  @override
  void hide(String key) => state = {...state, key};

  @override
  void unhide(String key) => state = {...state}..remove(key);
}

class _Routes extends NavigatorObserver {
  late Route<dynamic> last;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      last = route;
}

PrepAccount _account(PrepSource source, [String name = 'ClubPlayer']) =>
    PrepAccount(
      source: source,
      username: source == PrepSource.chessever ? '12345' : name,
      externalId: source == PrepSource.chessever ? '12345' : null,
      displayName: 'Club Player',
      // Avoid unrelated background rating lookups in action tests.
      ratings: const {'rapid': 2000},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late _Repository repo;
  late _Store store;
  late ProviderContainer container;
  late GlobalKey<NavigatorState> navigator;
  late _Routes routes;
  late BuildContext host;
  late WidgetRef hostRef;
  PrepProfile? target;
  Future<void>? action;

  Future<void> loaded() async {
    final done = Completer<void>();
    final subscription = container.listen(prepProfilesProvider, (_, state) {
      if (!state.isLoading && !done.isCompleted) done.complete();
    }, fireImmediately: true);
    await done.future;
    subscription.close();
  }

  setUp(() {
    directory = Directory.systemTemp.createTempSync('prep_auto_shortcut_');
    repo = _Repository();
    store = _Store();
    navigator = GlobalKey<NavigatorState>();
    routes = _Routes();
    target = null;
    action = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
    container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWithValue(null),
        prepRepositoryProvider.overrideWithValue(repo),
        prepUnlimitedProvider.overrideWithValue(true),
        prepKnownAccountsProvider.overrideWith((_) async => const {}),
        spaceShortcutsProvider.overrideWith(() => store),
        spaceHiddenAutoKeysProvider.overrideWith(_Hidden.new),
      ],
    );
  });

  tearDown(() async {
    await container.read(prepProfilesProvider.notifier).debugDrainWrites();
    container.dispose();
    repo.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  Future<void> pump(WidgetTester tester, {bool storeReady = true}) async {
    await tester.runAsync(loaded);
    await tester.runAsync(() async {
      store.ready = Completer<List<SpaceShortcut>>();
    });
    if (storeReady) {
      store.ready.complete([]);
      await tester.runAsync(
        () => container.read(spaceShortcutsProvider.future),
      );
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: navigator,
          navigatorObservers: [routes],
          theme: AppTheme.darkTheme,
          home: Consumer(
            builder: (context, ref, _) {
              ResponsiveHelper.init(context);
              host = context;
              hostRef = ref;
              return Scaffold(
                body: Column(
                  children: [
                    TextButton(
                      onPressed: () => action = prepAddMine(context, ref),
                      child: const Text('Mine'),
                    ),
                    TextButton(
                      onPressed: () => action = prepAddOpponent(context, ref),
                      child: const Text('Opponent'),
                    ),
                    TextButton(
                      onPressed: () =>
                          action = prepAddAccountTo(context, ref, target!),
                      child: const Text('Attach'),
                    ),
                    TextButton(
                      onPressed: () => action = prepChangeAccount(
                        context,
                        ref,
                        target!,
                        target!.accounts.first,
                      ),
                      child: const Text('Change'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Exercise the real action around its picker boundary. The picker result is
  /// synthetic (validated/scoped accounts), not a live provider lookup. Existing
  /// my_prep_profile_flow_test exercises the actual picker and scope pages.
  Future<void> add(
    WidgetTester tester,
    String button,
    List<PrepAccount>? accounts,
  ) async {
    await tester.runAsync(() => tester.tap(find.text(button)));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      navigator.currentState!.pop(
        accounts == null ? null : PrepAddResult.named(accounts),
      );
      await action;
    });
    // Complete the closing route, not the snack's entire four-second lifetime.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(() async {
      await action;
      await container.read(prepProfilesProvider.notifier).debugDrainWrites();
    });
    await tester.pump();
  }

  Future<PrepProfile> create(
    WidgetTester tester, {
    PrepKind kind = PrepKind.opponent,
    String name = 'Combined',
    required List<PrepAccount> accounts,
  }) async => (await tester.runAsync(() async {
    final profiles = container.read(prepProfilesProvider.notifier);
    final profile = profiles.create(kind: kind, name: name, accounts: accounts);
    await profiles.debugDrainWrites();
    return profile;
  }))!;

  Future<PrepImportDialog> openImport(
    WidgetTester tester, {
    PrepKind kind = PrepKind.opponent,
  }) async {
    await tester.runAsync(() async {
      action = prepImportSource(host, hostRef, target, kind: kind);
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    return tester.widget<PrepImportDialog>(find.byType(PrepImportDialog));
  }

  Future<void> closeImport(WidgetTester tester) async {
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await action;
      await container.read(prepProfilesProvider.notifier).debugDrainWrites();
    });
  }

  const importedGames = '''
[Event "First"]
[White "Club Player"]
[Black "First Opponent"]
[Result "*"]

1. e4 e5 *

[Event "Second"]
[White "Club Player"]
[Black "Second Opponent"]
[Result "*"]

1. d4 d5 *
''';

  for (final kind in [PrepKind.mine, PrepKind.opponent]) {
    testWidgets('PGN import creates a $kind profile and its shortcut', (
      tester,
    ) async {
      await pump(tester);
      final dialog = await openImport(tester, kind: kind);
      await tester.runAsync(() async {
        final reading = await dialog.onImport([
          (label: 'Club games.pgn', pgn: importedGames),
        ]);
        expect(reading.resolved, isTrue);
        await Future<void>.delayed(Duration.zero);
      });
      await closeImport(tester);
      final profile = container.read(prepProfilesProvider).requireValue.single;
      expect(profile.kind, kind);
      expect(profile.accounts.single.source, PrepSource.manual);
      expect(profile.gameCount, 2);
      expect(
        container.read(spaceShortcutsProvider).requireValue.single.key,
        prepProfileSpaceDraft(profile).key,
      );
      expect(store.attempts, hasLength(1));
      expect(repo.synced, isEmpty);
    });
  }

  testWidgets(
    'import into an existing profile pins once and preserves removal',
    (tester) async {
      await pump(tester);
      target = await create(tester, accounts: [_account(PrepSource.lichess)]);
      final dialog = await openImport(tester);
      Future<void> import() async {
        await tester.runAsync(() async {
          await dialog.onImport([(label: 'Games.pgn', pgn: importedGames)]);
          await Future<void>.delayed(Duration.zero);
        });
      }

      await import();
      final pin = container.read(spaceShortcutsProvider).requireValue.single;
      expect(pin.targetId, target!.id);
      final originalPin = pin.toJson();
      await import();
      expect(
        container.read(spaceShortcutsProvider).requireValue.single.toJson(),
        originalPin,
      );
      final removal = removeSpaceShortcut(hostRef, pin);
      await removal.written;
      await import();
      expect(container.read(spaceShortcutsProvider).requireValue, isEmpty);
      expect(
        container.read(prepProfileProvider(target!.id))!.accounts,
        hasLength(4),
      );
      expect(store.attempts, hasLength(2));
      await closeImport(tester);
    },
  );

  testWidgets('cancelled or rejected PGN imports add no profile or shortcut', (
    tester,
  ) async {
    await pump(tester);
    final dialog = await openImport(tester);
    await tester.runAsync(() async {
      await expectLater(
        dialog.onImport([(label: 'Invalid.pgn', pgn: 'not a chess game')]),
        throwsA(isA<PrepException>()),
      );
      // The first file was prepared, but a later invalid file must roll it back.
      await expectLater(
        dialog.onImport([
          (label: 'Valid.pgn', pgn: importedGames),
          (label: 'Invalid.pgn', pgn: 'not a chess game'),
        ], player: 'Club Player'),
        throwsA(isA<PrepException>()),
      );
    });
    await closeImport(tester);
    expect(container.read(prepProfilesProvider).requireValue, isEmpty);
    expect(store.attempts, isEmpty);
    expect(
      directory
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.pgn')),
      isEmpty,
    );
    await openImport(tester);
    await closeImport(tester);
    expect(container.read(prepProfilesProvider).requireValue, isEmpty);
    expect(store.attempts, isEmpty);
  });

  testWidgets('shortcut failure cannot roll back successfully imported games', (
    tester,
  ) async {
    await pump(tester);
    store.failAdd = true;
    final dialog = await openImport(tester);
    await tester.runAsync(() async {
      final reading = await dialog.onImport([
        (label: 'Games.pgn', pgn: importedGames),
      ]);
      expect(reading.resolved, isTrue);
      await Future<void>.delayed(Duration.zero);
    });
    await closeImport(tester);
    final profile = container.read(prepProfilesProvider).requireValue.single;
    final file = (await tester.runAsync(
      () => repo.gamesFile(profile.accounts.single),
    ))!;
    expect(profile.gameCount, 2);
    expect(file.readAsStringSync(), contains('Club Player'));
    expect(store.attempts, hasLength(1));
    expect(container.read(spaceShortcutsProvider).requireValue, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('import still pins after the initiating widget is disposed', (
    tester,
  ) async {
    await pump(tester);
    final dialog = await openImport(tester);
    late Future<void> imported;
    await tester.runAsync(() async {
      repo.importStarted = Completer<void>();
      repo.importReleased = Completer<void>();
      imported = dialog
          .onImport([(label: 'Games.pgn', pgn: importedGames)])
          .then((reading) => expect(reading.resolved, isTrue));
      await repo.importStarted!.future.timeout(const Duration(seconds: 10));
    });
    await tester.pumpWidget(const SizedBox.shrink());
    expect(host.mounted, isFalse);
    await tester.runAsync(() async {
      repo.importReleased!.complete();
      await imported;
      await Future<void>.delayed(Duration.zero);
    });
    final profile = container.read(prepProfilesProvider).requireValue.single;
    expect(
      container.read(spaceShortcutsProvider).requireValue.single.targetId,
      profile.id,
    );
    expect(tester.takeException(), isNull);
  });

  for (final fromMenu in [false, true]) {
    testWidgets('adding a favorite via ${fromMenu ? 'menu' : 'row'} pins it', (
      tester,
    ) async {
      await pump(tester);
      target = await create(
        tester,
        kind: PrepKind.favorite,
        accounts: [_account(PrepSource.lichess).copyWith(lastSyncAtMs: 1)],
      );
      await tester.runAsync(() async {
        if (fromMenu) {
          await prepProfileMenu(
            host,
            hostRef,
            target!,
          ).singleWhere((item) => item.label == 'Add to Profiles').onSelected();
        } else {
          await prepMoveFavoriteToOpponents(host, hostRef, target!);
        }
        await Future<void>.delayed(Duration.zero);
      });
      final profile = container.read(prepProfileProvider(target!.id))!;
      expect(profile.kind, PrepKind.opponent);
      expect(profile.accounts.single.key, target!.accounts.single.key);
      expect(
        container.read(spaceShortcutsProvider).requireValue.single.targetId,
        profile.id,
      );
      expect(store.attempts, hasLength(1));
      final labels = prepProfileMenu(
        host,
        hostRef,
        profile,
      ).map((item) => item.label);
      expect(labels, contains('Remove from My Space'));
      expect(labels, isNot(contains('Add to My Space')));
      expect(tester.takeException(), isNull);
    });
  }

  for (final button in ['Mine', 'Opponent']) {
    for (final source in PrepSource.playerSources) {
      testWidgets('$button adding ${source.label} pins the combined profile', (
        tester,
      ) async {
        await pump(tester);
        final account = _account(source);
        await add(tester, button, [account]);
        final profile = container
            .read(prepProfilesProvider)
            .requireValue
            .single;
        final pin = container.read(spaceShortcutsProvider).requireValue.single;
        expect(pin.key, prepProfileSpaceDraft(profile).key);
        expect(pin.kind, SpaceShortcutKind.prepProfile);
        expect(pin.targetId, profile.id);
        // Only what rebuilds the profile on the reader's other devices: no
        // source-only navigation/accountKey.
        expect(pin.params.keys, [kPrepPinRecipe]);
        final carried = prepProfileFromPin(pin)!;
        expect(carried.id, profile.id);
        expect(carried.kind, profile.kind);
        expect(carried.accounts.single.key, account.key);
        expect(pin.subtitle, 'Prep');
        expect(profile.accounts.single.key, account.key);
        expect(repo.synced, [account.key]);
        expect(store.attempts, hasLength(1));
        final labels = prepProfileMenu(
          host,
          hostRef,
          profile,
        ).map((item) => item.label);
        expect(labels, contains('Remove from My Space'));
        expect(labels, isNot(contains('Add to My Space')));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('multi-source creation makes one profile shortcut', (
    tester,
  ) async {
    await pump(tester);
    final accounts = [
      for (final source in PrepSource.playerSources) _account(source),
    ];
    await add(tester, 'Opponent', accounts);
    final profile = container.read(prepProfilesProvider).requireValue.single;
    expect(profile.accounts.map((a) => a.key), accounts.map((a) => a.key));
    expect(
      container.read(spaceShortcutsProvider).requireValue.single.targetId,
      profile.id,
    );
    expect(store.attempts, hasLength(1));
  });

  for (final button in ['Mine', 'Attach']) {
    for (final source in PrepSource.playerSources) {
      testWidgets('$button attaching ${source.label} pins existing profile once', (
        tester,
      ) async {
        await pump(tester);
        final profiles = container.read(prepProfilesProvider.notifier);
        final firstSource = source == PrepSource.lichess
            ? PrepSource.chesscom
            : PrepSource.lichess;
        final original = _account(firstSource, 'Original');
        target = await create(
          tester,
          kind: button == 'Mine' ? PrepKind.mine : PrepKind.opponent,
          name: 'Existing combined profile',
          accounts: [original],
        );
        // Creating test setup directly is not an explicit add action: no backfill.
        await tester.pump();
        expect(store.attempts, isEmpty);
        await add(tester, button, [_account(source)]);
        final live = profiles.byId(target!.id)!;
        expect(live.accounts.map((a) => a.key), [
          original.key,
          _account(source).key,
        ]);
        final pin = container.read(spaceShortcutsProvider).requireValue.single;
        expect(pin.targetId, target!.id);
        expect(pin.title, target!.name);
        // Another valid attachment neither duplicates nor moves/renames the pin.
        final before = pin.toJson();
        target = live;
        await add(tester, button, [_account(firstSource, 'Another')]);
        expect(
          container.read(spaceShortcutsProvider).requireValue.single.toJson(),
          before,
        );
        expect(profiles.byId(target!.id)!.accounts, hasLength(3));
      });
    }
  }

  testWidgets('automatic shortcut opens the same combined profile route', (
    tester,
  ) async {
    await pump(tester);
    await add(tester, 'Opponent', [
      _account(PrepSource.lichess),
      _account(PrepSource.chesscom),
    ]);
    final pin = container.read(spaceShortcutsProvider).requireValue.single;
    await tester.runAsync(() async {
      unawaited(openSpaceShortcut(host, hostRef, pin));
      await Future<void>.delayed(Duration.zero);
    });
    // Exercise the real shortcut navigator, inspecting its destination before
    // rendering the profile's unrelated statistics/download/photo surfaces.
    final route = routes.last as MaterialPageRoute<void>;
    final destination = route.builder(host) as PrepProfileScreen;
    expect(destination.profileId, pin.targetId);
    expect(destination.accountKey, isNull);
    expect(
      container.read(prepProfileProvider(pin.targetId))!.accounts,
      hasLength(2),
    );
    navigator.currentState!.removeRoute(route);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('existing manual pin retains identity, sort and metadata', (
    tester,
  ) async {
    await pump(tester);
    target = await create(tester, accounts: [_account(PrepSource.lichess)]);
    await store.add(
      prepProfileSpaceDraft(target!).copyWith(title: 'Kept title'),
    );
    final before = container
        .read(spaceShortcutsProvider)
        .requireValue
        .single
        .toJson();
    await add(tester, 'Attach', [_account(PrepSource.chesscom)]);
    expect(
      container.read(spaceShortcutsProvider).requireValue.single.toJson(),
      before,
    );
  });

  testWidgets(
    'duplicate attachment fails without pinning or changing source data',
    (tester) async {
      await pump(tester);
      final account = _account(PrepSource.lichess);
      target = await create(tester, accounts: [account]);
      final before = target!.toJson();
      await add(tester, 'Attach', [account]);
      expect(container.read(prepProfileProvider(target!.id))!.toJson(), before);
      expect(store.attempts, isEmpty);
      expect(repo.synced, isEmpty);
      expect(find.text('This source is already attached.'), findsOneWidget);
    },
  );

  testWidgets('failed mixed attachment is atomic and does not create a pin', (
    tester,
  ) async {
    await pump(tester);
    final account = _account(PrepSource.lichess);
    final profiles = container.read(prepProfilesProvider.notifier);
    target = await create(
      tester,
      kind: PrepKind.opponent,
      name: 'Combined',
      accounts: [account],
    );
    await add(tester, 'Attach', [_account(PrepSource.chesscom), account]);
    expect(profiles.byId(target!.id)!.accounts.single.key, account.key);
    expect(store.attempts, isEmpty);
    expect(repo.synced, isEmpty);
  });

  for (final button in ['Mine', 'Opponent', 'Attach']) {
    testWidgets('$button cancellation adds no shortcut or accounts', (
      tester,
    ) async {
      await pump(tester);
      if (button == 'Attach') {
        target = await create(
          tester,
          name: 'Existing',
          accounts: [_account(PrepSource.lichess)],
        );
      }
      final before = container
          .read(prepProfilesProvider)
          .requireValue
          .map((p) => p.toJson())
          .toList();
      await add(tester, button, null);
      expect(
        container
            .read(prepProfilesProvider)
            .requireValue
            .map((p) => p.toJson())
            .toList(),
        before,
      );
      expect(store.attempts, isEmpty);
      expect(repo.synced, isEmpty);
    });
  }

  testWidgets(
    'download failure leaves the valid profile shortcut and sources',
    (tester) async {
      await pump(tester);
      repo.failDownload = true;
      await add(tester, 'Opponent', [_account(PrepSource.lichess)]);
      final profile = container.read(prepProfilesProvider).requireValue.single;
      expect(profile.accounts.single.error, 'Offline');
      expect(
        container.read(spaceShortcutsProvider).requireValue.single.targetId,
        profile.id,
      );
    },
  );

  testWidgets('shortcut failure is nonfatal and does not block downloads', (
    tester,
  ) async {
    await pump(tester);
    store.failAdd = true;
    await add(tester, 'Opponent', [_account(PrepSource.lichess)]);
    expect(
      container.read(prepProfilesProvider).requireValue.single.accounts,
      hasLength(1),
    );
    expect(repo.synced, hasLength(1));
    expect(container.read(spaceShortcutsProvider).requireValue, isEmpty);
    expect(
      find.text(
        'Profile saved. Could not add to My Space. Try its profile menu.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'loading shortcuts do not delay downloads or overwrite cached pins',
    (tester) async {
      await pump(tester, storeReady: false);
      await add(tester, 'Opponent', [_account(PrepSource.lichess)]);
      expect(repo.synced, hasLength(1));
      expect(store.attempts, isEmpty);
      final profile = container.read(prepProfilesProvider).requireValue.single;
      final cached = prepProfileSpaceDraft(
        profile,
      ).copyWith(title: 'Cached title', sortIndex: 42);
      await tester.runAsync(() async {
        store.ready.complete([cached]);
        await container.read(spaceShortcutsProvider.future);
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      expect(
        container.read(spaceShortcutsProvider).requireValue.single.toJson(),
        cached.toJson(),
      );
      expect(store.attempts, hasLength(1));
    },
  );

  testWidgets(
    'shortcut initialization failure is reported without rolling back Prep',
    (tester) async {
      await pump(tester, storeReady: false);
      await add(tester, 'Opponent', [_account(PrepSource.lichess)]);
      await tester.runAsync(() async {
        store.ready.completeError(StateError('Test cache unavailable'));
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      expect(
        container.read(prepProfilesProvider).requireValue.single.accounts,
        hasLength(1),
      );
      expect(repo.synced, hasLength(1));
      expect(store.attempts, isEmpty);
      expect(
        find.text(
          'Profile saved. Could not add to My Space. Try its profile menu.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'intentional removal preserves data and survives attach, refresh and reload',
    (tester) async {
      await pump(tester);
      await add(tester, 'Opponent', [_account(PrepSource.lichess)]);
      final profiles = container.read(prepProfilesProvider.notifier);
      target = container.read(prepProfilesProvider).requireValue.single;
      final pin = container.read(spaceShortcutsProvider).requireValue.single;
      final pgn = (await tester.runAsync(
        () => repo.gamesFile(target!.accounts.single),
      ))!;
      pgn.writeAsStringSync('[Event "Keep"]\n\n1. e4 e5 *\n');
      final originalPgn = pgn.readAsStringSync();
      final removal = removeSpaceShortcut(hostRef, pin);
      await removal.written;
      expect(profiles.byId(target!.id)!.toJson(), target!.toJson());
      await add(tester, 'Attach', [_account(PrepSource.chesscom)]);
      expect(container.read(spaceShortcutsProvider).requireValue, isEmpty);
      expect(profiles.byId(target!.id)!.accounts, hasLength(2));
      expect(pgn.readAsStringSync(), originalPgn);
      await tester.runAsync(() async {
        await container
            .read(prepSyncProvider.notifier)
            .syncProfile(target!.id, force: true);
        await profiles.debugDrainWrites();
        container.invalidate(prepProfilesProvider);
        await loaded();
      });
      expect(container.read(spaceShortcutsProvider).requireValue, isEmpty);
      expect(
        container.read(prepProfileProvider(target!.id))!.accounts,
        hasLength(2),
      );
      expect(store.attempts, hasLength(1));
      // Explicit Undo may restore the exact shortcut, never the source itself.
      await removal.undo();
      expect(
        container.read(spaceShortcutsProvider).requireValue.single.key,
        pin.key,
      );
      expect(pgn.readAsStringSync(), originalPgn);
    },
  );

  testWidgets('removal while shortcut cache loads wins', (tester) async {
    await pump(tester, storeReady: false);
    await add(tester, 'Opponent', [_account(PrepSource.lichess)]);
    final profile = container.read(prepProfilesProvider).requireValue.single;
    container
        .read(spaceHiddenAutoKeysProvider.notifier)
        .hide(prepProfileSpaceDraft(profile).key);
    await tester.runAsync(() async {
      store.ready.complete([]);
      await container.read(spaceShortcutsProvider.future);
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    expect(container.read(spaceShortcutsProvider).requireValue, isEmpty);
    expect(store.attempts, isEmpty);
  });

  testWidgets('profile removed while cache loads does not leave a dead pin', (
    tester,
  ) async {
    await pump(tester, storeReady: false);
    await add(tester, 'Opponent', [_account(PrepSource.lichess)]);
    final profiles = container.read(prepProfilesProvider.notifier);
    final profile = container.read(prepProfilesProvider).requireValue.single;
    await tester.runAsync(() => profiles.delete(profile.id));
    await tester.runAsync(() async {
      store.ready.complete([]);
      await container.read(spaceShortcutsProvider.future);
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    expect(container.read(spaceShortcutsProvider).requireValue, isEmpty);
    expect(store.attempts, isEmpty);
  });

  testWidgets(
    'historical profile load and metadata edits never backfill shortcuts',
    (tester) async {
      final historical = PrepProfile(
        id: 'old',
        kind: PrepKind.opponent,
        name: 'Historical',
        createdAtMs: 1,
        accounts: [_account(PrepSource.lichess)],
      );
      final file = File('${directory.path}/prep/profiles.json');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        jsonEncode({
          'version': 1,
          'profiles': [historical.toJson()],
        }),
      );
      await pump(tester);
      await tester.runAsync(() async {
        final profiles = container.read(prepProfilesProvider.notifier);
        profiles.edit('old', (p) => p.copyWith(name: 'Renamed'));
        await profiles.debugDrainWrites();
      });
      await tester.pump();
      expect(store.attempts, isEmpty);
      expect(container.read(prepProfileProvider('old'))!.name, 'Renamed');
    },
  );

  testWidgets('explicit replacement reuses the combined profile shortcut', (
    tester,
  ) async {
    await pump(tester);
    target = await create(
      tester,
      accounts: [_account(PrepSource.lichess, 'Old')],
    );
    await add(tester, 'Change', [_account(PrepSource.lichess, 'New')]);
    expect(
      container.read(prepProfileProvider(target!.id))!.accounts.single.username,
      'New',
    );
    expect(
      container.read(spaceShortcutsProvider).requireValue.single.targetId,
      target!.id,
    );
  });

  testWidgets('replacement still pins and downloads after leaving its screen', (
    tester,
  ) async {
    await pump(tester);
    target = await create(
      tester,
      accounts: [_account(PrepSource.lichess, 'Old')],
    );
    await tester.runAsync(() async {
      repo.deleteStarted = Completer<void>();
      repo.deleteReleased = Completer<void>();
      await tester.tap(find.text('Change'));
    });
    await tester.pumpAndSettle();
    final replacement = _account(PrepSource.lichess, 'New');
    await tester.runAsync(() async {
      navigator.currentState!.pop(PrepAddResult.named([replacement]));
      await repo.deleteStarted!.future.timeout(const Duration(seconds: 10));
    });
    await tester.pumpWidget(const SizedBox.shrink());
    expect(host.mounted, isFalse);
    await tester.runAsync(() async {
      repo.deleteReleased!.complete();
      await action;
      await Future<void>.delayed(Duration.zero);
    });
    expect(
      container.read(prepProfileProvider(target!.id))!.accounts.single.key,
      replacement.key,
    );
    expect(
      container.read(spaceShortcutsProvider).requireValue.single.targetId,
      target!.id,
    );
    expect(repo.synced, [replacement.key]);
    expect(tester.takeException(), isNull);
  });
}
