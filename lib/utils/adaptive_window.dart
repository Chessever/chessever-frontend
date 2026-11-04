import 'dart:math' as math;
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:chessever2/utils/responsive_helper.dart';
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
  /// Window geometry and pixel density alone do not identify a physical hinge.
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
/// Uses platform-reported features only. Without a posture/hinge signal,
/// layouts adapt to their available space rather than inventing an occlusion.
@visibleForTesting
WindowFold? resolveWindowFold({
  required Size windowSize,
  required List<DisplayFeature> displayFeatures,
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
    final insideWindow = spansHeight
        ? bounds.left > 0 && bounds.right < windowSize.width
        : bounds.top > 0 && bounds.bottom < windowSize.height;
    if (!insideWindow) continue;
    return WindowFold(
      bounds: bounds,
      axis: spansHeight ? Axis.vertical : Axis.horizontal,
      reported: true,
    );
  }

  return null;
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
    final windowMedia = MediaQuery.of(context);
    // Keep full routes, their dialogs and keyboards together above an actual
    // tabletop obstruction. A flat, zero-height crease does not hide content.
    // Without a reported posture, the full window remains available.
    final windowFold = resolveWindowFold(
      windowSize: windowMedia.size,
      displayFeatures: windowMedia.displayFeatures,
    );
    final tabletop =
        windowFold?.axis == Axis.horizontal &&
        windowMedia.displayFeatures.any(
          (feature) =>
              feature.bounds == windowFold!.bounds &&
              (feature.bounds.height > 0 ||
                  feature.state == DisplayFeatureState.postureHalfOpened),
        );
    final viewport = Rect.fromLTWH(
      0,
      0,
      windowMedia.size.width,
      tabletop ? windowFold!.bounds.top : windowMedia.size.height,
    );
    final media = windowMedia
        .removeDisplayFeatures(viewport)
        .copyWith(size: viewport.size);
    // viewPadding survives keyboard occlusion; padding can drop to zero while
    // a keyboard is present. Keep the window's safe horizontal bounds stable.
    final left = media.viewPadding.left;
    final right = media.viewPadding.right;
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
    )?._shiftedBy(-left);

    final content = media.copyWith(
      size: contentSize,
      padding: media.padding.copyWith(left: 0, right: 0),
      viewPadding: media.viewPadding.copyWith(left: 0, right: 0),
      viewInsets: media.viewInsets.copyWith(
        left: math.max(0, media.viewInsets.left - left),
        right: math.max(0, media.viewInsets.right - right),
      ),
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
        padding: EdgeInsets.only(
          left: left,
          right: right,
          bottom: windowMedia.size.height - viewport.bottom,
        ),
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
