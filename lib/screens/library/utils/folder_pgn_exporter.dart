import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/chessboard/notation/notation_tree.dart';

/// Branded metadata headers appended to every exported game.
const _kBrandSite = 'https://chessever.com';
const _kBrandSource = 'Chessever';

/// Callback signature used by [exportFolderAsPgn] to report progress back to
/// the UI. [processed] is the number of games serialized so far; [total] is
/// the expected total (may equal `processed` once known).
typedef FolderExportProgress = void Function(int processed, int total);

/// A single PGN file produced by [exportFolderTreeAsPgnFiles]. Each entry
/// maps 1:1 to one folder in the tree — the root plus one per sub-database.
class FolderPgnFile {
  final String filename;
  final String pgn;
  final int gameCount;

  const FolderPgnFile({
    required this.filename,
    required this.pgn,
    required this.gameCount,
  });
}

/// Builds a single PGN string containing every game in a folder. Each game's
/// PGN headers are augmented with:
/// * `Site`: canonical chessever.com URL
/// * `Source`: "Chessever"
/// * `SourceURL`: direct link to the shared database (if [shareToken] is set)
///
/// Only the folder's **direct** games are included — sub-database games are
/// exported separately via [exportFolderTreeAsPgnFiles]. Games are streamed
/// in pages and concatenated with blank lines between them. Progress updates
/// are issued after each page via [onProgress].
Future<String> exportFolderAsPgn({
  required LibraryRepository repo,
  required String folderId,
  required String folderName,
  required bool isSubscribed,
  String? shareToken,
  FolderExportProgress? onProgress,
}) async {
  final total = await repo.getDirectAnalysisCountInFolder(folderId);
  onProgress?.call(0, total);

  final pgn = await _streamFolderPgn(
    repo: repo,
    folderId: folderId,
    folderName: folderName,
    isSubscribed: isSubscribed,
    shareToken: shareToken,
    expectedTotal: total,
    onFolderProgress: (processed) => onProgress?.call(processed, total),
  );
  return pgn;
}

/// Exports [rootFolder] plus each of its direct [childFolders] as separate
/// PGN files. Folders with zero direct games are skipped so users don't end
/// up with empty files in the share sheet. Progress is reported as a single
/// overall count across the whole subtree.
///
/// The share-token / source-URL metadata only makes sense for the root
/// (subscribed books are shared at the root level), so it's applied to the
/// root's PGN and each child uses its own [LibraryFolder.shareToken] if any.
Future<List<FolderPgnFile>> exportFolderTreeAsPgnFiles({
  required LibraryRepository repo,
  required LibraryFolder rootFolder,
  required List<LibraryFolder> childFolders,
  String? rootShareToken,
  FolderExportProgress? onProgress,
}) async {
  final folders = <LibraryFolder>[rootFolder, ...childFolders];

  final counts = <int>[];
  for (final f in folders) {
    counts.add(await repo.getDirectAnalysisCountInFolder(f.id));
  }
  final overallTotal = counts.fold<int>(0, (a, b) => a + b);
  onProgress?.call(0, overallTotal);

  final results = <FolderPgnFile>[];
  var processedAcross = 0;

  for (var i = 0; i < folders.length; i++) {
    final folder = folders[i];
    final folderTotal = counts[i];
    if (folderTotal == 0) continue;

    final baseBefore = processedAcross;
    final pgn = await _streamFolderPgn(
      repo: repo,
      folderId: folder.id,
      folderName: folder.name,
      isSubscribed: folder.isSubscribed,
      shareToken:
          folder.id == rootFolder.id ? rootShareToken : folder.shareToken,
      expectedTotal: folderTotal,
      onFolderProgress: (processed) {
        onProgress?.call(baseBefore + processed, overallTotal);
      },
    );

    if (pgn.trim().isEmpty) {
      processedAcross = baseBefore + folderTotal;
      continue;
    }

    results.add(
      FolderPgnFile(
        filename: _filenameForFolder(root: rootFolder, folder: folder),
        pgn: pgn,
        gameCount: folderTotal,
      ),
    );

    processedAcross = baseBefore + folderTotal;
    onProgress?.call(processedAcross, overallTotal);
  }

  return results;
}

/// Core page-streaming loop. Shared by [exportFolderAsPgn] and
/// [exportFolderTreeAsPgnFiles] so both paths produce byte-identical output
/// for the same folder.
Future<String> _streamFolderPgn({
  required LibraryRepository repo,
  required String folderId,
  required String folderName,
  required bool isSubscribed,
  required String? shareToken,
  required int expectedTotal,
  void Function(int processed)? onFolderProgress,
}) async {
  const pageSize = 100;

  final buffer = StringBuffer();
  var processed = 0;
  var offset = 0;

  while (true) {
    final List<SavedAnalysis> page =
        isSubscribed
            ? await repo.getSharedFolderAnalysesPaginated(
              folderId: folderId,
              limit: pageSize,
              offset: offset,
            )
            : await repo.getSavedAnalysesPaginated(
              folderId: folderId,
              limit: pageSize,
              offset: offset,
            );

    if (page.isEmpty) break;

    for (final analysis in page) {
      final pgn = _serializeAnalysis(
        analysis,
        folderName: folderName,
        shareToken: shareToken,
      );
      if (pgn.trim().isEmpty) continue;
      if (buffer.isNotEmpty) buffer.write('\n\n');
      buffer.write(pgn.trimRight());
      processed += 1;
    }

    onFolderProgress?.call(processed);

    if (page.length < pageSize) break;
    offset += page.length;
  }

  if (buffer.isEmpty) return '';
  // Guarantee trailing newline per PGN convention.
  if (!buffer.toString().endsWith('\n')) buffer.write('\n');
  return buffer.toString();
}

String _serializeAnalysis(
  SavedAnalysis analysis, {
  required String folderName,
  String? shareToken,
}) {
  // Clone the game with augmented metadata; original analysis is untouched.
  final md = Map<String, dynamic>.from(analysis.chessGame.metadata);
  md['Site'] = _kBrandSite;
  md['Source'] = _kBrandSource;
  md['Database'] = folderName;
  if (shareToken != null && shareToken.isNotEmpty) {
    md['SourceURL'] = '$_kBrandSite/books/$shareToken';
  }

  final branded = analysis.chessGame.copyWith(metadata: md);
  return exportGameToPgn(branded);
}

/// Suggested filename for a folder export (safe ASCII, short).
String suggestedExportFilename(String folderName) {
  final sanitized = folderName
      .replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_')
      .replaceAll(RegExp(r'_+'), '_');
  final base = sanitized.isEmpty ? 'chessever_database' : sanitized;
  return '$base.pgn';
}

/// Root files keep the folder name as-is; child files are prefixed with the
/// root so files land adjacent in any share target and collisions across
/// unrelated roots are avoided.
String _filenameForFolder({
  required LibraryFolder root,
  required LibraryFolder folder,
}) {
  if (folder.id == root.id) return suggestedExportFilename(folder.name);
  return suggestedExportFilename('${root.name}__${folder.name}');
}

/// PGN export brand constants, exposed for tests / UI strings.
class FolderExportBrand {
  const FolderExportBrand._();
  static const String site = _kBrandSite;
  static const String source = _kBrandSource;
}
