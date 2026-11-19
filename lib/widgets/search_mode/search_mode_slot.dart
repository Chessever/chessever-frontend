part of 'search_mode.dart';

/// Where a page's header and its search header take turns: put it inside
/// the page's `CollapsingChrome`.
///
/// Its height springs on the morph's timeline from the header's to the
/// search header's (the list under it moves with it, never jumps). The
/// header slides up [SearchModeMotion.headerSlide] and fades over the first
/// part of the timeline; the search header (top-aligned, so the field the
/// glass lands on holds still) brings its own parts in over the last part.
/// Both run backwards on close. The header stays mounted while searching,
/// paused and out of reach, so it comes back exactly as it was left.
///
/// With no [SearchModeHost] above it, it is just [header].
class SearchModeHeaderSlot extends StatefulWidget {
  const SearchModeHeaderSlot({
    super.key,
    required this.header,
    required this.search,
  });

  /// The page's own header (title row, tabs).
  final Widget header;

  /// Its search: a [SearchModeHeader].
  final Widget search;

  @override
  State<SearchModeHeaderSlot> createState() => _SearchModeHeaderSlotState();
}

class _SearchModeHeaderSlotState extends State<SearchModeHeaderSlot> {
  Animation<double>? _timeline;
  bool _atHeader = true;
  bool _atSearch = false;

  /// What the page's header draws that the search header draws too, at the
  /// same spot ([SearchModeShared]).
  final _SharedRegistry _shared = _SharedRegistry();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final timeline = SearchModeScope.maybeOf(context)?.timeline;
    if (timeline != _timeline) {
      _timeline?.removeListener(_onTick);
      timeline?.addListener(_onTick);
      _timeline = timeline;
      _read();
    }
  }

  @override
  void dispose() {
    _timeline?.removeListener(_onTick);
    _shared.dispose();
    super.dispose();
  }

  void _read() {
    final t = _timeline?.value ?? 0;
    _atHeader = t <= 0;
    _atSearch = t >= 1;
  }

  void _onTick() {
    final t = _timeline!.value;
    final atHeader = t <= 0;
    final atSearch = t >= 1;
    if (atHeader != _atHeader || atSearch != _atSearch) {
      setState(() {
        _atHeader = atHeader;
        _atSearch = atSearch;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = SearchModeScope.maybeOf(context);
    if (scope == null) return widget.header;
    final searching = scope.isSearching;
    final showSearch = searching || !_atHeader;
    final headerAway = searching && _atSearch;
    return _HeaderSlotLayout(
      timeline: scope.timeline,
      searching: searching,
      children: [
        KeyedSubtree(
          key: const ValueKey('search_mode_slot_header'),
          child: _SlotSide(
            header: true,
            searchShown: showSearch,
            registry: _shared,
            child: TickerMode(
              enabled: !headerAway,
              child: ExcludeFocus(excluding: searching, child: widget.header),
            ),
          ),
        ),
        if (showSearch)
          KeyedSubtree(
            key: const ValueKey('search_mode_slot_search'),
            child: _SlotSide(
              header: false,
              searchShown: true,
              registry: _shared,
              child: widget.search,
            ),
          ),
      ],
    );
  }
}

/// A control the page's header and its search header both draw, at the same
/// spot: the back chevron ([PageBackButton] is one on its own), Filters, a
/// toggle. Wrap it, with the same [id], in both headers.
///
/// It holds still through the morph: while the search header is on screen
/// its copy is the one drawn, whole from the tap (the page header's copy
/// steps aside rather than fading and sliding with the rest of the header),
/// so the glyph never blinks or slides away and back. A piece the page's
/// header does not draw arrives with the search header's other parts.
///
/// Anywhere else (no [SearchModeHeaderSlot] above it) it is just [child].
class SearchModeShared extends StatefulWidget {
  const SearchModeShared({super.key, required this.id, required this.child});

  /// The same in both headers, and unique among a header's shared pieces.
  final Object id;
  final Widget child;

  @override
  State<SearchModeShared> createState() => _SearchModeSharedState();
}

class _SearchModeSharedState extends State<SearchModeShared> {
  _SharedRegistry? _registry;
  Object? _registeredId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(SearchModeShared oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) _sync();
  }

  @override
  void dispose() {
    _unregister();
    super.dispose();
  }

  /// The header's copy tells the slot it is there.
  void _sync() {
    final side = _SlotSide.maybeOf(context, listen: false);
    final registry = side != null && side.header ? side.registry : null;
    if (registry == _registry && widget.id == _registeredId) return;
    _unregister();
    if (registry != null) {
      registry.add(widget.id);
      _registry = registry;
      _registeredId = widget.id;
    }
  }

  void _unregister() {
    final id = _registeredId;
    if (id != null) _registry?.remove(id);
    _registry = null;
    _registeredId = null;
  }

  @override
  Widget build(BuildContext context) {
    final side = _SlotSide.maybeOf(context);
    if (side == null) return widget.child;
    if (side.header) {
      // The search header's copy is drawn in its place: one glyph, still.
      return Opacity(opacity: side.searchShown ? 0 : 1, child: widget.child);
    }
    final arriving = SearchModeScope.maybeOf(context)?.searchContentOpacity;
    return ListenableBuilder(
      listenable: side.registry,
      child: widget.child,
      builder: (context, child) => _Arriving(
        opacity: arriving == null || side.registry.holds(widget.id)
            ? kAlwaysCompleteAnimation
            : arriving,
        child: child,
      ),
    );
  }
}

/// Which header a [SearchModeShared] sits in.
class _SlotSide extends InheritedWidget {
  const _SlotSide({
    required this.header,
    required this.searchShown,
    required this.registry,
    required super.child,
  });

  /// The page's own header (else the search header).
  final bool header;

  /// The search header is in the slot (opening, open or closing).
  final bool searchShown;
  final _SharedRegistry registry;

  static _SlotSide? maybeOf(BuildContext context, {bool listen = true}) =>
      listen
      ? context.dependOnInheritedWidgetOfExactType<_SlotSide>()
      : context.getInheritedWidgetOfExactType<_SlotSide>();

  @override
  bool updateShouldNotify(_SlotSide oldWidget) =>
      oldWidget.header != header ||
      oldWidget.searchShown != searchShown ||
      oldWidget.registry != registry;
}

/// The ids of the shared pieces the page's header draws.
class _SharedRegistry extends ChangeNotifier {
  final Map<Object, int> _counts = <Object, int>{};
  bool _notifyQueued = false;
  bool _disposed = false;

  bool holds(Object id) => _counts.containsKey(id);

  void add(Object id) {
    final count = _counts[id] ?? 0;
    _counts[id] = count + 1;
    if (count == 0) _changed();
  }

  void remove(Object id) {
    final count = _counts[id];
    if (count == null) return;
    if (count > 1) {
      _counts[id] = count - 1;
    } else {
      _counts.remove(id);
      _changed();
    }
  }

  /// Registered while the header builds: the search header (built after it,
  /// or not at all yet) hears of it once the frame is done.
  void _changed() {
    if (_notifyQueued || _disposed || !hasListeners) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      _notifyQueued = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _notifyQueued = false;
        if (!_disposed) notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _HeaderSlotLayout extends MultiChildRenderObjectWidget {
  const _HeaderSlotLayout({
    required this.timeline,
    required this.searching,
    required super.children,
  });

  final Animation<double> timeline;
  final bool searching;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHeaderSlot(timeline: timeline, searching: searching);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHeaderSlot renderObject,
  ) {
    renderObject
      ..timeline = timeline
      ..searching = searching;
  }
}

class _SlotParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderHeaderSlot extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SlotParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SlotParentData> {
  _RenderHeaderSlot({required this._timeline, required this._searching});

  Animation<double> _timeline;
  set timeline(Animation<double> value) {
    if (identical(value, _timeline)) return;
    if (attached) {
      _timeline.removeListener(_onTick);
      value.addListener(_onTick);
    }
    _timeline = value;
    _onTick();
  }

  bool _searching;
  set searching(bool value) {
    if (value == _searching) return;
    _searching = value;
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  double _headerHeight = 0;
  double _searchHeight = 0;
  bool _moving = false;
  final LayerHandle<ClipRectLayer> _clip = LayerHandle<ClipRectLayer>();
  final LayerHandle<OpacityLayer> _fade = LayerHandle<OpacityLayer>();

  RenderBox? get _header => firstChild;
  RenderBox? get _search {
    final header = firstChild;
    return header == null ? null : childAfter(header);
  }

  double get _t => _timeline.value.clamp(0.0, 1.0);

  /// How far the header has left: over the first part of the timeline.
  double get _away => _window(_t, 0, SearchModeMotion.headerOutEnd);

  void _onTick() {
    final t = _t;
    final moving = t > 0 && t < 1;
    if (moving != _moving) {
      _moving = moving;
      if (attached) markNeedsCompositingBitsUpdate();
    }
    if (attached) markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _moving = _t > 0 && _t < 1;
    _timeline.addListener(_onTick);
  }

  @override
  void detach() {
    _timeline.removeListener(_onTick);
    super.detach();
  }

  @override
  void dispose() {
    _clip.layer = null;
    _fade.layer = null;
    super.dispose();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SlotParentData) {
      child.parentData = _SlotParentData();
    }
  }

  @override
  bool get alwaysNeedsCompositing => _moving;

  BoxConstraints _childConstraints(BoxConstraints constraints) =>
      BoxConstraints(
        minWidth: constraints.minWidth,
        maxWidth: constraints.maxWidth,
      );

  double _blend(double header, double? search) =>
      search == null ? header : lerpDouble(header, search, _t)!;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final inner = _childConstraints(constraints);
    final header = _header?.getDryLayout(inner) ?? Size.zero;
    final search = _search?.getDryLayout(inner);
    final width = math.max(header.width, search?.width ?? 0);
    return constraints.constrain(
      Size(width, _blend(header.height, search?.height)),
    );
  }

  @override
  void performLayout() {
    final inner = _childConstraints(constraints);
    final header = _header;
    final search = _search;
    _headerHeight = 0;
    _searchHeight = 0;
    var width = 0.0;
    if (header != null) {
      header.layout(inner, parentUsesSize: true);
      _headerHeight = header.size.height;
      width = header.size.width;
    }
    if (search != null) {
      search.layout(inner, parentUsesSize: true);
      _searchHeight = search.size.height;
      width = math.max(width, search.size.width);
    }
    size = constraints.constrain(
      Size(width, _blend(_headerHeight, search == null ? null : _searchHeight)),
    );
    // Centred across, as the chrome's own alignment would place them.
    if (header != null) {
      (header.parentData! as _SlotParentData).offset = Offset(
        (size.width - header.size.width) / 2,
        search == null ? 0 : -SearchModeMotion.headerSlide * _away,
      );
    }
    if (search != null) {
      (search.parentData! as _SlotParentData).offset = Offset(
        (size.width - search.size.width) / 2,
        0,
      );
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _header?.getMinIntrinsicWidth(height) ?? 0;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _header?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  double computeMinIntrinsicHeight(double width) => _blend(
    _header?.getMinIntrinsicHeight(width) ?? 0,
    _search?.getMinIntrinsicHeight(width),
  );

  @override
  double computeMaxIntrinsicHeight(double width) => _blend(
    _header?.getMaxIntrinsicHeight(width) ?? 0,
    _search?.getMaxIntrinsicHeight(width),
  );

  bool get _headerDrawn => !(_searching && _t >= 1);

  @override
  void paint(PaintingContext context, Offset offset) {
    final tallest = math.max(
      _headerHeight,
      _search == null ? 0.0 : _searchHeight,
    );
    if (size.height < tallest - 0.5) {
      _clip.layer = context.pushClipRect(
        needsCompositing,
        offset,
        Offset.zero & size,
        _paintChildren,
        oldLayer: _clip.layer,
      );
    } else {
      _clip.layer = null;
      _paintChildren(context, offset);
    }
  }

  void _paintChildren(PaintingContext context, Offset offset) {
    final header = _header;
    final search = _search;
    if (header != null && _headerDrawn) {
      final at = offset + (header.parentData! as _SlotParentData).offset;
      final alpha = search == null ? 255 : ((1 - _away) * 255).round();
      if (alpha >= 255) {
        _fade.layer = null;
        context.paintChild(header, at);
      } else if (alpha > 0) {
        _fade.layer = context.pushOpacity(
          at,
          alpha,
          (context, offset) => context.paintChild(header, offset),
          oldLayer: _fade.layer,
        );
      } else {
        _fade.layer = null;
      }
    } else {
      _fade.layer = null;
    }
    if (search != null) {
      context.paintChild(
        search,
        offset + (search.parentData! as _SlotParentData).offset,
      );
    }
  }

  RenderBox? get _active => _searching ? (_search ?? _header) : _header;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final active = _active;
    if (active == null) return false;
    final data = active.parentData! as _SlotParentData;
    return result.addWithPaintOffset(
      offset: data.offset,
      position: position,
      hitTest: (result, transformed) =>
          active.hitTest(result, position: transformed),
    );
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    final active = _active;
    if (active != null) visitor(active);
  }
}
