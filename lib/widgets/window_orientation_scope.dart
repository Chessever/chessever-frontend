import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Keeps rotation capability independent of the app's constrained viewport.
///
/// A portrait lock can itself keep MediaQuery narrow. Using that width to
/// decide whether to release the lock traps an unfolded display in portrait.
/// The display's shortest logical side identifies compact displays regardless
/// of their current orientation, safe areas, letterboxing or split windows.
class WindowOrientationScope extends StatefulWidget {
  const WindowOrientationScope({super.key, required this.child});

  final Widget child;

  @override
  State<WindowOrientationScope> createState() => _WindowOrientationScopeState();
}

class _WindowOrientationScopeState extends State<WindowOrientationScope>
    with WidgetsBindingObserver {
  ui.FlutterView? _view;
  List<DeviceOrientation>? _requested;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _view = View.maybeOf(context);
    _updateOrientations();
  }

  @override
  void didChangeMetrics() => _updateOrientations();

  void _updateOrientations() {
    final display = _view?.display;
    final validDisplay =
        display != null &&
        display.devicePixelRatio > 0 &&
        display.size.shortestSide > 0;
    final compactDisplay =
        validDisplay &&
        display.size.shortestSide / display.devicePixelRatio < 600;
    // With expanded (or not-yet-known) display metrics, defer to the OS.
    // Info.plist already permits landscape. Compact phones retain the
    // existing portrait policy even when physically held sideways.
    final orientations = compactDisplay
        ? const [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]
        : const <DeviceOrientation>[];
    if (listEquals(_requested, orientations)) return;
    _requested = orientations;
    unawaited(SystemChrome.setPreferredOrientations(orientations));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _view = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
