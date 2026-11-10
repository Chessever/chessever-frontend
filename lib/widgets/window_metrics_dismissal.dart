import 'dart:ui' show FlutterView;

import 'package:flutter/widgets.dart';

/// Closes anchored transient menus whose measured geometry changed on a fold.
///
/// [WidgetsBindingObserver.didChangeMetrics] is not a "the window resized"
/// signal. iOS re-sends the viewport on every `viewDidLayoutSubviews` and
/// safe-area pass, and neither the engine nor the framework drops a report
/// whose values are identical. Dismissing on the bare callback therefore
/// closed a menu in the same frame it opened whenever UIKit happened to lay
/// out, which read as a chip that ignored taps. Only a real change of the
/// window's size or pixel ratio moves the anchor, so only that dismisses.
class WindowMetricsDismissal extends StatefulWidget {
  const WindowMetricsDismissal({
    super.key,
    required this.onChanged,
    required this.child,
  });

  final VoidCallback onChanged;
  final Widget child;

  @override
  State<WindowMetricsDismissal> createState() => _WindowMetricsDismissalState();
}

class _WindowMetricsDismissalState extends State<WindowMetricsDismissal>
    with WidgetsBindingObserver {
  FlutterView? _view;
  Size? _lastPhysicalSize;
  double? _lastDevicePixelRatio;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final view = View.maybeOf(context);
    if (identical(view, _view)) return;
    _view = view;
    _lastPhysicalSize = view?.physicalSize;
    _lastDevicePixelRatio = view?.devicePixelRatio;
  }

  @override
  void didChangeMetrics() {
    // Metrics can arrive while the element is deactivated but still mounted.
    final view = _view;
    if (!mounted || view == null) return;
    final size = view.physicalSize;
    final ratio = view.devicePixelRatio;
    if (size == _lastPhysicalSize && ratio == _lastDevicePixelRatio) return;
    _lastPhysicalSize = size;
    _lastDevicePixelRatio = ratio;
    widget.onChanged();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
