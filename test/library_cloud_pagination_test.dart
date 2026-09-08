import 'dart:async';

import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/library/providers/book_games_paginated_provider.dart';
import 'package:chessever2/screens/library/providers/library_auth_provider.dart';
import 'package:chessever2/screens/library/providers/library_cloud_changes_provider.dart';
import 'package:chessever2/widgets/game_filter/game_filter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Repository extends LibraryRepository {
  List<SavedAnalysis> rows = [];
  int reads = 0;
  int? lastLimit;
  int? responseCap;
  final requestedLimits = <int>[];
  String? lastSearch;
  List<String>? lastTags;
  Completer<List<SavedAnalysis>>? pendingPage;
  bool fail = false;

  @override
  Future<List<SavedAnalysis>> getSavedAnalysesPaginated({
    required String folderId,
    required GameFilter filter,
    String search = '',
    List<String> tags = const [],
    int limit = 30,
    int offset = 0,
  }) async {
    reads++;
    lastLimit = limit;
    requestedLimits.add(limit);
    lastSearch = search;
    lastTags = tags;
    if (fail) throw StateError('temporary read failure');
    if (offset > 0 && pendingPage != null) return pendingPage!.future;
    final page = rows.skip(offset).take(limit);
    return (responseCap == null ? page : page.take(responseCap!)).toList();
  }

  @override
  Future<int> getFilteredAnalysisCountInFolder({
    required String folderId,
    required GameFilter filter,
    String search = '',
    List<String> tags = const [],
  }) async => rows.length;
}

final _game = ChessGame.fromPgn('fixture', '1. e4 e5 *');
List<SavedAnalysis> _rows(String title) => List.generate(
  90,
  (index) => SavedAnalysis(
    id: 'game-$index',
    userId: 'account-a',
    folderId: 'database-a',
    title: title,
    chessGame: _game,
    analysisState: const {},
    variationComments: const {},
    lastViewedPosition: 0,
    tags: const ['Preparation'],
    isFavorite: false,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  ),
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://placeholder.supabase.co',
      publishableKey: 'placeholder-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(
        (_) async => throw StateError('No network in tests'),
      ),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());

  for (final scenario in [
    (pending: false, cap: null),
    (pending: true, cap: null),
    (pending: false, cap: 30),
  ]) {
    final pendingLoadMore = scenario.pending;
    testWidgets(
      'remote save preserves pages, filters and newer data ($scenario)',
      (tester) async {
        final repo =
            _Repository()
              ..rows = _rows('Before remote save')
              ..responseCap = scenario.cap;
        final revision = StateProvider<int>((ref) => 0);
        final container = ProviderContainer(
          overrides: [
            libraryRepositoryProvider.overrideWithValue(repo),
            libraryFolderAuthenticatedUserIdProvider.overrideWithValue(
              'account-a',
            ),
            libraryCloudRevisionProvider.overrideWith(
              (ref) => (userId: 'account-a', revision: ref.watch(revision)),
            ),
          ],
        );
        final key = BookPaginationKey(
          folderId: 'database-a',
          filter: GameFilter.defaultFilter(),
          search: 'Opening',
          tags: ['Preparation'],
        );
        final provider = bookGamesPaginatedProvider(key);
        container.listen(provider, (_, __) {});
        await tester.pump(Duration.zero);
        expect(container.read(provider).requireValue.games, hasLength(30));
        final oldPage = Completer<List<SavedAnalysis>>();
        if (pendingLoadMore) repo.pendingPage = oldPage;
        final loadMore = container.read(provider.notifier).loadMore();
        await tester.pump(Duration.zero);
        if (!pendingLoadMore) {
          await loadMore;
          expect(container.read(provider).requireValue.games, hasLength(60));
        }

        repo.rows = _rows('Saved on the other device');
        container.read(revision.notifier).state++;
        expect(container.read(libraryCloudRevisionProvider).revision, 1);
        await tester.pump(Duration.zero);
        await tester.pump(Duration.zero);
        expect(repo.requestedLimits, contains(60));
        expect(repo.lastSearch, 'Opening');
        expect(repo.lastTags, ['Preparation']);
        expect(container.read(provider).requireValue.games, hasLength(60));
        expect(
          container.read(provider).requireValue.games.first.title,
          'Saved on the other device',
        );
        if (pendingLoadMore) {
          oldPage.complete(
            _rows('Old in-flight result').skip(30).take(30).toList(),
          );
          await tester.pump(Duration.zero);
          await loadMore;
          expect(
            container.read(provider).requireValue.games.first.title,
            'Saved on the other device',
          );
        }

        repo.fail = true;
        container.read(revision.notifier).state++;
        await tester.pump(Duration.zero);
        await tester.pump(Duration.zero);
        expect(container.read(provider).requireValue.games, hasLength(60));
        container.dispose();
        await tester.pump(Duration.zero);
      },
    );
  }
}
