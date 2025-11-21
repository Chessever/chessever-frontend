import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/library/widgets/folder_card.dart';
import 'package:chessever2/screens/library/widgets/saved_analysis_card.dart';
import 'package:chessever2/screens/library/widgets/create_folder_dialog.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _handleCreateFolder() async {
    HapticFeedback.mediumImpact();
    final folderName = await showCreateFolderDialog(context);
    if (folderName != null && folderName.isNotEmpty) {
      try {
        final repository = ref.read(libraryRepositoryProvider);
        await repository.createFolder(name: folderName);
        if (mounted) {
          HapticFeedback.mediumImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Folder "$folderName" created'),
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
              content: Text('Failed to create folder: $e'),
              backgroundColor: kRedColor,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenWrapper(
      child: Column(
        children: [
          // Header
          _buildHeader(),

          // Tabs
          _buildTabs(),

          // Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildAllTab(),
                _buildFoldersTab(),
                _buildRecentTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).viewPadding.top + 16.h,
        left: 20.w,
        right: 20.w,
        bottom: 16.h,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Library',
                  style: AppTypography.textXlBold.copyWith(
                    color: kWhiteColor,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  'Your saved chess analyses',
                  style: AppTypography.textSmRegular.copyWith(
                    color: kWhiteColor.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          // Create folder button
          IconButton(
            onPressed: _handleCreateFolder,
            icon: Container(
              padding: EdgeInsets.all(8.sp),
              decoration: BoxDecoration(
                color: kPrimaryColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8.br),
                border: Border.all(
                  color: kPrimaryColor.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Icon(
                Icons.create_new_folder_outlined,
                color: kPrimaryColor,
                size: 20.sp,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 20.w),
      decoration: BoxDecoration(
        color: kBlack2Color,
        borderRadius: BorderRadius.circular(8.br),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: kPrimaryColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6.br),
        ),
        indicatorPadding: EdgeInsets.all(4.sp),
        labelColor: kPrimaryColor,
        unselectedLabelColor: kWhiteColor.withValues(alpha: 0.6),
        labelStyle: AppTypography.textSmBold,
        unselectedLabelStyle: AppTypography.textSmMedium,
        tabs: const [
          Tab(text: 'All'),
          Tab(text: 'Folders'),
          Tab(text: 'Recent'),
        ],
      ),
    );
  }

  Widget _buildAllTab() {
    final foldersAsync = ref.watch(_foldersStreamProvider);
    final analysesAsync = ref.watch(_allAnalysesStreamProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(_foldersStreamProvider);
        ref.invalidate(_allAnalysesStreamProvider);
      },
      color: kPrimaryColor,
      backgroundColor: kBlack2Color,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: 16.h)),

          // Folders section
          foldersAsync.when(
            data: (folders) => folders.isEmpty
                ? const SliverToBoxAdapter(child: SizedBox.shrink())
                : SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20.w),
                          child: Text(
                            'Folders',
                            style: AppTypography.textMdBold.copyWith(
                              color: kWhiteColor,
                            ),
                          ),
                        ),
                        SizedBox(height: 12.h),
                        SizedBox(
                          height: 100.h,
                          child: ListView.separated(
                            padding: EdgeInsets.symmetric(horizontal: 20.w),
                            scrollDirection: Axis.horizontal,
                            itemCount: folders.length,
                            separatorBuilder: (_, __) => SizedBox(width: 12.w),
                            itemBuilder: (context, index) {
                              return FolderCard(folder: folders[index]);
                            },
                          ),
                        ),
                        SizedBox(height: 24.h),
                      ],
                    ),
                  ),
            loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
            error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
          ),

          // All analyses section
          analysesAsync.when(
            data: (analyses) => analyses.isEmpty
                ? _buildEmptyState()
                : _buildAnalysesList(analyses),
            loading: () => _buildLoadingState(),
            error: (error, _) => _buildErrorState(error.toString()),
          ),

          SliverToBoxAdapter(child: SizedBox(height: 20.h)),
        ],
      ),
    );
  }

  Widget _buildFoldersTab() {
    final foldersAsync = ref.watch(_foldersStreamProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(_foldersStreamProvider);
      },
      color: kPrimaryColor,
      backgroundColor: kBlack2Color,
      child: foldersAsync.when(
        data: (folders) {
          if (folders.isEmpty) {
            return _buildEmptyFoldersState();
          }
          return ListView.separated(
            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
            itemCount: folders.length,
            separatorBuilder: (_, __) => SizedBox(height: 12.h),
            itemBuilder: (context, index) {
              return FolderCard(
                folder: folders[index],
                isExpanded: true,
              );
            },
          );
        },
        loading: () => _buildLoadingState(),
        error: (error, _) => _buildErrorState(error.toString()),
      ),
    );
  }

  Widget _buildRecentTab() {
    final recentAsync = ref.watch(_recentAnalysesStreamProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(_recentAnalysesStreamProvider);
      },
      color: kPrimaryColor,
      backgroundColor: kBlack2Color,
      child: recentAsync.when(
        data: (analyses) => analyses.isEmpty
            ? _buildEmptyState()
            : _buildAnalysesList(analyses),
        loading: () => _buildLoadingState(),
        error: (error, _) => _buildErrorState(error.toString()),
      ),
    );
  }

  Widget _buildAnalysesList(List<SavedAnalysis> analyses) {
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            return Padding(
              padding: EdgeInsets.only(bottom: 12.h),
              child: SavedAnalysisCard(analysis: analyses[index]),
            );
          },
          childCount: analyses.length,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.library_books_outlined,
              size: 64.sp,
              color: kWhiteColor.withValues(alpha: 0.3),
            ),
            SizedBox(height: 16.h),
            Text(
              'No saved analyses yet',
              style: AppTypography.textLgMedium.copyWith(
                color: kWhiteColor.withValues(alpha: 0.7),
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Save your chess analyses to view them here',
              style: AppTypography.textSmRegular.copyWith(
                color: kWhiteColor.withValues(alpha: 0.5),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyFoldersState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_outlined,
            size: 64.sp,
            color: kWhiteColor.withValues(alpha: 0.3),
          ),
          SizedBox(height: 16.h),
          Text(
            'No folders yet',
            style: AppTypography.textLgMedium.copyWith(
              color: kWhiteColor.withValues(alpha: 0.7),
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            'Create folders to organize your analyses',
            style: AppTypography.textSmRegular.copyWith(
              color: kWhiteColor.withValues(alpha: 0.5),
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 24.h),
          ElevatedButton.icon(
            onPressed: _handleCreateFolder,
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimaryColor,
              foregroundColor: kWhiteColor,
              padding: EdgeInsets.symmetric(
                horizontal: 24.w,
                vertical: 12.h,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.br),
              ),
            ),
            icon: const Icon(Icons.create_new_folder_outlined),
            label: Text(
              'Create Folder',
              style: AppTypography.textSmBold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return const SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: CircularProgressIndicator(color: kPrimaryColor),
      ),
    );
  }

  Widget _buildErrorState(String error) {
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

// Stream providers
final _foldersStreamProvider = StreamProvider.autoDispose<List<LibraryFolder>>((ref) {
  final repository = ref.watch(libraryRepositoryProvider);
  return repository.subscribeFolders();
});

final _allAnalysesStreamProvider = StreamProvider.autoDispose<List<SavedAnalysis>>((ref) {
  final repository = ref.watch(libraryRepositoryProvider);
  return repository.subscribeAnalyses();
});

final _recentAnalysesStreamProvider = StreamProvider.autoDispose<List<SavedAnalysis>>((ref) {
  final repository = ref.watch(libraryRepositoryProvider);
  return repository.subscribeAnalyses().map((analyses) {
    // Sort by last opened or created date, take top 20
    final sorted = [...analyses]..sort((a, b) {
      final aDate = a.lastOpenedAt ?? a.createdAt;
      final bDate = b.lastOpenedAt ?? b.createdAt;
      return bDate.compareTo(aDate);
    });
    return sorted.take(20).toList();
  });
});
