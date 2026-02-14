import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
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
final folderAnalysisCountProvider =
    FutureProvider.autoDispose.family<int, String>((ref, folderId) async {
  final repository = ref.watch(libraryRepositoryProvider);
  return repository.getAnalysisCountInFolder(folderId);
});

