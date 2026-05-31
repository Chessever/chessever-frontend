import 'dart:io';

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/library/pgn_import_preview_screen.dart';
import 'package:chessever2/screens/gamebase/widgets/position_games_sheet.dart';
import 'package:chessever2/screens/library/providers/book_games_paginated_provider.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/screens/library/utils/folder_pgn_exporter.dart';
import 'package:chessever2/screens/library/utils/load_saved_analysis.dart';
import 'package:chessever2/screens/library/widgets/add_to_library_sheet.dart';
import 'package:chessever2/screens/library/widgets/book_saved_game_card.dart';
import 'package:chessever2/screens/library/widgets/create_folder_dialog.dart';
import 'package:chessever2/screens/library/widgets/folder_card.dart';
import 'package:chessever2/screens/library/widgets/swipe_action_card.dart';
import 'package:chessever2/services/pgn_file_intake_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/pgn_multi_parser.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:file_picker/file_picker.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class FolderContentsScreen extends ConsumerStatefulWidget {
  final LibraryFolder folder;

  const FolderContentsScreen({super.key, required this.folder});

  @override
  ConsumerState<FolderContentsScreen> createState() =>
      _FolderContentsScreenState();
}

class _FolderContentsScreenState extends ConsumerState<FolderContentsScreen> {
  late final ScrollController _scrollController;
  late final TextEditingController _searchController;
  late final BookPaginationKey _paginationKey;
  final Set<String> _removingIds = {};
  GamebaseSortField _sortBy = GamebaseSortField.date;
  GamebaseSortDirection _sortDirection = GamebaseSortDirection.desc;
  // Overrides widget.folder.name after an in-place rename so the header
  // reflects the new name without needing to pop/reopen.
  String? _overrideFolderName;

  bool get _isSubscribed => widget.folder.isSubscribed;
  bool get _isFolder => widget.folder.isFolder;
  bool get _isDatabase => widget.folder.isDatabase;

  String get _currentFolderName => _overrideFolderName ?? widget.folder.name;

  @override
  void initState() {
    super.initState();
    _paginationKey = BookPaginationKey(
      folderId: widget.folder.id,
      isSubscribed: _isSubscribed,
    );
    _scrollController = ScrollController()..addListener(_onScroll);
    _searchController =
        TextEditingController()..addListener(() {
          setState(() {});
        });

    // Reset pagination state for this folder
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(bookGamesPaginatedProvider(_paginationKey).notifier).refresh();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    // Trigger load more when within 200px of the bottom.
    if (currentScroll >= maxScroll - 200) {
      ref.read(bookGamesPaginatedProvider(_paginationKey).notifier).loadMore();
    }
  }

  void _clearSearch() {
    HapticFeedbackService.light();
    _searchController.clear();
  }

  void _showSortOptions() {
    HapticFeedbackService.buttonPress();
    showGamebaseSortOptions(
      context: context,
      sortBy: _sortBy,
      sortDirection: _sortDirection,
      onChanged: (field, direction) {
        if (!mounted) return;
        setState(() {
          _sortBy = field;
          _sortDirection = direction;
        });
      },
    );
  }

  Future<void> _removeAnalysis(SavedAnalysis analysis) async {
    if (_removingIds.contains(analysis.id)) return;

    HapticFeedbackService.medium();
    _removingIds.add(analysis.id);

    final repository = ref.read(libraryRepositoryProvider);
    try {
      // Hard delete the row so the free-tier save counter (which sums
      // all user_saved_analyses rows, folder or not) reflects reality.
      // Previously we set folder_id = NULL which kept the row alive and
      // accumulated phantom orphans that still counted toward the cap.
      await repository.deleteSavedAnalysis(analysis.id);

      if (!mounted) return;
      // Refresh the paginated list after removal.
      ref.read(bookGamesPaginatedProvider(_paginationKey).notifier).refresh();
      // Library home cards cache per-folder game counts; without this
      // invalidation they keep showing the pre-delete number until app restart.
      ref.invalidate(folderAnalysisCountProvider);
      ref.invalidate(libraryFoldersStreamProvider);

      // Snapshot the deleted analysis so Undo can re-insert it. The new
      // row gets a fresh id; chess_game / analysis_state / variation
      // comments / move nags are preserved so the user's work survives.
      final snapshot = analysis;
      final targetFolderId = widget.folder.id;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Removed from "${widget.folder.name}"',
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          backgroundColor: context.colors.surface.withValues(alpha: 0.95),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Undo',
            textColor: kPrimaryColor,
            onPressed: () async {
              try {
                final now = DateTime.now();
                final restored = SavedAnalysis(
                  id: '',
                  userId: snapshot.userId,
                  folderId: targetFolderId,
                  title: snapshot.title,
                  sourceGameId: snapshot.sourceGameId,
                  sourceTournamentId: snapshot.sourceTournamentId,
                  chessGame: snapshot.chessGame,
                  analysisState: snapshot.analysisState,
                  variationComments: snapshot.variationComments,
                  moveNags: snapshot.moveNags,
                  lastViewedPosition: snapshot.lastViewedPosition,
                  tags: snapshot.tags,
                  notes: snapshot.notes,
                  isFavorite: snapshot.isFavorite,
                  createdAt: snapshot.createdAt,
                  updatedAt: now,
                );
                await repository.createSavedAnalysis(restored);
                if (!mounted) return;
                ref
                    .read(bookGamesPaginatedProvider(_paginationKey).notifier)
                    .refresh();
                ref.invalidate(folderAnalysisCountProvider);
                ref.invalidate(libraryFoldersStreamProvider);
              } catch (_) {
                // Best-effort undo; show nothing if it fails.
              }
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _removingIds.remove(analysis.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to remove: $e',
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          backgroundColor: kRedColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handlePlusButton() async {
    HapticFeedbackService.light();
    final choice = await showAddToLibrarySheet(
      context,
      title: 'Add to "$_currentFolderName"',
      showCreateDatabase: _isFolder,
      createDatabaseTitle: 'Create Folder or Database',
      createDatabaseSubtitle: 'Organize another folder or game database here',
      showImports: _isDatabase,
    );
    if (choice == null || !mounted) return;

    switch (choice) {
      case AddToLibraryChoice.createDatabase:
        await _handleCreateChildNode();
      case AddToLibraryChoice.importPgn:
        await _handleImportPgnFromClipboard();
      case AddToLibraryChoice.pickPgnFile:
        await _handlePickPgnFile();
    }
  }

  Future<void> _handlePickPgnFile() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pgn'],
        withData: false,
      );
    } catch (_) {
      try {
        result = await FilePicker.platform.pickFiles(type: FileType.any);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not open file picker: $e',
              style: AppTypography.textSmMedium.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
            backgroundColor: kRedColor.withValues(alpha: 0.9),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    final path = result?.files.singleOrNull?.path;
    if (path == null || path.isEmpty) return;
    if (!mounted) return;
    await PgnFileIntakeService.instance.ingestPgnFileFromContext(
      context: context,
      path: path,
      sourceLabel: 'device file',
      initialFolderId: widget.folder.id,
    );
    if (!mounted) return;
    ref.read(bookGamesPaginatedProvider(_paginationKey).notifier).refresh();
    ref.invalidate(folderAnalysisCountProvider);
    ref.invalidate(libraryFoldersStreamProvider);
  }

  Future<void> _handleImportPgnFromClipboard() async {
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clipboard?.text?.trim();
    if (text == null || text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Clipboard is empty. Copy a PGN first.',
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          backgroundColor: context.colors.surface.withValues(alpha: 0.95),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final parsed = parsePgnsToChessGames(text);
    if (parsed.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Clipboard does not contain a valid PGN',
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          backgroundColor: kRedColor.withValues(alpha: 0.9),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => PgnImportPreviewScreen(
              games: parsed.map((e) => e.chessGame).toList(),
              initialFolderId: widget.folder.id,
              sourceLabel: 'clipboard',
            ),
      ),
    );
    if (!mounted) return;
    // Refresh in case games were saved into this folder from the sheet.
    ref.read(bookGamesPaginatedProvider(_paginationKey).notifier).refresh();
    ref.invalidate(folderAnalysisCountProvider);
    ref.invalidate(libraryFoldersStreamProvider);
  }

  Future<void> _handleCreateChildNode() async {
    final data = await showCreateFolderDialog(
      context,
      initialParentId: widget.folder.id,
      lockToParent: true,
    );
    if (data == null || data.name.trim().isEmpty) return;

    try {
      await ref
          .read(libraryRepositoryProvider)
          .createFolder(
            name: data.name,
            parentId: data.parentId,
            nodeType: data.nodeType,
          );
      ref.invalidate(libraryFoldersStreamProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${data.nodeType == LibraryFolder.nodeTypeFolder ? 'Folder' : 'Database'} "${data.name}" created',
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          backgroundColor: context.colors.surface.withValues(alpha: 0.95),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to create item: $e',
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          backgroundColor: kRedColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleRename() async {
    HapticFeedbackService.light();
    final nextName = await showRenameFolderDialog(
      context,
      currentName: _currentFolderName,
    );
    final name = nextName?.trim();
    if (name == null || name.isEmpty || name == _currentFolderName) return;

    try {
      final repo = ref.read(libraryRepositoryProvider);
      await repo.updateFolder(
        widget.folder.copyWith(name: name, updatedAt: DateTime.now()),
      );
      ref.invalidate(libraryFoldersStreamProvider);
      if (!mounted) return;
      HapticFeedbackService.success();
      setState(() {
        _overrideFolderName = name;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Renamed to "$name"',
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          backgroundColor: context.colors.surface.withValues(alpha: 0.95),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      HapticFeedbackService.error();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to rename: $e',
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          backgroundColor: kRedColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleExportPgn() async {
    HapticFeedbackService.medium();

    final repo = ref.read(libraryRepositoryProvider);
    // Children are child nodes directly under this folder. Empty for
    // leaf / sub-level folders, which cleanly degrades to a single-file
    // export via the tree helper.
    final childFolders = ref.read(
      childLibraryFoldersProvider(widget.folder.id),
    );
    final dialogController = _ExportProgressController();

    // Show the progress dialog (non-dismissible) while export runs.
    final dialogFuture = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ExportProgressDialog(controller: dialogController),
    );

    List<FolderPgnFile>? files;
    Object? error;
    try {
      files = await exportFolderTreeAsPgnFiles(
        repo: repo,
        rootFolder: widget.folder,
        childFolders: childFolders,
        rootShareToken: widget.folder.shareToken,
        onProgress: (processed, total) {
          dialogController.update(processed: processed, total: total);
        },
      );
    } catch (e) {
      error = e;
    }

    // Dismiss the progress dialog.
    dialogController.close();
    await dialogFuture;

    if (!mounted) return;

    if (error != null || files == null || files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error != null
                ? 'Export failed: $error'
                : 'Nothing to export in this database',
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          backgroundColor: kRedColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final xFiles = <XFile>[];
      for (final entry in files) {
        final file = File('${tempDir.path}/${entry.filename}');
        await file.writeAsString(entry.pgn);
        xFiles.add(XFile(file.path, mimeType: 'application/x-chess-pgn'));
      }

      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      final origin =
          box != null
              ? box.localToGlobal(Offset.zero) & box.size
              : const Rect.fromLTWH(0, 0, 1, 1);

      final subject =
          xFiles.length > 1
              ? '${widget.folder.name} - Chessever PGN (${xFiles.length} files)'
              : '${widget.folder.name} - Chessever PGN';

      await Share.shareXFiles(
        xFiles,
        subject: subject,
        sharePositionOrigin: origin,
      );
      HapticFeedbackService.success();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Share failed: $e',
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          backgroundColor: kRedColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookAsync = ref.watch(bookGamesPaginatedProvider(_paginationKey));
    final query = _searchController.text.trim().toLowerCase();

    return Scaffold(
      key: e2eKey(E2eIds.folderContentsRoot),
      backgroundColor: context.colors.background,
      body: ScreenWrapper(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth:
                  ResponsiveHelper.isTablet
                      ? ResponsiveHelper.contentMaxWidth
                      : double.infinity,
            ),
            child: Column(
              children: [
                _buildTopArea(context, bookAsync),
                Expanded(child: _buildSavedGames(bookAsync, query)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopArea(
    BuildContext context,
    AsyncValue<PaginatedBookState> bookAsync,
  ) {
    final topPadding = MediaQuery.of(context).viewPadding.top;

    return Container(
      padding: EdgeInsets.only(top: topPadding + 8.h, bottom: 6.h),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            context.colors.background,
            context.colors.background.withValues(alpha: 0),
          ],
        ),
      ),
      child: Column(
        children: [_buildHeader(context, bookAsync), _buildSearchBar()],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    AsyncValue<PaginatedBookState> bookAsync,
  ) {
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 8.w,
      tablet: 16.w,
    );
    final totalCount = _isDatabase ? bookAsync.valueOrNull?.totalCount : null;

    final bool showExport =
        _isDatabase && (bookAsync.valueOrNull?.totalCount ?? 0) > 0;
    final bool showRename = !_isSubscribed;
    final bool showAdd = !_isSubscribed;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        0,
        horizontalPadding,
        8.h,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            onPressed: () {
              HapticFeedbackService.light();
              Navigator.of(context).pop();
            },
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.symmetric(horizontal: 6.w),
            constraints: BoxConstraints(minWidth: 32.w, minHeight: 32.h),
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: context.colors.textPrimary,
              size: 20.ic,
            ),
          ),
          SizedBox(width: 4.w),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _currentFolderName,
                  style: AppTypography.textMdBold.copyWith(
                    color: context.colors.textPrimary,
                    height: 1.15,
                    letterSpacing: -0.2,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (totalCount != null) ...[
                  SizedBox(height: 2.h),
                  Text(
                    totalCount == 1 ? '1 game' : '$totalCount games',
                    style: AppTypography.textXsRegular.copyWith(
                      color: context.colors.textPrimary.withValues(alpha: 0.5),
                      height: 1.1,
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(width: 4.w),
          if (showExport)
            IconButton(
              onPressed: _handleExportPgn,
              tooltip: 'Export as PGN',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.symmetric(horizontal: 6.w),
              constraints: BoxConstraints(minWidth: 32.w, minHeight: 32.h),
              icon: Icon(
                Icons.ios_share_rounded,
                color: context.colors.textPrimary,
                size: 20.ic,
              ),
            ),
          if (showRename)
            IconButton(
              onPressed: _handleRename,
              tooltip: 'Rename',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.symmetric(horizontal: 6.w),
              constraints: BoxConstraints(minWidth: 32.w, minHeight: 32.h),
              icon: Icon(
                Icons.edit_rounded,
                color: context.colors.textPrimary,
                size: 20.ic,
              ),
            ),
          if (showAdd)
            IconButton(
              onPressed: _handlePlusButton,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.symmetric(horizontal: 6.w),
              constraints: BoxConstraints(minWidth: 32.w, minHeight: 32.h),
              icon: Icon(
                Icons.add_rounded,
                color: context.colors.textPrimary,
                size: 26.ic,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final searchField = Container(
      height: 38.h,
      decoration: BoxDecoration(
        color: context.colors.textPrimary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10.br),
      ),
      child: Row(
        children: [
          SizedBox(width: 12.w),
          Icon(
            Icons.search_rounded,
            size: 18.sp,
            color: const Color(0xFFA1A1AA),
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: TextField(
              controller: _searchController,
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Search games...',
                hintStyle: AppTypography.textSmRegular.copyWith(
                  color: const Color(0xFFA1A1AA),
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
            ),
          ),
          if (_searchController.text.isNotEmpty) ...[
            GestureDetector(
              onTap: _clearSearch,
              child: Icon(
                Icons.close,
                size: 20.sp,
                color: const Color(0xFFA1A1AA),
              ),
            ),
            SizedBox(width: 8.w),
          ],
          SizedBox(width: 8.w),
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      child: Row(
        children: [
          Expanded(child: searchField),
          if (_isDatabase) ...[
            SizedBox(width: 8.w),
            GestureDetector(
              onTap: _showSortOptions,
              child: Container(
                width: 38.h,
                height: 38.h,
                decoration: BoxDecoration(
                  color: context.colors.textPrimary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10.br),
                  border: Border.all(
                    color: context.colors.textPrimary.withValues(alpha: 0.08),
                  ),
                ),
                child: Icon(
                  _sortDirection == GamebaseSortDirection.desc
                      ? Icons.south_rounded
                      : Icons.north_rounded,
                  size: 18.sp,
                  color: kPrimaryColor,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  int _ratingFromMetadata(SavedAnalysis analysis, String key) {
    final value = analysis.chessGame.metadata[key];
    if (value is num) return value.toInt();
    final text = value?.toString() ?? '';
    final digits = RegExp(r'\d+').firstMatch(text)?.group(0);
    return int.tryParse(digits ?? '') ?? 0;
  }

  DateTime _gameDate(SavedAnalysis analysis) {
    final raw = analysis.chessGame.metadata['Date']?.toString().trim() ?? '';
    if (raw.isNotEmpty && raw != '????.??.??') {
      final normalized = raw.replaceAll('.', '-').replaceAll('?', '01');
      final parsed = DateTime.tryParse(normalized);
      if (parsed != null) return parsed;
    }
    return analysis.createdAt;
  }

  int _sortValue(SavedAnalysis analysis, GamebaseSortField field) {
    switch (field) {
      case GamebaseSortField.whiteElo:
        return _ratingFromMetadata(analysis, 'WhiteElo');
      case GamebaseSortField.blackElo:
        return _ratingFromMetadata(analysis, 'BlackElo');
      case GamebaseSortField.avgElo:
        final white = _ratingFromMetadata(analysis, 'WhiteElo');
        final black = _ratingFromMetadata(analysis, 'BlackElo');
        if (white > 0 && black > 0) return ((white + black) / 2).round();
        return white > 0 ? white : black;
      case GamebaseSortField.date:
        return _gameDate(analysis).millisecondsSinceEpoch;
    }
  }

  List<SavedAnalysis> _sortAnalyses(List<SavedAnalysis> analyses) {
    final sorted = List<SavedAnalysis>.from(analyses);
    sorted.sort((a, b) {
      final comparison = _sortValue(
        a,
        _sortBy,
      ).compareTo(_sortValue(b, _sortBy));
      final directed =
          _sortDirection == GamebaseSortDirection.asc
              ? comparison
              : -comparison;
      if (directed != 0) return directed;
      return b.createdAt.compareTo(a.createdAt);
    });
    return sorted;
  }

  Widget _buildSavedGames(
    AsyncValue<PaginatedBookState> bookAsync,
    String query,
  ) {
    // Watch child folders (child nodes)
    final childFolders = ref.watch(
      childLibraryFoldersProvider(widget.folder.id),
    );

    return RefreshIndicator(
      onRefresh: () async {
        HapticFeedbackService.medium();
        await ref
            .read(bookGamesPaginatedProvider(_paginationKey).notifier)
            .refresh();
      },
      color: context.colors.textPrimary,
      backgroundColor: context.colors.surface,
      child: bookAsync.when(
        data: (bookState) {
          final analyses =
              _isDatabase ? bookState.games : const <SavedAnalysis>[];
          final filteredAnalyses = _sortAnalyses(
            analyses.where((analysis) {
              if (query.isEmpty) return true;
              final md = analysis.chessGame.metadata;
              final title = analysis.title.toLowerCase();
              final white = (md['White'] ?? '').toString().toLowerCase();
              final black = (md['Black'] ?? '').toString().toLowerCase();
              final event = (md['Event'] ?? '').toString().toLowerCase();
              return title.contains(query) ||
                  white.contains(query) ||
                  black.contains(query) ||
                  event.contains(query);
            }).toList(),
          );

          // Filter child folders if query is present
          final filteredFolders =
              childFolders.where((f) {
                if (query.isEmpty) return true;
                return f.name.toLowerCase().contains(query);
              }).toList();

          if (analyses.isEmpty && childFolders.isEmpty && !bookState.hasMore) {
            return _buildEmptySavedState();
          }
          if (filteredAnalyses.isEmpty &&
              filteredFolders.isEmpty &&
              query.isNotEmpty) {
            return _buildEmptySearchState();
          }

          // Total items = child nodes + Games + Loading Tail
          final showLoadingTail = bookState.hasMore && query.isEmpty;
          final itemCount =
              filteredFolders.length +
              filteredAnalyses.length +
              (showLoadingTail ? 1 : 0);

          return ListView.builder(
            controller: _scrollController,
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
            itemCount: itemCount,
            itemBuilder: (context, index) {
              // 1. Show child nodes first
              if (index < filteredFolders.length) {
                final folder = filteredFolders[index];
                return Padding(
                  padding: EdgeInsets.only(bottom: 8.h),
                  child: FolderCard(folder: folder, isExpanded: true),
                );
              }

              // 2. Show Games
              final analysisIndex = index - filteredFolders.length;
              if (analysisIndex < filteredAnalyses.length) {
                final analysis = filteredAnalyses[analysisIndex];

                // Subscribed: read-only cards (no swipe-to-remove)
                if (_isSubscribed) {
                  return Padding(
                    padding: EdgeInsets.only(bottom: 12.h),
                    child: BookSavedGameCard(
                      analysis: analysis,
                      onTap: () {
                        loadSavedAnalysisWithSwiping(
                          context,
                          filteredAnalyses,
                          analysisIndex,
                          readOnly: true,
                        );
                      },
                    ),
                  ).animate().fadeIn();
                }

                // Owned: swipe-to-remove enabled
                return Padding(
                  padding: EdgeInsets.only(bottom: 12.h),
                  child: SwipeActionCard(
                    dismissKey: ValueKey(analysis.id),
                    backgroundColor: kRedColor,
                    icon: Icons.delete_outline_rounded,
                    onAction: () async => _removeAnalysis(analysis),
                    behavior: SwipeActionBehavior.dismiss,
                    child: BookSavedGameCard(
                      analysis: analysis,
                      onTap: () {
                        loadSavedAnalysisWithSwiping(
                          context,
                          filteredAnalyses,
                          analysisIndex,
                        );
                      },
                    ),
                  ),
                ).animate().fadeIn();
              }

              // 3. Loading indicator at the bottom
              return Padding(
                padding: EdgeInsets.symmetric(vertical: 16.h),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.colors.textPrimary,
                    ),
                  ),
                ),
              );
            },
          );
        },
        loading:
            () => Center(
              child: CircularProgressIndicator(
                color: context.colors.textPrimary,
              ),
            ),
        error:
            (e, _) => Center(
              child: Text(
                'Error: $e',
                style: AppTypography.textSmRegular.copyWith(color: kRedColor),
              ),
            ),
      ),
    );
  }

  Widget _buildEmptySavedState() {
    final isFolder = _isFolder;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_open_rounded,
            size: 64.sp,
            color: context.colors.textPrimary.withValues(alpha: 0.1),
          ),
          SizedBox(height: 16.h),
          Text(
            isFolder ? 'This folder is empty' : 'This database is empty',
            style: AppTypography.textMdMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          if (!_isSubscribed) ...[
            SizedBox(height: 8.h),
            Text(
              isFolder
                  ? 'Create a folder or database here.'
                  : 'Save your first game here!',
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textPrimary.withValues(alpha: 0.5),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptySearchState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 64.sp,
            color: context.colors.textPrimary.withValues(alpha: 0.1),
          ),
          SizedBox(height: 16.h),
          Text(
            'No matches found',
            style: AppTypography.textMdMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            'Try a different search term',
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared state for the export progress dialog. The dialog listens to a
/// `ValueListenable<_ExportProgress>` so progress updates from the export
/// pipeline don't rebuild the whole screen.
class _ExportProgress {
  final int processed;
  final int total;
  final bool done;
  const _ExportProgress({
    required this.processed,
    required this.total,
    this.done = false,
  });

  double get fraction {
    if (total <= 0) return 0;
    return (processed / total).clamp(0.0, 1.0);
  }
}

class _ExportProgressController extends ValueNotifier<_ExportProgress> {
  _ExportProgressController()
    : super(const _ExportProgress(processed: 0, total: 0));

  void update({required int processed, required int total}) {
    value = _ExportProgress(processed: processed, total: total);
  }

  void close() {
    value = _ExportProgress(
      processed: value.processed,
      total: value.total,
      done: true,
    );
  }
}

class _ExportProgressDialog extends StatefulWidget {
  const _ExportProgressDialog({required this.controller});

  final _ExportProgressController controller;

  @override
  State<_ExportProgressDialog> createState() => _ExportProgressDialogState();
}

class _ExportProgressDialogState extends State<_ExportProgressDialog> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    final progress = widget.controller.value;
    if (progress.done) {
      Navigator.of(context, rootNavigator: true).maybePop();
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.controller.value;
    final label =
        progress.total > 0
            ? 'Exporting ${progress.processed} / ${progress.total} games...'
            : 'Preparing export...';

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.symmetric(horizontal: 24.w),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 20.h),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(16.br),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 16.sp,
                  height: 16.sp,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: kPrimaryColor,
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(
                    label,
                    style: AppTypography.textSmMedium.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 14.h),
            ClipRRect(
              borderRadius: BorderRadius.circular(4.br),
              child: LinearProgressIndicator(
                value: progress.total > 0 ? progress.fraction : null,
                backgroundColor: context.colors.textPrimary.withValues(
                  alpha: 0.08,
                ),
                valueColor: const AlwaysStoppedAnimation<Color>(kPrimaryColor),
                minHeight: 6.h,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              progress.total > 0
                  ? '${(progress.fraction * 100).toStringAsFixed(0)}%'
                  : '',
              style: AppTypography.textXsRegular.copyWith(
                color: context.colors.textPrimary.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
