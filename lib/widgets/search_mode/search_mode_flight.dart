part of 'search_mode.dart';

/// The search button's press: its disc is drawn at `1 - this * press`
/// (`InkFab`), so a drawn size says how far it was pressed.
const double _kButtonPressDepth = 0.1;

/// The flying magnifier is laid out at this size and scaled at paint time.
const double _kGlyphBox = 32;

/// Where the glass is at one moment of the flight, in global coordinates.
@immutable
class _FlightPose {
  const _FlightPose({
    required this.shape,
    required this.look,
    required this.frame,
    required this.glyphCenter,
    required this.glyphSize,
    required this.glyphColor,
  });

  final RRect shape;
  final GlassLook look;

  /// The field's frame while the field is in the tree: the field draws the
  /// glass inside it (under its text), the layer over the page everywhere
  /// else. Null once the field is gone (the frame a close lands): the layer
  /// draws all of it.
  final Rect? frame;

  final Offset glyphCenter;
  final double glyphSize;
  final Color glyphColor;
}

/// The glass in flight between the search button and the search field.
///
/// Both ends are read live, at paint time, from the boxes they are drawn
/// in: the button's disc inside its press (so the glass leaves at the size
/// the finger left it, and follows the button up and down with the
/// keyboard), and the field's frame (so it lands exactly on it, wherever
/// the header has folded to). Everything in between is the timeline t:
/// the shape, the corners (circle to field), the material (glass to the
/// field's solid fill and its edge, as the field draws them that frame: the
/// glass's rim, shadow and blur fading, the field's lift and edge arriving),
/// and the magnifier (button glyph to field glyph: place, size and tint).
class _Flight extends ChangeNotifier {
  _Flight(this._host);

  final _SearchModeHostState _host;

  /// The glass is flying. While it is, the button's disc, the field's fill
  /// and the field's magnifier are drawn by the flight instead.
  bool get active => _active.value;
  final ValueNotifier<bool> _active = ValueNotifier<bool>(false);

  double _t = 0;
  _FlightPose? _pose;
  bool _poseStale = true;

  Rect? _lastButton;
  Rect? _lastGlyph;
  Rect? _lastFrame;
  Rect? _lastIcon;
  double _lastScale = 1;

  GlassStyle _style = const GlassStyle(
    plate: Color(0x00000000),
    rimTop: Color(0x00000000),
    rimBottom: Color(0x00000000),
    shadow: <BoxShadow>[],
    ink: Color(0xFFFFFFFF),
  );

  /// The field's fill and edge: read live from the field each frame it is
  /// in the tree ([_RenderFieldFill]), so the glass lands on the field's
  /// colours as its focus lift leaves them that frame; the theme's resting
  /// field until then.
  Color _fieldFill = const Color(0xFF000000);
  Color _fieldEdge = const Color(0xFF000000);
  double _fieldRadius = 12;
  Color _brand = const Color(0xFF000000);
  Color _iconSecondary = const Color(0xFF000000);
  Color _buttonInk = const Color(0xFFFFFFFF);
  Color _fieldIcon = const Color(0xFF000000);

  int debugPaintCount = 0;
  Rect? debugLastRect;
  GlassLook? debugLastLook;

  /// The colours and corner of this page's theme.
  void configure(BuildContext context) {
    final colors = context.colors;
    _style = GlassStyle.of(context);
    if (!_active.value) {
      _fieldFill = HomeSearchFieldSurface.fillOf(context, 0);
      _fieldEdge = HomeSearchFieldSurface.edgeOf(context, 0);
    }
    _fieldRadius = SearchHeaderMetrics.fieldRadius;
    _brand = colors.brand;
    _iconSecondary = colors.iconSecondary;
    // The glyph's ink as the button draws it, the same as the buttons
    // beside it.
    _buttonInk = _style.ink;
  }

  /// Takes off (or keeps flying, turned round). [fieldIcon] is the field
  /// magnifier's tint at the field's end.
  void start({required Color fieldIcon}) {
    if (_active.value) return;
    _fieldIcon = fieldIcon;
    _lastButton = _lastGlyph = _lastFrame = _lastIcon = null;
    _lastScale = 1;
    _poseStale = true;
    _active.value = true;
    notifyListeners();
  }

  void tick(double t) {
    _t = t;
    _poseStale = true;
    if (_active.value) notifyListeners();
  }

  void end() {
    if (!_active.value) return;
    _active.value = false;
    _pose = null;
    notifyListeners();
  }

  /// Where the glass is this frame; null when it is not flying. Read at
  /// paint time, when every box has been laid out for this frame.
  _FlightPose? pose() {
    if (!_active.value) return null;
    if (_poseStale) {
      _poseStale = false;
      _pose = _resolve();
    }
    return _pose;
  }

  static Rect? _globalRect(RenderBox? box) => box == null
      ? null
      : MatrixUtils.transformRect(
          box.getTransformTo(null),
          Offset.zero & box.size,
        );

  _FlightPose? _resolve() {
    final keys = _host._flightButton;
    final buttonBox = _SearchModeHostState._box(keys?.disc);
    final button = _globalRect(buttonBox) ?? _lastButton;
    final glyph =
        _globalRect(_SearchModeHostState._box(keys?.glyph)) ?? _lastGlyph;
    final frameBox = _SearchModeHostState._box(_host._fieldFrame);
    final frame = _globalRect(frameBox) ?? _lastFrame;
    if (frameBox is _RenderFieldFill) {
      _fieldFill = frameBox._color;
      _fieldEdge = frameBox._edge;
    }
    final icon =
        _globalRect(_SearchModeHostState._box(_host._fieldIcon)) ?? _lastIcon;
    if (buttonBox == null || frameBox == null) {
      // An end not laid out (never, or no longer): the glass holds its last
      // sight of it this frame, and the host lands everything after it
      // unless the end is back by then.
      _host._scheduleOrphanCheck();
      if (button == null && frame == null) return null;
    }
    if (buttonBox != null && buttonBox.size.width > 0 && button != null) {
      _lastScale = button.width / buttonBox.size.width;
    }
    _lastButton = button;
    _lastGlyph = glyph;
    _lastFrame = frame;
    _lastIcon = icon;

    final from = button ?? frame!;
    final to = frame ?? button!;
    // Along the flight, parked at either end (see SearchModeMotion.arrival).
    final t = SearchModeMotion.glassAt(_t);
    final rect = Rect.lerp(from, to, t)!;
    final radius = lerpDouble(
      from.shortestSide / 2,
      _fieldRadius,
      t,
    )!.clamp(0.0, rect.shortestSide / 2);
    final lift = ((1 - _lastScale) / _kButtonPressDepth).clamp(0.0, 1.0);
    final glass = GlassLook.resolve(
      _style,
      lift: lift,
      fade: 1 - t,
      fill: _fieldFill,
      fillAmount: t,
    );
    // The glass's lit rim becomes the field's edge as it lands: one hairline
    // the whole way, on the field's own line the frame it arrives.
    final look = GlassLook(
      plate: glass.plate,
      rimTop: Color.lerp(glass.rimTop, _fieldEdge, t)!,
      rimBottom: Color.lerp(glass.rimBottom, _fieldEdge, t)!,
      shadow: glass.shadow,
      sigma: glass.sigma,
      fill: glass.fill,
    );

    final glyphFrom = glyph?.center ?? from.center;
    final glyphFromSize = glyph?.shortestSide ?? from.shortestSide * 0.42;
    final glyphTo = icon?.center ?? Offset(to.left + 18, to.center.dy);
    final glyphToSize = icon?.shortestSide ?? 20;

    return _FlightPose(
      shape: RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      look: look,
      // Left to the field only while the field is there to draw it.
      frame: frameBox == null ? null : frame,
      glyphCenter: Offset.lerp(glyphFrom, glyphTo, t)!,
      glyphSize: lerpDouble(glyphFromSize, glyphToSize, t)!,
      glyphColor: Color.lerp(_buttonInk, _fieldIcon, t)!,
    );
  }

  void _painted(_FlightPose pose) {
    debugPaintCount++;
    debugLastRect = pose.shape.outerRect;
    debugLastLook = pose.look;
  }

  @override
  void dispose() {
    _active.dispose();
    super.dispose();
  }
}

/// The glass's layer over the page: draws it everywhere but inside the
/// field's frame (the field draws that part under its own text), with the
/// magnifier on top.
class _FlightLayer extends SingleChildRenderObjectWidget {
  const _FlightLayer({required this.flight})
    : super(
        // Drawn white and tinted at paint time, so the glyph is never
        // rebuilt while it flies.
        child: const SvgWidget(
          SvgAsset.searchIcon,
          height: _kGlyphBox,
          width: _kGlyphBox,
          colorFilter: ColorFilter.mode(Color(0xFFFFFFFF), BlendMode.srcIn),
        ),
      );

  final _Flight flight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFlightLayer(flight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderFlightLayer renderObject,
  ) {
    renderObject.flight = flight;
  }
}

class _RenderFlightLayer extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  _RenderFlightLayer(this._flight);

  _Flight _flight;
  set flight(_Flight value) {
    if (identical(value, _flight)) return;
    if (attached) {
      _flight.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _flight = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _flight.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _flight.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    child?.layout(BoxConstraints.tight(const Size.square(_kGlyphBox)));
  }

  @override
  bool hitTestSelf(Offset position) => false;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      false;

  @override
  void paint(PaintingContext context, Offset offset) {
    final pose = _flight.pose();
    if (pose == null) return;
    final toLocal = Matrix4.tryInvert(getTransformTo(null));
    if (toLocal == null) return;
    Rect local(Rect global) =>
        MatrixUtils.transformRect(toLocal, global).shift(offset);

    final frame = pose.frame;
    GlassPainter.paint(
      context,
      shape: RRect.fromRectAndRadius(
        local(pose.shape.outerRect),
        pose.shape.tlRadius,
      ),
      look: pose.look,
      bounds: offset & size,
      excluding: frame == null ? null : local(frame),
    );

    final glyph = child;
    if (glyph != null && pose.glyphSize > 0) {
      final center =
          MatrixUtils.transformPoint(toLocal, pose.glyphCenter) + offset;
      final scale = pose.glyphSize / _kGlyphBox;
      final transform = Matrix4.identity()
        ..translateByDouble(center.dx, center.dy, 0, 1)
        ..scaleByDouble(scale, scale, 1, 1)
        ..translateByDouble(-_kGlyphBox / 2, -_kGlyphBox / 2, 0, 1);
      context.pushColorFilter(
        Offset.zero,
        ColorFilter.mode(pose.glyphColor, BlendMode.srcIn),
        (context, _) => context.pushTransform(
          true,
          Offset.zero,
          transform,
          (context, _) => context.paintChild(glyph, Offset.zero),
        ),
      );
    }
    _flight._painted(pose);
  }
}

/// A search field's fill, which the flying glass becomes.
///
/// At rest it is the field's solid rounded fill and its 1pt [edge], drawn
/// as `HomeSearchFieldSurface` draws them. While the glass flies, it draws
/// the part of the glass inside its own box instead, under the field's
/// text, so the text and hint fade in over the arriving glass (and out over
/// the leaving one); the layer over the page draws the rest. The glass
/// reads [color] and [edge] from it every frame, so it lands on exactly the
/// field drawn after it. Used by `EventSearchBarFrame` inside a
/// [SearchModeHeader]; anywhere else it is a plain fill.
class SearchFieldFill extends SingleChildRenderObjectWidget {
  const SearchFieldFill({
    super.key,
    required this.color,
    required this.radius,
    this.edge,
    super.child,
  });

  final Color color;
  final double radius;

  /// The 1pt edge inside the field; null for none (the fill's own colour).
  final Color? edge;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderFieldFill(
    color: color,
    edge: edge ?? color,
    radius: radius,
    flight: SearchFieldHandoff.maybeOf(context)?._flight,
  );

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderFieldFill)
      ..color = color
      ..edge = edge ?? color
      ..radius = radius
      ..flight = SearchFieldHandoff.maybeOf(context)?._flight;
  }
}

class _RenderFieldFill extends RenderProxyBox {
  _RenderFieldFill({
    required this._color,
    required this._edge,
    required this._radius,
    this._flight,
  });

  Color _color;
  set color(Color value) {
    if (value == _color) return;
    _color = value;
    markNeedsPaint();
  }

  Color _edge;
  set edge(Color value) {
    if (value == _edge) return;
    _edge = value;
    markNeedsPaint();
  }

  double _radius;
  set radius(double value) {
    if (value == _radius) return;
    _radius = value;
    markNeedsPaint();
  }

  _Flight? _flight;
  set flight(_Flight? value) {
    if (identical(value, _flight)) return;
    if (attached) {
      _flight?.removeListener(_onFlight);
      value?.addListener(_onFlight);
    }
    _flight = value;
    _onFlight();
  }

  bool _flying = false;

  void _onFlight() {
    final flying = _flight?.active ?? false;
    if (flying != _flying) {
      _flying = flying;
      if (attached) markNeedsCompositingBitsUpdate();
    }
    if (attached) markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _flying = _flight?.active ?? false;
    _flight?.addListener(_onFlight);
  }

  @override
  void detach() {
    _flight?.removeListener(_onFlight);
    super.detach();
  }

  @override
  bool get alwaysNeedsCompositing => _flying;

  @override
  void paint(PaintingContext context, Offset offset) {
    final box = offset & size;
    final flight = _flight;
    final pose = _flying ? flight?.pose() : null;
    final toLocal = pose == null
        ? null
        : Matrix4.tryInvert(getTransformTo(null));
    if (pose == null || toLocal == null) {
      final shape = RRect.fromRectAndRadius(box, Radius.circular(_radius));
      context.canvas.drawRRect(shape, Paint()..color = _color);
      if (_edge != _color) paintGlassRim(context.canvas, shape, _edge, _edge);
    } else {
      GlassPainter.paint(
        context,
        shape: RRect.fromRectAndRadius(
          MatrixUtils.transformRect(
            toLocal,
            pose.shape.outerRect,
          ).shift(offset),
          pose.shape.tlRadius,
        ),
        look: pose.look,
        bounds: box,
        within: box,
        shadow: false,
      );
      flight!._painted(pose);
    }
    super.paint(context, offset);
  }
}

/// Handed by a [SearchModeHeader] to the field inside it: the keys the
/// morph measures the field by, and its leading magnifier's stand-down while
/// the glass's own magnifier flies in its place.
class SearchFieldHandoff extends InheritedWidget {
  const SearchFieldHandoff._({
    required this.frameKey,
    required this.iconKey,
    required this._flight,
    required super.child,
  });

  /// On the field's filled frame ([SearchFieldFill]).
  final GlobalKey frameKey;

  /// On the field's leading magnifier.
  final GlobalKey iconKey;

  final _Flight _flight;

  static SearchFieldHandoff? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SearchFieldHandoff>();

  /// The field's leading magnifier, measured by [iconKey], and not drawn
  /// while the glass's magnifier flies in or out of its place.
  Widget magnifier(Widget icon) => KeyedSubtree(
    key: iconKey,
    child: ValueListenableBuilder<bool>(
      valueListenable: _flight._active,
      child: icon,
      builder: (context, flying, icon) =>
          Opacity(opacity: flying ? 0 : 1, child: icon),
    ),
  );

  @override
  bool updateShouldNotify(SearchFieldHandoff oldWidget) =>
      oldWidget.frameKey != frameKey ||
      oldWidget.iconKey != iconKey ||
      oldWidget._flight != _flight;
}
