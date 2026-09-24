import 'dart:io' as io;
import 'dart:ui' as ui;

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/share_card_palette.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

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
/// are captured in full (intrinsic height, no clipping). A card built on
/// [ShareCardColumn] spends that room above its footer, so the footer sits on
/// the bottom edge. Returns null if the boundary never mounts.
///
/// The card paints with [palette], handed down through [ShareCardScope]. Left
/// null, it follows the APP theme (read from the root overlay, not from
/// [context]): a share started inside a forced-dark island such as the feed
/// still matches the theme the user picked.
Future<Uint8List?> captureCardPng(
  BuildContext context, {
  required Widget child,
  required double width,
  required double pixelRatio,
  double minHeightFactor = 5 / 4,
  ShareCardPalette? palette,
}) async {
  final overlayState = Overlay.of(context, rootOverlay: true);
  final resolvedPalette =
      palette ??
      ShareCardPalette.forBrightness(Theme.of(overlayState.context).brightness);
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
                child: ShareCardScope(palette: resolvedPalette, child: child),
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

/// The sign-off under the ChessEver mark on every share card, so each image
/// ends on the same line whichever surface produced it.
const String kShareFooterSlogan = 'Follow Chess Better';

/// Root column of a share card whose LAST child is its footer.
///
/// [captureCardPng] pads a short card to its 4:5 floor. A plain min-size
/// column leaves that slack under the footer, so the sign-off floats mid-card
/// over an empty band. This column gives the slack to the gap above the
/// footer instead, pinning it to the bottom edge. With no minimum height to
/// fill (a scroll view, or a card taller than the floor) it lays out exactly
/// like `Column(mainAxisSize: min, crossAxisAlignment: stretch)`.
class ShareCardColumn extends StatelessWidget {
  const ShareCardColumn({super.key, required this.children});

  /// The card's sections top to bottom; the last one is the footer.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.length < 2) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    // Two children under spaceBetween put all free space between them. A
    // Spacer cannot do this: the capture never bounds the height.
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children.sublist(0, children.length - 1),
        ),
        children.last,
      ],
    );
  }
}

/// Snapshots a [RepaintBoundary] that is already live in the widget tree to PNG
/// bytes. Unlike [captureCardPng] (which mounts a fresh widget off-screen), this
/// captures whatever the boundary is currently painting — used for the bracket
/// "share" where the boundary wraps the pannable/zoomable canvas viewport, so
/// the snapshot is exactly the area the user framed. Returns null if [key] isn't
/// attached to a [RenderRepaintBoundary] yet.
Future<Uint8List?> captureBoundaryPng(
  GlobalKey key, {
  double pixelRatio = 3.0,
}) async {
  // A frame boundary lets any in-flight paint settle before we snapshot.
  await WidgetsBinding.instance.endOfFrame;
  final boundary =
      key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) return null;

  final image = await boundary.toImage(pixelRatio: pixelRatio);
  try {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// Shares [files] through the native sheet, dropping [text] on Android.
///
/// X (Twitter) on Android ignores `EXTRA_STREAM` whenever `EXTRA_TEXT` is also
/// set, so an image-plus-URL share arrives in its composer as text only and the
/// card is silently lost. Every share here pairs the image with a "Share Link"
/// action (and the board overlay's link bar), so the URL stays reachable
/// without riding along on the file share. iOS and web keep the text — they
/// attach both correctly.
///
/// Use this instead of calling [Share.shareXFiles] with a `text:` directly.
Future<void> shareFilesWithText(
  List<XFile> files, {
  String? text,
  String? subject,
  Rect? sharePositionOrigin,
}) {
  final isAndroid = !kIsWeb && io.Platform.isAndroid;
  return Share.shareXFiles(
    files,
    text: isAndroid ? null : text,
    subject: subject,
    sharePositionOrigin: sharePositionOrigin,
  );
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
            child: Container(
              // A paper card on the paper sheet needs an edge to sit on.
              foregroundDecoration:
                  context.isLightTheme
                      ? BoxDecoration(
                        borderRadius: BorderRadius.circular(12.br),
                        border: Border.all(color: context.colors.divider),
                      )
                      : null,
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
                      // Paper: a recessed fill with no edge, the secondary the
                      // game share overlay uses, so the row is not an outline
                      // beside a fill. Same box either way; dark keeps its
                      // brand-cyan edge.
                      backgroundColor:
                          context.isLightTheme
                              ? context.colors.surfaceRecessed
                              : null,
                      side:
                          context.isLightTheme
                              ? BorderSide.none
                              : BorderSide(color: context.colors.brand),
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
                    // White on cyan is ~2.4:1 in either theme; the accent ink
                    // clears AA on it (~6.3:1 dark, ~8:1 light).
                    foregroundColor: context.colors.inkOnAccent,
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
