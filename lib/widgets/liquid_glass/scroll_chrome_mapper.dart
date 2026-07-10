/// Pure scroll → chrome size mapping for floating liquid-glass outer chrome.
///
/// Progress `0` = fully expanded (normal size). Progress `1` = fully minimized
/// (shrunk). Positive scroll deltas (content moving up / user scrolling down)
/// increase progress; negative deltas restore size.
///
/// **Top edge rule:** when the scroll position is at (or past) the top of the
/// content, progress is forced to `0` so the bottom nav always grows back.
///
/// This is the shipped unit under test — UI widgets read [scale]/[progress]
/// only; they do not reimplement the mapping.
class ScrollChromeMapper {
  ScrollChromeMapper({
    this.minScale = 0.72,
    this.collapseRange = 64.0,
    /// Slightly shorter than collapse so scroll-up restores chrome quickly.
    this.expandRange = 36.0,
    this.topEpsilon = 1.0,
    double initialProgress = 0.0,
  }) : _progress = initialProgress.clamp(0.0, 1.0);

  /// Scale when fully minimized (progress = 1).
  final double minScale;

  /// Scroll distance (px) of downward motion needed to go expanded → minimized.
  final double collapseRange;

  /// Scroll distance (px) of upward motion needed to go minimized → expanded.
  final double expandRange;

  /// Pixels past [ScrollMetrics.minScrollExtent] still treated as “at top”.
  final double topEpsilon;

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
  /// Prefer [applyScroll] when metrics are available so the top edge expands.
  double applyScrollDelta(double delta) {
    _progress = nextProgress(
      current: _progress,
      delta: delta,
      collapseRange: collapseRange,
      expandRange: expandRange,
    );
    return scale;
  }

  /// Metrics-aware update: force expand at top, otherwise apply [delta].
  ///
  /// Call this from [ScrollUpdateNotification] / [ScrollEndNotification]
  /// handlers so arriving at (or overscrolling past) the top always restores
  /// the bottom nav to full size.
  double applyScroll({
    required double pixels,
    required double minScrollExtent,
    double? delta,
  }) {
    _progress = nextProgressFromMetrics(
      current: _progress,
      pixels: pixels,
      minScrollExtent: minScrollExtent,
      delta: delta,
      collapseRange: collapseRange,
      expandRange: expandRange,
      topEpsilon: topEpsilon,
    );
    return scale;
  }

  void reset() {
    _progress = 0.0;
  }

  void setProgress(double value) {
    _progress = value.clamp(0.0, 1.0);
  }

  /// Whether [pixels] is at or past the top of the scrollable.
  static bool isAtTop(
    double pixels,
    double minScrollExtent, {
    double topEpsilon = 1.0,
  }) {
    return pixels <= minScrollExtent + topEpsilon;
  }

  /// Pure next-progress from metrics + optional delta (no instance state).
  ///
  /// At the top edge, always returns `0` (fully expanded), ignoring [delta].
  static double nextProgressFromMetrics({
    required double current,
    required double pixels,
    required double minScrollExtent,
    double? delta,
    double collapseRange = 64.0,
    double expandRange = 36.0,
    double topEpsilon = 1.0,
  }) {
    if (isAtTop(pixels, minScrollExtent, topEpsilon: topEpsilon)) {
      return 0.0;
    }
    if (delta == null || delta == 0) {
      return current.clamp(0.0, 1.0);
    }
    return nextProgress(
      current: current,
      delta: delta,
      collapseRange: collapseRange,
      expandRange: expandRange,
    );
  }

  /// Pure next-progress function (no instance state).
  static double nextProgress({
    required double current,
    required double delta,
    double collapseRange = 64.0,
    double expandRange = 36.0,
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
