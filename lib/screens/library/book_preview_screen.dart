import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/screens/library/folder_contents_screen.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/logger/logger.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Deep link landing screen for shared books.
/// Shows book name, owner, game count, and subscribe/view CTA.
class BookPreviewScreen extends ConsumerStatefulWidget {
  const BookPreviewScreen({super.key, required this.shareToken});

  final String shareToken;

  @override
  ConsumerState<BookPreviewScreen> createState() => _BookPreviewScreenState();
}

class _BookPreviewScreenState extends ConsumerState<BookPreviewScreen> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final previewAsync = ref.watch(
      sharedBookPreviewProvider(widget.shareToken),
    );

    return Scaffold(
      key: e2eKey(E2eIds.bookPreviewRoot),
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
            child: previewAsync.when(
              data: (preview) {
                if (preview == null) return _buildNotFound();
                return _buildPreview(
                  preview.id,
                  preview.name,
                  preview.ownerDisplayName,
                  preview.gameCount,
                  preview.color,
                );
              },
              loading:
                  () =>  Center(
                    child: CircularProgressIndicator(color: context.colors.textPrimary),
                  ),
              error: (error, _) => _buildError(userFacingError(error)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreview(
    String folderId,
    String name,
    String? ownerDisplayName,
    int gameCount,
    String color,
  ) {
    final topPadding = MediaQuery.of(context).viewPadding.top;
    final currentUserId = ref.read(currentUserProvider)?.id;

    return Column(
      children: [
        // Header with back button
        Padding(
          padding: EdgeInsets.only(top: topPadding + 8.h, bottom: 8.h),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.w),
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: context.colors.textPrimary,
                  size: 20.ic,
                ),
              ),
            ),
          ),
        ),

        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Folder icon
                Container(
                  width: 80.h,
                  height: 80.h,
                  decoration: BoxDecoration(
                    color: context.colors.surfaceRecessed,
                    borderRadius: BorderRadius.circular(22.br),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.menu_book_rounded,
                      size: 40.sp,
                      color: context.colors.textPrimary.withValues(alpha: 0.85),
                    ),
                  ),
                ),
                SizedBox(height: 20.h),

                // Book name
                Text(
                  name,
                  style: AppTypography.displayXsMedium.copyWith(
                    color: context.colors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 6.h),

                // Owner name
                if (ownerDisplayName != null && ownerDisplayName.isNotEmpty)
                  Text(
                    'by $ownerDisplayName',
                    style: AppTypography.textMdRegular.copyWith(
                      color: context.colors.textPrimary.withValues(alpha: 0.6),
                    ),
                    textAlign: TextAlign.center,
                  ),
                SizedBox(height: 8.h),

                // Game count
                Text(
                  gameCount == 1 ? '1 game' : '$gameCount games',
                  style: AppTypography.textSmRegular.copyWith(
                    color: context.colors.textPrimary.withValues(alpha: 0.5),
                  ),
                ),
                SizedBox(height: 32.h),

                // CTA button
                _buildCta(folderId, currentUserId),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCta(String folderId, String? currentUserId) {
    return FutureBuilder<_BookRelation>(
      future: _checkRelation(folderId, currentUserId),
      builder: (context, snapshot) {
        final relation = snapshot.data ?? _BookRelation.loading;

        switch (relation) {
          case _BookRelation.loading:
            return SizedBox(
              height: 48,
              child: Center(
                child: CircularProgressIndicator(
                  color: context.colors.textPrimary,
                  strokeWidth: 2,
                ),
              ),
            );

          case _BookRelation.ownBook:
            return _buildActionButton(
              label: 'This is your folder',
              icon: Icons.check_circle_outline_rounded,
              onTap: () {
                HapticFeedbackService.light();
                Navigator.of(context).pop();
              },
            );

          case _BookRelation.subscribed:
            return _buildActionButton(
              label: 'Already in Library',
              icon: Icons.check_rounded,
              onTap: () {
                HapticFeedbackService.light();
                Navigator.of(context).pop();
              },
            );

          case _BookRelation.newBook:
            return _buildActionButton(
              label: _isLoading ? 'Adding...' : 'Add to Library',
              icon: Icons.add_rounded,
              isPrimary: true,
              onTap: _isLoading ? null : () => _subscribe(folderId),
            );
        }
      },
    );
  }

  Future<_BookRelation> _checkRelation(
    String folderId,
    String? currentUserId,
  ) async {
    if (currentUserId == null) return _BookRelation.newBook;

    final repo = ref.read(libraryRepositoryProvider);

    // Check if it's the user's own folder
    final ownFolder = await repo.getFolder(folderId);
    if (ownFolder != null) return _BookRelation.ownBook;

    // Check if already subscribed
    final subscribed = await repo.isSubscribedToBook(folderId);
    if (subscribed) return _BookRelation.subscribed;

    return _BookRelation.newBook;
  }

  Future<void> _subscribe(String folderId) async {
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(libraryRepositoryProvider);
      await repo.subscribeToBook(folderId);

      // Refresh subscribed books list
      ref.invalidate(subscribedBooksProvider);
      ref.invalidate(combinedLibraryFoldersProvider);

      if (!mounted) return;
      HapticFeedbackService.success();

      // Fetch the folder to navigate into it
      final subscribedBooks = await repo.getSubscribedBooks();
      final folder = subscribedBooks.where((f) => f.id == folderId).firstOrNull;

      if (!mounted) return;
      if (folder != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => FolderContentsScreen(folder: folder),
          ),
        );
      } else {
        Navigator.of(context).pop();
      }
    } catch (e, st) {
      talker.handle(e, st);
      if (!mounted) return;
      HapticFeedbackService.error();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().contains('Duplicate')
                ? 'Already in your library'
                : userFacingError(e, fallback: 'Could not add this. Please try again.'),
            style: AppTypography.textSmMedium.copyWith(color: context.colors.textPrimary),
          ),
          backgroundColor: kRedColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    VoidCallback? onTap,
    bool isPrimary = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 14.h),
        decoration: BoxDecoration(
          color:
              isPrimary
                  ? context.colors.textPrimary.withValues(alpha: 0.15)
                  : context.colors.textPrimary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(
            color:
                isPrimary
                    ? context.colors.textPrimary.withValues(alpha: 0.3)
                    : context.colors.textPrimary.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20.sp, color: context.colors.textPrimary.withValues(alpha: 0.85)),
            SizedBox(width: 10.w),
            Text(
              label,
              style: AppTypography.textMdMedium.copyWith(
                color: context.colors.textPrimary.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotFound() {
    final topPadding = MediaQuery.of(context).viewPadding.top;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.only(top: topPadding + 8.h, bottom: 8.h),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.w),
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: context.colors.textPrimary,
                  size: 20.ic,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.menu_book_outlined,
                  size: 64.sp,
                  color: context.colors.textPrimary.withValues(alpha: 0.35),
                ),
                SizedBox(height: 12.h),
                Text(
                  'Folder not found',
                  style: AppTypography.textLgMedium.copyWith(
                    color: context.colors.textPrimary.withValues(alpha: 0.85),
                  ),
                ),
                SizedBox(height: 6.h),
                Text(
                  'This folder may have been removed or the link is invalid.',
                  style: AppTypography.textSmRegular.copyWith(
                    color: context.colors.textPrimary.withValues(alpha: 0.55),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildError(String error) {
    final topPadding = MediaQuery.of(context).viewPadding.top;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.only(top: topPadding + 8.h, bottom: 8.h),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.w),
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: context.colors.textPrimary,
                  size: 20.ic,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 56.sp,
                  color: kRedColor.withValues(alpha: 0.85),
                ),
                SizedBox(height: 12.h),
                Text(
                  'Something went wrong',
                  style: AppTypography.textMdMedium.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
                SizedBox(height: 6.h),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32.w),
                  child: Text(
                    error,
                    style: AppTypography.textSmRegular.copyWith(
                      color: context.colors.textPrimary.withValues(alpha: 0.6),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

enum _BookRelation { loading, ownBook, subscribed, newBook }
