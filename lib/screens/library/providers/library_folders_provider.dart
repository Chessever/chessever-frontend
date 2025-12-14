import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final libraryFoldersStreamProvider =
    StreamProvider.autoDispose<List<LibraryFolder>>((ref) {
  final repository = ref.watch(libraryRepositoryProvider);
  return repository.subscribeFolders();
});

