import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Renders [child] to PNG bytes by briefly mounting it off-screen in a real
/// [Overlay] wrapped in a [RepaintBoundary], pumping a few frames so async
/// images (network photos, country flags, bundle icons) resolve, then
/// snapshotting the boundary.
///
/// This avoids `ScreenshotController.captureFromWidget`/`captureFromLongWidget`,
/// which build a detached pipeline and do a single synchronous paint flush —
/// any image that settles mid-capture dirties a repaint boundary with no layer
/// and throws `'node._layerHandle.layer != null'`. A boundary in the live tree
/// is driven by the engine's frame loop, so every image paints before capture.
///
/// [child] must supply its own Directionality/MediaQuery/Material. The width is
/// pinned to [width]; a minimum height of `width * minHeightFactor` enforces a
/// consistent portrait aspect (default 4:5) that looks aligned in an X/Twitter
/// post — short cards gain brand-bg breathing room, long ones grow past it and
/// are captured in full (intrinsic height, no clipping). Returns null if the
/// boundary never mounts.
Future<Uint8List?> captureCardPng(
  BuildContext context, {
  required Widget child,
  required double width,
  required double pixelRatio,
  double minHeightFactor = 5 / 4,
}) async {
  final overlayState = Overlay.of(context, rootOverlay: true);
  final boundaryKey = GlobalKey();

  final entry = OverlayEntry(
    builder:
        (_) => Positioned(
          // Painted (so it owns a compositing layer to snapshot) but pushed far
          // off-screen so the user never sees the measurement pass. Positioned
          // with only left/top passes UNBOUNDED constraints, so the
          // ConstrainedBox pins the width and imposes the minimum height.
          left: 0,
          top: 0,
          child: Transform.translate(
            offset: const Offset(-100000, 0),
            child: RepaintBoundary(
              key: boundaryKey,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: width,
                  maxWidth: width,
                  minHeight: width * minHeightFactor,
                ),
                child: child,
              ),
            ),
          ),
        ),
  );

  overlayState.insert(entry);
  try {
    // Let real frames run so async images finish loading and painting.
    for (var i = 0; i < 5; i++) {
      await WidgetsBinding.instance.endOfFrame;
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await WidgetsBinding.instance.endOfFrame;

    final boundary =
        boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return null;

    final image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    entry.remove();
  }
}

/// Shows the captured share image in a preview bottom sheet with up to two
/// actions: "Share Image" (always) and "Share Link" (when [onShareLink] is
/// provided). Each action dismisses the sheet then runs the native share flow.
Future<void> showShareImagePreview(
  BuildContext context, {
  required Uint8List imageBytes,
  required Future<void> Function() onShareImage,
  Future<void> Function()? onShareLink,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.colors.surface,
    isScrollControlled: true,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16.br)),
    ),
    constraints: BoxConstraints(
      maxWidth: ResponsiveHelper.bottomSheetMaxWidth,
      maxHeight: MediaQuery.of(context).size.height * 0.85,
    ),
    builder:
        (_) => SharePreviewSheet(
          imageBytes: imageBytes,
          onShareImage: onShareImage,
          onShareLink: onShareLink,
        ),
  );
}

/// Bottom sheet that previews a rendered share image before committing to the
/// native share flow. The image is scrollable so tall cards are fully
/// previewable.
class SharePreviewSheet extends StatelessWidget {
  const SharePreviewSheet({
    super.key,
    required this.imageBytes,
    required this.onShareImage,
    required this.onShareLink,
  });

  final Uint8List imageBytes;
  final Future<void> Function() onShareImage;

  /// Null when no shareable link is available, in which case only the
  /// "Share Image" action is shown.
  final Future<void> Function()? onShareLink;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Handle bar
        Container(
          margin: EdgeInsets.only(top: 10.h, bottom: 12.h),
          width: 36.w,
          height: 3.h,
          decoration: BoxDecoration(
            color: context.colors.textPrimary.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(2.br),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.sp),
          child: Row(
            children: [
              Text(
                'Share Preview',
                style: AppTypography.textMdBold.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(
                  Icons.close,
                  color: context.colors.textPrimaryMuted,
                  size: 20.ic,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 8.h),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12.br),
              child: Image.memory(
                imageBytes,
                fit: BoxFit.fitWidth,
                width: double.infinity,
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            16.sp,
            12.h,
            16.sp,
            MediaQuery.of(context).padding.bottom + 16.h,
          ),
          child: Row(
            children: [
              if (onShareLink != null) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await onShareLink!();
                    },
                    icon: Icon(Icons.link, size: 18.ic),
                    label: const Text('Share Link'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.colors.textPrimary,
                      side: BorderSide(color: context.colors.brand),
                      padding: EdgeInsets.symmetric(vertical: 14.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.br),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
              ],
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await onShareImage();
                  },
                  icon: Icon(Icons.ios_share, size: 18.ic),
                  label: const Text('Share Image'),
                  style: FilledButton.styleFrom(
                    backgroundColor: context.colors.brand,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.br),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
