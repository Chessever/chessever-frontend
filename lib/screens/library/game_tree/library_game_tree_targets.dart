import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/library/utils/folder_pgn_exporter.dart';
import 'package:chessever2/services/game_tree/game_tree_service.dart';
import 'package:chessever2/widgets/game_tree/build_tree_button.dart';

/// A cloud Library database (owned or followed) as an opening tree.
class LibraryFolderTreeTarget extends RemoteGameTreeTarget {
  const LibraryFolderTreeTarget({required this.repository, required this.folder});

  final LibraryRepository repository;
  final LibraryFolder folder;

  @override
  String get scopeId => GameTreeService.scopeFor('library:${folder.id}');

  @override
  String get title => folder.displayName;

  Future<int> _count() => folder.isSubscribed
      ? repository.getSharedFolderAnalysisCount(folder.id)
      : repository.getDirectAnalysisCountInFolder(folder.id);

  @override
  Future<String> revision() async => '${await _count()}';

  @override
  Future<void> collect(
    void Function(String pgn) add,
    void Function(int done, int? total) progress,
    bool Function() canceled,
  ) async {
    final total = await _count();
    progress(0, total);
    await forEachFolderGamePgn(
      repo: repository,
      folder: folder,
      onGame: add,
      onProgress: (done) => progress(done, total),
      canceled: canceled,
    );
  }
}

/// My Likes as an opening tree: the reader's liked-games folder.
class LikedGamesTreeTarget extends RemoteGameTreeTarget {
  const LikedGamesTreeTarget({required this.repository});

  final LibraryRepository repository;

  @override
  String get scopeId => GameTreeService.scopeFor('library:liked-games');

  @override
  String get title => 'My Likes';

  Future<LibraryFolder> _folder() => repository.ensureLikedGamesFolder();

  @override
  Future<String> revision() async =>
      '${await repository.getDirectAnalysisCountInFolder((await _folder()).id)}';

  @override
  Future<void> collect(
    void Function(String pgn) add,
    void Function(int done, int? total) progress,
    bool Function() canceled,
  ) async {
    final folder = await _folder();
    final total = await repository.getDirectAnalysisCountInFolder(folder.id);
    progress(0, total);
    await forEachFolderGamePgn(
      repo: repository,
      folder: folder,
      onGame: add,
      onProgress: (done) => progress(done, total),
      canceled: canceled,
    );
  }
}

/// A published collection (a book or an event) as an opening tree. Its
/// games are read through the same gated endpoint opening one uses, after
/// the same access check.
class CollectionTreeTarget extends RemoteGameTreeTarget {
  const CollectionTreeTarget({
    required this.repository,
    required this.slug,
    required this.title,
    required this.requestAccess,
    this.knownGameCount,
  });

  final CollectionsRepository repository;
  final String slug;
  @override
  final String title;

  /// Asks for Premium when the collection is locked to this reader.
  final Future<bool> Function(Collection collection) requestAccess;

  /// The game count the screen already shows, saving a listing request.
  final int? knownGameCount;

  @override
  String get scopeId => GameTreeService.scopeFor('collection:$slug');

  @override
  Future<String> revision() async =>
      '${knownGameCount ?? (await repository.fetchGames(slug)).length}';

  @override
  Future<void> collect(
    void Function(String pgn) add,
    void Function(int done, int? total) progress,
    bool Function() canceled,
  ) async {
    final release = repository.holdFreshAccess(slug);
    try {
      final detail = await repository.fetchCollection(slug);
      if (detail.isPremium && detail.contentLocked != false) {
        if (!await requestAccess(detail)) throw const GameTreeCanceled();
      }
      if (canceled()) return;
      final games = await repository.fetchPlayableGames(slug);
      progress(0, games.length);
      var done = 0;
      for (final game in games) {
        if (canceled()) return;
        final pgn = game.game.pgn;
        if (pgn != null && pgn.trim().isNotEmpty) add(pgn);
        done++;
        if (done % 200 == 0) progress(done, games.length);
      }
      progress(done, games.length);
    } finally {
      release();
    }
  }
}
