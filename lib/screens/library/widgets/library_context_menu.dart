import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/tablet_safe_menu.dart' show TabletPopupState;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show
        RenderFlex,
        RenderIndexedStack,
        RenderListBody,
        RenderViewportBase,
        RenderWrap;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show ProviderContainer, UncontrolledProviderScope;
import 'package:motor/motor.dart';

/// One action in the long-press focus menu.
@immutable
class LibraryMenuAction {
  const LibraryMenuAction({
    required this.icon,
    required this.label,
    required this.onSelected,
    this.destructive = false,
    this.enabled = true,
    this.prominent = false,
  });

  final IconData icon;
  final String label;

  /// Runs after the menu has closed, so the action is free to push routes,
  /// open sheets or show snacks against the host screen.
  final FutureOr<void> Function() onSelected;

  /// Renders in the danger colour, grouped on its own surface after every
  /// other action.
  final bool destructive;

  final bool enabled;

  /// Promotes the action into the quick row above the list: equal-width
  /// buttons with the icon over the label. The first four prominent actions
  /// get a button; any beyond that fall back into the list in order. A
  /// destructive action always stays in the destructive group.
  final bool prominent;
}

/// Lets the host that opened a menu close it without a selection, e.g. a My
/// Space tile that turns the same press into a drag once the finger moves on.
///
/// Pass one to [showLibraryContextMenu]; it is attached while that menu is on
/// screen and detached when it closes, so a stale handle is a no-op.
class LibraryContextMenuHandle {
  Route<Object?>? _route;

  bool get isOpen => _route?.isActive ?? false;

  /// Closes the menu as if the scrim were tapped: no action runs. Animates out
  /// when the menu is the top route, otherwise removes it outright.
  void close() {
    final route = _route;
    if (route == null || !route.isActive) return;
    final navigator = route.navigator;
    if (navigator == null) return;
    if (route.isCurrent) {
      navigator.pop();
    } else {
      navigator.removeRoute(route);
    }
  }
}

// ---------------------------------------------------------------- tokens

/// Springs for every moving part. All of them snap onto their target when
/// they settle, so nothing rests a hair off identity.
abstract final class _FocusMotion {
  /// Backdrop blur and dim, and the menu fade: they ride the route itself.
  static const open = CupertinoMotion.smooth(
    duration: Duration(milliseconds: 220),
    snapToEnd: true,
  );

  /// Closing is quicker than opening: the user has already decided.
  static const close = CupertinoMotion.smooth(
    duration: Duration(milliseconds: 160),
    snapToEnd: true,
  );

  /// The card rising off the page. A little give, never a wobble.
  static const lift = CupertinoMotion.bouncy(
    duration: Duration(milliseconds: 360),
    snapToEnd: true,
  );

  /// The card and menu gliding clear of a screen edge.
  static const travel = CupertinoMotion.snappy(
    duration: Duration(milliseconds: 380),
    snapToEnd: true,
  );

  /// The action panel growing out of the card edge it is attached to.
  static const pop = CupertinoMotion.snappy(
    duration: Duration(milliseconds: 300),
    snapToEnd: true,
  );

  /// Everything going home on close. Settles well inside [close]'s tail, so
  /// the route never removes a card that is still travelling.
  static const settle = CupertinoMotion.smooth(
    duration: Duration(milliseconds: 150),
    snapToEnd: true,
  );

  /// Press feedback on a button.
  static const press = CupertinoMotion.smooth(
    duration: Duration(milliseconds: 140),
    snapToEnd: true,
  );
}

/// The panel scales in from here, never from nothing.
const double _kMenuFromScale = 0.96;
const double _kMenuCloseScale = 0.97;
const double _kRowPressedScale = 0.98;
const double _kTilePressedScale = 0.97;

/// Largest lift. Big surfaces rise by a fixed number of points instead so a
/// tall card never balloons past the screen.
const double _kMaxLift = 0.035;
const double _kMaxLiftPoints = 18.0;

/// The blur fades in over one Impeller downsample band (sigma 11.3 to 22.6
/// all render at quarter resolution), so no frame of the fade blurs at full
/// resolution and the sampling grid never switches mid-fade (which shimmers).
const double _kBlurSigmaFrom = 12.0;
const double _kBlurSigma = 20.0;

/// A card taller than the room beside its menu shrinks to fit, down to this.
/// Below it the copy stays put and the menu sits over it instead.
const double _kMinFitScale = 0.35;

const double _kMinTarget = 44.0;
const double _kGap = 10.0;
const double _kGroupGap = 8.0;
const double _kPanelInset = 6.0;
const double _kRowVPad = 11.0;
const double _kRowHPad = 10.0;
const double _kIconGap = 12.0;
const double _kTileVPad = 10.0;
const double _kTileHPad = 8.0;
const double _kTileIconGap = 4.0;
const double _kScreenMargin = 16.0;
const double _kMinMenuWidth = 200.0;
const double _kMaxMenuWidth = 280.0;
const int _kMaxProminent = 4;

/// A quick-row button narrower than this demotes the last one to the list.
const double _kMinTileWidth = 64.0;

double _snapToOne(double value) => (value - 1).abs() < 0.0005 ? 1.0 : value;

// ---------------------------------------------------------------- entry

/// Long-press focus menu for any card.
///
/// The page behind blurs and dims while the pressed card is lifted, crisp,
/// at its exact on-screen rect; its actions open beside it. [previewBuilder]
/// should rebuild the card that was pressed (it inherits the card's themes
/// and provider scope). Without one, the menu anchors to [context]'s box.
///
/// The menu prefers to sit below the card, flips above it when there is no
/// room, and only moves the card when neither side fits (a card too tall for
/// that shrinks until it does). [origin] is where the press happened (or the
/// trigger's centre); on a card wider than the menu it decides which edge the
/// menu aligns to.
///
/// [onPreviewLiftChanged] gets `true` just before the copy covers the card and
/// `false` once the menu has fully closed. A host that hides its original
/// while it is true owns the hiding. For every other host the layer covers the
/// card's on-screen part with the surface the page paints behind it, so the
/// blur never shows a halo of the card around its copy (see [_SourceSurface]).
/// A copy with no fill of its own is set on that same surface, so its text
/// never floats over the veil.
///
/// It is a real route: Android back and a tap on the backdrop dismiss it, and
/// the selected action runs after the pop. It leaves a focused text field
/// focused, so a search result's menu never folds the results it came from.
Future<void> showLibraryContextMenu({
  required BuildContext context,
  required List<LibraryMenuAction> actions,
  WidgetBuilder? previewBuilder,
  VoidCallback? onPreviewTap,
  LibraryContextMenuHandle? handle,
  Offset? origin,
  ValueChanged<bool>? onPreviewLiftChanged,
}) async {
  if (actions.isEmpty) return;
  // One focus menu at a time: a second press while one is up is a no-op.
  if (_FocusMenuRoute._active?.isActive ?? false) return;

  final renderObject = context.findRenderObject();
  if (renderObject is! RenderBox ||
      !renderObject.hasSize ||
      !renderObject.attached) {
    return;
  }
  final size = renderObject.size;
  if (size.isEmpty) return;

  final navigator = Navigator.of(context, rootNavigator: true);
  final scope = _CapturedScope.of(context, navigator.context);

  // The painted rect in the coordinates the menu lays out in (the root
  // overlay), so a card inside a scaled parent still lines up. The preview
  // lays out at the card's own size and starts at the painted scale.
  final overlayObject = navigator.overlay?.context.findRenderObject();
  final overlayBox = overlayObject is RenderBox ? overlayObject : null;
  final painted = MatrixUtils.transformRect(
    renderObject.getTransformTo(overlayBox),
    Offset.zero & size,
  );
  final anchorRect = Rect.fromCenter(
    center: painted.center,
    width: size.width,
    height: size.height,
  );
  final paintedScale = painted.width / size.width;
  // Never grow from (nearly) nothing, whatever the parent was doing.
  final anchorScale = paintedScale.isFinite
      ? paintedScale.clamp(0.8, 1.2).toDouble()
      : 1.0;
  final localOrigin = origin == null || overlayBox == null
      ? origin
      : overlayBox.globalToLocal(origin);

  // Read before anything moves: how the card sits on its page. Best effort:
  // a page it cannot read is reported and the menu opens without it.
  _SourceSurface? surface;
  if (previewBuilder != null && context is Element) {
    try {
      surface = _SourceSurface.inspect(
        source: context,
        box: renderObject,
        overlay: overlayBox,
        painted: painted,
        fallback: context.colors.background,
      );
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'library_context_menu',
          context: ErrorDescription('while reading the pressed card\'s page'),
        ),
      );
    }
  }

  // The press is what summoned the menu, so the confirmation belongs to the
  // press: raised here rather than at each call site so no host can forget it.
  HapticFeedbackService.contextMenu();

  // A copy always lifts when there is one to lift, so the host can be told
  // before the first frame rather than after the layout decides.
  var lifted = false;
  void setLifted(bool value) {
    if (previewBuilder == null || lifted == value) return;
    lifted = value;
    onPreviewLiftChanged?.call(value);
  }

  // Tablets deliver a phantom tap some 300-400ms after a menu opens (see
  // tablet_safe_menu.dart). The menu that replaced showTabletSafeMenu keeps
  // that guard, and keeps flagging itself open for the rebuild deferral.
  final isTablet = ResponsiveHelper.isTablet;
  final wasPopupOpen = TabletPopupState.isAnyPopupOpen;
  final route = _FocusMenuRoute(
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    dismissGuard: isTablet ? _kTabletDismissGuard : Duration.zero,
    // A search field owns its results panel and the keyboard through its
    // focus. Taking it would fold the list the card was lifted from, drop the
    // keyboard under the veil and bring both back on close.
    requestFocus: !_textInputHasFocus(),
    builder: (routeContext, menuRoute) => scope.wrap(
      _FocusMenuLayer(
        route: menuRoute,
        anchorRect: anchorRect,
        anchorScale: anchorScale,
        origin: localOrigin,
        actions: actions,
        surface: surface,
        // A host that hides its own card needs no stand-in painted over it.
        coverSource: onPreviewLiftChanged == null,
        // Themes again inside the layer's Material, so the copy keeps the
        // card's own text style rather than the menu's.
        previewBuilder: previewBuilder == null
            ? null
            : (previewContext) =>
                  scope.themes.wrap(previewBuilder(previewContext)),
        onPreviewTap: onPreviewTap,
        onLiftEnded: () => setLifted(false),
      ),
    ),
  );

  setLifted(true);
  // Removal without an animation never reports dismissed; this still lands.
  unawaited(route.completed.whenComplete(() => setLifted(false)));
  handle?._route = route;
  _FocusMenuRoute._active = route;
  if (isTablet) TabletPopupState.markOpen();
  final LibraryMenuAction? selected;
  try {
    selected = await navigator.push(route);
  } finally {
    if (identical(handle?._route, route)) handle?._route = null;
    if (identical(_FocusMenuRoute._active, route)) {
      _FocusMenuRoute._active = null;
    }
    // Only clear the flag this menu raised, never one a popup beneath it set.
    if (isTablet && !wasPopupOpen) TabletPopupState.markClosed();
  }
  if (selected == null) return;
  await selected.onSelected();
}

/// The menu is pushed on the root navigator, so without help the preview
/// would lose the card's local themes and any nested ProviderScope override
/// (tournament games, the explorer). Both are carried across here.
class _CapturedScope {
  const _CapturedScope(this.themes, this.container);

  factory _CapturedScope.of(BuildContext from, BuildContext to) {
    final container = from
        .getInheritedWidgetOfExactType<UncontrolledProviderScope>()
        ?.container;
    final host = to
        .getInheritedWidgetOfExactType<UncontrolledProviderScope>()
        ?.container;
    return _CapturedScope(
      InheritedTheme.capture(from: from, to: to),
      container != null && !identical(container, host) ? container : null,
    );
  }

  final CapturedThemes themes;

  /// Only set when the card sits under a nested scope the root lacks.
  final ProviderContainer? container;

  Widget wrap(Widget child) {
    final themed = themes.wrap(child);
    final scoped = container;
    if (scoped == null) return themed;
    return UncontrolledProviderScope(container: scoped, child: themed);
  }
}

/// Whether the primary focus is a text field (a search bar, a filter box).
bool _textInputHasFocus() {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null || !focused.mounted) return false;
  return focused.widget is EditableText ||
      focused.findAncestorWidgetOfExactType<EditableText>() != null;
}

// ---------------------------------------------------------------- source

/// How the pressed card sits on its page, read once as the menu opens.
///
/// The blur samples everything under the veil, the original card included, so
/// a card left painted bleeds a soft halo of itself around its lifted copy.
/// When the host does not hide its card, the layer paints [slotColor] (what
/// the page paints behind the card) over [slot] (the part of the card that is
/// on screen), under the veil. When that colour cannot be told for certain (a
/// gradient, an image, a painter, something layered under the card) nothing
/// is painted: the old halo beats a block of the wrong colour.
///
/// A card with no opaque fill of its own gets a [plate] of that surface
/// behind its copy, so it lifts the way it looks in place.
@immutable
class _SourceSurface {
  const _SourceSurface({
    required this.slot,
    required this.slotColor,
    required this.plate,
  });

  /// Overlay coordinates; null when the surface behind is not known.
  final Rect? slot;
  final Color? slotColor;
  final _Plate? plate;

  /// A fill covering less of the card than this is a detail on it (an
  /// avatar, a badge), not its surface.
  static const double _kSurfaceShare = 0.6;

  static _SourceSurface inspect({
    required Element source,
    required RenderBox box,
    required RenderObject? overlay,
    required Rect painted,
    required Color fallback,
  }) {
    final behind = _behind(source, painted, overlay);
    Rect? slot;
    if (behind != null) {
      final visible = _visible(box, overlay, painted);
      if (!visible.isEmpty) slot = visible;
    }
    final direction =
        source.getInheritedWidgetOfExactType<Directionality>()?.textDirection ??
        TextDirection.ltr;
    final own = _ownSurface(source, box, direction);
    return _SourceSurface(
      slot: slot,
      slotColor: behind,
      plate: own.surfaced
          ? null
          : _Plate(
              color: behind ?? fallback,
              radius: own.radius ?? BorderRadius.circular(_panelRadius()),
              rect: own.rect,
            ),
    );
  }

  static Rect _painted(RenderBox box, RenderObject? overlay) =>
      MatrixUtils.transformRect(
        box.getTransformTo(overlay),
        Offset.zero & box.size,
      );

  static bool _sameRect(Rect a, Rect b) =>
      (a.left - b.left).abs() <= 1 &&
      (a.top - b.top).abs() <= 1 &&
      (a.right - b.right).abs() <= 1 &&
      (a.bottom - b.bottom).abs() <= 1;

  /// The opaque colour the page paints behind the card, with any translucent
  /// fills on the way composited over it. Null when it is not one flat colour.
  static Color? _behind(Element source, Rect painted, RenderObject? overlay) {
    final washes = <Color>[];
    Color? floor;
    var certain = true;
    var child = source;
    source.visitAncestorElements((ancestor) {
      final (layered, layer) = _layerUnder(ancestor, child, painted, overlay);
      if (layered) {
        // A flat backdrop layer is the floor; anything else is unreadable.
        if (layer == null) certain = false;
        floor = layer;
        return false;
      }
      child = ancestor;
      final render = ancestor.renderObject;
      // The card's own surface wrapping the pressed context is the card.
      if (render is RenderBox &&
          render.hasSize &&
          _sameRect(_painted(render, overlay), painted)) {
        return true;
      }
      final (color, unknown) = _fillUnder(ancestor.widget);
      if (unknown) {
        certain = false;
        return false;
      }
      if (color == null || color.a == 0) return true;
      if (color.a >= 0.999) {
        floor = color;
        return false;
      }
      washes.add(color);
      return true;
    });
    var result = floor;
    if (!certain || result == null) return null;
    for (final wash in washes.reversed) {
      result = Color.alphaBlend(wash, result!);
    }
    return result;
  }

  /// Whether a sibling painted before the card's branch sits under it (a
  /// backdrop layer in a [Stack]) and, when that layer is one opaque flat
  /// colour across the whole card, that colour.
  static (bool, Color?) _layerUnder(
    Element ancestor,
    Element child,
    Rect painted,
    RenderObject? overlay,
  ) {
    if (ancestor is! MultiChildRenderObjectElement) return (false, null);
    final render = ancestor.renderObject;
    // Laid out side by side, or only one child painted: nothing underneath.
    if (render is RenderFlex ||
        render is RenderWrap ||
        render is RenderListBody ||
        render is RenderIndexedStack ||
        render is RenderViewportBase) {
      return (false, null);
    }
    var below = true;
    Element? top;
    ancestor.visitChildren((sibling) {
      if (!below) return;
      if (identical(sibling, child)) {
        below = false;
        return;
      }
      final box = sibling.renderObject;
      if (box is RenderBox &&
          box.attached &&
          box.hasSize &&
          !box.size.isEmpty &&
          _painted(box, overlay).overlaps(painted)) {
        top = sibling;
      }
    });
    final layer = top;
    if (layer == null) return (false, null);
    return (true, _flatLayer(layer, painted, overlay));
  }

  /// The opaque colour [layer] fills the card's whole rect with, when that is
  /// all it paints there (`Positioned.fill(ColoredBox(...))`); otherwise null.
  static Color? _flatLayer(Element layer, Rect painted, RenderObject? overlay) {
    Element? current = layer;
    for (var depth = 0; current != null && depth < 32; depth++) {
      final element = current;
      final (color, unknown) = _fillUnder(element.widget);
      if (unknown) return null;
      if (color != null && color.a > 0) {
        final render = element.renderObject;
        if (color.a < 0.999 ||
            render is! RenderBox ||
            !render.hasSize ||
            !_paintsNothingOver(element)) {
          return null;
        }
        final rect = _painted(render, overlay);
        final covers =
            rect.left <= painted.left + 1 &&
            rect.top <= painted.top + 1 &&
            rect.right >= painted.right - 1 &&
            rect.bottom >= painted.bottom - 1;
        return covers ? color : null;
      }
      Element? only;
      var count = 0;
      element.visitChildren((child) {
        count++;
        only = child;
      });
      current = count == 1 ? only : null;
    }
    return null;
  }

  /// Whether nothing under [fill] paints over it: only sizing boxes (what a
  /// childless `Container` builds) down to an empty leaf.
  static bool _paintsNothingOver(Element fill) {
    Element? current = fill;
    for (var depth = 0; current != null && depth < 16; depth++) {
      Element? only;
      var count = 0;
      current.visitChildren((child) {
        count++;
        only = child;
      });
      if (count == 0) return true;
      final next = only;
      if (count > 1 || next == null) return false;
      final widget = next.widget;
      if (next is RenderObjectElement &&
          widget is! LimitedBox &&
          widget is! ConstrainedBox &&
          widget is! SizedBox &&
          widget is! Padding &&
          widget is! Align) {
        return false;
      }
      current = next;
    }
    return false;
  }

  /// The flat colour [widget] paints under its child, and whether what it
  /// paints there is something else (a gradient, an image, a filter).
  static (Color?, bool) _fillUnder(Widget widget) => switch (widget) {
    ColoredBox(:final color) => (color, false),
    DecoratedBox(:final decoration, :final position) =>
      position == DecorationPosition.background
          ? _decorationFill(decoration)
          : (null, false),
    DecoratedSliver(:final decoration, :final position) =>
      position == DecorationPosition.background
          ? _decorationFill(decoration)
          : (null, false),
    Ink(:final decoration?) => _decorationFill(decoration),
    PhysicalModel(:final color) => (color, false),
    PhysicalShape(:final color) => (color, false),
    CustomPaint(:final painter) => (null, painter != null),
    BackdropFilter() || ImageFiltered() || ColorFiltered() => (null, true),
    Opacity(:final opacity) => (null, opacity < 1),
    FadeTransition(:final opacity) => (null, opacity.value < 1),
    _ => (null, false),
  };

  static (Color?, bool) _decorationFill(Decoration decoration) =>
      switch (decoration) {
        BoxDecoration(gradient: null, image: null, :final color) => (
          color,
          false,
        ),
        ShapeDecoration(gradient: null, image: null, :final color) => (
          color,
          false,
        ),
        _ => (null, true),
      };

  /// The card's painted rect cut down to what its clipping ancestors (a
  /// scroll view, a pinned header's overlap) leave on screen.
  static Rect _visible(RenderBox box, RenderObject? overlay, Rect painted) {
    var visible = painted;
    RenderObject child = box;
    var parent = child.parent;
    while (parent != null) {
      final clip = parent.describeApproximatePaintClip(child);
      if (clip != null) {
        visible = visible.intersect(
          MatrixUtils.transformRect(parent.getTransformTo(overlay), clip),
        );
      }
      if (identical(parent, overlay)) break;
      child = parent;
      parent = parent.parent;
    }
    return visible;
  }

  /// Walks down the card's single-child spine for the fill it is drawn on.
  /// Opaque: the card is its own surface. Otherwise the first shape found (a
  /// border, a clip, a translucent fill) shapes the plate.
  static ({bool surfaced, Rect? rect, BorderRadius? radius}) _ownSurface(
    Element source,
    RenderBox box,
    TextDirection direction,
  ) {
    final full = Offset.zero & box.size;
    final area = full.width * full.height;
    Rect? shapeRect;
    BorderRadius? shapeRadius;
    Element? current = source;
    for (var depth = 0; current != null && depth < 64; depth++) {
      final element = current;
      final render = element.renderObject;
      if (render is RenderBox && render.hasSize && render.attached) {
        final rect = identical(render, box)
            ? full
            : MatrixUtils.transformRect(
                render.getTransformTo(box),
                Offset.zero & render.size,
              );
        final covered = rect.intersect(full);
        if (!covered.isEmpty &&
            covered.width * covered.height >= area * _kSurfaceShare) {
          final shape = _shapeOf(element.widget, render.size, direction);
          if (shape != null) {
            if (shape.opaque) {
              return (surfaced: true, rect: null, radius: null);
            }
            if (shapeRect == null) {
              shapeRect = rect;
              shapeRadius = shape.radius;
            }
          }
        }
      }
      Element? first;
      var count = 0;
      element.visitChildren((child) {
        count++;
        first ??= child;
      });
      // A stack's first child is its bottom layer, where a background sits.
      final widget = element.widget;
      final descend =
          count == 1 ||
          (count > 1 && widget is Stack && widget is! IndexedStack);
      current = descend ? first : null;
    }
    return (
      surfaced: false,
      rect: shapeRect == null || _sameRect(shapeRect, full) ? null : shapeRect,
      radius: shapeRadius,
    );
  }

  static ({bool opaque, BorderRadius radius})? _shapeOf(
    Widget widget,
    Size size,
    TextDirection direction,
  ) {
    final round = BorderRadius.circular(size.shortestSide / 2);
    bool solid(Color? color) => color != null && color.a >= 0.98;
    return switch (widget) {
      ColoredBox(:final color) => (
        opaque: solid(color),
        radius: BorderRadius.zero,
      ),
      DecoratedBox(:final decoration, :final position)
          when position == DecorationPosition.background =>
        _decorationShape(decoration, round, direction),
      PhysicalModel(:final color, :final shape, :final borderRadius) => (
        opaque: solid(color),
        radius: shape == BoxShape.circle
            ? round
            : (borderRadius ?? BorderRadius.zero),
      ),
      PhysicalShape(:final color, :final clipper) => (
        opaque: solid(color),
        radius: clipper is ShapeBorderClipper
            ? _radiusOf(clipper.shape, round, direction)
            : BorderRadius.zero,
      ),
      ClipRRect(:final borderRadius) => (
        opaque: false,
        radius: borderRadius.resolve(direction),
      ),
      ClipRSuperellipse(:final borderRadius) => (
        opaque: false,
        radius: borderRadius.resolve(direction),
      ),
      ClipOval() => (opaque: false, radius: round),
      _ => null,
    };
  }

  static ({bool opaque, BorderRadius radius})? _decorationShape(
    Decoration decoration,
    BorderRadius round,
    TextDirection direction,
  ) {
    bool solid(Color? color) => color != null && color.a >= 0.98;
    bool solidGradient(Gradient? gradient) =>
        gradient != null && gradient.colors.every(solid);
    return switch (decoration) {
      BoxDecoration() => (
        opaque:
            solid(decoration.color) ||
            decoration.image != null ||
            solidGradient(decoration.gradient),
        radius: decoration.shape == BoxShape.circle
            ? round
            : (decoration.borderRadius?.resolve(direction) ??
                  BorderRadius.zero),
      ),
      ShapeDecoration() => (
        opaque:
            solid(decoration.color) ||
            decoration.image != null ||
            solidGradient(decoration.gradient),
        radius: _radiusOf(decoration.shape, round, direction),
      ),
      _ => null,
    };
  }

  static BorderRadius _radiusOf(
    ShapeBorder shape,
    BorderRadius round,
    TextDirection direction,
  ) => switch (shape) {
    RoundedRectangleBorder(:final borderRadius) => borderRadius.resolve(
      direction,
    ),
    ContinuousRectangleBorder(:final borderRadius) => borderRadius.resolve(
      direction,
    ),
    RoundedSuperellipseBorder(:final borderRadius) => borderRadius.resolve(
      direction,
    ),
    CircleBorder() || StadiumBorder() => round,
    _ => BorderRadius.zero,
  };
}

/// The surface a fill-less copy is set on.
@immutable
class _Plate {
  const _Plate({required this.color, required this.radius, this.rect});

  final Color color;
  final BorderRadius radius;

  /// In the card's own coordinates; null fills the whole copy.
  final Rect? rect;
}

// ---------------------------------------------------------------- route

/// How long a tablet menu ignores backdrop taps after it opens: the same
/// `minOpenDuration` showTabletSafeMenu uses against phantom taps.
const Duration _kTabletDismissGuard = Duration(milliseconds: 600);

class _FocusMenuRoute extends PopupRoute<LibraryMenuAction> {
  _FocusMenuRoute({
    required this.builder,
    required this.barrierLabel,
    Duration dismissGuard = Duration.zero,
    super.requestFocus,
  }) : _dismissGuard = dismissGuard,
       _guarding = dismissGuard > Duration.zero;

  static _FocusMenuRoute? _active;

  final Widget Function(BuildContext context, _FocusMenuRoute route) builder;

  @override
  final String? barrierLabel;

  final Duration _dismissGuard;
  Timer? _guardTimer;
  bool _guarding;

  /// True while a fresh tablet menu still ignores backdrop and preview taps.
  /// Back and the action rows are never blocked.
  bool get dismissGuarded => _guarding;

  /// The layer paints its own blurred veil; the barrier only catches taps.
  /// While [dismissGuarded] it still swallows taps, it just does not close.
  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => !_guarding;

  @override
  TickerFuture didPush() {
    if (_guarding) {
      _guardTimer = Timer(_dismissGuard, () {
        _guarding = false;
        // Rebuilds the barrier so it picks up the new dismissible value.
        if (isActive) changedInternalState();
      });
    }
    return super.didPush();
  }

  @override
  void dispose() {
    _guardTimer?.cancel();
    super.dispose();
  }

  @override
  Duration get transitionDuration => const Duration(milliseconds: 220);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 160);

  /// The route's own progress is a spring, so the blur, dim and fade all move
  /// on physics and a close mid-open reverses from where it is, with its
  /// velocity.
  @override
  Simulation createSimulation({required bool forward}) {
    final controller = this.controller;
    final motion = forward ? _FocusMotion.open : _FocusMotion.close;
    return motion.createSimulation(
      start: controller?.value ?? (forward ? 0.0 : 1.0),
      end: forward ? 1.0 : 0.0,
      velocity: controller?.velocity ?? 0.0,
    );
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return builder(context, this);
  }
}

// ---------------------------------------------------------------- layer

class _FocusMenuLayer extends StatefulWidget {
  const _FocusMenuLayer({
    required this.route,
    required this.anchorRect,
    required this.anchorScale,
    required this.origin,
    required this.actions,
    required this.previewBuilder,
    required this.onPreviewTap,
    required this.onLiftEnded,
    required this.surface,
    required this.coverSource,
  });

  final _FocusMenuRoute route;
  final Rect anchorRect;
  final double anchorScale;
  final Offset? origin;
  final List<LibraryMenuAction> actions;
  final WidgetBuilder? previewBuilder;
  final VoidCallback? onPreviewTap;

  /// The copy no longer covers the card: the original may show again.
  final VoidCallback onLiftEnded;

  /// How the card sits on its page; null without a copy to lift.
  final _SourceSurface? surface;

  /// Paint the page's surface over the card while its copy is up, because
  /// the host leaves the original painted.
  final bool coverSource;

  @override
  State<_FocusMenuLayer> createState() => _FocusMenuLayerState();
}

class _FocusMenuLayerState extends State<_FocusMenuLayer> {
  bool _closing = false;
  bool _reduceMotion = false;
  Widget? _preview;
  Size? _openedAt;

  /// The card's slot stays covered until the original may show again.
  bool _covering = true;

  /// Safe area at open, keyboard included. Read once and without a
  /// dependency: a keyboard travelling under the menu would otherwise rebuild
  /// the layer every frame and retarget the card and the panel mid-flight.
  EdgeInsets? _safeArea;

  Animation<double> get _animation => widget.route.animation!;

  @override
  void initState() {
    super.initState();
    _animation.addStatusListener(_onStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The anchor rect is only true for the layout it was measured in. A
    // rotation or split-screen resize moves the card, so the menu steps aside.
    final screen = MediaQuery.sizeOf(context);
    final openedAt = _openedAt ??= screen;
    if (openedAt != screen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _dismiss());
    }
  }

  @override
  void dispose() {
    _animation.removeStatusListener(_onStatus);
    super.dispose();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.reverse) {
      // Under reduced motion the copy fades out where it is, so the original
      // has to be back underneath for the crossfade.
      final uncover = _reduceMotion;
      if (uncover) widget.onLiftEnded();
      if (mounted && (!_closing || (uncover && _covering))) {
        setState(() {
          _closing = true;
          if (uncover) _covering = false;
        });
      }
    } else if (status == AnimationStatus.dismissed) {
      // Same frame the route leaves: the card reappears exactly as its copy
      // disappears.
      widget.onLiftEnded();
    }
  }

  bool get _canAct => widget.route.isActive && widget.route.isCurrent;

  void _dismiss() {
    if (!mounted || !_canAct) return;
    widget.route.navigator?.pop();
  }

  void _select(LibraryMenuAction action) {
    if (!action.enabled || !_canAct) return;
    HapticFeedbackService.light();
    widget.route.navigator?.pop(action);
  }

  void _tapPreview() {
    // A tablet phantom tap on the lifted copy must not close it and open the
    // card behind the user's back.
    if (!_canAct || widget.route.dismissGuarded) return;
    widget.route.navigator?.pop();
    widget.onPreviewTap?.call();
  }

  static EdgeInsets _safeAreaAtOpen(BuildContext context) {
    final data =
        context.getInheritedWidgetOfExactType<MediaQuery>()?.data ??
        const MediaQueryData();
    return EdgeInsets.only(
      top: data.padding.top,
      bottom: math.max(data.padding.bottom, data.viewInsets.bottom),
    );
  }

  /// Sets a copy with no fill of its own on the surface it sat on, shaped
  /// like the card, so it lifts as one object rather than as text floating
  /// over the veil. Never clipped: a copy may paint past its box on purpose.
  Widget _onPlate(Widget copy) {
    final plate = widget.surface?.plate;
    if (plate == null) return copy;
    final fill = DecoratedBox(
      decoration: BoxDecoration(color: plate.color, borderRadius: plate.radius),
    );
    final rect = plate.rect;
    return Stack(
      clipBehavior: Clip.none,
      // The copy lays out exactly as it would without the plate.
      fit: StackFit.passthrough,
      children: [
        if (rect == null)
          Positioned.fill(child: fill)
        else
          Positioned.fromRect(rect: rect, child: fill),
        copy,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = _reduceMotion = MediaQuery.disableAnimationsOf(
      context,
    );
    final style = _FocusStyle.of(context);
    final popupLabel = MaterialLocalizations.of(context).popupMenuLabel;

    // No Material ancestor in a bare route: without one, Text in the rows and
    // in the preview hit Flutter's yellow double-underline debug style.
    return Material(
      type: MaterialType.transparency,
      child: Builder(
        builder: (context) {
          final screen = MediaQuery.sizeOf(context);
          final safeArea = _safeArea ??= _safeAreaAtOpen(context);
          // As many quick-row buttons as the window can give a readable width.
          final roomy = math.max(screen.width - 2 * _kScreenMargin.w, 1.0);
          final model = _MenuModel.from(
            widget.actions,
            maxProminent: ((roomy + _kGroupGap) / (_kMinTileWidth + _kGroupGap))
                .floor()
                .clamp(0, _kMaxProminent),
          );
          final width = _menuWidth(
            screenWidth: screen.width,
            cardWidth: widget.anchorRect.width,
            prominentCount: model.prominent.length,
          );
          final metrics = _MenuMetrics.measure(context, model, width);
          final geometry = _FocusGeometry.resolve(
            screen: screen,
            safeTop: safeArea.top,
            safeBottom: safeArea.bottom,
            anchor: widget.anchorRect,
            wantPreview: widget.previewBuilder != null,
            menuSize: Size(width, metrics.height),
            origin: widget.origin,
          );

          final preview = geometry.showPreview
              ? (_preview ??= _onPlate(widget.previewBuilder!(context)))
              : null;
          final surface = widget.surface;
          final slot = widget.coverSource ? surface?.slot : null;
          final slotColor = surface?.slotColor;

          final menu = _MenuBlock(
            model: model,
            metrics: metrics,
            style: style,
            reduceMotion: reduceMotion,
            maxHeight: geometry.menuMaxHeight,
            onSelect: _select,
          );

          return Semantics(
            scopesRoute: true,
            namesRoute: true,
            explicitChildNodes: true,
            label: popupLabel,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Under the veil, so the blur samples the page's own surface
                // where the card was instead of the card. Fixed for the life
                // of the menu, so the children after it never shift.
                if (slot != null && slotColor != null)
                  Positioned.fromRect(
                    rect: slot,
                    child: IgnorePointer(
                      child: ExcludeSemantics(
                        child: Offstage(
                          offstage: !_covering,
                          child: ColoredBox(color: slotColor),
                        ),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: _Veil(animation: _animation, color: style.veil),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: MotionBuilder<Offset>(
                    // Under reduced motion the group never travels back on
                    // close: the preview fades out where it is instead.
                    value: _closing && !reduceMotion
                        ? Offset.zero
                        : geometry.shift,
                    from: reduceMotion ? null : Offset.zero,
                    motion: _closing
                        ? _FocusMotion.settle
                        : _FocusMotion.travel,
                    active: !reduceMotion,
                    converter: MotionConverter.offset,
                    builder: (context, offset, child) =>
                        Transform.translate(offset: offset, child: child),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (preview != null)
                          Positioned(
                            left: geometry.cardRect.left,
                            top: geometry.cardRect.top,
                            width: geometry.cardRect.width,
                            child: _LiftedPreview(
                              animation: _animation,
                              closing: _closing,
                              reduceMotion: reduceMotion,
                              fromScale: widget.anchorScale,
                              lift: geometry.lift,
                              maxHeight: geometry.cardRect.height,
                              onTap: _tapPreview,
                              child: preview,
                            ),
                          ),
                        Positioned(
                          left: geometry.menuRect.left,
                          top: geometry.menuRect.top,
                          width: geometry.menuRect.width,
                          child: FadeTransition(
                            opacity: _animation,
                            child: SingleMotionBuilder(
                              value: reduceMotion
                                  ? 1.0
                                  : (_closing ? _kMenuCloseScale : 1.0),
                              from: reduceMotion ? null : _kMenuFromScale,
                              motion: _closing
                                  ? _FocusMotion.settle
                                  : _FocusMotion.pop,
                              active: !reduceMotion,
                              builder: (context, scale, child) =>
                                  Transform.scale(
                                    scale: _snapToOne(scale),
                                    alignment: geometry.menuOrigin,
                                    child: child,
                                  ),
                              child: RepaintBoundary(child: menu),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Full-screen blur plus a theme-aware dim, both growing with the route.
///
/// The fade wraps the filter and nothing else, so the engine folds its alpha
/// into the filter's own layer instead of giving the blur an empty layer to
/// sample. Sigma grows inside a single downsample band while it fades.
class _Veil extends StatelessWidget {
  const _Veil({required this.animation, required this.color});

  final Animation<double> animation;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: AnimatedBuilder(
        animation: animation,
        child: ColoredBox(color: color),
        builder: (context, child) {
          final t = animation.value.clamp(0.0, 1.0);
          final sigma = _kBlurSigmaFrom + (_kBlurSigma - _kBlurSigmaFrom) * t;
          return BackdropFilter(
            filter: ui.ImageFilter.blur(
              sigmaX: sigma,
              sigmaY: sigma,
              tileMode: TileMode.clamp,
            ),
            child: child,
          );
        },
      ),
    );
  }
}

/// The pressed card, rebuilt once and lifted in place.
class _LiftedPreview extends StatelessWidget {
  const _LiftedPreview({
    required this.animation,
    required this.closing,
    required this.reduceMotion,
    required this.fromScale,
    required this.lift,
    required this.maxHeight,
    required this.onTap,
    required this.child,
  });

  final Animation<double> animation;
  final bool closing;
  final bool reduceMotion;
  final double fromScale;
  final double lift;
  final double maxHeight;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final card = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        // Width is the card's own; height may not exceed it, so a card that
        // fills its slot (grid tiles, fixed rails) gets a bounded box to fill
        // while a list row still sizes to its content.
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: RepaintBoundary(
          // A copy of the card: its own handlers must stay inert, so the only
          // live gesture is the one this layer owns, and screen readers hear
          // the actions rather than the card twice.
          child: IgnorePointer(child: ExcludeSemantics(child: child)),
        ),
      ),
    );

    // Under reduced motion there is no lift or travel: the copy simply fades
    // back into the page as the blur clears. A card shrunk to make room for
    // its menu is layout, not motion, so it keeps that size (without easing).
    final double target;
    if (reduceMotion) {
      target = math.min(lift, 1.0);
    } else {
      target = closing ? 1.0 : lift;
    }

    // One structure for every mode, so switching to the close never remounts
    // the copy.
    return FadeTransition(
      opacity: reduceMotion && closing ? animation : kAlwaysCompleteAnimation,
      child: SingleMotionBuilder(
        value: target,
        from: reduceMotion ? null : fromScale,
        motion: closing ? _FocusMotion.settle : _FocusMotion.lift,
        active: !reduceMotion,
        builder: (context, scale, child) =>
            Transform.scale(scale: _snapToOne(scale), child: child),
        child: card,
      ),
    );
  }
}

// ---------------------------------------------------------------- style

@immutable
class _FocusStyle {
  const _FocusStyle._({
    required this.veil,
    required this.panel,
    required this.lipTop,
    required this.lipBottom,
    required this.shadow,
    required this.pressedFill,
    required this.label,
    required this.icon,
    required this.danger,
  });

  factory _FocusStyle.of(BuildContext context) {
    final colors = context.colors;
    final light = context.isLightTheme;
    final ink = colors.textPrimary;
    return _FocusStyle._(
      // Dark: deep ink so the lifted card and panel read as the only lit
      // things. Light: an ink veil deep enough to set the paper panel apart
      // without turning the page grey.
      veil: light
          ? ink.withValues(alpha: 0.25)
          : const Color(0xFF000000).withValues(alpha: 0.42),
      panel: colors.surface,
      // A lip in the panel's own light: brighter on top where light lands.
      // On paper a highlight would vanish; only the lower lip darkens.
      lipTop: light
          ? ink.withValues(alpha: 0.02)
          : const Color(0xFFFFFFFF).withValues(alpha: 0.11),
      lipBottom: light
          ? ink.withValues(alpha: 0.11)
          : const Color(0xFFFFFFFF).withValues(alpha: 0.03),
      shadow: light
          ? ink.withValues(alpha: 0.16)
          : const Color(0xFF000000).withValues(alpha: 0.5),
      pressedFill: light
          ? ink.withValues(alpha: 0.07)
          : const Color(0xFFFFFFFF).withValues(alpha: 0.08),
      label: colors.textPrimary,
      icon: colors.iconPrimary.withValues(alpha: light ? 0.82 : 0.86),
      danger: colors.danger,
    );
  }

  final Color veil;
  final Color panel;
  final Color lipTop;
  final Color lipBottom;
  final Color shadow;
  final Color pressedFill;
  final Color label;
  final Color icon;
  final Color danger;

  /// One light source above: tight, cast downward, pulled in at the sides.
  List<BoxShadow> get panelShadow => [
    BoxShadow(
      color: shadow,
      blurRadius: 14,
      offset: const Offset(0, 6),
      spreadRadius: -4,
    ),
  ];
}

// ---------------------------------------------------------------- model

@immutable
class _MenuModel {
  const _MenuModel(this.prominent, this.regular, this.destructive);

  factory _MenuModel.from(
    List<LibraryMenuAction> actions, {
    int maxProminent = _kMaxProminent,
  }) {
    final prominent = <LibraryMenuAction>[];
    final regular = <LibraryMenuAction>[];
    final destructive = <LibraryMenuAction>[];
    for (final action in actions) {
      if (action.destructive) {
        destructive.add(action);
      } else if (action.prominent && prominent.length < maxProminent) {
        prominent.add(action);
      } else {
        regular.add(action);
      }
    }
    return _MenuModel(prominent, regular, destructive);
  }

  final List<LibraryMenuAction> prominent;
  final List<LibraryMenuAction> regular;
  final List<LibraryMenuAction> destructive;
}

double _menuWidth({
  required double screenWidth,
  required double cardWidth,
  required int prominentCount,
}) {
  final screenMax = math.max(screenWidth - 2 * _kScreenMargin.w, 1.0);
  // A quick row needs room for its labels; it widens the floor, not the card.
  final floor = switch (prominentCount) {
    >= 4 => 288.0.w,
    3 => 256.0.w,
    _ => _kMinMenuWidth.w,
  };
  final maxWidth = math.min(math.max(_kMaxMenuWidth.w, floor), screenMax);
  final minWidth = math.min(floor, maxWidth);
  return cardWidth.clamp(minWidth, maxWidth).toDouble();
}

double _rowIconSize() => 18.ic;
double _tileIconSize() => 20.ic;
double _panelRadius() => 14.br;
double _rowRadius() => math.max(_panelRadius() - _kPanelInset, 4.0);
double _minRowHeight() => math.max(_kMinTarget, _kMinTarget.h);

/// Every height the layout needs before anything is laid out, measured with
/// the same style, scaler and width the rows paint with (a point narrower, so
/// a rounding difference can only ever leave spare room, never clip a line).
@immutable
class _MenuMetrics {
  const _MenuMetrics({
    required this.width,
    required this.tileHeight,
    required this.regularHeights,
    required this.destructiveHeights,
  });

  factory _MenuMetrics.measure(
    BuildContext context,
    _MenuModel model,
    double width,
  ) {
    final base = DefaultTextStyle.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final heightBehavior =
        base.textHeightBehavior ?? DefaultTextHeightBehavior.maybeOf(context);
    final locale = Localizations.maybeLocaleOf(context);

    double textHeight(String text, TextStyle style, double maxWidth) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: base.style.merge(style)),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 2,
        ellipsis: '…',
        textWidthBasis: base.textWidthBasis,
        textHeightBehavior: heightBehavior,
        locale: locale,
      )..layout(maxWidth: math.max(maxWidth - 1, 1));
      final height = painter.height;
      painter.dispose();
      return height;
    }

    final rowTextWidth =
        width -
        2 * _kPanelInset -
        2 * _kRowHPad.w -
        _rowIconSize() -
        _kIconGap.w;
    double rowHeight(LibraryMenuAction action) {
      final text = textHeight(
        action.label,
        AppTypography.textSmMedium,
        rowTextWidth,
      );
      return math.max(
        _minRowHeight(),
        math.max(text, _rowIconSize()) + 2 * _kRowVPad,
      );
    }

    var tileHeight = 0.0;
    final count = model.prominent.length;
    if (count > 0) {
      final tileWidth = (width - (count - 1) * _kGroupGap) / count;
      var text = 0.0;
      for (final action in model.prominent) {
        text = math.max(
          text,
          textHeight(
            action.label,
            AppTypography.textXsMedium,
            tileWidth - 2 * _kTileHPad,
          ),
        );
      }
      tileHeight = math.max(
        _minRowHeight(),
        2 * _kTileVPad + _tileIconSize() + _kTileIconGap + text,
      );
    }

    return _MenuMetrics(
      width: width,
      tileHeight: tileHeight,
      regularHeights: [for (final a in model.regular) rowHeight(a)],
      destructiveHeights: [for (final a in model.destructive) rowHeight(a)],
    );
  }

  final double width;
  final double tileHeight;
  final List<double> regularHeights;
  final List<double> destructiveHeights;

  static double _panel(List<double> rows) =>
      rows.isEmpty ? 0 : 2 * _kPanelInset + rows.fold(0.0, (a, b) => a + b);

  double get height {
    final groups = [
      if (tileHeight > 0) tileHeight,
      if (regularHeights.isNotEmpty) _panel(regularHeights),
      if (destructiveHeights.isNotEmpty) _panel(destructiveHeights),
    ];
    if (groups.isEmpty) return 0;
    return groups.fold(0.0, (a, b) => a + b) + (groups.length - 1) * _kGroupGap;
  }
}

// ---------------------------------------------------------------- geometry

/// Where the card and the menu go. Coordinates are in the group's frame: the
/// card rests on its anchor and the whole group then travels by [shift].
@immutable
class _FocusGeometry {
  const _FocusGeometry({
    required this.showPreview,
    required this.cardRect,
    required this.shift,
    required this.menuRect,
    required this.menuOrigin,
    required this.menuMaxHeight,
    required this.lift,
  });

  final bool showPreview;
  final Rect cardRect;
  final Offset shift;
  final Rect menuRect;
  final Alignment menuOrigin;
  final double? menuMaxHeight;
  final double lift;

  static double liftFor(Size size) {
    final side = math.max(size.width, size.height);
    if (side <= 0) return 1.0;
    return 1 + math.min(_kMaxLift, _kMaxLiftPoints / side);
  }

  /// Delta that brings the span [start, end] inside [lo, hi]. A span longer
  /// than the range is aligned to its start.
  static double nudge(double start, double end, double lo, double hi) {
    if (end - start > hi - lo) return lo - start;
    if (start < lo) return lo - start;
    if (end > hi) return hi - end;
    return 0.0;
  }

  static _FocusGeometry resolve({
    required Size screen,
    required double safeTop,
    required double safeBottom,
    required Rect anchor,
    required bool wantPreview,
    required Size menuSize,
    required Offset? origin,
  }) {
    final edge = math.max(8.0, 12.h);
    final margin = _kScreenMargin.w;
    final top = safeTop + edge;
    final bottom = math.max(top + 1, screen.height - safeBottom - edge);
    final available = bottom - top;
    final menuWidth = menuSize.width;
    final menuHeight = menuSize.height;
    final lift = liftFor(anchor.size);

    // Which edge of the card the menu hangs from. A card narrower than the
    // menu opens toward the roomier half of the screen; a wider one follows
    // the press, leading edge by default.
    double menuLeft(Rect card) {
      final bool alignRight;
      if (card.width < menuWidth) {
        alignRight = card.center.dx > screen.width / 2;
      } else {
        alignRight = origin != null && origin.dx > card.center.dx;
      }
      final raw = alignRight ? card.right - menuWidth : card.left;
      return raw
          .clamp(margin, math.max(margin, screen.width - margin - menuWidth))
          .toDouble();
    }

    double originX(Rect card, double left) {
      final alignRight =
          (left + menuWidth - card.right).abs() < (left - card.left).abs();
      return alignRight ? 1.0 : -1.0;
    }

    if (wantPreview) {
      // A card too tall to sit beside its menu shrinks until it does.
      final fitScale = (available - _kGap - menuHeight) / anchor.height;
      if (fitScale >= _kMinFitScale) {
        final scale = math.min(lift, fitScale);
        final growX = anchor.width * (scale - 1) / 2;
        final growY = anchor.height * (scale - 1) / 2;
        final visual = Rect.fromLTRB(
          anchor.left - growX,
          anchor.top - growY,
          anchor.right + growX,
          anchor.bottom + growY,
        );
        // A tile half scrolled out of a rail comes fully into view.
        final xInset = visual.width <= screen.width - margin ? margin / 2 : 0.0;
        final dx = visual.width <= screen.width
            ? nudge(visual.left, visual.right, xInset, screen.width - xInset)
            : 0.0;
        final dyBelow = nudge(
          visual.top,
          visual.bottom + _kGap + menuHeight,
          top,
          bottom,
        );
        final dyAbove = nudge(
          visual.top - _kGap - menuHeight,
          visual.bottom,
          top,
          bottom,
        );
        // Below if it fits, above if that fits, otherwise whichever side
        // needs the card to move least.
        final below =
            dyBelow == 0 || (dyAbove != 0 && dyBelow.abs() <= dyAbove.abs());
        final dy = below ? dyBelow : dyAbove;
        final menuTop = below
            ? visual.bottom + _kGap
            : visual.top - _kGap - menuHeight;
        final shiftedCard = anchor.shift(Offset(dx, 0));
        final left = menuLeft(shiftedCard);
        return _FocusGeometry(
          showPreview: true,
          cardRect: anchor,
          shift: Offset(dx, dy),
          menuRect: Rect.fromLTWH(left - dx, menuTop, menuWidth, menuHeight),
          menuOrigin: Alignment(originX(shiftedCard, left), below ? -1 : 1),
          menuMaxHeight: null,
          lift: scale,
        );
      }

      // Nothing sensible fits side by side: the copy stays where the card is
      // and the menu sits over its visible part, scrolling if it must.
      final height = math.min(menuHeight, available);
      final visibleTop = math.min(math.max(anchor.top, top), bottom);
      final visibleBottom = math.max(
        visibleTop,
        math.min(anchor.bottom, bottom),
      );
      final menuTop = ((visibleTop + visibleBottom) / 2 - height / 2)
          .clamp(top, bottom - height)
          .toDouble();
      final left = menuLeft(anchor);
      return _FocusGeometry(
        showPreview: true,
        cardRect: anchor,
        shift: Offset.zero,
        menuRect: Rect.fromLTWH(left, menuTop, menuWidth, height),
        menuOrigin: Alignment(originX(anchor, left), 0),
        menuMaxHeight: menuHeight > available ? available : null,
        lift: 1.0,
      );
    }

    // No preview: the menu anchors to the box itself.
    final left = menuLeft(anchor);
    final x = originX(anchor, left);
    if (menuHeight > available) {
      return _FocusGeometry(
        showPreview: false,
        cardRect: anchor,
        shift: Offset.zero,
        menuRect: Rect.fromLTWH(left, top, menuWidth, available),
        menuOrigin: Alignment(x, -1),
        menuMaxHeight: available,
        lift: lift,
      );
    }
    final double menuTop;
    final double y;
    if (anchor.bottom + _kGap >= top &&
        anchor.bottom + _kGap + menuHeight <= bottom) {
      menuTop = anchor.bottom + _kGap;
      y = -1;
    } else if (anchor.top - _kGap <= bottom &&
        anchor.top - _kGap - menuHeight >= top) {
      menuTop = anchor.top - _kGap - menuHeight;
      y = 1;
    } else {
      // A box taller than the room around it: centre on its visible part.
      final visibleTop = math.min(math.max(anchor.top, top), bottom);
      final visibleBottom = math.max(
        visibleTop,
        math.min(anchor.bottom, bottom),
      );
      menuTop = ((visibleTop + visibleBottom) / 2 - menuHeight / 2)
          .clamp(top, bottom - menuHeight)
          .toDouble();
      y = 0;
    }
    return _FocusGeometry(
      showPreview: false,
      cardRect: anchor,
      shift: Offset.zero,
      menuRect: Rect.fromLTWH(left, menuTop, menuWidth, menuHeight),
      menuOrigin: Alignment(x, y),
      menuMaxHeight: null,
      lift: lift,
    );
  }
}

// ---------------------------------------------------------------- menu

class _MenuBlock extends StatelessWidget {
  const _MenuBlock({
    required this.model,
    required this.metrics,
    required this.style,
    required this.reduceMotion,
    required this.maxHeight,
    required this.onSelect,
  });

  final _MenuModel model;
  final _MenuMetrics metrics;
  final _FocusStyle style;
  final bool reduceMotion;
  final double? maxHeight;
  final ValueChanged<LibraryMenuAction> onSelect;

  @override
  Widget build(BuildContext context) {
    final groups = <Widget>[];

    if (model.prominent.isNotEmpty) {
      final tiles = <Widget>[];
      for (var i = 0; i < model.prominent.length; i++) {
        if (i > 0) tiles.add(const SizedBox(width: _kGroupGap));
        tiles.add(
          Expanded(
            child: _ActionTile(
              action: model.prominent[i],
              height: metrics.tileHeight,
              style: style,
              reduceMotion: reduceMotion,
              onSelect: onSelect,
            ),
          ),
        );
      }
      groups.add(Row(children: tiles));
    }

    Widget panel(List<LibraryMenuAction> actions, List<double> heights) {
      return _Surface(
        style: style,
        radius: _panelRadius(),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: _kPanelInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < actions.length; i++)
                _ActionRow(
                  action: actions[i],
                  height: heights[i],
                  style: style,
                  reduceMotion: reduceMotion,
                  onSelect: onSelect,
                ),
            ],
          ),
        ),
      );
    }

    if (model.regular.isNotEmpty) {
      groups.add(panel(model.regular, metrics.regularHeights));
    }
    // Destructive actions sit on their own surface after a gap, so they never
    // read as the next item in the list.
    if (model.destructive.isNotEmpty) {
      groups.add(panel(model.destructive, metrics.destructiveHeights));
    }

    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < groups.length; i++) ...[
          if (i > 0) const SizedBox(height: _kGroupGap),
          groups[i],
        ],
      ],
    );

    final limit = maxHeight;
    if (limit == null) return column;
    // Only when the actions outgrow the screen: scroll rather than overflow.
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: limit),
      child: SingleChildScrollView(child: column),
    );
  }
}

/// Opaque panel material: a tonal step above the veil, a lip in its own light
/// and one tight shadow cast from above.
class _Surface extends StatelessWidget {
  const _Surface({
    required this.style,
    required this.radius,
    required this.child,
  });

  final _FocusStyle style;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: style.panel,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: style.panelShadow,
      ),
      child: CustomPaint(
        foregroundPainter: _LipPainter(
          radius: radius,
          top: style.lipTop,
          bottom: style.lipBottom,
        ),
        child: child,
      ),
    );
  }
}

class _LipPainter extends CustomPainter {
  const _LipPainter({
    required this.radius,
    required this.top,
    required this.bottom,
  });

  final double radius;
  final Color top;
  final Color bottom;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [top, bottom],
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.deflate(0.5),
        Radius.circular(math.max(radius - 0.5, 0)),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_LipPainter oldDelegate) =>
      oldDelegate.radius != radius ||
      oldDelegate.top != top ||
      oldDelegate.bottom != bottom;
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.action,
    required this.height,
    required this.style,
    required this.reduceMotion,
    required this.onSelect,
  });

  final LibraryMenuAction action;
  final double height;
  final _FocusStyle style;
  final bool reduceMotion;
  final ValueChanged<LibraryMenuAction> onSelect;

  @override
  Widget build(BuildContext context) {
    final labelColor = action.destructive ? style.danger : style.label;
    final iconColor = action.destructive ? style.danger : style.icon;
    final dim = action.enabled ? 1.0 : 0.35;

    return Semantics(
      button: true,
      enabled: action.enabled,
      label: action.label,
      onTap: action.enabled ? () => onSelect(action) : null,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _kPanelInset),
        child: _Pressable(
          enabled: action.enabled,
          onTap: () => onSelect(action),
          pressedScale: _kRowPressedScale,
          fill: style.pressedFill,
          radius: _rowRadius(),
          foregroundFill: false,
          reduceMotion: reduceMotion,
          child: Container(
            height: height,
            padding: EdgeInsets.symmetric(horizontal: _kRowHPad.w),
            child: Row(
              children: [
                // Bare glyph on the surface: no tile behind it. Every Material
                // glyph renders in a square box, so all labels share one axis.
                Icon(
                  action.icon,
                  size: _rowIconSize(),
                  color: iconColor.withValues(alpha: iconColor.a * dim),
                ),
                SizedBox(width: _kIconGap.w),
                Expanded(
                  child: Text(
                    action.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.textSmMedium.copyWith(
                      color: labelColor.withValues(alpha: labelColor.a * dim),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.action,
    required this.height,
    required this.style,
    required this.reduceMotion,
    required this.onSelect,
  });

  final LibraryMenuAction action;
  final double height;
  final _FocusStyle style;
  final bool reduceMotion;
  final ValueChanged<LibraryMenuAction> onSelect;

  @override
  Widget build(BuildContext context) {
    final dim = action.enabled ? 1.0 : 0.35;
    final radius = _panelRadius();

    return Semantics(
      button: true,
      enabled: action.enabled,
      label: action.label,
      onTap: action.enabled ? () => onSelect(action) : null,
      excludeSemantics: true,
      child: _Pressable(
        enabled: action.enabled,
        onTap: () => onSelect(action),
        pressedScale: _kTilePressedScale,
        fill: style.pressedFill,
        radius: radius,
        foregroundFill: true,
        reduceMotion: reduceMotion,
        child: _Surface(
          style: style,
          radius: radius,
          child: SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: _kTileHPad),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    action.icon,
                    size: _tileIconSize(),
                    color: style.icon.withValues(alpha: style.icon.a * dim),
                  ),
                  const SizedBox(height: _kTileIconGap),
                  Text(
                    action.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppTypography.textXsMedium.copyWith(
                      color: style.label.withValues(alpha: style.label.a * dim),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Press feedback for a menu button: a tonal fill and a slight give, both on
/// one spring so a quick tap still reads and a release is never abrupt.
class _Pressable extends StatefulWidget {
  const _Pressable({
    required this.enabled,
    required this.onTap,
    required this.pressedScale,
    required this.fill,
    required this.radius,
    required this.foregroundFill,
    required this.reduceMotion,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onTap;
  final double pressedScale;
  final Color fill;
  final double radius;

  /// Paint the fill over the child (a button that is its own surface) rather
  /// than under it (a row on a shared panel).
  final bool foregroundFill;
  final bool reduceMotion;
  final Widget child;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  void _set(bool value) {
    if (_down == value || !mounted) return;
    setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      onTap: enabled ? widget.onTap : null,
      child: SingleMotionBuilder(
        value: _down ? 1.0 : 0.0,
        motion: _FocusMotion.press,
        active: !widget.reduceMotion,
        child: widget.child,
        builder: (context, t, child) {
          final k = t.clamp(0.0, 1.0);
          final fill = widget.fill.withValues(alpha: widget.fill.a * k);
          return Transform.scale(
            scale: widget.reduceMotion
                ? 1.0
                : _snapToOne(1 - (1 - widget.pressedScale) * k),
            child: DecoratedBox(
              position: widget.foregroundFill
                  ? DecorationPosition.foreground
                  : DecorationPosition.background,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(widget.radius),
              ),
              child: child,
            ),
          );
        },
      ),
    );
  }
}
