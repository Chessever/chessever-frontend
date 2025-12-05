import 'dart:async';

import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/library/utils/create_empty_game.dart';
import 'package:chessever2/screens/library/widgets/create_folder_dialog.dart';
import 'package:chessever2/screens/library/widgets/folder_card.dart';
import 'package:chessever2/screens/library/widgets/saved_analysis_card.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounceTimer;
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  // Filter method - commented out as filter button is not ready yet
  // void _onFilterPressed() {
  //   HapticFeedback.selectionClick();
  //   ScaffoldMessenger.of(context).showSnackBar(
  //     SnackBar(
  //       behavior: SnackBarBehavior.floating,
  //       backgroundColor: kBlack2Color.withValues(alpha: 0.95),
  //       content: Text(
  //         'Sorting and filters coming soon',
  //         style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
  //       ),
  //     ),
  //   );
  // }

  void _handleSearchInput(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 220), () {
      setState(() => _searchQuery = query.trim().toLowerCase());
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _handleSearchInput('');
    _searchFocusNode.unfocus();
  }

  void _navigateToEmptyBoard() {
    HapticFeedback.mediumImpact();
    ref.read(chessboardViewFromProviderNew.notifier).state = ChessboardView.tour;
    final emptyGame = createEmptyGame();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChessBoardScreenNew(
          currentIndex: 0,
          games: [emptyGame],
          hideEventInfo: true,
        ),
      ),
    );
  }

  List<LibraryFolder> _filterFolders(List<LibraryFolder> folders) {
    if (_searchQuery.isEmpty) return folders;
    return folders
        .where(
          (folder) => folder.name.toLowerCase().contains(_searchQuery),
        )
        .toList();
  }

  List<SavedAnalysis> _filterAnalyses(List<SavedAnalysis> analyses) {
    if (_searchQuery.isEmpty) {
      return analyses;
    }

    return analyses.where((analysis) {
      if (analysis.title.toLowerCase().contains(_searchQuery)) {
        return true;
      }

      final whiteName = analysis.chessGame.metadata['White'] as String? ?? '';
      final blackName = analysis.chessGame.metadata['Black'] as String? ?? '';
      if (whiteName.toLowerCase().contains(_searchQuery) ||
          blackName.toLowerCase().contains(_searchQuery)) {
        return true;
      }

      if (analysis.tags.any((tag) => tag.toLowerCase().contains(_searchQuery))) {
        return true;
      }

      return false;
    }).toList();
  }

  Future<void> _handleCreateFolder() async {
    HapticFeedback.mediumImpact();
    final name = await showCreateFolderDialog(context);
    if (name == null || name.isEmpty) return;

    try {
      final repository = ref.read(libraryRepositoryProvider);
      await repository.createFolder(name: name);

      // Force refresh folders provider to ensure immediate UI update
      // (Supabase streams may have slight delay)
      ref.invalidate(_foldersStreamProvider);
      await ref.read(_foldersStreamProvider.future);

      if (mounted) {
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Folder "$name" created',
              style: TextStyle(color: kWhiteColor),
            ),
            backgroundColor: kBlack2Color.withValues(alpha: 0.95),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        HapticFeedback.lightImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to create folder: $e',
              style: TextStyle(color: kWhiteColor),
            ),
            backgroundColor: kRedColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenWrapper(
      child: Column(
        children: [
          _buildTopBar(),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    final topPadding = MediaQuery.of(context).viewPadding.top;

    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, topPadding + 10.h, 16.w, 8.h),
      child: Row(
        children: [
          Expanded(child: _buildSearchField()),
          SizedBox(width: 10.w),
          // Filter button - commented out as it's not ready yet
          // _SquareIconButton(
          //   icon: Icons.tune,
          //   onTap: _onFilterPressed,
          // ),
          // SizedBox(width: 8.w),
          _SquareSvgIconButton(
            svgAsset: SvgAsset.chase_grid,
            onTap: _navigateToEmptyBoard,
          ),
          SizedBox(width: 8.w),
          _SquareIconButton(
            icon: Icons.add,
            onTap: _handleCreateFolder,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: kBlack2Color,
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(
          color: kWhiteColor.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.search, color: kWhiteColor.withValues(alpha: 0.7)),
          SizedBox(width: 10.w),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              style: AppTypography.textSmRegular.copyWith(color: kWhiteColor),
              onChanged: _handleSearchInput,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search library',
                hintStyle: AppTypography.textSmRegular.copyWith(
                  color: kWhiteColor.withValues(alpha: 0.5),
                ),
                border: InputBorder.none,
              ),
            ),
          ),
          if (_searchController.text.isNotEmpty)
            GestureDetector(
              onTap: _clearSearch,
              child: Container(
                padding: EdgeInsets.all(6.sp),
                decoration: BoxDecoration(
                  color: kWhiteColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.close,
                  size: 14.sp,
                  color: kWhiteColor.withValues(alpha: 0.7),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final foldersAsync = ref.watch(_foldersStreamProvider);
    final analysesAsync = ref.watch(_allAnalysesStreamProvider);

    return RefreshIndicator(
      onRefresh: () async {
        HapticFeedbackService.medium();
        ref.invalidate(_foldersStreamProvider);
        ref.invalidate(_allAnalysesStreamProvider);
      },
      color: kPrimaryColor,
      backgroundColor: kBlack2Color,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: 4.h)),
          foldersAsync.when(
            data: (folders) => _buildFoldersSliver(folders),
            loading: () => _buildLoadingSliver(),
            error: (error, _) => _buildErrorSliver(error.toString()),
          ),
          _buildAnalysesSearchSliver(analysesAsync),
          SliverToBoxAdapter(child: SizedBox(height: 24.h)),
        ],
      ),
    );
  }

  Widget _buildFoldersSliver(List<LibraryFolder> folders) {
    final filteredFolders = _filterFolders(folders);

    if (folders.isEmpty && _searchQuery.isEmpty) {
      return _buildLibraryEmptyState();
    }

    if (filteredFolders.isEmpty) {
      return _buildSearchEmptyState('No folders match your search');
    }

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => Padding(
            padding: EdgeInsets.only(bottom: 12.h),
            child: FolderCard(
              folder: filteredFolders[index],
              isExpanded: true,
            ),
          ),
          childCount: filteredFolders.length,
        ),
      ),
    );
  }

  Widget _buildAnalysesSearchSliver(
    AsyncValue<List<SavedAnalysis>> analysesAsync,
  ) {
    if (_searchQuery.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return analysesAsync.when(
      data: (analyses) {
        final filtered = _filterAnalyses(analyses);
        if (filtered.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }

        return SliverPadding(
          padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 0),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index == 0) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(bottom: 12.h),
                        child: Text(
                          'Games',
                          style: AppTypography.textSmMedium.copyWith(
                            color: kWhiteColor.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                      SavedAnalysisCard(analysis: filtered[index]),
                      SizedBox(height: 12.h),
                    ],
                  );
                }

                return Padding(
                  padding: EdgeInsets.only(bottom: 12.h),
                  child: SavedAnalysisCard(analysis: filtered[index]),
                );
              },
              childCount: filtered.length,
            ),
          ),
        );
      },
      loading: () => _buildInlineLoading(),
      error: (error, _) => _buildInlineError(error.toString()),
    );
  }

  Widget _buildLibraryEmptyState() {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: 80.sp,
              color: kWhiteColor.withValues(alpha: 0.35),
            ),
            SizedBox(height: 18.h),
            Text(
              'Nothing saved yet',
              style: AppTypography.textLgBold.copyWith(color: kWhiteColor),
            ),
            SizedBox(height: 8.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 36.w),
              child: Text(
                'Save a board position or create your first folder to get started.',
                style: AppTypography.textSmRegular.copyWith(
                  color: kWhiteColor.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchEmptyState(String message) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_outlined,
              size: 56.sp,
              color: kWhiteColor.withValues(alpha: 0.4),
            ),
            SizedBox(height: 12.h),
            Text(
              message,
              style: AppTypography.textMdMedium.copyWith(
                color: kWhiteColor.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingSliver() {
    return const SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: CircularProgressIndicator(color: kPrimaryColor),
      ),
    );
  }

  Widget _buildInlineLoading() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 16.h),
        child: Center(
          child: SizedBox(
            width: 24.w,
            height: 24.h,
            child: const CircularProgressIndicator(color: kPrimaryColor),
          ),
        ),
      ),
    );
  }

  Widget _buildInlineError(String error) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        child: Container(
          padding: EdgeInsets.all(12.sp),
          decoration: BoxDecoration(
            color: kRedColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10.br),
            border: Border.all(color: kRedColor.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: kRedColor, size: 18.sp),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(
                  error,
                  style: AppTypography.textSmRegular.copyWith(
                    color: kRedColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorSliver(String error) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64.sp,
              color: kRedColor.withValues(alpha: 0.7),
            ),
            SizedBox(height: 16.h),
            Text(
              'Failed to load library',
              style: AppTypography.textLgMedium.copyWith(
                color: kWhiteColor.withValues(alpha: 0.7),
              ),
            ),
            SizedBox(height: 8.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 40.w),
              child: Text(
                error,
                style: AppTypography.textSmRegular.copyWith(
                  color: kWhiteColor.withValues(alpha: 0.5),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SquareIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? backgroundColor;
  final Color? iconColor;
  final Color? borderColor;

  const _SquareIconButton({
    required this.icon,
    required this.onTap,
    this.backgroundColor,
    this.iconColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(10.sp),
        decoration: BoxDecoration(
          color: backgroundColor ?? kBlack2Color,
          borderRadius: BorderRadius.circular(10.br),
          border: Border.all(
            color: borderColor ?? kWhiteColor.withValues(alpha: 0.08),
          ),
        ),
        child: Icon(
          icon,
          size: 18.sp,
          color: iconColor ?? kWhiteColor,
        ),
      ),
    );
  }
}

class _SquareSvgIconButton extends StatelessWidget {
  final String svgAsset;
  final VoidCallback onTap;
  final Color? backgroundColor;
  final Color? borderColor;

  const _SquareSvgIconButton({
    required this.svgAsset,
    required this.onTap,
    this.backgroundColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(10.sp),
        decoration: BoxDecoration(
          color: backgroundColor ?? kBlack2Color,
          borderRadius: BorderRadius.circular(10.br),
          border: Border.all(
            color: borderColor ?? kWhiteColor.withValues(alpha: 0.08),
          ),
        ),
        child: SvgPicture.asset(
          svgAsset,
          width: 18.sp,
          height: 18.sp,
        ),
      ),
    );
  }
}

final _foldersStreamProvider =
    StreamProvider.autoDispose<List<LibraryFolder>>((ref) {
  final repository = ref.watch(libraryRepositoryProvider);
  return repository.subscribeFolders();
});

final _allAnalysesStreamProvider =
    StreamProvider.autoDispose<List<SavedAnalysis>>((ref) {
  final repository = ref.watch(libraryRepositoryProvider);
  return repository.subscribeAnalyses();
});
