import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/shared_book_preview.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Special TWIC book identifier — not a real Supabase folder.
const kTwicBookId = '__twic__';

/// Synthetic TWIC folder for display in the library list.
final kTwicFolder = LibraryFolder(
  id: kTwicBookId,
  userId: '',
  name: 'TWIC',
  color: '#0FB4E5',
  icon: 'twic',
  orderIndex: -1,
  createdAt: DateTime(2000),
  updatedAt: DateTime(2000),
);

final libraryFoldersStreamProvider =
    StreamProvider.autoDispose<List<LibraryFolder>>((ref) {
      final repository = ref.watch(libraryRepositoryProvider);
      return repository.subscribeFolders();
    });

/// Analysis count per folder for subtitle display
final folderAnalysisCountProvider = FutureProvider.autoDispose
    .family<int, String>((ref, folderId) async {
      final repository = ref.watch(libraryRepositoryProvider);
      return repository.getAnalysisCountInFolder(folderId);
    });

/// Fetches folders the current user is subscribed to.
final subscribedBooksProvider = FutureProvider.autoDispose<List<LibraryFolder>>(
  (ref) async {
    final repository = ref.watch(libraryRepositoryProvider);
    return repository.getSubscribedBooks();
  },
);

/// Combined library folders: owned folders + subscribed books.
/// Owned folders come first (order_index), then subscribed books (alphabetical).
final combinedLibraryFoldersProvider =
    FutureProvider.autoDispose<List<LibraryFolder>>((ref) async {
      // Watch both owned stream and subscribed future
      final ownedAsync = ref.watch(libraryFoldersStreamProvider);
      final subscribedAsync = ref.watch(subscribedBooksProvider);

      final owned = ownedAsync.valueOrNull ?? [];
      final subscribed = subscribedAsync.valueOrNull ?? [];

      return [...owned, ...subscribed];
    });

/// Top-level (root) folders only
final rootLibraryFoldersProvider = Provider.autoDispose<List<LibraryFolder>>((
  ref,
) {
  final all = ref.watch(combinedLibraryFoldersProvider).valueOrNull ?? [];
  return all.where((f) => f.parentId == null).toList();
});

/// Children of a specific folder
final childLibraryFoldersProvider = Provider.autoDispose
    .family<List<LibraryFolder>, String>((ref, parentId) {
      final all = ref.watch(combinedLibraryFoldersProvider).valueOrNull ?? [];
      return all.where((f) => f.parentId == parentId).toList();
    });

/// Top 3 most recently updated databases for quick selection
final recentDatabasesProvider = Provider.autoDispose<List<LibraryFolder>>((
  ref,
) {
  final all = ref.watch(combinedLibraryFoldersProvider).valueOrNull ?? [];
  // Exclude TWIC and the special Liked Games folder; sort by updatedAt desc.
  final owned = all.where((f) => f.id != kTwicBookId && !f.isLikedGames).toList();
  owned.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return owned.take(3).toList();
});

/// Preview data for a shared book by its share token (for deep link landing).
final sharedBookPreviewProvider = FutureProvider.autoDispose
    .family<SharedBookPreview?, String>((ref, shareToken) async {
      final repository = ref.watch(libraryRepositoryProvider);
      return repository.getBookByShareToken(shareToken);
    });
