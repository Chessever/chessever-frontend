import 'package:chessever2/screens/chessboard/video/video_session.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';

/// The phone popup and tablet overlay use the same entries and row styling.
List<PopupMenuEntry<String>> chessBoardContextMenuItems(
  BuildContext context, {
  required EventVideoSession? videoSession,
  required bool analysisCleared,
  bool allowCopyPgn = true,
  bool allowAttachVideo = false,
}) {
  PopupMenuItem<String> action({
    required String value,
    required String label,
    required Widget icon,
    Color? color,
  }) {
    final foreground = color ?? context.colors.textPrimary;
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          SizedBox.square(
            dimension: 24,
            child: IconTheme.merge(
              data: IconThemeData(size: 24, color: foreground),
              child: icon,
            ),
          ),
          SizedBox(width: 8.w),
          Flexible(
            child: Text(label, style: TextStyle(color: foreground)),
          ),
        ],
      ),
    );
  }

  return [
    action(
      value: 'flip_board',
      label: 'Flip Board',
      // Preserve the original bottom-bar flip mark.
      icon: SvgWidget(
        SvgAsset.refresh,
        height: 24,
        width: 24,
        colorFilter: ColorFilter.mode(
          context.colors.textPrimary,
          BlendMode.srcIn,
        ),
      ),
    ),
    if (videoSession?.hasVideo == true) ...[
      action(
        value: videoSession!.visible ? 'disable_video' : 'enable_video',
        label: videoSession.visible ? 'Close Stream' : 'Show Stream',
        icon: Icon(
          videoSession.visible ? Icons.close : Icons.videocam_outlined,
        ),
      ),
    ],
    if (allowAttachVideo)
      action(
        value: 'attach_video',
        label: 'Attach analysis video',
        icon: const Icon(Icons.video_library_outlined),
      ),
    // Feed's own mark: Watch opens this game as Feed's first post.
    action(
      value: 'watch',
      label: 'Watch',
      icon: const Icon(Icons.smart_display_outlined),
    ),
    action(
      value: 'board_settings',
      label: 'Board Settings',
      icon: const Icon(Icons.settings),
    ),
    action(value: 'share', label: 'Share Game', icon: const Icon(Icons.share)),
    if (allowCopyPgn)
      action(
        value: 'copy_pgn',
        label: 'Copy PGN',
        icon: const Icon(Icons.copy),
      ),
    const PopupMenuDivider(),
    action(
      value: 'clear_analysis',
      label: analysisCleared ? 'Restore Analysis' : 'Clear Analysis',
      icon: Icon(analysisCleared ? Icons.restore : Icons.auto_delete_outlined),
      color: analysisCleared
          ? context.colors.textPrimary
          : context.colors.danger,
    ),
  ];
}
