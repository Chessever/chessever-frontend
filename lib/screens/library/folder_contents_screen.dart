import 'dart:io';

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/library/pgn_import_preview_screen.dart';
import 'package:chessever2/screens/library/providers/book_games_paginated_provider.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/screens/library/utils/folder_pgn_exporter.dart';
import 'package:chessever2/screens/library/utils/load_saved_analysis.dart';
import 'package:chessever2/screens/library/widgets/add_to_library_sheet.dart';
import 'package:chessever2/screens/library/widgets/book_saved_game_card.dart';
import 'package:chessever2/screens/library/widgets/create_folder_dialog.dart';
import 'package:chessever2/screens/library/widgets/folder_card.dart';
import 'package:chessever2/screens/library/widgets/swipe_action_card.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/pgn_multi_parser.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
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
  // Overrides widget.folder.name after an in-place rename so the header
  // reflects the new name without needing to pop/reopen.
  String? _overrideFolderName;

  bool get _isSubscribed => widget.folder.isSubscribed;

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

  Future<void> _removeAnalysis(SavedAnalysis analysis) async {
    if (_removingIds.contains(analysis.id)) return;

    HapticFeedbackService.medium();
    _removingIds.add(analysis.id);

    final repository = ref.read(libraryRepositoryProvider);
    try {
      await repository.moveAnalysisToFolder(analysis.id, null);

      if (!mounted) return;
      // Refresh the paginated list after removal.
      ref.read(bookGamesPaginatedProvider(_paginationKey).notifier).refresh();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Removed from "${widget.folder.name}"',
            style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
          ),
          backgroundColor: kBlack2Color.withValues(alpha: 0.95),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Undo',
            textColor: kPrimaryColor,
            onPressed: () async {
              try {
                await repository.moveAnalysisToFolder(
                  analysis.id,
                  widget.folder.id,
                );
                ref
                    .read(bookGamesPaginatedProvider(_paginationKey).notifier)
                    .refresh();
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
            style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
          ),
          backgroundColor: kRedColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handlePlusButton() async {
    HapticFeedbackService.light();
    // Sub-databases can't nest further (2-layer hierarchy), so only offer
    // "Create Sub-Database" on root folders.
    final isRootFolder = widget.folder.parentId == null;
    final choice = await showAddToLibrarySheet(
      context,
      title: 'Add to "$_currentFolderName"',
      showCreateDatabase: isRootFolder,
      createDatabaseTitle: 'Create Sub-Database',
      createDatabaseSubtitle: 'New empty sub-database under this one',
    );
    if (choice == null || !mounted) return;

    switch (choice) {
      case AddToLibraryChoice.createDatabase:
        await _handleCreateSubfolder();
      case AddToLibraryChoice.importPgn:
        await _handleImportPgnFromClipboard();
    }
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
            style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
          ),
          backgroundColor: kBlack2Color.withValues(alpha: 0.95),
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
            style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
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
  }

  Future<void> _handleCreateSubfolder() async {
    final data = await showCreateFolderDialog(
      context,
      initialParentId: widget.folder.id,
      lockToParent: true,
    );
    if (data == null || data.name.trim().isEmpty) return;

    try {
      await ref
          .read(libraryRepositoryProvider)
          .createFolder(name: data.name, parentId: data.parentId);
      ref.invalidate(libraryFoldersStreamProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sub-database "${data.name}" created',
            style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
          ),
          backgroundColor: kBlack2Color.withValues(alpha: 0.95),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to create sub-database: $e',
            style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
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
            style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
          ),
          backgroundColor: kBlack2Color.withValues(alpha: 0.95),
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
            style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
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
    final dialogController = _ExportProgressController();

    // Show the progress dialog (non-dismissible) while export runs.
    final dialogFuture = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ExportProgressDialog(controller: dialogController),
    );

    String? pgn;
    Object? error;
    try {
      pgn = await exportFolderAsPgn(
        repo: repo,
        folderId: widget.folder.id,
        folderName: widget.folder.name,
        isSubscribed: _isSubscribed,
        shareToken: widget.folder.shareToken,
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

    if (error != null || pgn == null || pgn.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error != null
                ? 'Export failed: $error'
                : 'Nothing to export in this database',
            style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
          ),
          backgroundColor: kRedColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final filename = suggestedExportFilename(widget.folder.name);
      final file = File('${tempDir.path}/$filename');
      await file.writeAsString(pgn);

      final box = context.findRenderObject() as RenderBox?;
      final origin =
          box != null
              ? box.localToGlobal(Offset.zero) & box.size
              : const Rect.fromLTWH(0, 0, 1, 1);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/x-chess-pgn')],
        subject: '${widget.folder.name} - Chessever PGN',
        sharePositionOrigin: origin,
      );
      HapticFeedbackService.success();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Share failed: $e',
            style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
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
      backgroundColor: kBackgroundColor,
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
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [kBlackColor, kBackgroundColor],
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
    final totalCount = bookAsync.valueOrNull?.totalCount;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        0,
        horizontalPadding,
        8.h,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: () {
                HapticFeedbackService.light();
                Navigator.of(context).pop();
              },
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: kWhiteColor,
                size: 20.ic,
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if ((bookAsync.valueOrNull?.totalCount ?? 0) > 0)
                  IconButton(
                    onPressed: _handleExportPgn,
                    tooltip: 'Export as PGN',
                    icon: Icon(
                      Icons.ios_share_rounded,
                      color: kWhiteColor,
                      size: 22.ic,
                    ),
                  ),
                // Rename is only available for owned databases (subscribed
                // folders are read-only — you can't rename someone else's book).
                if (!_isSubscribed)
                  IconButton(
                    onPressed: _handleRename,
                    tooltip: 'Rename Database',
                    icon: Icon(
                      Icons.edit_rounded,
                      color: kWhiteColor,
                      size: 22.ic,
                    ),
                  ),
                // Shown for owned databases at both root and sub levels.
                // The sheet itself hides "Create Sub-Database" on sub-level
                // folders since 2-layer hierarchy doesn't allow deeper nesting.
                if (!_isSubscribed)
                  IconButton(
                    onPressed: _handlePlusButton,
                    icon: Icon(
                      Icons.add_rounded,
                      color: kWhiteColor,
                      size: 28.ic,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 56.w),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _currentFolderName,
                  style: AppTypography.textLgBold.copyWith(
                    color: kWhiteColor,
                    height: 1.1,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (totalCount != null)
                  Text(
                    totalCount == 1 ? '1 game' : '$totalCount games',
                    style: AppTypography.textXsRegular.copyWith(
                      color: kWhiteColor.withValues(alpha: 0.5),
                      height: 1.2,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      child: Container(
        height: 38.h,
        decoration: BoxDecoration(
          color: kWhiteColor.withValues(alpha: 0.06),
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
                style: AppTypography.textSmRegular.copyWith(color: kWhiteColor),
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
      ),
    );
  }

  Widget _buildSavedGames(
    AsyncValue<PaginatedBookState> bookAsync,
    String query,
  ) {
    // Watch child folders (sub-databases)
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
      color: kWhiteColor,
      backgroundColor: kBlack2Color,
      child: bookAsync.when(
        data: (bookState) {
          final analyses = bookState.games;
          final filteredAnalyses =
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
              }).toList();

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

          // Total items = Subfolders + Games + Loading Tail
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
              // 1. Show Subfolders first
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
                      onTap: () async {
                        final allowed = await requirePremiumGuard(context, ref);
                        if (!allowed || !mounted) return;
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
                      onTap: () async {
                        final allowed = await requirePremiumGuard(context, ref);
                        if (!allowed || !mounted) return;
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
                child: const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: kWhiteColor,
                    ),
                  ),
                ),
              );
            },
          );
        },
        loading:
            () => const Center(
              child: CircularProgressIndicator(color: kWhiteColor),
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_open_rounded,
            size: 64.sp,
            color: kWhiteColor.withValues(alpha: 0.1),
          ),
          SizedBox(height: 16.h),
          Text(
            'This database is empty',
            style: AppTypography.textMdMedium.copyWith(color: kWhiteColor),
          ),
          if (!_isSubscribed) ...[
            SizedBox(height: 8.h),
            Text(
              'Save your first game here!',
              style: AppTypography.textSmRegular.copyWith(
                color: kWhiteColor.withValues(alpha: 0.5),
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
            color: kWhiteColor.withValues(alpha: 0.1),
          ),
          SizedBox(height: 16.h),
          Text(
            'No matches found',
            style: AppTypography.textMdMedium.copyWith(color: kWhiteColor),
          ),
          SizedBox(height: 8.h),
          Text(
            'Try a different search term',
            style: AppTypography.textSmRegular.copyWith(
              color: kWhiteColor.withValues(alpha: 0.5),
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
          color: kBlack2Color,
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
                      color: kWhiteColor,
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
                backgroundColor: kWhiteColor.withValues(alpha: 0.08),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(kPrimaryColor),
                minHeight: 6.h,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              progress.total > 0
                  ? '${(progress.fraction * 100).toStringAsFixed(0)}%'
                  : '',
              style: AppTypography.textXsRegular.copyWith(
                color: kWhiteColor.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
