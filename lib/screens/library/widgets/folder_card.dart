import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/screens/library/folder_contents_screen.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/screens/library/widgets/create_folder_dialog.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/number_format_utils.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';
import 'package:share_plus/share_plus.dart';

String _formatGameCount(int count) {
  if (count == 0) return 'Empty';
  if (count == 1) return '1 game';
  return '${formatCompactCount(count)} games';
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

  Widget _buildCompactCard(BuildContext context) {
    return GestureDetector(
      onTap: onTap ?? () => _navigateToFolder(context),
      child: Container(
        width: 140.w,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1C),
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
                  color: const Color(0xFF262626),
                  borderRadius: BorderRadius.circular(10.br),
                ),
                child: Center(
                  child: SvgWidget(
                    SvgAsset.folderOutline,
                    width: 18.sp,
                    height: 18.sp,
                  ),
                ),
              ),
              Text(
                folder.name,
                style: AppTypography.textSmMedium.copyWith(
                  color: const Color(0xFFFAFAFA),
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

    // CSS specs: featured = 64x64 icon, ~18px radius; regular = 36x36 icon, 10px radius
    final iconSize = isFeatured ? 64.0.h : 36.0.h;
    final iconRadius = isFeatured ? 17.78.br : 10.0.br;
    final svgSize = isFeatured ? 35.56.sp : 20.0.sp;

    final Widget countWidget;
    if (isTwic) {
      countWidget = Text(
        '4M+ master games',
        style: AppTypography.textXsRegular.copyWith(
          color: const Color(0xFFA1A1A1),
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
                color: const Color(0xFFA1A1A1),
                height: 16 / 12,
              ),
            ),
        loading:
            () => Text(
              '...',
              style: AppTypography.textXsRegular.copyWith(
                color: const Color(0xFFA1A1A1),
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
          color: const Color(0xFFA1A1A1),
          height: 16 / 12,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return _PressableMotionCard(
      onTap: onTap ?? () => _navigateToFolder(context),
      onLongPress: isTwic ? null : () => _showOverlayMenu(context, ref),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 14.h),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1C),
          borderRadius: BorderRadius.circular(12.br),
        ),
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
                    color: const Color(0xFF262626),
                    borderRadius: BorderRadius.circular(iconRadius),
                  ),
                  child: Center(
                    child: SvgWidget(
                      SvgAsset.folderOutline,
                      width: svgSize,
                      height: svgSize,
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
                        color: const Color(0xFF262626),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF1A1A1C),
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.link_rounded,
                          size: 10.sp,
                          color: const Color(0xFFA1A1A1),
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
                    folder.name,
                    style: AppTypography.textSmMedium.copyWith(
                      color: const Color(0xFFFAFAFA),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitleWidget != null) subtitleWidget,
                  countWidget,
                ],
              ),
            ),

            // Right arrow for TWIC, 3-dot menu for other books
            if (isTwic)
              Padding(
                padding: EdgeInsets.only(left: 8.w),
                child: Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: const Color(0xFFFFFFFF).withValues(alpha: 0.7),
                  size: 20.sp,
                  weight: 700,
                ),
              )
            else
              _DotsMenuButton(onTap: () => _showOverlayMenu(context, ref)),
          ],
        ),
      ),
    );
  }

  void _showOverlayMenu(BuildContext context, WidgetRef ref) {
    HapticFeedbackService.light();

    if (folder.isSubscribed) {
      // Subscribed books: only show Unsubscribe
      showSubscribedFolderOverlayMenu(
        context: context,
        onUnsubscribe: () => _unsubscribeFromBook(context, ref),
      );
    } else if (folder.shareToken != null) {
      // Already shared: show Copy Link, Stop Sharing, Rename, Delete
      showSharedFolderOverlayMenu(
        context: context,
        onCopyLink: () => _copyShareLink(context, folder.shareToken!),
        onStopSharing: () => _stopSharing(context, ref),
        onRename: () => _renameFolder(context, ref),
        onDelete: () => _deleteFolder(context, ref),
      );
    } else {
      // Not shared: show Share, Rename, Delete
      showFolderOverlayMenu(
        context: context,
        onShare: () => _shareFolder(context, ref),
        onRename: () => _renameFolder(context, ref),
        onDelete: () => _deleteFolder(context, ref),
      );
    }
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
    } catch (e) {
      if (!context.mounted) return;
      HapticFeedbackService.error();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to share: $e',
            style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
          ),
          backgroundColor: kRedColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _copyShareLink(BuildContext context, String shareToken) {
    final url = 'https://chessever.com/books/$shareToken';
    Clipboard.setData(ClipboardData(text: url));
    HapticFeedbackService.success();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Link copied',
          style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
        ),
        backgroundColor: kBlack2Color.withValues(alpha: 0.95),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _stopSharing(BuildContext context, WidgetRef ref) async {
    try {
      final repo = ref.read(libraryRepositoryProvider);
      await repo.revokeShareToken(folder.id);
      ref.invalidate(libraryFoldersStreamProvider);

      if (!context.mounted) return;
      HapticFeedbackService.success();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sharing stopped',
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
            'Failed to stop sharing: $e',
            style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
          ),
          backgroundColor: kRedColor,
          behavior: SnackBarBehavior.floating,
        ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unsubscribed from "${folder.name}"',
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
            'Failed to unsubscribe: $e',
            style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
          ),
          backgroundColor: kRedColor,
          behavior: SnackBarBehavior.floating,
        ),
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
      builder:
          (_) => Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: ResponsiveHelper.isTablet ? 400 : double.infinity,
              ),
              child: AlertDialog(
                backgroundColor: kBlack2Color,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16.br),
                ),
                title: Text(
                  'Delete book?',
                  style: AppTypography.textSmBold.copyWith(color: kWhiteColor),
                ),
                content: Text(
                  'This removes the book. Games in it will stay saved but become unassigned.',
                  style: AppTypography.textXsRegular.copyWith(
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
                      style: AppTypography.textSmMedium.copyWith(
                        color: kRedColor,
                      ),
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

/// Motor-animated press card with bouncy scale feedback
class _PressableMotionCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _PressableMotionCard({
    required this.child,
    this.onTap,
    this.onLongPress,
  });

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
      onLongPress: () {
        HapticFeedback.mediumImpact();
        widget.onLongPress?.call();
      },
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

/// 3-dot menu button — CSS: 24x24, rotated 90deg, white 70% opacity
class _DotsMenuButton extends StatelessWidget {
  final VoidCallback onTap;

  const _DotsMenuButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.only(left: 8.w),
        child: RotatedBox(
          quarterTurns: 1,
          child: Icon(
            Icons.more_horiz_rounded,
            color: const Color(0xFFFFFFFF).withValues(alpha: 0.7),
            size: 24.sp,
          ),
        ),
      ),
    );
  }
}

// ============ OVERLAY MENUS ============

/// Shows the folder overlay menu for unshared folders: Share, Rename, Delete.
void showFolderOverlayMenu({
  required BuildContext context,
  required VoidCallback onShare,
  required VoidCallback onRename,
  required VoidCallback onDelete,
}) {
  _showOverlay(
    context: context,
    items: [
      _OverlayMenuItemData(
        Icons.ios_share_rounded,
        'Share',
        onShare,
        _MenuItemPosition.top,
      ),
      _OverlayMenuItemData(
        Icons.edit_rounded,
        'Rename Folder',
        onRename,
        _MenuItemPosition.middle,
      ),
      _OverlayMenuItemData(
        Icons.delete_outline_rounded,
        'Delete Folder',
        onDelete,
        _MenuItemPosition.bottom,
      ),
    ],
  );
}

/// Shows the overlay menu for already-shared folders: Copy Link, Stop Sharing, Rename, Delete.
void showSharedFolderOverlayMenu({
  required BuildContext context,
  required VoidCallback onCopyLink,
  required VoidCallback onStopSharing,
  required VoidCallback onRename,
  required VoidCallback onDelete,
}) {
  _showOverlay(
    context: context,
    items: [
      _OverlayMenuItemData(
        Icons.copy_rounded,
        'Copy Link',
        onCopyLink,
        _MenuItemPosition.top,
      ),
      _OverlayMenuItemData(
        Icons.link_off_rounded,
        'Stop Sharing',
        onStopSharing,
        _MenuItemPosition.middle,
      ),
      _OverlayMenuItemData(
        Icons.edit_rounded,
        'Rename Folder',
        onRename,
        _MenuItemPosition.middle,
      ),
      _OverlayMenuItemData(
        Icons.delete_outline_rounded,
        'Delete Folder',
        onDelete,
        _MenuItemPosition.bottom,
      ),
    ],
  );
}

/// Shows the overlay menu for subscribed folders: just Unsubscribe.
void showSubscribedFolderOverlayMenu({
  required BuildContext context,
  required VoidCallback onUnsubscribe,
}) {
  _showOverlay(
    context: context,
    items: [
      _OverlayMenuItemData(
        Icons.link_off_rounded,
        'Unsubscribe',
        onUnsubscribe,
        _MenuItemPosition.top,
      ),
    ],
  );
}

class _OverlayMenuItemData {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final _MenuItemPosition position;

  _OverlayMenuItemData(this.icon, this.label, this.onTap, this.position);
}

void _showOverlay({
  required BuildContext context,
  required List<_OverlayMenuItemData> items,
}) {
  final overlay = Overlay.of(context);
  final renderBox = context.findRenderObject() as RenderBox;
  final cardRect = renderBox.localToGlobal(Offset.zero) & renderBox.size;

  late OverlayEntry entry;

  entry = OverlayEntry(
    builder:
        (_) => _FolderOverlayMenu(
          anchorRect: cardRect,
          onDismiss: () => entry.remove(),
          items:
              items
                  .map(
                    (item) => _OverlayMenuItemData(item.icon, item.label, () {
                      entry.remove();
                      item.onTap();
                    }, item.position),
                  )
                  .toList(),
        ),
  );

  overlay.insert(entry);
}

class _FolderOverlayMenu extends StatefulWidget {
  final Rect anchorRect;
  final VoidCallback onDismiss;
  final List<_OverlayMenuItemData> items;

  const _FolderOverlayMenu({
    required this.anchorRect,
    required this.onDismiss,
    required this.items,
  });

  @override
  State<_FolderOverlayMenu> createState() => _FolderOverlayMenuState();
}

class _FolderOverlayMenuState extends State<_FolderOverlayMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _opacityAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnim = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _opacityAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    const menuWidth = 240.0;
    final menuHeight = widget.items.length * 40.0;

    // Position: right-aligned to the card, below the anchor
    double left = widget.anchorRect.right - menuWidth;
    double top = widget.anchorRect.bottom + 4.h;

    // Clamp to screen bounds
    if (left < 8) left = 8;
    if (left + menuWidth > screenSize.width - 8) {
      left = screenSize.width - menuWidth - 8;
    }
    if (top + menuHeight > screenSize.height - 8) {
      top = widget.anchorRect.top - menuHeight - 4.h;
    }

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Scrim
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _dismiss,
              child: FadeTransition(
                opacity: _opacityAnim,
                child: Container(color: Colors.black.withValues(alpha: 0.3)),
              ),
            ),
          ),
          // Menu
          Positioned(
            left: left,
            top: top,
            child: FadeTransition(
              opacity: _opacityAnim,
              child: ScaleTransition(
                scale: _scaleAnim,
                alignment: Alignment.topRight,
                child: Container(
                  width: menuWidth,
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(12.br),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x40000000),
                        blurRadius: 12,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final item in widget.items)
                        _OverlayMenuItem(
                          icon: item.icon,
                          label: item.label,
                          onTap: item.onTap,
                          position: item.position,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _MenuItemPosition { top, middle, bottom }

/// CSS: 240×40, bg #111111, padding 8px, gap 11px
/// Icon: 24×24 container bg #1A1A1C radius 3px, icon 15px white
/// Text: Inter 500 16px white
/// Divider: 1px solid rgba(226,226,226,0.075)
class _OverlayMenuItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final _MenuItemPosition position;

  const _OverlayMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.position,
  });

  @override
  State<_OverlayMenuItem> createState() => _OverlayMenuItemState();
}

class _OverlayMenuItemState extends State<_OverlayMenuItem> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          color: _isPressed ? const Color(0xFF1A1A1C) : const Color(0xFF111111),
          border:
              widget.position != _MenuItemPosition.top
                  ? const Border(
                    top: BorderSide(
                      color: Color(0x13E2E2E2), // rgba(226,226,226,0.075)
                    ),
                  )
                  : null,
        ),
        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
        child: Row(
          children: [
            // Icon container: 24×24, bg #1A1A1C, radius 3px
            Container(
              width: 24.sp,
              height: 24.sp,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1C),
                borderRadius: BorderRadius.circular(3.br),
              ),
              child: Center(
                child: Icon(widget.icon, color: kWhiteColor, size: 15.sp),
              ),
            ),
            SizedBox(width: 11.w),
            Expanded(
              child: Text(
                widget.label,
                style: AppTypography.textMdMedium.copyWith(color: kWhiteColor),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
