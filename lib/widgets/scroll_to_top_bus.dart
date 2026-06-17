import 'package:flutter/material.dart';

/// Fires a "scroll-to-top" intent on its descendants when the parent tab
/// switcher detects the active tab title being re-tapped.
class ScrollToTopBus extends ChangeNotifier {
  int _tick = 0;

  int get tick => _tick;

  void request() {
    _tick++;
    notifyListeners();
  }
}

class ScrollToTopScope extends InheritedNotifier<ScrollToTopBus> {
  const ScrollToTopScope({
    super.key,
    required ScrollToTopBus bus,
    required super.child,
  }) : super(notifier: bus);

  static ScrollToTopBus? maybeOf(BuildContext context) {
    final element = context
        .getElementForInheritedWidgetOfExactType<ScrollToTopScope>();
    final widget = element?.widget as ScrollToTopScope?;
    return widget?.notifier;
  }
}

mixin ScrollToTopListenerMixin<T extends StatefulWidget> on State<T> {
  ScrollToTopBus? _scrollToTopBus;

  void onScrollToTopRequested();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bus = ScrollToTopScope.maybeOf(context);
    if (!identical(bus, _scrollToTopBus)) {
      _scrollToTopBus?.removeListener(_handleScrollToTop);
      _scrollToTopBus = bus;
      _scrollToTopBus?.addListener(_handleScrollToTop);
    }
  }

  @override
  void dispose() {
    _scrollToTopBus?.removeListener(_handleScrollToTop);
    _scrollToTopBus = null;
    super.dispose();
  }

  void _handleScrollToTop() {
    if (mounted) onScrollToTopRequested();
  }
}

/// Helper to animate a [ScrollController] back to its top with consistent timing.
void animateScrollControllerToTop(
  ScrollController controller, {
  Duration duration = const Duration(milliseconds: 300),
  Curve curve = Curves.easeOutCubic,
}) {
  if (controller.hasClients) {
    controller.animateTo(0, duration: duration, curve: curve);
  }
}
