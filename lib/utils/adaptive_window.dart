import 'dart:math' as math;
import 'dart:ui' show DisplayFeature, DisplayFeatureType;

import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Where a foldable's hinge crosses the app's window.
///
/// Coordinates are the app's content area, the same space [MediaQuery.sizeOf]
/// describes below [AdaptiveWindowScope].
@immutable
class WindowFold {
  const WindowFold({
    required this.bounds,
    required this.axis,
    required this.reported,
  });

  /// The hinge's area. Zero-width while the device lies flat; Android reports
  /// a wider band for a physical hinge.
  final Rect bounds;

  /// [Axis.vertical]: the hinge runs top to bottom and splits the window
  /// into a leading and a trailing side (iPhone Duo opened like a book).
  /// [Axis.horizontal]: it splits the window into a top and a bottom.
  final Axis axis;

  /// True when the platform reported the fold (Android foldables today).
  ///
  /// False when it is inferred from the window alone: Flutter does not report
  /// iPhone Duo's hinge yet (flutter/flutter#192515), so its position there
  /// comes from the device's geometry, and nothing says whether the device
  /// is flat or partially folded.
  final bool reported;

  /// Clear space kept between a pane and the hinge.
  static const double clearance = 12;

  /// The widest a pane that starts at [leadingEdge] may be and still end
  /// [clearance] before a vertical hinge. Null for a horizontal hinge.
  double? leadingExtentFrom(double leadingEdge) {
    if (axis != Axis.vertical) return null;
    return bounds.left - clearance - leadingEdge;
  }

  /// Where a pane after a vertical hinge should start to sit clear of it.
  double? get trailingStart =>
      axis == Axis.vertical ? bounds.right + clearance : null;

  WindowFold _shiftedBy(double dx) => WindowFold(
    bounds: bounds.shift(Offset(dx, 0)),
    axis: axis,
    reported: reported,
  );

  @override
  bool operator ==(Object other) =>
      other is WindowFold &&
      other.bounds == bounds &&
      other.axis == axis &&
      other.reported == reported;

  @override
  int get hashCode => Object.hash(bounds, axis, reported);

  @override
  String toString() => 'WindowFold(${axis.name}, $bounds, reported: $reported)';
}

/// Finds the hinge that splits a window of [windowSize], if any.
///
/// A reported fold or hinge wins. Otherwise an iPhone window at least 600
/// points on its short side can only be iPhone Duo's inner display: every
/// other iPhone window is narrower than that on one side, and iPads render
/// at 2x where iPhones render at 3x. Its hinge bisects the long side, as the
/// inner display is two outer-display-sized halves. A Split View window
/// narrower than 600 points is one side of the hinge, so it gets none.
@visibleForTesting
WindowFold? resolveWindowFold({
  required Size windowSize,
  required List<DisplayFeature> displayFeatures,
  required double devicePixelRatio,
  required TargetPlatform platform,
}) {
  for (final feature in displayFeatures) {
    if (feature.type != DisplayFeatureType.fold &&
        feature.type != DisplayFeatureType.hinge) {
      continue;
    }
    final bounds = feature.bounds;
    final spansHeight = bounds.top <= 0 && bounds.bottom >= windowSize.height;
    final spansWidth = bounds.left <= 0 && bounds.right >= windowSize.width;
    if (spansHeight == spansWidth) continue;
    return WindowFold(
      bounds: bounds,
      axis: spansHeight ? Axis.vertical : Axis.horizontal,
      reported: true,
    );
  }

  final isDuoInnerDisplay =
      platform == TargetPlatform.iOS &&
      devicePixelRatio >= 2.5 &&
      windowSize.shortestSide >= 600;
  if (!isDuoInnerDisplay) return null;

  if (windowSize.width >= windowSize.height) {
    final x = windowSize.width / 2;
    return WindowFold(
      bounds: Rect.fromLTWH(x, 0, 0, windowSize.height),
      axis: Axis.vertical,
      reported: false,
    );
  }
  final y = windowSize.height / 2;
  return WindowFold(
    bounds: Rect.fromLTWH(0, y, windowSize.width, 0),
    axis: Axis.horizontal,
    reported: false,
  );
}

/// Lets the whole app follow its window as it changes size mid-session:
/// iPhone Duo closing and opening, iPad Split View and Stage Manager,
/// Android foldables.
///
/// Mounted once, in [MaterialApp.builder], so routes, dialogs and sheets are
/// all below it. It does three things:
///
/// * **Keeps content out of the side columns.** On iPhone Duo the status bar,
///   Dynamic Island and system controls run down one side of the screen,
///   reported as a left or right safe-area inset. This app draws its own
///   bars and was laid out for portrait phones, where those insets are zero,
///   so the scope removes them for everyone below: the content area is
///   narrowed and padded, and [MediaQuery] describes the narrower area.
///   Wherever the insets are zero, which is every phone and tablet in
///   portrait today, nothing moves.
/// * **Re-measures [ResponsiveHelper]** against that content area on every
///   size change. Its scale factors and [ResponsiveHelper.isTablet] are
///   statics read by thousands of widgets that never subscribe to
///   [MediaQuery]; before this, they kept describing the window the app
///   launched in until something else happened to rebuild them.
/// * **Rebuilds without remounting.** When the size changes, every element
///   below is marked for rebuild, so those statics are read again, while
///   every [State] (scroll positions, tabs, text fields, the board) is kept.
///
/// It also publishes the window's hinge, if any, through [AdaptiveWindow].
class AdaptiveWindowScope extends StatefulWidget {
  const AdaptiveWindowScope({super.key, required this.child});

  final Widget child;

  @override
  State<AdaptiveWindowScope> createState() => _AdaptiveWindowScopeState();
}

class _AdaptiveWindowScopeState extends State<AdaptiveWindowScope> {
  Size? _laidOutFor;

  /// Marks everything below for rebuild. Marking descendants while this
  /// element builds is allowed: the framework builds parents before their
  /// children, so they are rebuilt in this same frame, after the statics
  /// above have been updated.
  void _rebuildDescendants() {
    void mark(Element element) {
      element.markNeedsBuild();
      element.visitChildren(mark);
    }

    (context as Element).visitChildren(mark);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final left = media.padding.left;
    final right = media.padding.right;
    final windowSize = media.size;
    final contentSize = Size(
      math.max(0, windowSize.width - left - right),
      windowSize.height,
    );

    ResponsiveHelper.initFromSize(contentSize);
    final previous = _laidOutFor;
    _laidOutFor = contentSize;
    if (previous != null && previous != contentSize) _rebuildDescendants();

    final fold = resolveWindowFold(
      windowSize: windowSize,
      displayFeatures: media.displayFeatures,
      devicePixelRatio: media.devicePixelRatio,
      platform: defaultTargetPlatform,
    )?._shiftedBy(-left);

    final content = media.copyWith(
      size: contentSize,
      padding: media.padding.copyWith(left: 0, right: 0),
      viewPadding: media.viewPadding.copyWith(left: 0, right: 0),
      viewInsets: media.viewInsets.copyWith(left: 0, right: 0),
      systemGestureInsets: media.systemGestureInsets.copyWith(
        left: math.max(0, media.systemGestureInsets.left - left),
        right: math.max(0, media.systemGestureInsets.right - right),
      ),
      displayFeatures: [
        for (final feature in media.displayFeatures)
          DisplayFeature(
            bounds: feature.bounds.shift(Offset(-left, 0)),
            type: feature.type,
            state: feature.state,
          ),
      ],
    );

    // The background shows only in the inset columns, behind the system UI
    // that sits there. The widget structure stays the same whether or not
    // there are insets, so nothing below is remounted when they appear.
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Padding(
        padding: EdgeInsets.only(left: left, right: right),
        child: MediaQuery(
          data: content,
          child: AdaptiveWindow(fold: fold, child: widget.child),
        ),
      ),
    );
  }
}

/// The hinge that crosses the app's window, published by
/// [AdaptiveWindowScope].
class AdaptiveWindow extends InheritedWidget {
  const AdaptiveWindow({super.key, required this.fold, required super.child});

  final WindowFold? fold;

  /// The hinge crossing the window, or null on a single screen (and outside
  /// an [AdaptiveWindowScope], as in widget tests).
  static WindowFold? foldOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AdaptiveWindow>()?.fold;

  /// The hinge, only when it runs top to bottom.
  static WindowFold? verticalFoldOf(BuildContext context) {
    final fold = foldOf(context);
    return fold?.axis == Axis.vertical ? fold : null;
  }

  @override
  bool updateShouldNotify(AdaptiveWindow oldWidget) => fold != oldWidget.fold;
}
