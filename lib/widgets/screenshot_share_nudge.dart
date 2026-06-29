import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenshot_detect/flutter_screenshot_detect.dart';

/// Wraps [child] and, while it is the current visible route, watches for device
/// screenshots. When the user grabs one, it directly opens the branded share
/// preview (same flow as tapping the explicit share button) so the user can
/// post the polished ChessEver card instead of the raw screenshot.
///
/// Detection is best-effort by platform: iOS and Android 14+ fire with no
/// permission; older Android needs a storage permission we deliberately do not
/// request, so this never fires there (it never blocks or crashes).
/// [enabled] gates the whole thing — pass false when there's nothing worth
/// sharing yet (e.g. games still loading).
class ScreenshotShareNudge extends StatefulWidget {
  const ScreenshotShareNudge({
    super.key,
    required this.child,
    required this.onShare,
    this.enabled = true,
  });

  final Widget child;

  /// Runs the branded share flow (preview sheet + native share).
  final Future<void> Function() onShare;

  /// When false the listener is inert (no share opened).
  final bool enabled;

  @override
  State<ScreenshotShareNudge> createState() => _ScreenshotShareNudgeState();
}

class _ScreenshotShareNudgeState extends State<ScreenshotShareNudge> {
  final FlutterScreenshotDetect _detector = FlutterScreenshotDetect();
  StreamSubscription<FlutterScreenshotEvent>? _subscription;
  DateTime? _lastShown;
  bool _shareInFlight = false;

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
    if (!widget.enabled || !mounted || _shareInFlight) return;
    // Only fire from the screen actually on top, not screens parked in the
    // back stack (their nudge widget is still mounted and listening).
    if (ModalRoute.of(context)?.isCurrent != true) return;
    final now = DateTime.now();
    if (_lastShown != null &&
        now.difference(_lastShown!) < const Duration(seconds: 4)) {
      return;
    }
    _lastShown = now;
    unawaited(_openSharePreview());
  }

  Future<void> _openSharePreview() async {
    _shareInFlight = true;
    try {
      await widget.onShare();
    } finally {
      _shareInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
