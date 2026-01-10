import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/screens/library/folder_contents_screen.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/screens/library/widgets/create_folder_dialog.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class FolderCard extends ConsumerWidget {
  final LibraryFolder folder;
  final bool isExpanded;
  final VoidCallback? onTap;

  const FolderCard({
    super.key,
    required this.folder,
    this.isExpanded = false,
    this.onTap,
  });

  void _navigateToFolder(BuildContext context) {
    HapticFeedback.mediumImpact();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => FolderContentsScreen(folder: folder)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Wrap with Material to prevent yellow underline bug in modals/overlays
    return Material(
      type: MaterialType.transparency,
      child: isExpanded ? _buildExpandedCard(context, ref) : _buildCompactCard(context),
    );
  }

  Widget _buildCompactCard(BuildContext context) {
    return GestureDetector(
      onTap: onTap ?? () => _navigateToFolder(context),
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
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedCard(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: onTap ?? () => _navigateToFolder(context),
      child: Container(
        padding: EdgeInsets.all(16.sp),
        decoration: BoxDecoration(
          color: const Color(0xFF18181B), // Zinc 900
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(color: const Color(0xFF27272A)), // Zinc 800
        ),
        child: Row(
          children: [
            // Folder icon
            Icon(
              Icons.folder_outlined,
              color: const Color(0xFFFAFAFA),
              size: 26.sp,
            ),

            SizedBox(width: 16.w),

            // Folder info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    folder.name,
                    style: AppTypography.textMdMedium.copyWith(color: kWhiteColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _openMenu(context, ref),
              child: Padding(
                padding: EdgeInsets.only(left: 12.w),
                child: Icon(
                  Icons.more_vert_rounded,
                  color: const Color(0xFFA1A1AA), // Zinc 400
                  size: 20.sp,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMenu(BuildContext context, WidgetRef ref) async {
    HapticFeedbackService.light();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: ResponsiveHelper.bottomSheetConstraints,
      builder: (ctx) => _FolderActionsSheet(
        folder: folder,
        onRename: () async {
          Navigator.of(ctx).pop();
          await _renameFolder(context, ref);
        },
        onDelete: () async {
          Navigator.of(ctx).pop();
          await _deleteFolder(context, ref);
        },
      ),
    );
  }

  Future<void> _renameFolder(BuildContext context, WidgetRef ref) async {
    final nextName = await showRenameFolderDialog(
      context,
      currentName: folder.name,
    );
    final name = nextName?.trim();
    if (name == null || name.isEmpty || name == folder.name) return;

    try {
      final repo = ref.read(libraryRepositoryProvider);
      await repo.updateFolder(
        LibraryFolder(
          id: folder.id,
          userId: folder.userId,
          name: name,
          color: folder.color,
          icon: folder.icon,
          orderIndex: folder.orderIndex,
          createdAt: folder.createdAt,
          updatedAt: DateTime.now(),
        ),
      );
      ref.invalidate(libraryFoldersStreamProvider);
      if (!context.mounted) return;
      HapticFeedbackService.success();
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
      if (!context.mounted) return;
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

  Future<void> _deleteFolder(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.isTablet ? 400 : double.infinity,
          ),
          child: AlertDialog(
            backgroundColor: kBlack2Color,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.br),
            ),
            title: Text(
              'Delete book?',
              style: AppTypography.textMdBold.copyWith(color: kWhiteColor),
            ),
            content: Text(
              'This removes the book. Games in it will stay saved but become unassigned.',
              style: AppTypography.textSmRegular.copyWith(
                color: kWhiteColor.withValues(alpha: 0.7),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(
                  'Cancel',
                  style: AppTypography.textSmMedium.copyWith(
                    color: kWhiteColor.withValues(alpha: 0.7),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(
                  'Delete',
                  style: AppTypography.textSmMedium.copyWith(color: kRedColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      final repo = ref.read(libraryRepositoryProvider);
      await repo.deleteFolder(folder.id);
      ref.invalidate(libraryFoldersStreamProvider);
      if (!context.mounted) return;
      HapticFeedbackService.success();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Book deleted',
            style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
          ),
          backgroundColor: kBlack2Color.withValues(alpha: 0.95),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      HapticFeedbackService.error();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to delete: $e',
            style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
          ),
          backgroundColor: kRedColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

class _FolderActionsSheet extends StatelessWidget {
  const _FolderActionsSheet({
    required this.folder,
    required this.onRename,
    required this.onDelete,
  });

  final LibraryFolder folder;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: kBlack2Color,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16.br)),
          border: Border.all(color: kWhiteColor.withValues(alpha: 0.08)),
        ),
        padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: kWhiteColor.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(10.br),
                ),
              ),
            ),
            SizedBox(height: 14.h),
            Text(
              folder.name,
              style: AppTypography.textMdMedium.copyWith(color: kWhiteColor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: 12.h),
            _ActionTile(
              icon: Icons.edit_rounded,
              label: 'Rename',
              onTap: onRename,
            ),
            SizedBox(height: 10.h),
            _ActionTile(
              icon: Icons.delete_outline_rounded,
              label: 'Delete',
              labelColor: kRedColor,
              iconColor: kRedColor,
              onTap: onDelete,
            ),
            SizedBox(height: MediaQuery.of(context).viewPadding.bottom),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.labelColor,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? labelColor;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
        decoration: BoxDecoration(
          color: kBlack3Color,
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(color: kWhiteColor.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor ?? kWhiteColor, size: 18.ic),
            SizedBox(width: 10.w),
            Text(
              label,
              style: AppTypography.textSmMedium.copyWith(
                color: labelColor ?? kWhiteColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
