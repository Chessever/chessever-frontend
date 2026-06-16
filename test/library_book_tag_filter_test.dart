import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/library/providers/book_games_paginated_provider.dart';
import 'package:chessever2/widgets/game_filter/game_filter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeLibraryRepository extends LibraryRepository {
  String? lastOwnedPageTag;
  String? lastOwnedCountTag;
  String? lastSharedPageTag;
  String? lastSharedCountTag;
  String? lastTagCountsFolderId;
  bool? lastTagCountsSubscribed;

  @override
  Future<List<SavedAnalysis>> getSavedAnalysesPaginated({
    required String folderId,
    required GameFilter filter,
    String search = '',
    String? tag,
    int limit = 30,
    int offset = 0,
  }) async {
    lastOwnedPageTag = tag;
    return const <SavedAnalysis>[];
  }

  @override
  Future<int> getFilteredAnalysisCountInFolder({
    required String folderId,
    required GameFilter filter,
    String search = '',
    String? tag,
  }) async {
    lastOwnedCountTag = tag;
    return 7;
  }

  @override
  Future<List<SavedAnalysis>> getSharedFolderAnalysesPaginated({
    required String folderId,
    required GameFilter filter,
    String search = '',
    String? tag,
    int limit = 30,
    int offset = 0,
  }) async {
    lastSharedPageTag = tag;
    return const <SavedAnalysis>[];
  }

  @override
  Future<int> getFilteredSharedFolderAnalysisCount({
    required String folderId,
    required GameFilter filter,
    String search = '',
    String? tag,
  }) async {
    lastSharedCountTag = tag;
    return 3;
  }

  @override
  Future<Map<String, int>> getTagCountsInFolder({
    required String folderId,
    bool isSubscribed = false,
  }) async {
    lastTagCountsFolderId = folderId;
    lastTagCountsSubscribed = isSubscribed;
    return const <String, int>{'Sacrifice': 2};
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://placeholder.supabase.co',
      anonKey: 'placeholder-anon-key',
    );
  });

  test(
    'owned database pagination sends selected tag to page and count queries',
    () async {
      final repo = _FakeLibraryRepository();
      final container = ProviderContainer(
        overrides: [libraryRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      final state = await container.read(
        bookGamesPaginatedProvider(
          BookPaginationKey(
            folderId: 'folder-1',
            filter: GameFilter.defaultFilter(),
            tag: 'Sacrifice',
          ),
        ).future,
      );

      expect(state.totalCount, 7);
      expect(repo.lastOwnedPageTag, 'Sacrifice');
      expect(repo.lastOwnedCountTag, 'Sacrifice');
    },
  );

  test(
    'shared database pagination sends selected tag to page and count queries',
    () async {
      final repo = _FakeLibraryRepository();
      final container = ProviderContainer(
        overrides: [libraryRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      final state = await container.read(
        bookGamesPaginatedProvider(
          BookPaginationKey(
            folderId: 'shared-1',
            isSubscribed: true,
            filter: GameFilter.defaultFilter(),
            tag: 'Trap',
          ),
        ).future,
      );

      expect(state.totalCount, 3);
      expect(repo.lastSharedPageTag, 'Trap');
      expect(repo.lastSharedCountTag, 'Trap');
    },
  );

  test('folder tag counts preserve subscribed query mode', () async {
    final repo = _FakeLibraryRepository();
    final container = ProviderContainer(
      overrides: [libraryRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    final counts = await container.read(
      folderTagCountsProvider(
        const FolderTagCountsKey(folderId: 'shared-1', isSubscribed: true),
      ).future,
    );

    expect(counts, const <String, int>{'Sacrifice': 2});
    expect(repo.lastTagCountsFolderId, 'shared-1');
    expect(repo.lastTagCountsSubscribed, isTrue);
  });
}
