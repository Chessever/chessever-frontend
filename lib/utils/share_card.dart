import 'dart:io' as io;
import 'dart:ui' as ui;

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/share_card_palette.dart';
import 'package:chessever2/widgets/smooth_bottom_sheet.dart';
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
    builder: (_) => Positioned(
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

/// Where the preview sheet's last tapped action stood on screen. Set just
/// before that action's callback runs (the sheet closes first).
Rect? _lastSharePreviewActionOrigin;

/// The iPad share popover's anchor for a share started from the preview
/// sheet: the action the reader tapped there, else the bottom centre of the
/// screen. Never the top-left corner, where the popover points at nothing.
Rect sharePreviewOrigin() =>
    _lastSharePreviewActionOrigin ?? shareScreenBottomOrigin();

/// A 1x1 anchor at the bottom centre of the app's screen, for a share with
/// no control on screen to rise from.
Rect shareScreenBottomOrigin() {
  final view = WidgetsBinding.instance.platformDispatcher.implicitView;
  if (view == null || view.devicePixelRatio <= 0) {
    return const Rect.fromLTWH(0, 0, 1, 1);
  }
  final size = view.physicalSize / view.devicePixelRatio;
  return Rect.fromLTWH(size.width / 2, size.height - 1, 1, 1);
}

void _rememberSharePreviewOrigin(BuildContext buttonContext) {
  final box = buttonContext.findRenderObject();
  _lastSharePreviewActionOrigin =
      box is RenderBox && box.attached && box.hasSize
      ? box.localToGlobal(Offset.zero) & box.size
      : null;
}

@visibleForTesting
void debugResetSharePreviewOrigin() => _lastSharePreviewActionOrigin = null;

/// Shows the captured share image in a preview bottom sheet with up to two
/// actions: "Share Image" (always) and "Share Link" (when [onShareLink] is
/// provided). Each action dismisses the sheet then runs the native share flow.
Future<void> showShareImagePreview(
  BuildContext context, {
  required Uint8List imageBytes,
  required Future<void> Function() onShareImage,
  Future<void> Function()? onShareLink,
}) async {
  // The sheet's surface is the popups' frosted glass, toned to the surface
  // it used to be painted on; the scrim under it is a plain tint.
  await showGlassModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    constraints: BoxConstraints(
      maxWidth: ResponsiveHelper.bottomSheetMaxWidth,
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
    ),
    builder: (sheetContext) => GlassSheet(
      radius: 16.br,
      tone: sheetContext.colors.surface,
      inkSurface: true,
      child: SharePreviewSheet(
        imageBytes: imageBytes,
        onShareImage: onShareImage,
        onShareLink: onShareLink,
      ),
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
              foregroundDecoration: context.isLightTheme
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(12.br),
                      border: Border.all(color: context.colors.divider),
                    )
                  : null,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12.br),
                // Decoded at the size it is shown (never above the render's
                // own), not at the full share render's. The box is reserved
                // from the image's header, so the sheet opens at its final
                // height rather than growing once the picture decodes.
                child: _ReservedAspect(
                  aspectRatio: shareImageAspectRatio(imageBytes),
                  child: LayoutBuilder(
                    builder: (context, constraints) => Image.memory(
                      imageBytes,
                      fit: BoxFit.fitWidth,
                      width: double.infinity,
                      cacheWidth: constraints.maxWidth.isFinite
                          ? (constraints.maxWidth *
                                    MediaQuery.devicePixelRatioOf(context))
                                .ceil()
                          : null,
                    ),
                  ),
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
                  child: Builder(
                    builder: (buttonContext) => OutlinedButton.icon(
                      onPressed: () async {
                        // The iPad popover rises from this button.
                        _rememberSharePreviewOrigin(buttonContext);
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
                        backgroundColor: context.isLightTheme
                            ? context.colors.surfaceRecessed
                            : null,
                        side: context.isLightTheme
                            ? BorderSide.none
                            : BorderSide(color: context.colors.brand),
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.br),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
              ],
              Expanded(
                child: Builder(
                  builder: (buttonContext) => FilledButton.icon(
                    onPressed: () async {
                      // The iPad popover rises from this button.
                      _rememberSharePreviewOrigin(buttonContext);
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
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Width over height of an encoded share image, read from its header
/// without decoding it: a PNG's IHDR (every share render is one), else a
/// JPEG's first start-of-frame. Null when neither header is readable.
///
/// The share preview reserves this box before the image decodes, so the
/// sheet opens at its final height instead of growing under the reader's
/// eyes once the picture lands.
double? shareImageAspectRatio(Uint8List bytes) {
  int u16(int at) => (bytes[at] << 8) | bytes[at + 1];
  int u32(int at) =>
      (bytes[at] << 24) |
      (bytes[at + 1] << 16) |
      (bytes[at + 2] << 8) |
      bytes[at + 3];
  double? ratio(int width, int height) =>
      width > 0 && height > 0 ? width / height : null;

  const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (bytes.length >= 24 &&
      List.generate(8, (i) => bytes[i] == png[i]).every((same) => same)) {
    // Signature, then the IHDR chunk: length, type, width, height.
    return ratio(u32(16), u32(20));
  }
  if (bytes.length >= 4 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
    var at = 2;
    while (at + 9 < bytes.length) {
      if (bytes[at] != 0xFF) return null;
      final marker = bytes[at + 1];
      // Start of frame (baseline, progressive, ...), not DHT/JPG/DAC.
      if (marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC) {
        return ratio(u16(at + 7), u16(at + 5));
      }
      at += 2 + u16(at + 2);
    }
  }
  return null;
}

/// [child] in a box of [aspectRatio], or as it lays itself out when that is
/// unknown.
class _ReservedAspect extends StatelessWidget {
  const _ReservedAspect({required this.aspectRatio, required this.child});

  final double? aspectRatio;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ratio = aspectRatio;
    if (ratio == null) return child;
    return AspectRatio(aspectRatio: ratio, child: child);
  }
}
