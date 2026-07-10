import 'package:flutter/widgets.dart';

/// Scroll → chrome expand/collapse for floating island headers.
///
/// [expanded] `true` at the top of a list (full segment island).
/// Scroll down past [collapseThreshold] → collapse to compact chips.
/// Scroll up past [expandThreshold] or return to top → expand again.
class ChromeScrollCollapse {
  ChromeScrollCollapse({
    this.collapseThreshold = 36.0,
    this.expandThreshold = 28.0,
    this.topEpsilon = 1.0,
  });

  final double collapseThreshold;
  final double expandThreshold;
  final double topEpsilon;

  bool expanded = true;
  double _accumulator = 0.0;

  /// Apply a vertical scroll update. Returns `true` if [expanded] flipped.
  bool applyScrollUpdate({
    required double pixels,
    required double minScrollExtent,
    required double? delta,
  }) {
    if (pixels <= minScrollExtent + topEpsilon) {
      return _setExpanded(true);
    }

    final d = delta ?? 0.0;
    if (d == 0) return false;

    // Reset accumulator when direction flips.
    if ((d > 0 && _accumulator < 0) || (d < 0 && _accumulator > 0)) {
      _accumulator = 0.0;
    }
    _accumulator += d;

    if (_accumulator > collapseThreshold && expanded) {
      return _setExpanded(false);
    }
    if (_accumulator < -expandThreshold && !expanded) {
      return _setExpanded(true);
    }
    return false;
  }

  /// Convenience for [ScrollUpdateNotification].
  bool onScrollUpdate(ScrollUpdateNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    return applyScrollUpdate(
      pixels: notification.metrics.pixels,
      minScrollExtent: notification.metrics.minScrollExtent,
      delta: notification.scrollDelta,
    );
  }

  /// Force expanded (tab change, re-tap to top, etc.).
  void reset() {
    expanded = true;
    _accumulator = 0.0;
  }

  bool _setExpanded(bool value) {
    if (expanded == value) {
      if (value) _accumulator = 0.0;
      return false;
    }
    expanded = value;
    _accumulator = 0.0;
    return true;
  }
}
