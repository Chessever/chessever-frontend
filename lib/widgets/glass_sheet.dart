import 'dart:math' as math;

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/popup_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// The page dimming under a glass sheet: the theme's scrim at the strength
/// the glass plate is solved against ([PopupGlassStyle.scrim]), so the
/// sheet's glass averages out to the tone its opaque surface used to be.
Color glassSheetBarrier(BuildContext context) =>
    context.colors.scrim.withValues(alpha: PopupGlassStyle.of(context).scrim);

/// Every bottom sheet's surface: the popups' frosted glass ([PopupGlass]),
/// rounded at the top, its lit rim and sheen along the top lip only.
///
/// The glass reaches [bleed] past the sheet's sides and bottom, so where the
/// sheet meets the screen's edges its rim is off-screen: no line runs down
/// the screen's sides or along its bottom, only the top lip catches the
/// light. The content is laid out exactly where it would be without the
/// glass.
///
/// It takes the place of the sheet's old coloured surface: [tone] is the
/// colour that surface was (the theme's surface when null), [height],
/// [constraints] and [padding] mean what they meant there.
///
/// [inkSurface] is for a sheet whose old surface was a [Material] (the
/// route's own fill, `showModalBottomSheet(backgroundColor: ...)`, or a
/// smooth_sheets `MaterialSheetDecoration`): the ink of the taps inside was
/// drawn on that Material, so a transparent [Material] on the glass keeps it
/// (and the default text style it gave). A sheet that drew its own coloured
/// box over the route's transparent Material never showed that ink, and
/// keeps it so.
///
/// Frosted or solid is one rule for every sheet: a sheet is solid (an
/// opaque plate in [tone], with the same top rim, sheen and grain, and no
/// live blur) when it is taller than [PopupGlassStyle.frostMaxScreenShare]
/// of the screen at its first layout, or when it says so ([solid]). The
/// rest are frosted, their light plate dense enough ([lightCover]) to stay
/// the brand's paper over the darkest page.
///
/// Never put it under an [Opacity]: the filter would lose its backdrop.
/// Slide it. The barrier under it should be [glassSheetBarrier], the plain
/// scrim the plate is solved over; never a blur.
class GlassSheet extends StatelessWidget {
  const GlassSheet({
    super.key,
    required this.child,
    required this.radius,
    this.tone,
    this.height,
    this.constraints,
    this.padding,
    this.inkSurface = false,
    this.cover,
    this.solid = false,
    this.lip = true,
  });

  final Widget child;

  /// The top corners' radius.
  final double radius;
  final Color? tone;
  final double? height;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry? padding;
  final bool inkSurface;

  /// See [PopupGlassStyle.of]; null is [lightCover] in light, the theme's
  /// coverage in dark.
  final double? cover;

  /// A sheet whose content animates continuously, or is mostly covered by
  /// opaque content, at any height: see [PopupGlass.solid]. A sheet taller
  /// than [PopupGlassStyle.frostMaxScreenShare] of the screen is solid
  /// without it.
  final bool solid;

  /// Whether the top lip is lit. False where the sheet cannot be dragged:
  /// a lit lip reads as a grab handle.
  final bool lip;

  /// How far the glass reaches past the sheet's sides and bottom.
  static const double bleed = 2;

  /// How much of the blurred page a frosted light sheet's plate covers:
  /// [PopupGlassStyle.sheetLightCover], whatever route the sheet is in.
  static const double lightCover = PopupGlassStyle.sheetLightCover;

  @override
  Widget build(BuildContext context) {
    const inset = EdgeInsets.fromLTRB(bleed, 0, bleed, bleed);
    final extra = padding;
    Widget sheet = _SheetGlassBleed(
      bleed: bleed,
      child: PopupGlass(
        borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
        openBottom: true,
        tone: tone,
        cover: cover ?? (context.isLightTheme ? lightCover : null),
        solid: solid,
        lip: lip,
        padding: extra == null ? inset : inset.add(extra),
        child: inkSurface
            ? Material(type: MaterialType.transparency, child: child)
            : child,
      ),
    );
    // The sheet's own box, outside the bleed: the glass hangs past it.
    var box = constraints;
    if (height != null) {
      box =
          box?.tighten(height: height) ??
          BoxConstraints.tightFor(height: height);
    }
    if (box != null) sheet = ConstrainedBox(constraints: box, child: sheet);
    return sheet;
  }
}

/// Lays its child out [bleed] wider on each side and [bleed] taller at the
/// bottom than the space it takes, hanging over the sides and the bottom.
class _SheetGlassBleed extends SingleChildRenderObjectWidget {
  const _SheetGlassBleed({required this.bleed, required super.child});

  final double bleed;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSheetGlassBleed(bleed);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSheetGlassBleed renderObject,
  ) {
    renderObject.bleed = bleed;
  }
}

class _RenderSheetGlassBleed extends RenderShiftedBox {
  _RenderSheetGlassBleed(this._bleed) : super(null);

  double _bleed;
  double get bleed => _bleed;
  set bleed(double value) {
    if (value == _bleed) return;
    _bleed = value;
    markNeedsLayout();
  }

  BoxConstraints _grown(BoxConstraints c) {
    double grow(double value, double by) => value.isFinite ? value + by : value;
    return BoxConstraints(
      minWidth: c.minWidth + 2 * _bleed,
      maxWidth: grow(c.maxWidth, 2 * _bleed),
      minHeight: c.minHeight + _bleed,
      maxHeight: grow(c.maxHeight, _bleed),
    );
  }

  Size _shrunk(BoxConstraints constraints, Size childSize) =>
      constraints.constrain(
        Size(
          math.max(0, childSize.width - 2 * _bleed),
          math.max(0, childSize.height - _bleed),
        ),
      );

  @override
  double computeMinIntrinsicWidth(double height) => math.max(
    0,
    (child?.getMinIntrinsicWidth(height + _bleed) ?? 0) - 2 * _bleed,
  );

  @override
  double computeMaxIntrinsicWidth(double height) => math.max(
    0,
    (child?.getMaxIntrinsicWidth(height + _bleed) ?? 0) - 2 * _bleed,
  );

  @override
  double computeMinIntrinsicHeight(double width) => math.max(
    0,
    (child?.getMinIntrinsicHeight(width + 2 * _bleed) ?? 0) - _bleed,
  );

  @override
  double computeMaxIntrinsicHeight(double width) => math.max(
    0,
    (child?.getMaxIntrinsicHeight(width + 2 * _bleed) ?? 0) - _bleed,
  );

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    return _shrunk(constraints, child.getDryLayout(_grown(constraints)));
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(_grown(constraints), parentUsesSize: true);
    (child.parentData! as BoxParentData).offset = Offset(-_bleed, 0);
    size = _shrunk(constraints, child.size);
  }
}
