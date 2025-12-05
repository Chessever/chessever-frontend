import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/screens/library/folder_contents_screen.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class FolderCard extends ConsumerWidget {
  final LibraryFolder folder;
  final bool isExpanded;

  const FolderCard({
    super.key,
    required this.folder,
    this.isExpanded = false,
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

  void _navigateToFolder(BuildContext context) {
    HapticFeedback.mediumImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FolderContentsScreen(folder: folder),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analysesCountAsync = ref.watch(_folderAnalysesCountProvider(folder.id));
    final folderColor = _parseColorString(folder.color);

    // Wrap with Material to prevent yellow underline bug in modals/overlays
    return Material(
      type: MaterialType.transparency,
      child: isExpanded
          ? _buildExpandedCard(context, analysesCountAsync, folderColor)
          : _buildCompactCard(context, analysesCountAsync, folderColor),
    );
  }

  Widget _buildCompactCard(
    BuildContext context,
    AsyncValue<int> analysesCountAsync,
    Color folderColor,
  ) {
    return GestureDetector(
      onTap: () => _navigateToFolder(context),
      child: Container(
        width: 140.w,
        padding: EdgeInsets.all(16.sp),
        decoration: BoxDecoration(
          color: kBlack2Color,
          borderRadius: BorderRadius.circular(12.br),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Folder icon - neutral gray
            Icon(
              Icons.folder_outlined,
              color: kWhiteColor.withValues(alpha: 0.6),
              size: 32.sp,
            ),

            // Folder name and count
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  folder.name,
                  style: AppTypography.textSmBold.copyWith(
                    color: kWhiteColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 4.h),
                analysesCountAsync.when(
                  data: (count) => Text(
                    '$count ${count == 1 ? 'analysis' : 'analyses'}',
                    style: AppTypography.textXsRegular.copyWith(
                      color: kWhiteColor.withValues(alpha: 0.5),
                    ),
                  ),
                  loading: () => SizedBox(
                    width: 12.w,
                    height: 12.h,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        kWhiteColor.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                  error: (_, __) => Text(
                    '0 analyses',
                    style: AppTypography.textXsRegular.copyWith(
                      color: kWhiteColor.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedCard(
    BuildContext context,
    AsyncValue<int> analysesCountAsync,
    Color folderColor,
  ) {
    return GestureDetector(
      onTap: () => _navigateToFolder(context),
      child: Container(
        padding: EdgeInsets.all(16.sp),
        decoration: BoxDecoration(
          color: kBlack2Color,
          borderRadius: BorderRadius.circular(12.br),
        ),
        child: Row(
          children: [
            // Folder icon - neutral gray outlined
            Icon(
              Icons.folder_outlined,
              color: kWhiteColor.withValues(alpha: 0.6),
              size: 32.sp,
            ),

            SizedBox(width: 16.w),

            // Folder info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    folder.name,
                    style: AppTypography.textMdBold.copyWith(
                      color: kWhiteColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4.h),
                  analysesCountAsync.when(
                    data: (count) => Text(
                      '$count ${count == 1 ? 'analysis' : 'analyses'}',
                      style: AppTypography.textSmRegular.copyWith(
                        color: kWhiteColor.withValues(alpha: 0.5),
                      ),
                    ),
                    loading: () => SizedBox(
                      width: 16.w,
                      height: 16.h,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          kWhiteColor.withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                    error: (_, __) => Text(
                      '0 analyses',
                      style: AppTypography.textSmRegular.copyWith(
                        color: kWhiteColor.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Three dot menu icon (like in reference image)
            Icon(
              Icons.more_vert,
              color: kWhiteColor.withValues(alpha: 0.4),
              size: 20.sp,
            ),
          ],
        ),
      ),
    );
  }
}

// Provider to get count of analyses in a folder
final _folderAnalysesCountProvider =
    FutureProvider.family.autoDispose<int, String>((ref, folderId) async {
  final repository = ref.watch(libraryRepositoryProvider);
  final analyses = await repository.getSavedAnalyses(folderId: folderId);
  return analyses.length;
});
