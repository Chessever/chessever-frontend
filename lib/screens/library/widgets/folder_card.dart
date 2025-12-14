import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/screens/library/folder_contents_screen.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class FolderCard extends ConsumerWidget {
  final LibraryFolder folder;
  final bool isExpanded;

  const FolderCard({super.key, required this.folder, this.isExpanded = false});

  void _navigateToFolder(BuildContext context) {
    HapticFeedback.mediumImpact();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => FolderContentsScreen(folder: folder)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analysesCountAsync = ref.watch(
      _folderAnalysesCountProvider(folder.id),
    );

    // Wrap with Material to prevent yellow underline bug in modals/overlays
    return Material(
      type: MaterialType.transparency,
      child:
          isExpanded
              ? _buildExpandedCard(context, analysesCountAsync)
              : _buildCompactCard(context, analysesCountAsync),
    );
  }

  Widget _buildCompactCard(
    BuildContext context,
    AsyncValue<int> analysesCountAsync,
  ) {
    return GestureDetector(
      onTap: () => _navigateToFolder(context),
      child: Container(
        width: 140.w,
        decoration: BoxDecoration(
          color: const Color(0xFF09090B), // Zinc 950
          borderRadius: BorderRadius.circular(8.br),
          border: Border.all(
            color: const Color(0xFF27272A), // Zinc 800
            width: 1,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(12.sp),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Folder icon
              Icon(
                Icons.folder_outlined,
                color: const Color(0xFFFAFAFA), // Zinc 50
                size: 24.sp,
              ),

              // Folder name and count
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    folder.name,
                    style: AppTypography.textSmMedium.copyWith(
                      color: const Color(0xFFFAFAFA), // Zinc 50
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 2.h),
                  analysesCountAsync.when(
                    data:
                        (count) => Text(
                          '$count ${count == 1 ? 'game' : 'games'}',
                          style: AppTypography.textXsRegular.copyWith(
                            color: const Color(0xFFA1A1AA), // Zinc 400
                          ),
                        ),
                    loading:
                        () => SizedBox(
                          width: 12.w,
                          height: 12.h,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              const Color(0xFF27272A), // Zinc 800
                            ),
                          ),
                        ),
                    error:
                        (_, __) => Text(
                          '0 games',
                          style: AppTypography.textXsRegular.copyWith(
                            color: const Color(0xFFA1A1AA), // Zinc 400
                          ),
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedCard(
    BuildContext context,
    AsyncValue<int> analysesCountAsync,
  ) {
    return GestureDetector(
      onTap: () => _navigateToFolder(context),
      child: Container(
        padding: EdgeInsets.all(16.sp),
        decoration: BoxDecoration(
          color: const Color(0xFF09090B), // Zinc 950
          borderRadius: BorderRadius.circular(8.br),
          border: Border.all(
            color: const Color(0xFF27272A), // Zinc 800
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Folder icon
            Icon(
              Icons.folder_outlined,
              color: const Color(0xFFFAFAFA), // Zinc 50
              size: 24.sp,
            ),

            SizedBox(width: 16.w),

            // Folder info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    folder.name,
                    style: AppTypography.textMdMedium.copyWith(
                      color: const Color(0xFFFAFAFA), // Zinc 50
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 2.h),
                  analysesCountAsync.when(
                    data:
                        (count) => Text(
                          '$count ${count == 1 ? 'game' : 'games'}',
                          style: AppTypography.textSmRegular.copyWith(
                            color: const Color(0xFFA1A1AA), // Zinc 400
                          ),
                        ),
                    loading:
                        () => SizedBox(
                          width: 16.w,
                          height: 16.h,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              const Color(0xFF27272A), // Zinc 800
                            ),
                          ),
                        ),
                    error:
                        (_, __) => Text(
                          '0 games',
                          style: AppTypography.textSmRegular.copyWith(
                            color: const Color(0xFFA1A1AA), // Zinc 400
                          ),
                        ),
                  ),
                ],
              ),
            ),

            // Arrow
            // The image did not show an arrow, but keeping it subtle might be safer for UX.
            // However, the user said "1to1 identical". The image shows no arrow.
            // I'll remove the arrow to be safe and match "1to1".
          ],
        ),
      ),
    );
  }
}

// Provider to get count of analyses in a folder
final _folderAnalysesCountProvider = FutureProvider.family
    .autoDispose<int, String>((ref, folderId) async {
      final repository = ref.watch(libraryRepositoryProvider);
      final analyses = await repository.getSavedAnalyses(folderId: folderId);
      return analyses.length;
    });
