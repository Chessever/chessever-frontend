import 'package:chessever2/widgets/liquid_glass/scroll_chrome_mapper.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Immutable snapshot of floating chrome size driven by scroll.
class ScrollChromeState {
  const ScrollChromeState({
    this.progress = 0.0,
    this.minScale = 0.72,
  });

  final double progress;
  final double minScale;

  double get scale =>
      ScrollChromeMapper.scaleForProgress(progress, minScale: minScale);

  bool get isMinimized => progress >= 0.5;

  ScrollChromeState copyWith({double? progress, double? minScale}) {
    return ScrollChromeState(
      progress: progress ?? this.progress,
      minScale: minScale ?? this.minScale,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScrollChromeState &&
          runtimeType == other.runtimeType &&
          progress == other.progress &&
          minScale == other.minScale;

  @override
  int get hashCode => Object.hash(progress, minScale);
}

class ScrollChromeNotifier extends StateNotifier<ScrollChromeState> {
  ScrollChromeNotifier({
    double minScale = 0.72,
    double collapseRange = 64.0,
    double expandRange = 36.0,
  }) : _mapper = ScrollChromeMapper(
         minScale: minScale,
         collapseRange: collapseRange,
         expandRange: expandRange,
       ),
       super(ScrollChromeState(minScale: minScale));

  final ScrollChromeMapper _mapper;

  /// Apply a scroll delta only (no metrics). Prefer [onScrollNotification].
  void applyScrollDelta(double delta) {
    _mapper.applyScrollDelta(delta);
    _publish();
  }

  /// Metrics-aware update: expand fully at top, shrink/expand via delta otherwise.
  void applyScroll({
    required double pixels,
    required double minScrollExtent,
    double? delta,
  }) {
    _mapper.applyScroll(
      pixels: pixels,
      minScrollExtent: minScrollExtent,
      delta: delta,
    );
    _publish();
  }

  /// Drive chrome from a [ScrollNotification] bubbling under the home shell.
  ///
  /// - Vertical only (ignore horizontal carousels / PageViews).
  /// - [ScrollUpdateNotification]: top-edge force expand + delta shrink/expand.
  /// - [ScrollEndNotification]: if settled at top, force expand (covers flings
  ///   that land on min extent without enough expand delta).
  ///
  /// Returns `false` so children keep receiving notifications.
  bool onScrollNotification(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical) return false;

    if (notification is ScrollUpdateNotification) {
      applyScroll(
        pixels: metrics.pixels,
        minScrollExtent: metrics.minScrollExtent,
        delta: notification.scrollDelta,
      );
      return false;
    }

    if (notification is ScrollEndNotification) {
      // Fling / animateTo may settle on the top without a final expand delta.
      if (ScrollChromeMapper.isAtTop(
        metrics.pixels,
        metrics.minScrollExtent,
        topEpsilon: _mapper.topEpsilon,
      )) {
        reset();
      }
      return false;
    }

    return false;
  }

  void reset() {
    _mapper.reset();
    if (state.progress != 0.0) {
      state = state.copyWith(progress: 0.0);
    }
  }

  void _publish() {
    final next = state.copyWith(progress: _mapper.progress);
    if (next != state) {
      state = next;
    }
  }
}

/// Home phone bottom-nav scroll → minimize state.
final homeScrollChromeProvider =
    StateNotifierProvider.autoDispose<ScrollChromeNotifier, ScrollChromeState>(
      (ref) => ScrollChromeNotifier(),
    );
