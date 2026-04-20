import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/notation/notation_tree.dart';

/// Branded metadata headers appended to every exported game.
const _kBrandSite = 'https://chessever.com';
const _kBrandSource = 'Chessever';

/// Callback signature used by [exportFolderAsPgn] to report progress back to
/// the UI. [processed] is the number of games serialized so far; [total] is
/// the expected total (may equal `processed` once known).
typedef FolderExportProgress = void Function(int processed, int total);

/// Builds a single PGN string containing every game in a folder. Each game's
/// PGN headers are augmented with:
/// * `Site`: canonical chessever.com URL
/// * `Source`: "Chessever"
/// * `SourceURL`: direct link to the shared database (if [shareToken] is set)
///
/// Games are streamed in pages and concatenated with blank lines between them.
/// Progress updates are issued after each page via [onProgress], so the UI can
/// render a meaningful bar even on folders with thousands of games.
Future<String> exportFolderAsPgn({
  required LibraryRepository repo,
  required String folderId,
  required String folderName,
  required bool isSubscribed,
  String? shareToken,
  FolderExportProgress? onProgress,
}) async {
  const pageSize = 100;

  final int total =
      isSubscribed
          ? await repo.getSharedFolderAnalysisCount(folderId)
          : await repo.getAnalysisCountInFolder(folderId);

  onProgress?.call(0, total);

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

    onProgress?.call(processed, total > 0 ? total : processed);

    if (page.length < pageSize) break;
    offset += page.length;
  }

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

/// PGN export brand constants, exposed for tests / UI strings.
class FolderExportBrand {
  const FolderExportBrand._();
  static const String site = _kBrandSite;
  static const String source = _kBrandSource;
}
