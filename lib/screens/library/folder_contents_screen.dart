import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/library/widgets/saved_analysis_card.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class FolderContentsScreen extends ConsumerWidget {
  final LibraryFolder folder;

  const FolderContentsScreen({
    super.key,
    required this.folder,
  });

  Color _parseColorString(String colorString) {
    try {
      // Remove # if present
      final hex = colorString.replaceAll('#', '');
      // Add FF for alpha if not present
      final colorValue = hex.length == 6 ? 'FF$hex' : hex;
      return Color(int.parse(colorValue, radix: 16));
    } catch (e) {
      return kPrimaryColor; // Fallback color
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analysesAsync = ref.watch(_folderAnalysesProvider(folder.id));
    final folderColor = _parseColorString(folder.color);

    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: ScreenWrapper(
        child: Column(
          children: [
            // Header
            _buildHeader(context, folderColor),

            // Content
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  HapticFeedbackService.medium();
                  ref.invalidate(_folderAnalysesProvider(folder.id));
                },
                color: kPrimaryColor,
                backgroundColor: kBlack2Color,
                child: analysesAsync.when(
                  data: (analyses) => analyses.isEmpty
                      ? _buildEmptyState()
                      : _buildAnalysesList(analyses),
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: kPrimaryColor),
                  ),
                  error: (error, _) => _buildErrorState(error.toString()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Color folderColor) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).viewPadding.top + 12.h,
        left: 12.w,
        right: 20.w,
        bottom: 16.h,
      ),
      child: Row(
        children: [
          // Back button
          IconButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).pop();
            },
            icon: Icon(
              Icons.arrow_back_ios,
              color: kWhiteColor,
              size: 20.sp,
            ),
          ),

          SizedBox(width: 8.w),

          // Folder icon
          Container(
            padding: EdgeInsets.all(10.sp),
            decoration: BoxDecoration(
              color: folderColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8.br),
            ),
            child: Icon(
              Icons.folder,
              color: folderColor,
              size: 24.sp,
            ),
          ),

          SizedBox(width: 12.w),

          // Folder name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  folder.name,
                  style: AppTypography.textLgBold.copyWith(
                    color: kWhiteColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 2.h),
                Text(
                  'Folder',
                  style: AppTypography.textXsRegular.copyWith(
                    color: kWhiteColor.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalysesList(List<SavedAnalysis> analyses) {
    return ListView.separated(
      padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
      itemCount: analyses.length,
      separatorBuilder: (_, __) => SizedBox(height: 12.h),
      itemBuilder: (context, index) {
        return SavedAnalysisCard(analysis: analyses[index]);
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_open_outlined,
            size: 64.sp,
            color: kWhiteColor.withValues(alpha: 0.3),
          ),
          SizedBox(height: 16.h),
          Text(
            'No analyses in this folder',
            style: AppTypography.textLgMedium.copyWith(
              color: kWhiteColor.withValues(alpha: 0.7),
            ),
          ),
          SizedBox(height: 8.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 40.w),
            child: Text(
              'Save new analyses and organize them into this folder',
              style: AppTypography.textSmRegular.copyWith(
                color: kWhiteColor.withValues(alpha: 0.5),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
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
            'Failed to load folder',
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
    );
  }
}

// Stream provider for folder analyses
final _folderAnalysesProvider =
    StreamProvider.family.autoDispose<List<SavedAnalysis>, String>(
  (ref, folderId) {
    final repository = ref.watch(libraryRepositoryProvider);
    return repository.subscribeAnalyses(folderId: folderId);
  },
);
