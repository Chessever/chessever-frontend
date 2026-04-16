import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/library/providers/book_games_paginated_provider.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/screens/library/utils/load_saved_analysis.dart';
import 'package:chessever2/screens/library/widgets/book_saved_game_card.dart';
import 'package:chessever2/screens/library/widgets/create_folder_dialog.dart';
import 'package:chessever2/screens/library/widgets/folder_card.dart';
import 'package:chessever2/screens/library/widgets/swipe_action_card.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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

  bool get _isSubscribed => widget.folder.isSubscribed;

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

  void _handleCreateSubfolder() async {
    HapticFeedbackService.light();
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
          // Only show '+' button if this is a root folder (to enforce 2-layer hierarchy)
          if (widget.folder.parentId == null && !_isSubscribed)
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                onPressed: _handleCreateSubfolder,
                icon: Icon(Icons.add_rounded, color: kWhiteColor, size: 28.ic),
              ),
            ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 56.w),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.folder.name,
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
