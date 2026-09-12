import 'dart:async';
import 'package:flutter/material.dart';

/// Collapses the top toolbar in response to deliberate vertical scrolling.
/// Nested notation scrolling and automatic move following do not affect it.
class ScrollHidingToolbar extends StatefulWidget {
  const ScrollHidingToolbar({
    super.key,
    required this.toolbar,
    required this.builder,
    this.bottomBar,
    this.resetKey,
    this.autoHide = false,
  });

  final PreferredSizeWidget toolbar;
  final Widget? bottomBar;
  final bool autoHide;

  /// Restore the default chrome when the board changes layout (e.g. video off).
  final Object? resetKey;
  final Widget Function(BuildContext, PreferredSizeWidget, Widget?) builder;

  @override
  State<ScrollHidingToolbar> createState() => _ScrollHidingToolbarState();
}

class _ScrollHidingToolbarState extends State<ScrollHidingToolbar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _visibility = AnimationController(
    vsync: this,
    value: 1,
    duration: const Duration(milliseconds: 180),
  );
  double _movement = 0;
  Timer? _hideTimer;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (widget.autoHide && !_dragging) {
      _hideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) _visibility.reverse();
      });
    }
  }

  void _show() {
    _visibility.forward();
    _scheduleHide();
  }

  @override
  void didUpdateWidget(covariant ScrollHidingToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetKey != widget.resetKey) {
      _movement = 0;
      _visibility.value = 1;
    }
    if (oldWidget.resetKey != widget.resetKey ||
        oldWidget.autoHide != widget.autoHide) {
      _scheduleHide();
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is ScrollStartNotification) {
      _movement = 0;
      _dragging = notification.dragDetails != null;
      if (_dragging) _hideTimer?.cancel();
    }
    if (notification is ScrollEndNotification && _dragging) {
      _dragging = false;
      _scheduleHide();
    }
    // Android reports a downward pull at the top as overscroll, not an update.
    if (notification is OverscrollNotification &&
        notification.dragDetails != null &&
        notification.overscroll < 0) {
      _show();
    }
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      final delta = notification.scrollDelta ?? 0;
      if (notification.metrics.pixels <= notification.metrics.minScrollExtent) {
        _show();
        _movement = 0;
      } else if (delta != 0) {
        if (_movement.sign != delta.sign) _movement = 0;
        _movement += delta;
        if (_movement.abs() >= 12) {
          if (_movement > 0) {
            _visibility.reverse();
          } else {
            _show();
          }
          _movement = 0;
        }
      }
    }
    return false;
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _visibility.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: AnimatedBuilder(
          animation: _visibility,
          builder: (context, _) {
            final fraction = Curves.easeInOut.transform(_visibility.value);
            final toolbar = PreferredSize(
              preferredSize: Size.fromHeight(
                widget.toolbar.preferredSize.height * fraction,
              ),
              child: SafeArea(
                bottom: false,
                child: ClipRect(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    heightFactor: fraction,
                    child: SizedBox(
                      height: widget.toolbar.preferredSize.height,
                      child: MediaQuery.removePadding(
                        context: context,
                        removeTop: true,
                        child: widget.toolbar,
                      ),
                    ),
                  ),
                ),
              ),
            );
            return widget.builder(context, toolbar, widget.bottomBar);
          },
        ),
      );
}
