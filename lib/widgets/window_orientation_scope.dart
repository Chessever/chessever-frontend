import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Allows the native supported orientations in every window configuration.
///
/// Folded landscape is a supported state too. A compact display cannot be
/// portrait-locked without excluding that state, including at cold start.
/// Layout adapts to the viewport; rotation remains under OS control.
class WindowOrientationScope extends StatefulWidget {
  const WindowOrientationScope({super.key, required this.child});

  final Widget child;

  @override
  State<WindowOrientationScope> createState() => _WindowOrientationScopeState();
}

class _WindowOrientationScopeState extends State<WindowOrientationScope> {
  @override
  void initState() {
    super.initState();
    // Also clears a portrait restriction left by an earlier hot-restarted VM.
    unawaited(SystemChrome.setPreferredOrientations(const []));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
