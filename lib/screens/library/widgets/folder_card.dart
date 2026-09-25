import 'dart:math' as math;

import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/screens/library/folder_contents_screen.dart';
import 'package:chessever2/screens/library/miniatures_screen.dart';
import 'package:chessever2/screens/my_likes/my_likes_screen.dart';
import 'package:chessever2/screens/library/providers/gamebase_database_games_provider.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/screens/library/providers/miniatures_provider.dart';
import 'package:chessever2/screens/library/widgets/create_folder_dialog.dart';
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/my_space/actions/space_menu_action.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/logger/logger.dart';
import 'package:chessever2/utils/number_format_utils.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// The platform minimum tap target the trailing 3-dot is sized to.
const double _kMoreTarget = 44.0;

String _formatGameCount(int count) {
  if (count == 0) return 'Empty database';
  if (count == 1) return '1 game';
  return '${formatCompactCount(count)} games';
}

String _formatChildCount(int count) {
  if (count == 0) return 'Empty folder';
  if (count == 1) return '1 item';
  return '$count items';
}

class FolderCard extends ConsumerWidget {
  final LibraryFolder folder;
  final bool isExpanded;
  final bool isFeatured;
  final VoidCallback? onTap;

  const FolderCard({
    super.key,
    required this.folder,
    this.isExpanded = false,
    this.isFeatured = false,
    this.onTap,
  });

  void _navigateToFolder(BuildContext context) {
    HapticFeedback.mediumImpact();
    if (folder.isLikedGames) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const MyLikesScreen()));
      return;
    }
    if (folder.id == kMiniaturesBookId) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const MiniaturesScreen()));
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => FolderContentsScreen(folder: folder)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      type: MaterialType.transparency,
      child:
          isExpanded
              ? _buildExpandedCard(context, ref)
              : _buildCompactCard(context),
    );
  }

  /// Library node glyph. Databases get the chess-database cylinder glyph
  /// (matching the desktop app); folders keep the folder outline; the special
  /// My Likes collection keeps its heart.
  Widget _buildNodeIcon(
    BuildContext context, {
    required double size,
    required bool isLiked,
  }) {
    if (isLiked) {
      return Icon(Icons.favorite, size: size, color: context.colors.danger);
    }
    if (folder.id == kMiniaturesBookId) {
      return Icon(
        Icons.bolt_rounded,
        size: size,
        color: context.colors.iconPrimary,
      );
    }
    if (folder.isDatabase) {
      return _ChessDatabaseGlyph(
        color: context.colors.iconPrimary,
        size: size,
      );
    }
    return SvgWidget(
      SvgAsset.folderOutline,
      width: size,
      height: size,
      colorFilter:
          context.isLightTheme
              ? ColorFilter.mode(context.colors.iconPrimary, BlendMode.srcIn)
              : null,
    );
  }

  Widget _buildCompactCard(BuildContext context) {
    return GestureDetector(
      onTap: onTap ?? () => _navigateToFolder(context),
      child: Container(
        width: 140.w,
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(12.br),
        ),
        child: Padding(
          padding: EdgeInsets.all(12.sp),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 34.h,
                height: 34.h,
                decoration: BoxDecoration(
                  color: context.colors.surfaceRecessed,
                  borderRadius: BorderRadius.circular(10.br),
                ),
                child: Center(
                  child: _buildNodeIcon(
                    context,
                    size: 18.sp,
                    isLiked: folder.isLikedGames,
                  ),
                ),
              ),
              Text(
                folder.displayName,
                style: AppTypography.textSmMedium.copyWith(
                  color: context.colors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedCard(BuildContext context, WidgetRef ref) {
    final isTwic = folder.id == kTwicBookId;
    final isMiniatures = folder.id == kMiniaturesBookId;
    final isLiked = folder.isLikedGames;
    // Synthetic / special, permanent collections — no rename/delete/share menu.
    final isProtected = isTwic || isMiniatures || isLiked;

    // CSS specs: featured = 64x64 icon, ~18px radius; regular = 36x36 icon, 10px radius
    final iconSize = isFeatured ? 64.0.h : 36.0.h;
    final iconRadius = isFeatured ? 17.78.br : 10.0.br;
    final svgSize = isFeatured ? 35.56.sp : 20.0.sp;

    final Widget countWidget;
    if (isTwic) {
      final twicTotalAsync = ref.watch(twicDatabaseTotalGamesProvider);
      final twicLabelStyle = AppTypography.textXsRegular.copyWith(
        color: context.colors.textSecondary,
        height: 16 / 12,
      );
      countWidget = twicTotalAsync.when(
        data:
            (count) => Text(
              count > 0
                  ? '${formatCompactCount(count)} master games'
                  : 'Master games',
              style: twicLabelStyle,
            ),
        loading: () => Text('Master games', style: twicLabelStyle),
        error: (_, __) => Text('Master games', style: twicLabelStyle),
      );
    } else if (isMiniatures) {
      final miniaturesTotalAsync = ref.watch(miniaturesTotalCountProvider);
      final miniaturesLabelStyle = AppTypography.textXsRegular.copyWith(
        color: context.colors.textSecondary,
        height: 16 / 12,
      );
      countWidget = miniaturesTotalAsync.when(
        data:
            (count) => Text(
              count > 0
                  ? '${formatCompactCount(count)} miniatures'
                  : 'Short decisive games',
              style: miniaturesLabelStyle,
            ),
        loading: () => Text('Short decisive games', style: miniaturesLabelStyle),
        error: (_, __) => Text('Short decisive games', style: miniaturesLabelStyle),
      );
    } else if (folder.isFolder) {
      final childCount =
          ref.watch(childLibraryFoldersProvider(folder.id)).length;
      countWidget = Text(
        _formatChildCount(childCount),
        style: AppTypography.textXsRegular.copyWith(
          color: context.colors.textSecondary,
          height: 16 / 12,
        ),
      );
    } else {
      final countAsync = ref.watch(folderAnalysisCountProvider(folder.id));
      countWidget = countAsync.when(
        data:
            (count) => Text(
              _formatGameCount(count),
              style: AppTypography.textXsRegular.copyWith(
                color: context.colors.textSecondary,
                height: 16 / 12,
              ),
            ),
        loading:
            () => Text(
              '...',
              style: AppTypography.textXsRegular.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
        error: (_, __) => const SizedBox.shrink(),
      );
    }

    // Subtitle for subscribed books: show owner name
    Widget? subtitleWidget;
    if (folder.isSubscribed && folder.ownerDisplayName != null) {
      subtitleWidget = Text(
        'by ${folder.ownerDisplayName}',
        style: AppTypography.textXsRegular.copyWith(
          color: context.colors.textSecondary,
          height: 16 / 12,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    // The 3-dot takes exactly the footprint the old dots had in the row (an
    // 8.w lead, then a 24.sp glyph flush to the content edge), so the card's
    // height, the name column and the glyph never move. Its 44dp target
    // floats over the card, centred on that glyph, instead of widening or
    // heightening the row.
    final moreFootprint = 8.w + 24.sp;
    final moreGlyphFromRight = 12.w + 12.sp;
    final open = onTap ?? () => _navigateToFolder(context);

    final row = Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 14.h),
      child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Folder icon squircle with optional shared badge
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: iconSize,
                  height: iconSize,
                  decoration: BoxDecoration(
                    color: context.colors.surfaceRecessed,
                    borderRadius: BorderRadius.circular(iconRadius),
                  ),
                  child: Center(
                    child: _buildNodeIcon(
                      context,
                      size: svgSize,
                      isLiked: isLiked,
                    ),
                  ),
                ),
                // Shared link badge for subscribed books
                if (folder.isSubscribed)
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Container(
                      width: 18.sp,
                      height: 18.sp,
                      decoration: BoxDecoration(
                        color: context.colors.surfaceRecessed,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: context.colors.surface,
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.link_rounded,
                          size: 10.sp,
                          color: context.colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),

            SizedBox(width: 8.w),

            // Folder info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    folder.displayName,
                    style: AppTypography.textSmMedium.copyWith(
                      color: context.colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitleWidget != null) subtitleWidget,
                  countWidget,
                ],
              ),
            ),

            // Right arrow for protected collections (TWIC, Liked Games),
            // plus a source-links affordance for the ChessEver master DB.
            if (isProtected)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isTwic)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedbackService.light();
                        _showChessEverSourceLinksDialog(context);
                      },
                      child: Padding(
                        padding: EdgeInsets.only(left: 8.w, right: 6.w),
                        child: Icon(
                          Icons.info_outline_rounded,
                          color: context.colors.textPrimary.withValues(
                            alpha: 0.7,
                          ),
                          size: 20.sp,
                        ),
                      ),
                    ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: context.colors.textPrimary.withValues(alpha: 0.7),
                    size: 20.sp,
                    weight: 700,
                  ),
                ],
              )
            else
              // The old dots' footprint; the glyph itself is drawn by the
              // floating target below, over this exact spot.
              SizedBox(width: moreFootprint, height: 24.sp),
          ],
        ),
    );

    final card = _PressableMotionCard(
      onTap: open,
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(12.br),
        ),
        child:
            isProtected
                ? row
                : Stack(
                  clipBehavior: Clip.none,
                  children: [
                    row,
                    Positioned(
                      top: 0,
                      bottom: 0,
                      right: moreGlyphFromRight - _kMoreTarget / 2,
                      width: _kMoreTarget,
                      child: Center(
                        child: CardMoreButton(
                          vertical: true,
                          tooltip: 'Folder actions',
                          color: context.colors.textPrimary.withValues(
                            alpha: 0.7,
                          ),
                          size: 24.sp,
                        ),
                      ),
                    ),
                  ],
                ),
      ),
    );

    // Long-press and the 3-dot open one menu: the card lifts in place with
    // its actions. Built-in collections have nothing to rename or delete, so
    // theirs offers only the My Space shortcut.
    return CardContextMenu(
      onPreviewTap: open,
      actions: (cardContext) => _menuActions(cardContext, ref),
      child: card,
    );
  }

  void _showChessEverSourceLinksDialog(BuildContext context) {
    showAlertModal<void>(
      context: context,
      child: Builder(
        builder:
            (dialogContext) => Container(
              constraints: BoxConstraints(
                maxWidth: ResponsiveHelper.isTablet ? 400.w : double.infinity,
              ),
              padding: EdgeInsets.all(20.sp),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(16.br),
                border: Border.all(
                  color: context.colors.textPrimary.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ChessEver source databases',
                    style: AppTypography.textMdMedium.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 16.h),
                  Text(
                    'Links',
                    style: AppTypography.textSmMedium.copyWith(
                      color: context.colors.textPrimary.withValues(alpha: 0.8),
                    ),
                  ),
                  SizedBox(height: 12.h),
                  _buildSourceLink(
                    dialogContext,
                    'Lichess',
                    'https://lichess.org/',
                  ),
                  _buildSourceLink(
                    dialogContext,
                    'TWIC',
                    'https://theweekinchess.com/',
                  ),
                  _buildSourceLink(
                    dialogContext,
                    'Lumbra\'s Gigabase',
                    'https://lumbrasgigabase.com/en/download-in-pgn-format-en/',
                  ),
                  _buildSourceLink(
                    dialogContext,
                    'ChessEver',
                    'https://chessever.com/',
                  ),
                  SizedBox(height: 16.h),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: Text(
                        'Close',
                        style: AppTypography.textSmMedium.copyWith(
                          color: context.colors.textPrimary.withValues(
                            alpha: 0.8,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
      ),
    );
  }

  Future<void> _launchDatabaseSource(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      if (!context.mounted) return;
      HapticFeedbackService.error();
      showAppSnack(context, 'Could not open link', tone: AppSnackTone.danger);
      return;
    }

    final canOpen = await canLaunchUrl(uri);
    if (!canOpen) {
      if (!context.mounted) return;
      HapticFeedbackService.error();
      showAppSnack(context, 'Could not open $url', tone: AppSnackTone.danger);
      return;
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _buildSourceLink(BuildContext context, String label, String url) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: TextButton(
        onPressed: () async {
          Navigator.of(context).pop();
          await _launchDatabaseSource(context, url);
        },
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          alignment: Alignment.centerLeft,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppTypography.textSmMedium.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
            SizedBox(height: 2.h),
            Text(
              url,
              style: AppTypography.textXsRegular.copyWith(
                color: context.colors.accentText.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// This node as a My Space shortcut. The synthetic collections map to their
  /// own kinds so My Space opens the same screen the card does.
  SpaceShortcut _spaceDraft() {
    if (folder.isLikedGames) {
      return SpaceShortcut.draft(
        kind: SpaceShortcutKind.likes,
        targetId: 'me',
        title: folder.displayName,
      );
    }
    if (folder.id == kMiniaturesBookId) {
      return SpaceShortcut.draft(
        kind: SpaceShortcutKind.miniatures,
        targetId: 'today',
        title: folder.displayName,
        subtitle: 'Short decisive games',
      );
    }
    return SpaceShortcut.draft(
      kind: SpaceShortcutKind.folder,
      targetId: folder.id,
      title: folder.displayName,
      subtitle:
          folder.id == kTwicBookId
              ? 'Master games'
              : folder.isSubscribed && folder.ownerDisplayName != null
              ? 'by ${folder.ownerDisplayName}'
              : folder.isFolder
              ? 'Folder'
              : 'Database',
      params: {
        'nodeType': folder.nodeType,
        if (folder.isSubscribed) 'subscribed': true,
      },
    );
  }

  LibraryMenuAction _spaceAction(BuildContext context, WidgetRef ref) =>
      spaceMenuAction(context: context, ref: ref, draft: _spaceDraft());

  /// Every action the old overlay menus offered, in the same order and with
  /// the same labels, now raised through the shared focus menu.
  List<LibraryMenuAction> _menuActions(BuildContext context, WidgetRef ref) {
    final isProtected =
        folder.id == kTwicBookId ||
        folder.id == kMiniaturesBookId ||
        folder.isLikedGames;
    final spaceAction = _spaceAction(context, ref);
    if (isProtected) return [spaceAction];

    if (folder.isSubscribed) {
      // Subscribed books: My Space and Unsubscribe
      return [
        spaceAction,
        LibraryMenuAction(
          icon: Icons.link_off_rounded,
          label: 'Unsubscribe',
          destructive: true,
          onSelected: () => _unsubscribeFromBook(context, ref),
        ),
      ];
    }

    final isNonShareable = folder.parentId != null || folder.isFolder;
    // Only a root database can be shared. A nested one keeps the row so the
    // tap explains why, exactly as before.
    void explainRootOnly() {
      HapticFeedbackService.error();
      showAppSnack(context, 'only root-level folder can be shared with others');
    }

    final delete = LibraryMenuAction(
      icon: Icons.delete_outline_rounded,
      label: 'Delete',
      destructive: true,
      onSelected: () => _deleteFolder(context, ref),
    );
    final rename = LibraryMenuAction(
      icon: Icons.edit_rounded,
      label: 'Rename',
      onSelected: () => _renameFolder(context, ref),
    );

    final shareToken = folder.shareToken;
    if (shareToken != null) {
      // Already shared: Copy Link, Stop Sharing, Rename, My Space, Delete
      return [
        LibraryMenuAction(
          icon: Icons.copy_rounded,
          label: 'Copy Link',
          onSelected:
              isNonShareable
                  ? explainRootOnly
                  : () => _copyShareLink(context, shareToken),
        ),
        LibraryMenuAction(
          icon: Icons.link_off_rounded,
          label: 'Stop Sharing',
          onSelected: () => _stopSharing(context, ref),
        ),
        rename,
        spaceAction,
        delete,
      ];
    }

    // Not shared: Share, Rename, My Space, Delete
    return [
      LibraryMenuAction(
        icon: Icons.ios_share_rounded,
        label: 'Share',
        onSelected:
            isNonShareable ? explainRootOnly : () => _shareFolder(context, ref),
      ),
      rename,
      spaceAction,
      delete,
    ];
  }

  Future<void> _shareFolder(BuildContext context, WidgetRef ref) async {
    try {
      final repo = ref.read(libraryRepositoryProvider);
      final updatedFolder = await repo.generateShareToken(folder.id);
      ref.invalidate(libraryFoldersStreamProvider);

      if (!context.mounted) return;
      final url = 'https://chessever.com/books/${updatedFolder.shareToken}';
      final box = context.findRenderObject() as RenderBox?;
      final origin =
          box != null
              ? box.localToGlobal(Offset.zero) & box.size
              : const Rect.fromLTWH(0, 0, 1, 1);
      await Share.share(url, sharePositionOrigin: origin);
    } catch (e, st) {
      talker.handle(e, st);
      if (!context.mounted) return;
      HapticFeedbackService.error();
      showAppSnack(
        context,
        userFacingError(e, fallback: 'Could not share this. Please try again.'),
        tone: AppSnackTone.danger,
      );
    }
  }

  void _copyShareLink(BuildContext context, String shareToken) {
    final url = 'https://chessever.com/books/$shareToken';
    Clipboard.setData(ClipboardData(text: url));
    HapticFeedbackService.success();
    showAppSnack(context, 'Link copied');
  }

  Future<void> _stopSharing(BuildContext context, WidgetRef ref) async {
    try {
      final repo = ref.read(libraryRepositoryProvider);
      await repo.revokeShareToken(folder.id);
      ref.invalidate(libraryFoldersStreamProvider);

      if (!context.mounted) return;
      HapticFeedbackService.success();
      showAppSnack(context, 'Sharing stopped');
    } catch (e, st) {
      talker.handle(e, st);
      if (!context.mounted) return;
      HapticFeedbackService.error();
      showAppSnack(
        context,
        userFacingError(e, fallback: 'Could not stop sharing. Please try again.'),
        tone: AppSnackTone.danger,
      );
    }
  }

  Future<void> _unsubscribeFromBook(BuildContext context, WidgetRef ref) async {
    try {
      final repo = ref.read(libraryRepositoryProvider);
      await repo.unsubscribeFromBook(folder.id);
      ref.invalidate(subscribedBooksProvider);
      ref.invalidate(combinedLibraryFoldersProvider);

      if (!context.mounted) return;
      HapticFeedbackService.success();
      showAppSnack(context, 'Unsubscribed from "${folder.name}"');
    } catch (e, st) {
      talker.handle(e, st);
      if (!context.mounted) return;
      HapticFeedbackService.error();
      showAppSnack(
        context,
        userFacingError(e, fallback: 'Could not unsubscribe. Please try again.'),
        tone: AppSnackTone.danger,
      );
    }
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
        folder.copyWith(name: name, updatedAt: DateTime.now()),
      );
      ref.invalidate(libraryFoldersStreamProvider);
      if (!context.mounted) return;
      HapticFeedbackService.success();
      showAppSnack(context, 'Renamed to "$name"');
    } catch (e, st) {
      talker.handle(e, st);
      if (!context.mounted) return;
      HapticFeedbackService.error();
      showAppSnack(
        context,
        userFacingError(e, fallback: 'Could not rename this item. Please try again.'),
        tone: AppSnackTone.danger,
      );
    }
  }

  Future<void> _deleteFolder(BuildContext context, WidgetRef ref) async {
    final confirmed = await showSmoothConfirmDialog(
      context: context,
      title: 'Delete ${folder.isFolder ? 'folder' : 'database'}?',
      message:
          folder.isFolder
              ? 'This permanently deletes the folder and every database inside it. This cannot be undone.'
              : 'This permanently deletes the database and every game inside it. This cannot be undone.',
      confirmText: 'Delete',
      isDangerous: true,
    );

    if (confirmed != true) return;

    try {
      final repo = ref.read(libraryRepositoryProvider);
      await repo.deleteFolder(folder.id);
      ref.invalidate(libraryFoldersStreamProvider);
      // Deleting a folder cascades its analyses; any parent folder's
      // recursive count must be re-queried.
      ref.invalidate(folderAnalysisCountProvider);
      if (!context.mounted) return;
      HapticFeedbackService.success();
      showAppSnack(
        context,
        '${folder.isFolder ? 'Folder' : 'Database'} deleted',
      );
    } catch (e, st) {
      talker.handle(e, st);
      if (!context.mounted) return;
      HapticFeedbackService.error();
      showAppSnack(
        context,
        userFacingError(e, fallback: 'Could not delete this item. Please try again.'),
        tone: AppSnackTone.danger,
      );
    }
  }
}

/// Motor-animated press card with bouncy scale feedback
class _PressableMotionCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _PressableMotionCard({required this.child, this.onTap});

  @override
  State<_PressableMotionCard> createState() => _PressableMotionCardState();
}

class _PressableMotionCardState extends State<_PressableMotionCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      // No long-press here: the enclosing CardContextMenu owns it.
      child: SingleMotionBuilder(
        motion: CupertinoMotion.bouncy(),
        value: _isPressed ? 0.97 : 1.0,
        builder: (context, value, child) {
          return Transform.scale(scale: value, child: child);
        },
        child: widget.child,
      ),
    );
  }
}

/// Chess-database glyph: a database cylinder with a tiny 2x2 chessboard,
/// ported from the desktop app to mark database nodes in the library.
class _ChessDatabaseGlyph extends StatelessWidget {
  const _ChessDatabaseGlyph({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _ChessDatabaseGlyphPainter(color)),
    );
  }
}

class _ChessDatabaseGlyphPainter extends CustomPainter {
  const _ChessDatabaseGlyphPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 20, size.height / 20);
    final stroke =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.45
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    final fill =
        Paint()
          ..color = color.withValues(alpha: 0.14)
          ..style = PaintingStyle.fill;
    final squareFill =
        Paint()
          ..color = color.withValues(alpha: 0.42)
          ..style = PaintingStyle.fill;

    final body = Rect.fromLTWH(3.2, 4.4, 13.6, 11.8);
    final top = Rect.fromLTWH(3.2, 2.2, 13.6, 5.0);
    final bottom = Rect.fromLTWH(3.2, 13.7, 13.6, 4.8);

    final path =
        Path()
          ..moveTo(body.left, top.center.dy)
          ..lineTo(body.left, bottom.center.dy)
          ..arcTo(bottom, math.pi, -math.pi, false)
          ..lineTo(body.right, top.center.dy);

    canvas.drawPath(path, fill);
    canvas.drawOval(top, fill);
    canvas.drawPath(path, stroke);
    canvas.drawOval(top, stroke);
    canvas.drawArc(bottom, 0, math.pi, false, stroke);

    const cell = 2.25;
    final boardLeft = body.left + 4.55;
    final boardTop = body.top + 5.25;
    final boardStroke =
        Paint()
          ..color = color.withValues(alpha: 0.72)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.75;
    final board = Rect.fromLTWH(boardLeft, boardTop, cell * 2, cell * 2);
    canvas.drawRect(board, boardStroke);
    canvas.drawRect(Rect.fromLTWH(boardLeft, boardTop, cell, cell), squareFill);
    canvas.drawRect(
      Rect.fromLTWH(boardLeft + cell, boardTop + cell, cell, cell),
      squareFill,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ChessDatabaseGlyphPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
