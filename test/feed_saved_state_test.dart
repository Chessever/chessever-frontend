import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/feed/widgets/feed_save.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Save's "Saved" is read from the database: a copy of the game in any
/// folder but My Likes. A like is told from a save by the folder it sits in,
/// not by the likes this session happened to load.
void main() {
  final like = _row('like-1', _likesFolder);
  final copy = _row('copy-1', 'openings-db');

  test('a like alone is not a save', () async {
    expect(await _saved(copies: [like], likes: [like]), isFalse);
  });

  test('a like the session\'s likes do not hold is still not a save: made '
      'on another device, or an unlike whose row is not deleted yet', () async {
    expect(await _saved(copies: [like], likes: const []), isFalse);
  });

  test('a copy in one of the viewer\'s databases is a save, liked or not', () {
    expectLater(_saved(copies: [copy], likes: const []), completion(isTrue));
    expectLater(
      _saved(copies: [like, copy], likes: [like]),
      completion(isTrue),
    );
  });

  test('a save still shows when the likes failed to load', () async {
    expect(
      await _saved(copies: [like, copy], likes: const [], likesFail: true),
      isTrue,
    );
  });

  test('no copies, no save', () async {
    expect(await _saved(copies: const [], likes: const []), isFalse);
  });

  test('without the My Likes folder, the session\'s likes tell them apart', () {
    expectLater(
      _saved(copies: [like], likes: [like], folderFails: true),
      completion(isFalse),
    );
    expectLater(
      _saved(copies: [like, copy], likes: [like], folderFails: true),
      completion(isTrue),
    );
  });

  test('a lookup that fails offers Save', () async {
    expect(
      await _saved(copies: [copy], likes: const [], lookupFails: true),
      isFalse,
    );
  });

  test('signed out, nothing is saved and nothing is read', () async {
    final repo = _Repo([copy]);
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWithValue(null),
        libraryRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    expect(await container.read(feedGameSavedProvider('g0').future), isFalse);
    expect(repo.reads, 0);
  });
}

const _likesFolder = 'likes-folder';

Future<bool> _saved({
  required List<SavedAnalysis> copies,
  required List<SavedAnalysis> likes,
  bool likesFail = false,
  bool folderFails = false,
  bool lookupFails = false,
}) async {
  final container = ProviderContainer(
    overrides: [
      currentUserProvider.overrideWithValue(
        AppUser(id: 'u1', createdAt: DateTime(2026)),
      ),
      libraryRepositoryProvider.overrideWithValue(
        _Repo(copies, fails: lookupFails),
      ),
      likedGamesFolderProvider.overrideWith((ref) async {
        if (folderFails) throw StateError('offline');
        return _folder();
      }),
      likedGamesProvider.overrideWith(() => _Likes(likes, fails: likesFail)),
    ],
  );
  addTearDown(container.dispose);
  // The Feed holds the likes while it shows a post.
  container.listen(likedGamesProvider, (_, _) {});
  return container.read(feedGameSavedProvider('g0').future);
}

LibraryFolder _folder() => LibraryFolder(
  id: _likesFolder,
  userId: 'u1',
  name: 'My Likes',
  color: '#F5453A',
  icon: 'liked',
  orderIndex: 0,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  isLikedGames: true,
);

SavedAnalysis _row(String id, String folderId) => SavedAnalysis(
  id: id,
  userId: 'u1',
  folderId: folderId,
  title: 'Carlsen vs Nakamura',
  sourceGameId: 'g0',
  chessGame: ChessGame.fromPgn('g0', '1. e4 e5 *'),
  analysisState: const {},
  variationComments: const {},
  lastViewedPosition: -1,
  tags: const [],
  isFavorite: false,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

class _Repo implements LibraryRepository {
  _Repo(this.copies, {this.fails = false});

  final List<SavedAnalysis> copies;
  final bool fails;
  int reads = 0;

  @override
  Future<List<SavedAnalysis>> getSavedAnalysesBySourceGame({
    required String sourceGameId,
  }) async {
    reads++;
    if (fails) throw StateError('offline');
    return [
      for (final copy in copies)
        if (copy.sourceGameId == sourceGameId) copy,
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Likes extends LikedGamesNotifier {
  _Likes(this.rows, {this.fails = false});

  final List<SavedAnalysis> rows;
  final bool fails;

  @override
  Future<List<SavedAnalysis>> build() async {
    if (fails) throw StateError('offline');
    return rows;
  }
}
