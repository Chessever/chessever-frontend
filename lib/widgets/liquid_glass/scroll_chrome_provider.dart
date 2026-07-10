import 'package:chessever2/widgets/liquid_glass/scroll_chrome_mapper.dart';
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
    double expandRange = 48.0,
  }) : _mapper = ScrollChromeMapper(
         minScale: minScale,
         collapseRange: collapseRange,
         expandRange: expandRange,
       ),
       super(ScrollChromeState(minScale: minScale));

  final ScrollChromeMapper _mapper;

  /// Apply a scroll delta from a [ScrollUpdateNotification].
  void applyScrollDelta(double delta) {
    _mapper.applyScrollDelta(delta);
    final next = state.copyWith(progress: _mapper.progress);
    if (next != state) {
      state = next;
    }
  }

  void reset() {
    _mapper.reset();
    if (state.progress != 0.0) {
      state = state.copyWith(progress: 0.0);
    }
  }
}

/// Home phone bottom-nav scroll → minimize state.
final homeScrollChromeProvider =
    StateNotifierProvider.autoDispose<ScrollChromeNotifier, ScrollChromeState>(
      (ref) => ScrollChromeNotifier(),
    );
