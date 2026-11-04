import 'package:flutter/widgets.dart';

/// Closes anchored transient menus whose measured geometry changed on a fold.
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() => widget.onChanged();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
