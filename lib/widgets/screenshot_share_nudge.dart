import 'dart:async';

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenshot_detect/flutter_screenshot_detect.dart';

/// Wraps [child] and, while it is the current visible route, watches for device
/// screenshots. When the user grabs one, it surfaces a bottom sheet nudging them
/// to share ChessEver's polished card instead of the raw screenshot.
///
/// Detection is best-effort by platform: iOS and Android 14+ fire with no
/// permission; older Android needs a storage permission we deliberately do not
/// request, so the nudge simply never appears there (it never blocks or crashes).
/// [enabled] gates the whole thing — pass false when there's nothing worth
/// sharing yet (e.g. games still loading).
class ScreenshotShareNudge extends StatefulWidget {
  const ScreenshotShareNudge({
    super.key,
    required this.child,
    required this.onShare,
    this.enabled = true,
    this.title = 'Share a cleaner image',
    this.message =
        'Post the polished ChessEver card instead of a raw screenshot.',
    this.actionLabel = 'Share image',
  });

  final Widget child;

  /// Runs the branded share flow (preview sheet + native share).
  final Future<void> Function() onShare;

  /// When false the listener is inert (no nudge shown).
  final bool enabled;

  final String title;
  final String message;
  final String actionLabel;

  @override
  State<ScreenshotShareNudge> createState() => _ScreenshotShareNudgeState();
}

class _ScreenshotShareNudgeState extends State<ScreenshotShareNudge> {
  final FlutterScreenshotDetect _detector = FlutterScreenshotDetect();
  StreamSubscription<FlutterScreenshotEvent>? _subscription;
  DateTime? _lastShown;
  bool _sheetOpen = false;

  @override
  void initState() {
    super.initState();
    try {
      _subscription = _detector.onScreenshot.listen(
        (_) => _onScreenshot(),
        onError: (_) {},
      );
    } catch (_) {
      // Detection unavailable on this platform — degrade silently.
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _detector.dispose();
    super.dispose();
  }

  void _onScreenshot() {
    if (!widget.enabled || !mounted || _sheetOpen) return;
    // Only nudge from the screen actually on top, not screens parked in the
    // back stack (their nudge widget is still mounted and listening).
    if (ModalRoute.of(context)?.isCurrent != true) return;
    final now = DateTime.now();
    if (_lastShown != null &&
        now.difference(_lastShown!) < const Duration(seconds: 4)) {
      return;
    }
    _lastShown = now;
    unawaited(_showNudge());
  }

  Future<void> _showNudge() async {
    _sheetOpen = true;
    try {
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: context.colors.surface,
        isScrollControlled: false,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16.br)),
        ),
        constraints: BoxConstraints(
          maxWidth: ResponsiveHelper.bottomSheetMaxWidth,
        ),
        builder:
            (sheetContext) => _NudgeSheet(
              title: widget.title,
              message: widget.message,
              actionLabel: widget.actionLabel,
              onShare: () async {
                Navigator.of(sheetContext).pop();
                await widget.onShare();
              },
            ),
      );
    } finally {
      _sheetOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _NudgeSheet extends StatelessWidget {
  const _NudgeSheet({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onShare,
  });

  final String title;
  final String message;
  final String actionLabel;
  final Future<void> Function() onShare;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: EdgeInsets.only(top: 10.h, bottom: 14.h),
            width: 36.w,
            height: 3.h,
            decoration: BoxDecoration(
              color: context.colors.textPrimary.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2.br),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20.sp, 0, 20.sp, 8.h),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40.w,
                  height: 40.w,
                  decoration: BoxDecoration(
                    color: context.colors.brand.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10.br),
                  ),
                  child: Icon(
                    Icons.ios_share_rounded,
                    color: context.colors.brand,
                    size: 20.ic,
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTypography.textMdBold.copyWith(
                          color: context.colors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 3.h),
                      Text(
                        message,
                        style: AppTypography.textSmRegular.copyWith(
                          color: context.colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20.sp, 10.h, 20.sp, 16.h),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.colors.textPrimary,
                      side: BorderSide(color: context.colors.divider),
                      padding: EdgeInsets.symmetric(vertical: 13.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.br),
                      ),
                    ),
                    child: const Text('Not now'),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onShare,
                    icon: Icon(Icons.ios_share, size: 18.ic),
                    label: Text(actionLabel),
                    style: FilledButton.styleFrom(
                      backgroundColor: context.colors.brand,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 13.h),
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
      ),
    );
  }
}
