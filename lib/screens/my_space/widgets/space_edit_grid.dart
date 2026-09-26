import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/screens/my_space/widgets/space_reorder.dart'
    show spaceNearestSlot;
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:motor/motor.dart';

// See all's Edit: the group's own cards in the order the page shows them,
// each with its selection circle, picked up by a hold and dropped where the
// reader wants it. Like See all, the cards are built a row at a time as they
// scroll in. Everything moves on springs: the circles grow in as Edit starts
// (in a lane that opens before a list's rows, on the board of a card that
// draws one) and shrink away as it ends, a lifted card rises and casts one
// tight shadow of its own shape, the others glide aside as it passes, and it
// lands in its new place. A circle that has not finished growing is already
// there, only smaller, and nothing ever cuts it.

/// One thing on an Edit page: its key (what is selected, moved and removed),
/// what a screen reader calls it, and its card at the width it is given.
@immutable
class SpaceEditItem {
  const SpaceEditItem({
    required this.key,
    required this.label,
    required this.builder,
    this.band = 0,
    this.wide = false,
  });

  final String key;
  final String label;
  final Widget Function(BuildContext context, double width) builder;

  /// The run of cards this one moves among. A page that keeps some cards
  /// ahead of the rest (live events first, games still loading last) gives
  /// each run its own band, in the page's order: a card moves only within
  /// its band, so Edit always shows the order the page will.
  final int band;

  /// Stands alone on its row at the whole width, however many columns the
  /// others take (a saved row among grid cards). Its circle stands in a
  /// lane before it.
  final bool wide;
}

/// Where a card's selection circle stands.
enum SpaceEditMark {
  /// In a lane before the card, which gives up that width while Edit lasts:
  /// the rows of a list (events, databases, compact game rows).
  lane,

  /// On the rim of a face's circle, top left (the flag holds the top right):
  /// the Players' faces, which keep their width.
  face,

  /// On the card's board, over its top-left square: the cards that draw a
  /// board (grid and board view), which keep their width and their place,
  /// so Edit reflows nothing.
  board,
}

/// How long a finger rests on a card before it lifts.
const Duration kSpaceEditLiftDelay = Duration(milliseconds: 280);

/// The selection circle's diameter.
double get kSpaceEditCheck => 22.ic;

/// The lane a card's circle stands in: the circle and the air after it.
double get kSpaceEditLane => kSpaceEditCheck + 12.w;

/// How far in from a card's corner its circle stands when the card turns
/// out to draw no board after all.
double get kSpaceEditBoardInset => 6.sp;

/// The circle on a board is as wide as the board's top-left square, and
/// never narrower than this share of [kSpaceEditCheck], so it stays a
/// circle to see on the smallest grid board.
const double kSpaceEditBoardCheckMin = 0.8;

/// Where [SpaceEditMark.board] puts a card's circle, in the card's
/// coordinates, for a card whose board is [board] (null: the card draws
/// none) and a circle of diameter [check]: centred on the board's top-left
/// square and as wide as it (never under [kSpaceEditBoardCheckMin] of
/// [check]), so it covers that one square's piece whole, whatever the
/// board's size, and reaches no neighbour's; with no board, [check] wide
/// at [inset] from the card's corner.
Rect spaceEditBoardCheckRect(Rect? board, double check, double inset) {
  if (board == null || board.width <= 0) {
    return Offset(inset, inset) & Size.square(check);
  }
  final square = board.width / 8;
  final d = math.max(square, check * kSpaceEditBoardCheckMin);
  return Rect.fromCircle(
    center: board.topLeft + Offset(square / 2, square / 2),
    radius: d / 2,
  );
}

/// Drives one face of a See all page (the page, or its Edit) and opens the
/// list it drives at [start], read as the list attaches, so each face can
/// open where the reader left the other. A start past the end of a shorter
/// list lands on its end on the first layout, rather than springing back
/// to it. It keeps nothing in page storage: its owner says where.
class SpaceStartController extends ScrollController {
  SpaceStartController({this.start = 0}) : super(keepScrollOffset: false);

  /// Where the next list this drives opens.
  double start;

  @override
  double get initialScrollOffset => start;

  /// Where the list it drives stands; null while it drives none.
  double? get at =>
      positions.length == 1 && position.hasPixels ? position.pixels : null;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _StartPosition(
    physics: physics,
    context: context,
    initialPixels: initialScrollOffset,
    oldPosition: oldPosition,
    debugLabel: debugLabel,
  );
}

class _StartPosition extends ScrollPositionWithSingleContext {
  _StartPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.oldPosition,
    super.debugLabel,
  }) : super(keepScrollOffset: false);

  bool _placed = false;

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    if (!_placed && hasPixels) {
      _placed = true;
      final inside = clampDouble(
        pixels,
        minScrollExtent,
        math.max(minScrollExtent, maxScrollExtent),
      );
      if (inside != pixels) {
        correctPixels(inside);
        return false;
      }
    }
    return super.applyContentDimensions(minScrollExtent, maxScrollExtent);
  }
}

/// The order [keys] stand in while a drag reorders them: the keys of
/// [order] keep their preview place; a key the store added meanwhile slots
/// in at its own index, and one it removed drops out, so a refresh never
/// yanks the grid under the finger.
List<String> spaceEditPreviewOrder(List<String> keys, List<String>? order) {
  if (order == null) return keys;
  final known = keys.toSet();
  final out = [
    for (final k in order)
      if (known.contains(k)) k,
  ];
  final placed = out.toSet();
  for (var i = 0; i < keys.length; i++) {
    if (placed.contains(keys[i])) continue;
    out.insert(math.min(i, out.length), keys[i]);
  }
  return out;
}

/// The keys of [key]'s band in [order], in that order: the cards it moves
/// among. [bands] maps a key to its band (0 when missing).
List<String> spaceEditBand(
  List<String> order,
  Map<String, int> bands,
  String key,
) {
  final band = bands[key] ?? 0;
  return [
    for (final k in order)
      if ((bands[k] ?? 0) == band) k,
  ];
}

/// [order] as the grid's rows: up to [columns] cards of one band to a row,
/// a band starting on a row of its own, a wide card alone on its row. Keys
/// with no item are left out.
List<List<String>> spaceEditRows(
  List<String> order,
  Map<String, SpaceEditItem> items,
  int columns,
) {
  final rows = <List<String>>[];
  List<String>? run;
  int? runBand;
  for (final k in order) {
    final item = items[k];
    if (item == null) continue;
    if (item.wide || columns <= 1) {
      rows.add([k]);
      run = null;
      continue;
    }
    final open = run;
    if (open == null || open.length >= columns || runBand != item.band) {
      final next = [k];
      rows.add(next);
      run = next;
      runBand = item.band;
    } else {
      open.add(k);
    }
  }
  return rows;
}

/// The board a card draws, in [root]'s coordinates: the largest square box
/// inside it at least half its width. Null for a card with no board.
/// Read after layout (or from a layout callback).
Rect? spaceEditBoardIn(RenderBox root) {
  if (!root.hasSize || root.size.width <= 0) return null;
  final least = root.size.width * 0.5;
  Rect? best;
  void visit(RenderObject child) {
    if (child is RenderBox && child.hasSize) {
      final s = child.size;
      if (s.width >= least && (s.width - s.height).abs() <= 1) {
        final found = best;
        if (found == null || s.width > found.width + 0.5) {
          final at = MatrixUtils.transformPoint(
            child.getTransformTo(root),
            Offset.zero,
          );
          best = at & s;
        }
        // Nothing inside a board is a larger board.
        return;
      }
    }
    child.visitChildren(visit);
  }

  root.visitChildren(visit);
  return best;
}

/// The group's cards in Edit, in the order the page shows them: [columns]
/// to a row (or [itemWidth] wide each, as many as fit), each marked by its
/// selection circle ([mark]; a [SpaceEditItem.wide] card in a grid takes a
/// lane). A tap selects or clears a card; with [onReorder], a hold lifts it
/// and a drop moves it within its band ([onReorder] gets the key and the
/// band's new order; every other card keeps its place). A group that orders
/// itself (Players) passes none and only selects.
///
/// It scrolls on its own, [header] riding at its top, on [controller] when
/// one is given (a [SpaceStartController], so Edit opens where the reader
/// was on the page, and the page can come back where the reader left Edit).
/// With [closing] its circles go the way they came, then
/// [onClosed] is called (at once when motion is off), so Done ends Edit in
/// one motion before the page takes its place.
class SpaceEditGrid extends StatefulWidget {
  const SpaceEditGrid({
    super.key,
    required this.items,
    required this.selected,
    required this.onToggle,
    required this.gutter,
    this.onReorder,
    this.columns = 1,
    this.gap,
    this.runSpacing,
    this.itemWidth,
    this.mark = SpaceEditMark.lane,
    this.faceCircle,
    this.faceTop = 0,
    this.top = 0,
    this.bottom = 0,
    this.header,
    this.controller,
    this.closing = false,
    this.onClosed,
  });

  final List<SpaceEditItem> items;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final void Function(String key, List<String> bandOrder)? onReorder;
  final double gutter;
  final int columns;

  /// Between two cards of a row; [runSpacing] between rows.
  final double? gap;
  final double? runSpacing;

  /// Each cell's width, when the cells are not [columns] to a row (faces).
  final double? itemWidth;
  final SpaceEditMark mark;

  /// A face's circle diameter and how far under the cell's top it starts,
  /// for [SpaceEditMark.face].
  final double? faceCircle;
  final double faceTop;

  final double top;
  final double bottom;
  final Widget? header;
  final ScrollController? controller;
  final bool closing;
  final VoidCallback? onClosed;

  @override
  State<SpaceEditGrid> createState() => _SpaceEditGridState();
}

class _SpaceEditGridState extends State<SpaceEditGrid>
    with TickerProviderStateMixin {
  ScrollController? _ownScroll;
  ScrollController get _scroll =>
      widget.controller ?? (_ownScroll ??= ScrollController());
  final _stackKey = GlobalKey();

  /// Each card's cell, so a card that changes rows keeps its element (and
  /// its glide) rather than being built again.
  final Map<String, GlobalKey> _cellKeys = {};

  late Map<String, SpaceEditItem> _byKey;
  late Map<String, int> _bands;

  /// The circles growing in as Edit starts (and away as it ends), 0 to 1.
  late final SingleMotionController _enter;

  /// The lifted card's rise, 0 at rest to 1 held.
  late final SingleMotionController _rise;

  /// Where a dropped card flies to land (the grid's coordinates).
  late final MotionController<Offset> _land;
  late final Ticker _autoscroll;

  /// The hold that lifts a card. The grid's own rather than a card's, so a
  /// carried card that moves to another row or scrolls out of the built
  /// rows never loses the drag.
  LongPressGestureRecognizer? _hold;

  /// The order a drag shows; kept after the drop until the store has it.
  List<String>? _order;
  Timer? _orderExpiry;

  String? _lifted;
  Widget? _liftedCell;
  Size _liftedSize = Size.zero;
  double _liftedLane = 0;
  Offset _grab = Offset.zero;

  /// A card of a one-column run (a list, a wide row) is carried straight up
  /// and down, never sideways out of its column: its left edge on screen.
  double? _liftedLeft;
  final ValueNotifier<Offset> _finger = ValueNotifier(Offset.zero);
  bool _landing = false;

  /// Where a dropped card lands; it is home once within half a point of it
  /// (a spring's tail is too small to see, so it never holds the socket).
  Offset? _landAt;

  /// Cells glide to their new places (a drag, a removal) only while this
  /// holds, so a lane opening or a card changing height never sets them off.
  bool _glide = false;
  Timer? _glideOff;

  /// Finishes the entrance should its spring be held (a muted ticker): the
  /// circles are never left half grown. [_closeDone] does the same for the
  /// way out, so Done always ends Edit.
  Timer? _enterDone;
  Timer? _closeDone;
  bool _closedSent = false;

  bool get _still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void initState() {
    super.initState();
    _index();
    _enter = SingleMotionController(
      motion: const CupertinoMotion.smooth(
        duration: Duration(milliseconds: 380),
        snapToEnd: true,
      ),
      vsync: this,
      initialValue: 0,
    );
    _rise = SingleMotionController(
      motion: const CupertinoMotion.snappy(
        duration: Duration(milliseconds: 320),
        snapToEnd: true,
      ),
      vsync: this,
      initialValue: 0,
    );
    _land = MotionController<Offset>(
      motion: const CupertinoMotion.snappy(
        duration: Duration(milliseconds: 360),
        snapToEnd: true,
      ),
      vsync: this,
      converter: MotionConverter.offset,
      initialValue: Offset.zero,
    );
    _land.addListener(_onLanding);
    _autoscroll = createTicker(_onAutoscroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.closing ? _close() : _open();
    });
  }

  void _index() {
    _byKey = {for (final i in widget.items) i.key: i};
    _bands = {for (final i in widget.items) i.key: i.band};
  }

  @override
  void didUpdateWidget(SpaceEditGrid old) {
    super.didUpdateWidget(old);
    _index();
    final before = [for (final i in old.items) i.key];
    final now = _keys;
    if (!listEquals(before, now)) {
      // Something left or arrived (a removal, its undo): the rest glide.
      if (!setEquals(before.toSet(), now.toSet())) {
        _glideFor(const Duration(milliseconds: 700));
      }
      // The store answered a drop: its order stands from here.
      if (_lifted == null && _order != null) _order = null;
    }
    final lifted = _lifted;
    if (lifted != null && !now.contains(lifted)) _cancelLift();
    if (widget.closing != old.closing) widget.closing ? _close() : _open();
  }

  @override
  void dispose() {
    _orderExpiry?.cancel();
    _glideOff?.cancel();
    _enterDone?.cancel();
    _closeDone?.cancel();
    _hold?.dispose();
    _autoscroll.dispose();
    _enter.dispose();
    _rise.dispose();
    _land.dispose();
    _finger.dispose();
    _ownScroll?.dispose();
    super.dispose();
  }

  // ------------------------------------------------------ entering, leaving

  void _open() {
    _closeDone?.cancel();
    _closedSent = false;
    _enterDone?.cancel();
    if (_still) {
      _enter.value = 1;
      return;
    }
    unawaited(_enter.animateTo(1));
    _enterDone = Timer(const Duration(milliseconds: 700), () {
      if (mounted && !widget.closing && _enter.value < 1) _enter.value = 1;
    });
  }

  void _close() {
    // A card still held when Edit ends goes back to its place: nothing is
    // written while the page is being rebuilt.
    if (_lifted != null) _cancelLift();
    _hold?.dispose();
    _hold = null;
    _enterDone?.cancel();
    if (_still) {
      _enter.value = 0;
      // After this frame: the page's own rebuild is what calls here.
      WidgetsBinding.instance.addPostFrameCallback((_) => _sendClosed());
      return;
    }
    _enter.animateTo(0).whenCompleteOrCancel(_sendClosed);
    _closeDone?.cancel();
    _closeDone = Timer(const Duration(milliseconds: 520), _sendClosed);
  }

  void _sendClosed() {
    if (!mounted || !widget.closing || _closedSent) return;
    _closedSent = true;
    _closeDone?.cancel();
    widget.onClosed?.call();
  }

  void _glideFor(Duration d) {
    _glide = true;
    _glideOff?.cancel();
    _glideOff = Timer(d, () {
      if (!mounted || _lifted != null) return;
      setState(() => _glide = false);
    });
  }

  List<String> get _keys => [for (final i in widget.items) i.key];

  List<String> get _shown => spaceEditPreviewOrder(_keys, _order);

  /// The mark [item] wears: a wide card in a grid stands in a lane.
  SpaceEditMark _markOf(SpaceEditItem item) =>
      item.wide && widget.mark == SpaceEditMark.board
      ? SpaceEditMark.lane
      : widget.mark;

  /// Whether [item] stands alone in its column (it is only ever carried up
  /// and down).
  bool _columnOf(SpaceEditItem item) =>
      item.wide || (widget.itemWidth == null && widget.columns <= 1);

  GlobalKey _cellKey(String key) =>
      _cellKeys.putIfAbsent(key, () => GlobalKey(debugLabel: 'edit:$key'));

  RenderBox? get _stackBox =>
      _stackKey.currentContext?.findRenderObject() as RenderBox?;

  /// A built cell's box: where the grid laid it out (a glide paints its
  /// card on the way there, never moves the box). Null when its row is not
  /// built.
  RenderBox? _cellBox(String key) {
    final box = _cellKeys[key]?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box;
  }

  // ------------------------------------------------------------- lifting

  /// A finger came down on [key]'s card: the grid's hold starts counting.
  void _holdDown(PointerDownEvent event, String key) {
    if (widget.onReorder == null ||
        widget.closing ||
        _lifted != null ||
        _landing) {
      return;
    }
    _hold?.dispose();
    final hold = _hold = LongPressGestureRecognizer(
      duration: kSpaceEditLiftDelay,
      debugOwner: this,
    );
    hold
      ..onLongPressStart = ((d) => _liftStart(key, d.globalPosition))
      ..onLongPressMoveUpdate = ((d) => _liftMove(d.globalPosition))
      ..onLongPressEnd = ((_) => _liftEnd())
      // A carried card whose touch the system takes away goes down where
      // it is, never stays hanging over the page.
      ..onLongPressCancel = (() {
        if (_lifted != null) _liftEnd();
      });
    hold.addPointer(event);
  }

  void _liftStart(String key, Offset global) {
    final item = _byKey[key];
    if (item == null || widget.onReorder == null) return;
    if (_landing || _lifted != null || widget.closing) return;
    final box = _cellBox(key);
    if (box == null) return;
    HapticFeedbackService.light();
    _orderExpiry?.cancel();
    _liftedSize = box.size;
    _grab = box.globalToLocal(global);
    _liftedLeft = _columnOf(item) ? box.localToGlobal(Offset.zero).dx : null;
    _liftedLane = _markOf(item) == SpaceEditMark.lane ? kSpaceEditLane : 0;
    _finger.value = global;
    _liftedCell = _cellFace(
      item,
      selected: widget.selected.contains(key),
      width: box.size.width,
    );
    setState(() {
      _order = _shown;
      _lifted = key;
      _glide = true;
    });
    _glideOff?.cancel();
    if (_still) {
      _rise.value = 1;
    } else {
      unawaited(_rise.animateTo(1));
    }
    _autoscroll.start();
  }

  void _liftMove(Offset global) {
    if (_lifted == null || _landing) return;
    _finger.value = global;
    _retarget();
  }

  /// Where the lifted card's top left is on screen, under the finger.
  Offset get _liftedTopLeft {
    final at = _finger.value - _grab;
    final left = _liftedLeft;
    return left == null ? at : Offset(left, at.dy);
  }

  /// Moves the lifted card's slot to the one of its band its centre is
  /// nearest. Cards of another band, and rows not built (the finger is on
  /// screen, so its slot is among the built ones), never take it.
  void _retarget() {
    final key = _lifted;
    final order = _order;
    if (key == null || order == null) return;
    final center =
        _liftedTopLeft + Offset(_liftedSize.width / 2, _liftedSize.height / 2);
    final band = _bands[key] ?? 0;
    const away = Offset(-1e9, -1e9);
    final centers = [
      for (final k in order)
        if ((_bands[k] ?? 0) != band)
          away
        else if (_cellBox(k) case final box?)
          box.localToGlobal(box.size.center(Offset.zero))
        else
          away,
    ];
    final from = order.indexOf(key);
    if (from < 0) return;
    final to = spaceNearestSlot(
      centers,
      center,
      from,
      hysteresis: (widget.gap ?? 12.sp) * 0.5,
    );
    if (to == from || centers[to] == away) return;
    HapticFeedbackService.selection();
    setState(() {
      _order = [...order]
        ..removeAt(from)
        ..insert(to, key);
    });
  }

  void _onAutoscroll(Duration _) {
    if (_lifted == null || _landing || !_scroll.hasClients) return;
    final stack = _stackBox;
    if (stack == null || !stack.hasSize) return;
    final at = stack.globalToLocal(_finger.value).dy;
    final edge = math.min(88.0, stack.size.height / 4);
    double pull = 0;
    if (at < edge) {
      pull = -(edge - at) / edge;
    } else if (at > stack.size.height - edge) {
      pull = (at - (stack.size.height - edge)) / edge;
    }
    if (pull == 0) return;
    final position = _scroll.position;
    final next = (position.pixels + pull.clamp(-1.0, 1.0) * 16).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((next - position.pixels).abs() < 0.5) return;
    _scroll.jumpTo(next);
    _retarget();
  }

  void _liftEnd() {
    final key = _lifted;
    final order = _order;
    if (key == null || order == null || _landing) return;
    _autoscroll.stop();
    final stack = _stackBox;
    final box = _cellBox(key);
    final from = stack?.globalToLocal(_liftedTopLeft);
    final moved = !listEquals(order, _keys);
    if (moved) {
      // Held until the store has it (or gives up on it), so the grid never
      // flicks back to the old order between the drop and the write.
      _orderExpiry?.cancel();
      _orderExpiry = Timer(const Duration(seconds: 2), () {
        if (mounted && _lifted == null) setState(() => _order = null);
      });
      widget.onReorder?.call(key, spaceEditBand(order, _bands, key));
    }
    if (stack == null || box == null || from == null) {
      _landed();
      return;
    }
    final to = stack.globalToLocal(box.localToGlobal(Offset.zero));
    setState(() => _landing = true);
    if (_still) {
      _rise.value = 0;
      _landed();
      return;
    }
    _landAt = to;
    _land.value = from;
    unawaited(_rise.animateTo(0));
    _land.animateTo(to).whenCompleteOrCancel(_landed);
  }

  void _onLanding() {
    final at = _landAt;
    if (!_landing || at == null) return;
    if ((_land.value - at).distance < 0.5) {
      _land.stop();
      _landed();
    }
  }

  void _landed() {
    if (!mounted || (_lifted == null && !_landing)) return;
    _landAt = null;
    _rise.value = 0;
    setState(() {
      _lifted = null;
      _liftedCell = null;
      _landing = false;
      final order = _order;
      if (order != null && listEquals(order, _keys)) _order = null;
    });
    _glideFor(const Duration(milliseconds: 600));
  }

  void _cancelLift() {
    _autoscroll.stop();
    _lifted = null;
    _liftedCell = null;
    _landing = false;
    _landAt = null;
    _order = null;
    _rise.value = 0;
  }

  // ---------------------------------------------------- screen readers

  /// A step within the card's band: sideways in its row, or a row up or
  /// down.
  Map<CustomSemanticsAction, VoidCallback> _moves(
    String key,
    List<String> order,
  ) {
    final reorder = widget.onReorder;
    final item = _byKey[key];
    if (reorder == null || item == null || _lifted != null) return const {};
    final band = spaceEditBand(order, _bands, key);
    final at = band.indexOf(key);
    if (at < 0) return const {};
    final columns = _columnOf(item) || widget.itemWidth != null
        ? 1
        : math.max(1, widget.columns);
    void to(int index) {
      final next = [...band]
        ..removeAt(at)
        ..insert(index, key);
      HapticFeedbackService.selection();
      reorder(key, next);
    }

    final column = at % columns;
    return {
      if (columns > 1 && column > 0)
        const CustomSemanticsAction(label: 'Move left'): () => to(at - 1),
      if (columns > 1 && column < columns - 1 && at < band.length - 1)
        const CustomSemanticsAction(label: 'Move right'): () => to(at + 1),
      if (at - columns >= 0)
        const CustomSemanticsAction(label: 'Move up'): () => to(at - columns),
      if (at + columns < band.length)
        const CustomSemanticsAction(label: 'Move down'): () => to(at + columns),
    };
  }

  // -------------------------------------------------------------- views

  /// A cell as it looks: its circle and its card.
  Widget _cellFace(
    SpaceEditItem item, {
    required bool selected,
    required double width,
  }) {
    return _EditFace(
      item: item,
      width: width,
      selected: selected,
      mark: _markOf(item),
      enter: _enter,
      faceCircle: widget.faceCircle,
      faceTop: widget.faceTop,
    );
  }

  Widget _cell(String k, double width, List<String> order) {
    final item = _byKey[k]!;
    final selected = widget.selected.contains(k);
    return _EditCell(
      key: _cellKey(k),
      item: item,
      width: width,
      lifted: _lifted == k,
      liftedHeight: _liftedSize.height,
      laneInset: _markOf(item) == SpaceEditMark.lane ? kSpaceEditLane : 0,
      glide: _glide,
      face: _cellFace(item, selected: selected, width: width),
      selected: selected,
      moves: _moves(k, order),
      onToggle: () {
        HapticFeedbackService.selection();
        widget.onToggle(k);
      },
      onPointerDown: widget.onReorder == null ? null : (e) => _holdDown(e, k),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gap = widget.gap ?? 12.sp;
    final runSpacing = widget.runSpacing ?? gap;
    final order = _shown;
    final header = widget.header;

    final list = LayoutBuilder(
      builder: (context, constraints) {
        final inner = math.max(0.0, constraints.maxWidth - 2 * widget.gutter);
        final itemWidth = widget.itemWidth;
        final columns = itemWidth != null
            ? math.max(1, ((inner + gap) / (itemWidth + gap)).floor())
            : math.max(1, widget.columns);
        final cellWidth = itemWidth ?? (inner - (columns - 1) * gap) / columns;
        final rows = spaceEditRows(order, _byKey, columns);

        Widget row(BuildContext context, int i) {
          final keys = rows[i];
          final first = _byKey[keys.first]!;
          final Widget content;
          if (keys.length == 1 && (first.wide || columns == 1)) {
            content = _cell(keys.first, first.wide ? inner : cellWidth, order);
          } else {
            content = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var j = 0; j < keys.length; j++) ...[
                  if (j > 0) SizedBox(width: gap),
                  _cell(keys[j], cellWidth, order),
                ],
              ],
            );
          }
          return Padding(
            padding: EdgeInsets.fromLTRB(
              widget.gutter,
              i == 0 ? 0 : runSpacing,
              widget.gutter,
              0,
            ),
            child: Align(alignment: Alignment.topLeft, child: content),
          );
        }

        return IgnorePointer(
          ignoring: widget.closing,
          child: CustomScrollView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(child: SizedBox(height: widget.top)),
              if (header != null) SliverToBoxAdapter(child: header),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  row,
                  childCount: rows.length,
                  // A cell must paint as its row moves, to catch its own
                  // glide; the boards inside keep their own boundaries.
                  addRepaintBoundaries: false,
                ),
              ),
              SliverToBoxAdapter(child: SizedBox(height: widget.bottom)),
            ],
          ),
        );
      },
    );

    return Stack(
      key: _stackKey,
      children: [
        Positioned.fill(child: list),
        if (_liftedCell case final cell?) _liftedLayer(cell),
      ],
    );
  }

  /// The lifted card over the page: risen a little, an opaque card of its
  /// own shape (a grid card's rows over the page's colour, so its names
  /// never lie on the card it passes over) casting one tight shadow from a
  /// light above; following the finger, and flying home once dropped. The
  /// socket it left is the same shape.
  Widget _liftedLayer(Widget cell) {
    final colors = context.colors;
    final light = context.isLightTheme;
    final size = _liftedSize;
    // A fixed rise in points, so a tall board card never balloons.
    final rise = math.min(0.03, 12 / math.max(1.0, size.longestSide));
    final shade = light
        ? colors.shadow.withValues(alpha: math.min(1.0, colors.shadow.a * 1.6))
        : const Color(0xFF000000).withValues(alpha: 0.6);
    return AnimatedBuilder(
      animation: Listenable.merge([_finger, _land, _rise]),
      builder: (context, child) {
        final stack = _stackBox;
        final at = _landing
            ? _land.value
            : (stack == null
                  ? Offset.zero
                  : stack.globalToLocal(_liftedTopLeft));
        final t = _rise.value.clamp(0.0, 1.0);
        final scale = 1 + rise * t;
        return Positioned(
          left: at.dx,
          top: at.dy,
          width: size.width,
          height: size.height,
          child: IgnorePointer(
            child: Transform.scale(
              scale: (scale - 1).abs() < 0.0005 ? 1.0 : scale,
              child: _LiftShadow(
                t: t,
                color: shade,
                ground: colors.background,
                lane: _liftedLane,
                radius: 8.br,
                child: child,
              ),
            ),
          ),
        );
      },
      child: HeroMode(enabled: false, child: ExcludeSemantics(child: cell)),
    );
  }
}

/// A cell's look: its selection circle and its card, the card taking no
/// touch of its own (a tap selects, a hold lifts).
class _EditFace extends StatelessWidget {
  const _EditFace({
    required this.item,
    required this.width,
    required this.selected,
    required this.mark,
    required this.enter,
    required this.faceCircle,
    required this.faceTop,
  });

  final SpaceEditItem item;
  final double width;
  final bool selected;
  final SpaceEditMark mark;
  final Animation<double> enter;
  final double? faceCircle;
  final double faceTop;

  /// How far along [enter] is, with a spring's last hair counted as there.
  static double _grown(Animation<double> enter) {
    final t = enter.value.clamp(0.0, 1.0);
    return t >= 0.999 ? 1.0 : t;
  }

  @override
  Widget build(BuildContext context) {
    final check = SpaceEditCheck(
      key: ValueKey<String>('space_edit_check_${item.key}'),
      selected: selected,
      onPicture: mark == SpaceEditMark.board,
    );
    final size = kSpaceEditCheck;
    // Grows from nothing on the enter spring and shrinks back on the way
    // out, about its own centre.
    Widget growing() => AnimatedBuilder(
      animation: enter,
      builder: (context, child) =>
          Transform.scale(scale: _grown(enter), child: child),
      child: check,
    );
    Widget card(double width) => IgnorePointer(
      child: ExcludeSemantics(child: item.builder(context, width)),
    );

    switch (mark) {
      case SpaceEditMark.lane:
        final lane = kSpaceEditLane;
        return SizedBox(
          width: width,
          child: Row(
            children: [
              // The lane opens on the spring as Edit starts, the circle
              // growing with it from its left edge: the whole lane, scaled,
              // so the circle always fits what is open and nothing cuts it.
              AnimatedBuilder(
                animation: enter,
                builder: (context, child) {
                  final t = _grown(enter);
                  return SizedBox(
                    width: lane * t,
                    height: size,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: 0,
                          top: 0,
                          width: size,
                          height: size,
                          child: Transform.scale(
                            scale: t,
                            alignment: Alignment.centerLeft,
                            child: child,
                          ),
                        ),
                      ],
                    ),
                  );
                },
                child: check,
              ),
              Expanded(child: card(math.max(0.0, width - lane))),
            ],
          ),
        );
      case SpaceEditMark.board:
        return SizedBox(
          width: width,
          child: _OnBoard(
            check: size,
            inset: kSpaceEditBoardInset,
            card: card(width),
            mark: growing(),
          ),
        );
      case SpaceEditMark.face:
        final circle = faceCircle ?? 56;
        // Just outside the circle's rim, top left (45 degrees round from its
        // top), so it frames the face rather than sitting on the initials.
        final r = circle / 2;
        final out = (r + 2.5) * 0.7071;
        final center = Offset(width / 2 - out, faceTop + r - out);
        return SizedBox(
          width: width,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              card(width),
              Positioned(
                left: center.dx - size / 2,
                top: center.dy - size / 2,
                child: growing(),
              ),
            ],
          ),
        );
    }
  }
}

/// One cell of the grid: a tap selects, a finger coming down tells the grid
/// (whose hold lifts the card, when the grid reorders), and a press gives a
/// little under the finger. While its card is lifted it holds the card's
/// place as a recessed socket. Its moves glide ([_SpaceGlide]).
class _EditCell extends StatefulWidget {
  const _EditCell({
    super.key,
    required this.item,
    required this.width,
    required this.lifted,
    required this.liftedHeight,
    required this.laneInset,
    required this.glide,
    required this.face,
    required this.selected,
    required this.moves,
    required this.onToggle,
    required this.onPointerDown,
  });

  final SpaceEditItem item;
  final double width;
  final bool lifted;
  final double liftedHeight;

  /// The lane before the card (its socket starts after it).
  final double laneInset;
  final bool glide;
  final Widget face;
  final bool selected;
  final Map<CustomSemanticsAction, VoidCallback> moves;
  final VoidCallback onToggle;
  final PointerDownEventListener? onPointerDown;

  @override
  State<_EditCell> createState() => _EditCellState();
}

class _EditCellState extends State<_EditCell>
    with SingleTickerProviderStateMixin {
  late final MotionController<Offset> _glide = MotionController<Offset>(
    motion: const CupertinoMotion.snappy(
      duration: Duration(milliseconds: 380),
      snapToEnd: true,
    ),
    vsync: this,
    converter: MotionConverter.offset,
    initialValue: Offset.zero,
  );
  bool _pressed = false;

  @override
  void dispose() {
    _glide.dispose();
    super.dispose();
  }

  void _press(bool value) {
    if (_pressed != value && mounted) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final Widget body;
    if (widget.lifted) {
      body = SizedBox(
        width: widget.width,
        height: widget.liftedHeight,
        child: Padding(
          padding: EdgeInsets.only(left: widget.laneInset),
          child: _Socket(
            key: ValueKey<String>('space_edit_socket_${widget.item.key}'),
          ),
        ),
      );
    } else {
      body = SingleMotionBuilder(
        motion: still ? const Motion.none() : const CupertinoMotion.snappy(),
        value: _pressed ? 0.98 : 1.0,
        builder: (context, scale, child) => Transform.scale(
          scale: (scale - 1).abs() < 0.0005 ? 1.0 : scale,
          child: child,
        ),
        child: widget.face,
      );
    }

    final gestures = <Type, GestureRecognizerFactory>{
      TapGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
            TapGestureRecognizer.new,
            (r) => r
              ..onTapDown = ((_) => _press(true))
              ..onTapUp = ((_) => _press(false))
              ..onTapCancel = (() => _press(false))
              ..onTap = widget.onToggle,
          ),
    };

    return _SpaceGlide(
      controller: _glide,
      active: widget.glide && !still,
      child: Semantics(
        container: true,
        button: true,
        selected: widget.selected,
        label: widget.item.label,
        onTap: widget.onToggle,
        customSemanticsActions: widget.moves,
        child: Listener(
          onPointerDown: widget.onPointerDown,
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: gestures,
            excludeFromSemantics: true,
            child: body,
          ),
        ),
      ),
    );
  }
}

/// The place a lifted card left: a recessed plate of its shape.
class _Socket extends StatelessWidget {
  const _Socket({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.isLightTheme
            ? colors.surfaceRecessed
            : colors.surface.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8.br),
      ),
    );
  }
}

/// The selection circle: a quiet ring, or once selected a disc of the ink
/// with a check knocked out of it. The disc grows from the centre and the
/// check draws itself on one spring, and both go back the same way. The
/// ring stands on a solid disc of the page's own colour, so over a face's
/// photo or a board's square nothing shows through it: the same circle
/// wherever it stands.
class SpaceEditCheck extends StatelessWidget {
  const SpaceEditCheck({
    super.key,
    required this.selected,
    this.onPicture = false,
  });

  final bool selected;

  /// It stands on a picture (a board) rather than the page: a hair of shade
  /// just outside its disc keeps the disc's edge on a light square.
  final bool onPicture;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final size = kSpaceEditCheck;
    return SizedBox.square(
      dimension: size,
      child: SingleMotionBuilder(
        motion: still
            ? const Motion.none()
            : const CupertinoMotion.snappy(
                duration: Duration(milliseconds: 300),
              ),
        value: selected ? 1.0 : 0.0,
        builder: (context, t, _) => CustomPaint(
          painter: _CheckPainter(
            t: t,
            ring: colors.textSecondary,
            ink: colors.textPrimary,
            ground: colors.background,
            edge: onPicture ? const Color(0x47000000) : null,
          ),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  const _CheckPainter({
    required this.t,
    required this.ring,
    required this.ink,
    required this.ground,
    this.edge,
  });

  final double t;
  final Color ring;
  final Color ink;
  final Color ground;

  /// A hair just outside the disc, on a picture.
  final Color? edge;

  @override
  void paint(Canvas canvas, Size size) {
    final p = t.clamp(0.0, 1.0);
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final stroke = size.shortestSide * 0.075;
    // The check's unit: a circle drawn wider (over a board's square) is the
    // same circle, larger.
    final u = size.shortestSide / 22;
    // A solid ground under the ring, so nothing of a photo or a piece shows
    // through it; on a board, a hair of shade just outside, so the disc
    // holds its edge on a light square.
    final edge = this.edge;
    if (edge != null) {
      canvas.drawCircle(
        center,
        radius + 0.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = edge,
      );
    }
    canvas.drawCircle(center, radius, Paint()..color = ground);
    canvas.drawCircle(
      center,
      radius - stroke / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = Color.lerp(ring, ink, p)!,
    );
    if (p <= 0.001) return;
    // The disc, from the centre out (a touch past 1 on the spring's
    // overshoot is held at the rim).
    canvas.drawCircle(center, radius * p.clamp(0.0, 1.0), Paint()..color = ink);
    // The check, drawing itself along its two strokes, its box centred on
    // the disc (the heavy bottom vertex would read low if it sat lower).
    final a = center + Offset(-5.25 * u, 0.05 * u);
    final b = center + Offset(-1.65 * u, 3.55 * u);
    final c = center + Offset(5.35 * u, -3.75 * u);
    final first = (a - b).distance;
    final second = (c - b).distance;
    final drawn = (first + second) * ((p - 0.25) / 0.75).clamp(0.0, 1.0);
    if (drawn <= 0) return;
    final path = Path()..moveTo(a.dx, a.dy);
    if (drawn <= first) {
      final q = Offset.lerp(a, b, drawn / first)!;
      path.lineTo(q.dx, q.dy);
    } else {
      path.lineTo(b.dx, b.dy);
      final q = Offset.lerp(b, c, (drawn - first) / second)!;
      path.lineTo(q.dx, q.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2 * u
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = ground,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) =>
      old.t != t ||
      old.ring != ring ||
      old.ink != ink ||
      old.ground != ground ||
      old.edge != edge;
}

/// A card with its circle on its board, over the board's top-left square
/// ([spaceEditBoardCheckRect]): the card keeps its width and its place, and
/// the circle covers that one square, as a photo's sits on the photo. The
/// board is found in the laid-out card ([spaceEditBoardIn]); a card with
/// none wears the circle at its own top left.
class _OnBoard extends MultiChildRenderObjectWidget {
  _OnBoard({
    required Widget card,
    required Widget mark,
    required this.check,
    required this.inset,
  }) : super(children: [card, mark]);

  final double check;
  final double inset;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderOnBoard(check, inset);

  @override
  void updateRenderObject(BuildContext context, _RenderOnBoard render) {
    render
      ..check = check
      ..inset = inset;
  }
}

class _OnBoardData extends ContainerBoxParentData<RenderBox> {}

class _RenderOnBoard extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _OnBoardData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _OnBoardData> {
  _RenderOnBoard(this._check, this._inset);

  double _check;
  double _inset;

  set check(double value) {
    if (value == _check) return;
    _check = value;
    markNeedsLayout();
  }

  set inset(double value) {
    if (value == _inset) return;
    _inset = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _OnBoardData) child.parentData = _OnBoardData();
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      firstChild?.getMinIntrinsicWidth(height) ?? 0;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      firstChild?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  double computeMinIntrinsicHeight(double width) =>
      firstChild?.getMinIntrinsicHeight(width) ?? 0;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      firstChild?.getMaxIntrinsicHeight(width) ?? 0;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      firstChild?.getDryLayout(constraints) ?? constraints.smallest;

  @override
  void performLayout() {
    final card = firstChild;
    if (card == null) {
      size = constraints.smallest;
      return;
    }
    card.layout(constraints, parentUsesSize: true);
    size = constraints.constrain(card.size);
    (card.parentData! as _OnBoardData).offset = Offset.zero;
    final mark = childAfter(card);
    if (mark == null) return;
    Rect? board;
    // The card's own boxes are read, not only the card's size: allowed
    // from a layout callback.
    invokeLayoutCallback<BoxConstraints>((_) {
      board = spaceEditBoardIn(card);
    });
    final at = spaceEditBoardCheckRect(board, _check, _inset);
    mark.layout(BoxConstraints.tight(at.size));
    (mark.parentData! as _OnBoardData).offset = at.topLeft;
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// A lifted card's body and its one shadow: the card's shape (after its
/// lane) filled with the page's colour under the card, so a card with no
/// surface of its own (a grid card's rows) is opaque while it is carried,
/// and a shadow of that shape, tight, soft and a little below, as from a
/// light above. [t] is how far the card has risen.
class _LiftShadow extends SingleChildRenderObjectWidget {
  const _LiftShadow({
    required this.t,
    required this.color,
    required this.ground,
    required this.lane,
    required this.radius,
    super.child,
  });

  final double t;
  final Color color;
  final Color ground;
  final double lane;
  final double radius;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLiftShadow(t, color, ground, lane, radius);

  @override
  void updateRenderObject(BuildContext context, _RenderLiftShadow render) {
    render
      ..t = t
      ..color = color
      ..ground = ground
      ..lane = lane
      ..radius = radius;
  }
}

class _RenderLiftShadow extends RenderProxyBox {
  _RenderLiftShadow(
    this._t,
    this._color,
    this._ground,
    this._lane,
    this._radius,
  );

  double _t;
  Color _color;
  Color _ground;
  double _lane;
  double _radius;

  set t(double value) {
    if (value == _t) return;
    _t = value;
    markNeedsPaint();
  }

  set color(Color value) {
    if (value == _color) return;
    _color = value;
    markNeedsPaint();
  }

  set ground(Color value) {
    if (value == _ground) return;
    _ground = value;
    markNeedsPaint();
  }

  set lane(double value) {
    if (value == _lane) return;
    _lane = value;
    markNeedsPaint();
  }

  set radius(double value) {
    if (value == _radius) return;
    _radius = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final body = RRect.fromRectAndRadius(
      Rect.fromLTRB(math.min(_lane, size.width), 0, size.width, size.height),
      Radius.circular(_radius),
    ).shift(offset);
    final canvas = context.canvas;
    if (_t > 0.001) {
      final shadow = BoxShadow(
        color: _color.withValues(alpha: _color.a * _t),
        blurRadius: 12,
        spreadRadius: -4,
        offset: Offset(0, 5 * _t),
      );
      canvas.drawRRect(
        body.shift(shadow.offset).inflate(shadow.spreadRadius),
        shadow.toPaint(),
      );
    }
    canvas.drawRRect(body, Paint()..color = _ground);
    super.paint(context, offset);
  }
}

/// Glides its child from where it was painted to where it now lays out
/// whenever its place in the scrolling page changes while [active] (the grid
/// is reordering, or a removal closed a gap), even when the move took it to
/// another row. The move is caught in paint, the frame it happens, so the
/// card never flashes at its new place first. Places are read against the
/// page's content (the viewport plus how far it has scrolled), so a scroll
/// never reads as a move.
class _SpaceGlide extends SingleChildRenderObjectWidget {
  const _SpaceGlide({
    required this.controller,
    required this.active,
    super.child,
  });

  final MotionController<Offset> controller;
  final bool active;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSpaceGlide(controller, active);

  @override
  void updateRenderObject(BuildContext context, _RenderSpaceGlide render) {
    render
      ..controller = controller
      ..active = active;
  }
}

class _RenderSpaceGlide extends RenderProxyBox {
  _RenderSpaceGlide(this._controller, this.active);

  MotionController<Offset> _controller;
  bool active;

  /// Where on the page this cell was last painted. Kept across a move to
  /// another row (the cell keeps its render object), so that move glides.
  Offset? _last;

  /// The shift painted this frame, before the spring takes it over.
  Offset? _pending;

  set controller(MotionController<Offset> value) {
    if (identical(value, _controller)) return;
    if (attached) _controller.removeListener(markNeedsPaint);
    _controller = value;
    if (attached) _controller.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  Offset get _shift => _pending ?? _controller.value;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _controller.removeListener(markNeedsPaint);
    super.detach();
  }

  /// This cell's top left on the page's content, or null outside a
  /// scrolling page.
  Offset? _onPage() {
    final viewport = RenderAbstractViewport.maybeOf(this);
    if (viewport is! RenderViewportBase) return null;
    final at = MatrixUtils.transformPoint(
      getTransformTo(viewport),
      Offset.zero,
    );
    final offset = viewport.offset;
    final pixels = offset.hasPixels ? offset.pixels : 0.0;
    return viewport.axis == Axis.vertical
        ? at + Offset(0, pixels)
        : at + Offset(pixels, 0);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final now = _onPage();
    final last = _last;
    _last = now;
    if (active && now != null && last != null && (last - now).distance > 0.5) {
      final from = _shift + (last - now);
      _pending = from;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (_pending != from || !attached) return;
        _pending = null;
        _controller.value = from;
        unawaited(_controller.animateTo(Offset.zero));
      });
    }
    final child = this.child;
    if (child == null) return;
    context.paintChild(child, offset + _shift);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return result.addWithPaintOffset(
      offset: _shift,
      position: position,
      hitTest: (result, transformed) =>
          super.hitTestChildren(result, position: transformed),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final shift = _shift;
    transform.translateByDouble(shift.dx, shift.dy, 0, 1);
  }
}
