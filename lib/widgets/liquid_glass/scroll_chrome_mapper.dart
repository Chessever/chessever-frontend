/// Pure scroll → chrome size mapping for floating liquid-glass outer chrome.
///
/// Progress `0` = fully expanded (normal size). Progress `1` = fully minimized
/// (shrunk). Positive scroll deltas (content moving up / user scrolling down)
/// increase progress; negative deltas restore size.
///
/// This is the shipped unit under test — UI widgets read [scale]/[progress]
/// only; they do not reimplement the mapping.
class ScrollChromeMapper {
  ScrollChromeMapper({
    this.minScale = 0.72,
    this.collapseRange = 64.0,
    this.expandRange = 48.0,
    double initialProgress = 0.0,
  }) : _progress = initialProgress.clamp(0.0, 1.0);

  /// Scale when fully minimized (progress = 1).
  final double minScale;

  /// Scroll distance (px) of downward motion needed to go expanded → minimized.
  final double collapseRange;

  /// Scroll distance (px) of upward motion needed to go minimized → expanded.
  final double expandRange;

  double _progress;

  /// Minimize progress in \[0, 1\].
  double get progress => _progress;

  /// Linear scale from `1.0` (expanded) down to [minScale] (minimized).
  double get scale => scaleForProgress(_progress, minScale: minScale);

  /// Whether chrome is considered minimized (progress past midpoint).
  bool get isMinimized => _progress >= 0.5;

  /// Apply a raw [ScrollUpdateNotification.scrollDelta].
  ///
  /// Positive = user scrolling down → shrink. Negative = scrolling up → expand.
  double applyScrollDelta(double delta) {
    _progress = nextProgress(
      current: _progress,
      delta: delta,
      collapseRange: collapseRange,
      expandRange: expandRange,
    );
    return scale;
  }

  void reset() {
    _progress = 0.0;
  }

  void setProgress(double value) {
    _progress = value.clamp(0.0, 1.0);
  }

  /// Pure next-progress function (no instance state).
  static double nextProgress({
    required double current,
    required double delta,
    double collapseRange = 64.0,
    double expandRange = 48.0,
  }) {
    assert(collapseRange > 0);
    assert(expandRange > 0);
    if (delta > 0) {
      return (current + delta / collapseRange).clamp(0.0, 1.0);
    }
    if (delta < 0) {
      return (current + delta / expandRange).clamp(0.0, 1.0);
    }
    return current.clamp(0.0, 1.0);
  }

  /// Pure scale-from-progress function (no instance state).
  static double scaleForProgress(
    double progress, {
    double minScale = 0.72,
  }) {
    final p = progress.clamp(0.0, 1.0);
    return 1.0 - p * (1.0 - minScale);
  }
}
