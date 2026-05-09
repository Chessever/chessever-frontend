import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

enum AddToLibraryChoice { createDatabase, importPgn, pickPgnFile }

/// Bottom sheet that offers the three "add to library" entry points:
/// creating a new (sub-)database, importing a PGN from clipboard, and
/// picking a `.pgn` file from the device.
///
/// Pass [showCreateDatabase] = false to hide the create option — e.g. when
/// shown from inside a sub-database where deeper nesting isn't allowed.
Future<AddToLibraryChoice?> showAddToLibrarySheet(
  BuildContext context, {
  String title = 'Add to Library',
  bool showCreateDatabase = true,
  String createDatabaseTitle = 'Create Database',
  String createDatabaseSubtitle = 'New empty database or sub-database',
}) {
  return showModalBottomSheet<AddToLibraryChoice>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder:
        (context) => SafeArea(
          top: false,
          child: Container(
            margin: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: const Color(0xFF121214),
              borderRadius: BorderRadius.circular(20.br),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(20.w, 18.h, 20.w, 6.h),
                  child: Row(
                    children: [
                      Text(
                        title,
                        style: AppTypography.textLgBold.copyWith(
                          color: context.colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (showCreateDatabase) ...[
                  _AddSourceTile(
                    icon: Icons.create_new_folder_outlined,
                    title: createDatabaseTitle,
                    subtitle: createDatabaseSubtitle,
                    onTap:
                        () => Navigator.of(
                          context,
                        ).pop(AddToLibraryChoice.createDatabase),
                  ),
                  Divider(
                    height: 1,
                    thickness: 0.5,
                    color: kWhiteColor.withValues(alpha: 0.05),
                  ),
                ],
                _AddSourceTile(
                  icon: Icons.content_paste_go_rounded,
                  title: 'Import PGN',
                  subtitle: 'Paste one or more games from clipboard',
                  onTap:
                      () => Navigator.of(
                        context,
                      ).pop(AddToLibraryChoice.importPgn),
                ),
                Divider(
                  height: 1,
                  thickness: 0.5,
                  color: kWhiteColor.withValues(alpha: 0.05),
                ),
                _AddSourceTile(
                  icon: Icons.folder_open_rounded,
                  title: 'Import PGN file',
                  subtitle: 'Choose a .pgn file from your device',
                  onTap:
                      () => Navigator.of(
                        context,
                      ).pop(AddToLibraryChoice.pickPgnFile),
                ),
                SizedBox(height: 8.h),
              ],
            ),
          ),
        ),
  );
}

class _AddSourceTile extends StatelessWidget {
  const _AddSourceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 14.h),
        child: Row(
          children: [
            Container(
              width: 40.sp,
              height: 40.sp,
              decoration: BoxDecoration(
                color: kPrimaryColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10.br),
              ),
              child: Icon(icon, color: kPrimaryColor, size: 22.sp),
            ),
            SizedBox(width: 14.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.textSmMedium.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    subtitle,
                    style: AppTypography.textXsRegular.copyWith(
                      color: kWhiteColor.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: kWhiteColor.withValues(alpha: 0.35),
              size: 20.sp,
            ),
          ],
        ),
      ),
    );
  }
}
