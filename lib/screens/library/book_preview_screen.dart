import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/screens/library/folder_contents_screen.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/logger/logger.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/liquid_glass/glass_kit.dart';
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
    final title = previewAsync.valueOrNull?.name ?? 'Shared folder';

    return GlassFullScreenPage(
      key: e2eKey(E2eIds.bookPreviewRoot),
      backgroundColor: context.colors.background,
      contentPadding: const EdgeInsets.only(top: 68, bottom: 16),
      topOverlayPadding: const EdgeInsets.only(top: 4),
      topOverlay: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth:
                ResponsiveHelper.isTablet
                    ? ResponsiveHelper.contentMaxWidth
                    : double.infinity,
          ),
          child: GlassIslandTopBar(
            topPadding: 0,
            height: 48,
            leading: const GlassBackButton(),
            title: GlassTitleChip(label: title, maxWidth: 220.w),
          ),
        ),
      ),
      content: Center(
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
                () => Semantics(
                  label: 'Loading shared folder',
                  liveRegion: true,
                  child: Center(
                    child: CircularProgressIndicator(
                      color: context.colors.textPrimary,
                    ),
                  ),
                ),
            error: (error, _) => _buildError(userFacingError(error)),
          ),
        ),
      ),
    );
  }

  Widget _centeredScrollableBody(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight =
            (constraints.maxHeight - 48.h)
                .clamp(0.0, double.infinity)
                .toDouble();
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 24.h),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Center(child: child),
          ),
        );
      },
    );
  }

  Widget _buildPreview(
    String folderId,
    String name,
    String? ownerDisplayName,
    int gameCount,
    String color,
  ) {
    final currentUserId = ref.read(currentUserProvider)?.id;

    return _centeredScrollableBody(
      Column(
        mainAxisSize: MainAxisSize.min,
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
                color: context.colors.iconPrimary,
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
          ),
          SizedBox(height: 6.h),

          // Owner name
          if (ownerDisplayName != null && ownerDisplayName.isNotEmpty)
            Text(
              'by $ownerDisplayName',
              style: AppTypography.textMdRegular.copyWith(
                color: context.colors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          SizedBox(height: 8.h),

          // Game count
          Text(
            gameCount == 1 ? '1 game' : '$gameCount games',
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textTertiary,
            ),
          ),
          SizedBox(height: 32.h),

          // CTA button
          _buildCta(folderId, currentUserId),
        ],
      ),
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
                : userFacingError(
                  e,
                  fallback: 'Could not add this. Please try again.',
                ),
            style: AppTypography.textSmMedium.copyWith(
              color: Theme.of(context).colorScheme.onError,
            ),
          ),
          backgroundColor: context.colors.danger,
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
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Material(
            color:
                isPrimary
                    ? context.colors.brand.withValues(alpha: 0.16)
                    : context.colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14.br),
              side: BorderSide(
                color:
                    isPrimary
                        ? context.colors.brand.withValues(alpha: 0.45)
                        : context.colors.divider,
              ),
            ),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(14.br),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 14.h),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 20.sp, color: context.colors.iconPrimary),
                    SizedBox(width: 10.w),
                    Flexible(
                      child: Text(
                        label,
                        style: AppTypography.textMdMedium.copyWith(
                          color: context.colors.textPrimary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNotFound() {
    return _centeredScrollableBody(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.menu_book_outlined,
            size: 64.sp,
            color: context.colors.iconSecondary,
          ),
          SizedBox(height: 12.h),
          Text(
            'Folder not found',
            style: AppTypography.textLgMedium.copyWith(
              color: context.colors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 6.h),
          Text(
            'This folder may have been removed or the link is invalid.',
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildError(String error) {
    return _centeredScrollableBody(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 56.sp,
            color: context.colors.danger,
          ),
          SizedBox(height: 12.h),
          Text(
            'Something went wrong',
            style: AppTypography.textMdMedium.copyWith(
              color: context.colors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 6.h),
          Text(
            error,
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

enum _BookRelation { loading, ownBook, subscribed, newBook }
