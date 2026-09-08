import 'dart:async';
import 'dart:convert';

import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/library/pgn_import_preview_screen.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/screens/library/widgets/bulk_add_to_folder_sheet.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/testing.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _database = LibraryFolder(
  id: 'database-1',
  userId: 'user-1',
  name: 'Opening preparation',
  color: '#0FB4E5',
  icon: 'database',
  orderIndex: 0,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

final _games = [
  ChessGame.fromPgn('import-1', '''
[Event "Imported collection"]
[White "White One"]
[Black "Black One"]
[Result "1-0"]

1. e4 e5 1-0
'''),
  ChessGame.fromPgn('import-2', '''
[Event "Imported collection"]
[White "White Two"]
[Black "Black Two"]
[Result "0-1"]

1. d4 d5 0-1
'''),
];

class _LibraryRepository extends LibraryRepository {
  int folderReads = 0;
  Future<List<LibraryFolder>> Function()? fetchFolders;
  final saved = <SavedAnalysis>[];

  @override
  Future<List<LibraryFolder>> getFolders() async {
    folderReads++;
    return fetchFolders == null ? [_database] : await fetchFolders!();
  }

  @override
  Future<void> createSavedAnalysesBulk(List<SavedAnalysis> analyses) async {
    saved.addAll(analyses);
  }
}

class _PremiumSubscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _PremiumSubscription() : super(SubscriptionState(isSubscribed: true));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _openImportSheet(
  WidgetTester tester, {
  required _LibraryRepository repository,
  required LibraryFolderStreamFactory streamFactory,
  bool bulk = false,
}) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        libraryRepositoryProvider.overrideWithValue(repository),
        libraryFolderAuthenticatedUserIdProvider.overrideWithValue('user-1'),
        libraryFolderStreamFactoryProvider.overrideWithValue(streamFactory),
        subscriptionProvider.overrideWith((ref) => _PremiumSubscription()),
      ],
      child: MaterialApp(
        builder: (context, child) {
          ResponsiveHelper.init(context);
          return child!;
        },
        home: Builder(
          builder:
              (context) => Scaffold(
                body: TextButton(
                  onPressed: () {
                    if (bulk) {
                      showBulkAddToFolderSheet(
                        context: context,
                        games:
                            buildPgnImportBoardNavigation(
                              visibleGames: _games,
                              selectedIndex: 0,
                            ).games,
                        sourceLabel: 'shared.pgn',
                      );
                      return;
                    }
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder:
                            (_) => PgnImportPreviewScreen(
                              games: _games,
                              sourceLabel: 'shared.pgn',
                            ),
                      ),
                    );
                  },
                  child: const Text('Open PGN'),
                ),
              ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open PGN'));
  await tester.pumpAndSettle();
  if (!bulk) await tester.tap(find.byTooltip('Save to folder'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  expect(
    find.text(bulk ? 'Add to My Library' : 'Import to My Library'),
    findsOneWidget,
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final fonts =
        FontLoader('InterDisplay')
          ..addFont(rootBundle.load('assets/fonts/Inter-Regular.otf'))
          ..addFont(rootBundle.load('assets/fonts/Inter-Medium.otf'))
          ..addFont(rootBundle.load('assets/fonts/Inter-Bold.otf'));
    await fonts.load();
    await Supabase.initialize(
      url: 'https://placeholder.supabase.co',
      publishableKey: 'placeholder-publishable-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        throw StateError('Unexpected network request: ${request.url.path}');
      }),
    );
  });

  tearDownAll(() => Supabase.instance.dispose());

  testWidgets('Realtime failure does not hide loaded import destinations', (
    tester,
  ) async {
    final updates = StreamController<List<LibraryFolder>>();
    addTearDown(updates.close);
    await _openImportSheet(
      tester,
      repository: _LibraryRepository(),
      streamFactory: () => updates.stream,
    );
    updates.add([_database]);
    await tester.pumpAndSettle();
    await tester.tap(find.text(_database.name));
    await tester.pumpAndSettle();
    expect(find.text('Import (1)'), findsOneWidget);

    updates.addError(
      const RealtimeSubscribeException(RealtimeSubscribeStatus.channelError),
    );
    await tester.pumpAndSettle();

    expect(find.text('Couldn’t load your databases'), findsNothing);
    expect(find.text(_database.name), findsOneWidget);
    expect(find.text('Import (1)'), findsOneWidget);
    expect(
      tester
          .widget<PgnImportPreviewScreen>(
            find.byType(PgnImportPreviewScreen, skipOffstage: false),
          )
          .games,
      same(_games),
    );
  });

  testWidgets('Realtime failure before first data uses an HTTP folder read', (
    tester,
  ) async {
    final repository = _LibraryRepository();
    await _openImportSheet(
      tester,
      repository: repository,
      streamFactory:
          () => Stream.error(
            const RealtimeSubscribeException(RealtimeSubscribeStatus.timedOut),
          ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Couldn’t load your databases'), findsNothing);
    expect(find.text(_database.name), findsOneWidget);
    expect(repository.folderReads, 1);
  });

  testWidgets('Retry recovers a failed HTTP fallback without losing the PGN', (
    tester,
  ) async {
    final repository =
        _LibraryRepository()
          ..fetchFolders = () async => throw StateError('HTTP read failed');
    var subscriptions = 0;
    await _openImportSheet(
      tester,
      repository: repository,
      streamFactory: () {
        subscriptions++;
        return Stream.error(
          const RealtimeSubscribeException(RealtimeSubscribeStatus.timedOut),
        );
      },
    );
    await tester.pumpAndSettle();
    expect(find.text('Couldn’t load your databases'), findsOneWidget);
    expect(find.text('No folders yet. Create one below.'), findsNothing);

    repository.fetchFolders = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Couldn’t load your databases'), findsNothing);
    expect(find.text(_database.name), findsOneWidget);
    expect(subscriptions, 2);
    expect(repository.folderReads, 2);
    expect(
      tester
          .widget<PgnImportPreviewScreen>(
            find.byType(PgnImportPreviewScreen, skipOffstage: false),
          )
          .games,
      same(_games),
    );
  });

  testWidgets('a stalled HTTP fallback ends in Retry instead of spinning', (
    tester,
  ) async {
    final stalled = Completer<List<LibraryFolder>>();
    final repository =
        _LibraryRepository()..fetchFolders = () => stalled.future;
    await _openImportSheet(
      tester,
      repository: repository,
      streamFactory:
          () => Stream.error(
            const RealtimeSubscribeException(RealtimeSubscribeStatus.timedOut),
          ),
    );
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    stalled.complete([_database]);
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('the bulk save picker can retry the same folder loading error', (
    tester,
  ) async {
    var fail = true;
    await _openImportSheet(
      tester,
      repository: _LibraryRepository(),
      bulk: true,
      streamFactory:
          () =>
              fail
                  ? Stream.error(
                    StateError('Folder read failed'),
                    StackTrace.empty,
                  )
                  : Stream.value([_database]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);

    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text(_database.name), findsOneWidget);
    expect(find.text('Couldn’t load your databases'), findsNothing);
    expect(find.text('Error loading folders'), findsNothing);
  });

  testWidgets('live recovery wins over an older in-flight HTTP snapshot', (
    tester,
  ) async {
    final snapshot = Completer<List<LibraryFolder>>();
    final repository =
        _LibraryRepository()..fetchFolders = () => snapshot.future;
    final updates = StreamController<List<LibraryFolder>>();
    addTearDown(updates.close);
    await _openImportSheet(
      tester,
      repository: repository,
      streamFactory: () => updates.stream,
    );
    for (var i = 0; i < 3; i++) {
      updates.addError(
        const RealtimeSubscribeException(RealtimeSubscribeStatus.channelError),
      );
    }
    await tester.pump();
    expect(repository.folderReads, 1);

    final renamed = _database.copyWith(name: 'Updated preparation');
    updates.add([renamed]);
    await tester.pumpAndSettle();
    expect(find.text(renamed.name), findsOneWidget);

    snapshot.complete([_database]);
    await tester.pumpAndSettle();
    expect(find.text(renamed.name), findsOneWidget);
    expect(find.text(_database.name), findsNothing);

    updates.add([]);
    await tester.pumpAndSettle();
    expect(find.text(renamed.name), findsNothing);
    expect(find.text('No folders yet. Create one below.'), findsOneWidget);
  });

  test(
    'an old account’s pending snapshot cannot populate the new account',
    () async {
      final userIdProvider = StateProvider<String>((ref) => 'user-1');
      final snapshot = Completer<List<LibraryFolder>>();
      final repository =
          _LibraryRepository()..fetchFolders = () => snapshot.future;
      final updates = StreamController<List<LibraryFolder>>.broadcast();
      addTearDown(updates.close);
      final container = ProviderContainer(
        overrides: [
          libraryRepositoryProvider.overrideWithValue(repository),
          libraryFolderAuthenticatedUserIdProvider.overrideWith(
            (ref) => ref.watch(userIdProvider),
          ),
          libraryFolderStreamFactoryProvider.overrideWithValue(
            () => updates.stream,
          ),
        ],
      );
      addTearDown(container.dispose);
      final emitted = <List<LibraryFolder>>[];
      container.listen(
        libraryFoldersStreamProvider,
        (_, next) => next.whenData(emitted.add),
        fireImmediately: true,
      );
      updates.addError(
        const RealtimeSubscribeException(RealtimeSubscribeStatus.channelError),
      );
      await Future<void>.delayed(Duration.zero);
      expect(repository.folderReads, 1);

      container.read(userIdProvider.notifier).state = 'user-2';
      await container.pump();
      final other = _database.copyWith(id: 'database-2', userId: 'user-2');
      updates.add([other]);
      await container.read(libraryFoldersStreamProvider.future);
      snapshot.complete([_database]);
      await Future<void>.delayed(Duration.zero);

      expect(emitted, [
        [other],
      ]);
      expect(container.read(libraryFoldersStreamProvider).requireValue, [
        other,
      ]);
    },
  );

  test(
    'non-Realtime errors remain visible and receive scoped Sentry context',
    () async {
      final events = <SentryEvent>[];
      await Sentry.init((options) {
        options.dsn = 'https://public@example.invalid/1';
        options.sendClientReports = false;
        options.beforeSend = (event, hint) {
          events.add(event);
          return null; // Inspect locally; never send test events to Sentry.
        };
      });
      addTearDown(Sentry.close);
      final repository = _LibraryRepository();
      final updates = StreamController<List<LibraryFolder>>();
      addTearDown(updates.close);
      final container = ProviderContainer(
        overrides: [
          libraryRepositoryProvider.overrideWithValue(repository),
          libraryFolderAuthenticatedUserIdProvider.overrideWithValue('user-1'),
          libraryFolderStreamFactoryProvider.overrideWithValue(
            () => updates.stream,
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(libraryFoldersStreamProvider, (_, __) {});
      final error = StateError('Invalid folder response');
      final result = container.read(libraryFoldersStreamProvider.future);
      updates.addError(error, StackTrace.current);
      await expectLater(result, throwsA(same(error)));
      for (var i = 0; i < 20 && events.isEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(repository.folderReads, 0);
      expect(events, hasLength(1));
      expect(events.single.user?.id, 'user-1');
      expect(events.single.tags?['area'], 'library_destinations');
      expect(events.single.tags?['stage'], 'stream');
      updates.addError(error, StackTrace.current);
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));

      updates.add([_database]);
      await Future<void>.delayed(Duration.zero);
      updates.addError(StateError('A later failure'), StackTrace.current);
      for (var i = 0; i < 20 && events.length < 2; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(events, hasLength(2));
    },
  );

  testWidgets('a refused folder subscription still saves the parsed games', (
    tester,
  ) async {
    await Supabase.instance.client.auth.recoverSession(
      jsonEncode(
        Session(
          accessToken: 'test-access-token',
          refreshToken: 'test-refresh-token',
          tokenType: 'bearer',
          expiresIn: 3600,
          user: const User(
            id: 'user-1',
            appMetadata: {},
            userMetadata: {},
            aud: 'authenticated',
            createdAt: '2026-09-08T00:00:00Z',
          ),
        ).toJson(),
      ),
    );
    final repository = _LibraryRepository();
    await _openImportSheet(
      tester,
      repository: repository,
      streamFactory:
          () => Stream.error(
            // CHESSEVER-1WJ reports refused user_folders subscriptions on
            // phones. Importing must still work when HTTP succeeds.
            RealtimeSubscribeException(
              RealtimeSubscribeStatus.channelError,
              Exception(
                'Unable to subscribe to changes with given parameters. '
                'Please check Realtime is enabled for the given connect '
                'parameters: [event: *, schema: public, table: user_folders, '
                'filters: [{"user_id", "eq", "user-1", false}], select: nil]',
              ),
            ),
          ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(_database.name));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import (1)'));
    await tester.pumpAndSettle();

    expect(repository.saved, hasLength(2));
    expect(
      repository.saved.map((row) => row.folderId),
      everyElement(_database.id),
    );
    expect(repository.saved.map((row) => row.chessGame), orderedEquals(_games));
    expect(find.byType(PgnImportPreviewScreen), findsNothing);
    expect(find.text('Open PGN'), findsOneWidget);
  });
}
