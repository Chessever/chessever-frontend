import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/screens/board_editor/board_editor_screen.dart';
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/my_space/actions/space_share.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/navigation/space_shortcut_navigator.dart'
    show spaceShortcutFen;
import 'package:chessever2/screens/my_space/widgets/space_glyphs.dart';
import 'package:chessever2/screens/my_space/widgets/space_metrics.dart';
import 'package:chessever2/screens/my_space/widgets/space_reorder.dart';
import 'package:chessever2/screens/my_space/widgets/space_tile_content.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:collection/collection.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:motor/motor.dart';
import 'package:share_plus/share_plus.dart';

/// How long a finger must rest on a tile before the tile owns the pointer.
/// Any movement past touch slop before this fires hands the gesture to the
/// page (or to the rail, for sideways moves). After it, a sideways slide
/// reorders; an up or down move is still the page's scroll, handed back to
/// it, because a scroll that hesitated on a tile looks exactly like this.
const Duration kSpaceTileGrabDelay = Duration(milliseconds: 200);

/// Press-and-hold without moving opens the tile's menu. It is also the hold
/// that throwing a tile out needs: only a tile held this long, menu up, can
/// be pulled out of My Space, so no scroll or flick ever removes one.
const Duration kSpaceTileLongPress = Duration(milliseconds: 450);

/// How far a grabbed finger travels before it commits to one gesture: up or
/// down to the page's scroll, sideways to reorder.
const double _kAxisLock = 8;

/// How far the finger has to slide once the menu is open before the menu
/// steps aside and the same press carries the tile instead.
const double _kMenuHandoff = 10;

/// The lifted scale, shared by the menu and a drag so one flows into the other.
const double _kLift = 1.04;

/// Edge auto-scroll speed, per pixel the lifted tile overhangs the edge
/// (the value Flutter's own reorderable lists use).
const double _kAutoScrollVelocity = 50;

/// A spring given as the spec gives it: stiffness and damping on unit mass.
SpringMotion _spring(double stiffness, double damping) => SpringMotion(
  SpringDescription(mass: 1, stiffness: stiffness, damping: damping),
  snapToEnd: true,
);

/// The spec's default follow spring.
final SpringMotion _kFollow = _spring(520, 38);

/// One tile in a My Space rail, with its whole gesture vocabulary:
///
/// * tap opens it,
/// * press scales it to 0.97,
/// * grab and slide sideways lifts it to 1.04 and carries it to a new place;
///   its neighbours make room as it goes and it springs into the slot it is
///   dropped on (in the "See all" grid, up and down too once held, or at
///   once where the page cannot scroll),
/// * grab and move up or down scrolls the page, as if the tile were not
///   there,
/// * hold without moving lifts it to 1.04 and opens Open / Move to front /
///   Share / Remove; sliding on from there closes the menu and carries the
///   tile, the same press, like the iOS home screen. In a rail, pulling up
///   from there instead throws it out of My Space past 90pt (or on a flick
///   that has travelled at least 40% of that), revealing a bin under it that
///   turns red at the point of no return.
///
/// Neighbours slide into a freed slot on their own: every tile knows its slot
/// ([slotX], [slotY]) and springs from the old one to the new one whenever it
/// changes, keeping whatever speed it already had (the same FLIP handles
/// removal, undo, move-to-front and every step of a reorder).
class SpaceTile extends StatefulWidget {
  const SpaceTile({
    super.key,
    required this.shortcut,
    required this.onOpen,
    required this.onMoveToFront,
    required this.onRemove,
    this.slotX = 0,
    this.slotY = 0,
    this.entering = false,
    this.swipeToRemove = true,
    this.canMoveToFront = true,
    this.reorder,
    this.holdToGrab = true,
    this.menuActions,
    this.subtitle,
  });

  final SpaceShortcut shortcut;
  final VoidCallback onOpen;
  final FutureOr<void> Function() onMoveToFront;

  /// Commits the removal once the tile has flown out. Resolves false when
  /// nothing was removed, and the tile settles back into place.
  final Future<bool> Function() onRemove;

  /// Left edge of this tile's slot inside its rail or grid.
  final double slotX;

  /// Top edge of this tile's slot inside its grid (0 in a rail).
  final double slotY;

  /// Pops in from 0.9 (an Undo, or an item that arrived while visible). Only
  /// scale moves; the tile is fully opaque from its first frame.
  final bool entering;

  /// Off where tiles do not sit in a single rail (the "See all" grid).
  final bool swipeToRemove;

  final bool canMoveToFront;

  /// Null where the tile cannot move (a row with one tile).
  final SpaceTileReorder? reorder;

  /// Off for a tile that is shown rather than pinned (a Library or My Likes
  /// mirror, a suggestion): it cannot be carried or thrown out, so it never
  /// takes the pointer from the rail or the page. A plain long press opens
  /// its menu instead, and every scroll starts at once.
  final bool holdToGrab;

  /// Replaces the pinned tile's menu (Open, Move to front, Share, Remove)
  /// with the tile's own actions, Open included.
  final List<LibraryMenuAction> Function(BuildContext context)? menuActions;

  /// A live second line for glyph tiles; see [SpaceTileContent.subtitle].
  final Widget? subtitle;

  @override
  State<SpaceTile> createState() => _SpaceTileState();
}

class _SpaceTileState extends State<SpaceTile>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  final Map<String, SingleMotionController> _springs = {};

  /// Ticks whenever any spring moves. Only the painted face listens, so a
  /// spring frame never rebuilds the recognizer, the semantics or the board.
  final _frame = _FrameTicker();

  Timer? _longPressTimer;
  Timer? _flyTimer;
  Timer? _pressTimer;

  bool _grabbed = false;
  bool _live = false;
  bool _menuOpen = false;
  bool _flying = false;
  bool _pressed = false;
  bool _pastThreshold = false;
  Offset _travel = Offset.zero;
  Offset _pressOrigin = Offset.zero;
  int? _pointer;

  // An up or down move before the hold belongs to the page: [_paged] from
  // the moment it is handed over until the finger lifts, [_pageDrag] while
  // the page's scroll is still following it.
  bool _paged = false;
  Drag? _pageDrag;
  ScrollPhysics? _pagePhysics;

  // Reorder: [_dragging] while the finger carries the tile, [_floating] from
  // the lift until it has landed in its slot again.
  bool _dragging = false;
  bool _floating = false;
  Offset _liftSlot = Offset.zero;
  Offset _liftGlobal = Offset.zero;
  Offset _liftScroll = Offset.zero;
  Offset _dragBase = Offset.zero;
  ScrollableState? _scrollable;
  EdgeDraggingAutoScroller? _autoScroller;
  int _landing = 0;

  // The lifted face is painted in the overlay so it passes over its
  // neighbours; the GlobalKey carries the built board or avatar there and
  // back without rebuilding it.
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  final _contentKey = GlobalKey();

  LibraryContextMenuHandle? _menuHandle;
  Offset _menuTravel = Offset.zero;
  int _menuSession = 0;

  /// While the menu's lifted copy covers the tile, the tile itself is not
  /// painted, so the blur behind the copy never shows a second face around
  /// it. [_liftToken] retires a menu's report once the tile has already been
  /// handed back (a drag, a throw, a removal).
  bool _underMenu = false;
  int _liftToken = 0;

  /// Whether the first dependencies (and so the reduce-motion setting) have
  /// been read; the entering pop waits for them.
  bool _started = false;

  double get _threshold => SpaceMetrics.removeThreshold.w;

  /// The system's reduce-motion setting: every spring lands at once.
  bool _reduceMotion = false;

  Motion _motion(Motion m) => _reduceMotion ? const Motion.none() : m;

  @override
  bool get wantKeepAlive => _dragging || _floating;

  /// Built once per shortcut: spring ticks rebuild only the transform around
  /// it, never the board or the avatar inside.
  late Widget _content = _buildContent();

  Widget _buildContent() => RepaintBoundary(
    key: _contentKey,
    child: SpaceTileContent(
      shortcut: widget.shortcut,
      subtitle: widget.subtitle,
    ),
  );

  /// Whether two copies of a shortcut paint the same tile. Its place and open
  /// count do not show, so a reorder or an open never rebuilds the face.
  static bool _sameFace(SpaceShortcut a, SpaceShortcut b) =>
      identical(a, b) ||
      (a.key == b.key &&
          a.title == b.title &&
          a.subtitle == b.subtitle &&
          const DeepCollectionEquality().equals(a.params, b.params));

  // ---------------------------------------------------------------- springs

  SingleMotionController _c(String key, [double initial = 0]) {
    return _springs.putIfAbsent(key, () {
      final c = SingleMotionController(
        motion: _kFollow,
        vsync: this,
        initialValue: initial,
      );
      c.addListener(_frame.tick);
      return c;
    });
  }

  double _v(String key, [double fallback = 0]) =>
      _springs[key]?.value ?? fallback;

  void _jump(String key, double value, {double initial = 0}) {
    _c(key, initial).value = value;
  }

  TickerFuture _to(
    String key,
    double target, {
    Motion? motion,
    double? velocity,
    double initial = 0,
  }) {
    final c = _c(key, initial);
    c.motion = _motion(motion ?? _kFollow);
    return c.animateTo(target, withVelocity: velocity);
  }

  /// FLIP for a slot that moved by [moved]: paint where the tile was, then
  /// spring home. A tile already sliding keeps its speed, so a finger sweeping
  /// back and forth over a row moves its neighbours like one fluid thing.
  void _flip(String key, double moved) {
    final c = _c(key);
    final velocity = c.velocity;
    c.motion = _motion(const CupertinoMotion.snappy(snapToEnd: true));
    c.animateTo(0, from: c.value + moved, withVelocity: velocity);
  }

  // ---------------------------------------------------------------- life

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_started) return;
    _started = true;
    // Read here rather than in initState, where the setting is not yet
    // available: under reduced motion the tile simply appears at full size.
    if (widget.entering && !_reduceMotion) {
      _jump('s', 0.9, initial: 1);
      _to('s', 1, motion: _spring(380, 18), initial: 1);
    }
  }

  @override
  void didUpdateWidget(SpaceTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameFace(oldWidget.shortcut, widget.shortcut) ||
        oldWidget.subtitle.runtimeType != widget.subtitle.runtimeType ||
        oldWidget.subtitle?.key != widget.subtitle?.key) {
      _content = _buildContent();
    }
    final movedX = oldWidget.slotX - widget.slotX;
    final movedY = oldWidget.slotY - widget.slotY;
    if (movedX.abs() <= 0.5 && movedY.abs() <= 0.5) return;
    if (_dragging) {
      // The finger holds the tile; its slot moved under it. Nothing is
      // reported from here, the host is mid-build.
      _applyDrag(report: false);
      return;
    }
    if (_flying) return;
    if (movedX.abs() > 0.5) _flip('shift', movedX);
    if (movedY.abs() > 0.5) _flip('shiftY', movedY);
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _flyTimer?.cancel();
    _pressTimer?.cancel();
    _endDragSession();
    // A page scroll still following this press must not be left mid-drag.
    // Ending it dispatches scroll notifications, which cannot run while the
    // tree is being torn down, so it ends right after; if the page went
    // away too, its own disposal already ended it and cleared the field.
    final page = _pageDrag;
    if (page != null) {
      scheduleMicrotask(() {
        if (!identical(_pageDrag, page)) return;
        _pageDrag = null;
        page.cancel();
      });
    }
    for (final c in _springs.values) {
      c.dispose();
    }
    _frame.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- press

  void _onPointerDown(PointerDownEvent event) {
    if (_flying || _menuOpen || _dragging || _paged) return;
    _pressed = true;
    _pointer = event.pointer;
    _pressOrigin = event.position;
    // A beat before the press shows, so flinging the page across a rail does
    // not ripple every tile the finger lands on.
    _pressTimer?.cancel();
    _pressTimer = Timer(const Duration(milliseconds: 70), () {
      if (_pressed && !_live && !_menuOpen && !_flying && !_dragging) {
        _to('s', 0.97, initial: 1);
      }
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    // Before the grab the page or the rail may take the gesture; the moment
    // the finger travels, let go of the pressed look.
    if (!_pressed || _grabbed) return;
    if ((event.position - _pressOrigin).distance > kTouchSlop) _unpress();
  }

  void _unpress() {
    _pressTimer?.cancel();
    if (!_pressed) return;
    _pressed = false;
    if (!_live && !_menuOpen && !_flying && !_dragging) {
      _to('s', 1, initial: 1);
    }
  }

  // ---------------------------------------------------------------- grab

  Drag? _onGrab(Offset position) {
    if (_flying || _menuOpen || _dragging || _paged) return null;
    _grabbed = true;
    _live = false;
    _pastThreshold = false;
    _travel = Offset.zero;
    _longPressTimer?.cancel();
    _longPressTimer = Timer(
      kSpaceTileLongPress - kSpaceTileGrabDelay,
      _openMenu,
    );
    return _TileDrag(this);
  }

  void _dragUpdate(DragUpdateDetails details) {
    if (!_grabbed || _flying) return;
    _travel += details.delta;

    if (_paged) {
      final dy = details.delta.dy;
      _pageDrag?.update(
        DragUpdateDetails(
          globalPosition: details.globalPosition,
          localPosition: details.localPosition,
          sourceTimeStamp: details.sourceTimeStamp,
          delta: Offset(0, dy),
          primaryDelta: dy,
        ),
      );
      return;
    }

    if (_menuOpen) {
      _menuTravel += details.delta;
      if (_menuTravel.distance <= _kMenuHandoff) return;
      final vertical = _menuTravel.dy.abs() > _menuTravel.dx.abs();
      if (widget.swipeToRemove && vertical) {
        // Held long enough to own the tile: up or down is the throw-out.
        _handMenuToThrow();
      } else if (widget.reorder != null) {
        _handMenuToDrag();
        return;
      } else {
        return;
      }
    } else if (_dragging) {
      _applyDrag();
      return;
    } else if (!_live) {
      // Before the hold, the tile only ever answers a sideways slide. Up or
      // down belongs to the page, since a scroll that paused on a tile looks
      // just like this; throwing a tile out needs the hold (see above).
      final ax = _travel.dx.abs();
      final ay = _travel.dy.abs();
      final reorder = widget.reorder;
      if (ay > _kAxisLock && ay >= ax) {
        if (_handToPage(details)) return;
        // Nothing to scroll. A grid still reorders up and down; a rail
        // waits for the hold, and a finger that has clearly moved was not
        // holding still.
        if (reorder != null && reorder.axis == SpaceReorderAxis.free) {
          _startDrag();
          return;
        }
        if (ay > kTouchSlop) _longPressTimer?.cancel();
        return;
      }
      if (ax > _kAxisLock) {
        if (reorder != null) {
          _startDrag();
          return;
        }
        // Nothing to reorder in a row of one, and a finger that wandered
        // off sideways was not holding still: no menu either.
        if (ax > kTouchSlop) _longPressTimer?.cancel();
      }
      return;
    }

    final raw = _travel.dy;
    final up = math.min(0.0, raw);
    // Follows the finger 1:1 up to the threshold, then rubber-bands at 0.4.
    var dy = up > -_threshold ? up : -_threshold + (up + _threshold) * 0.4;
    if (raw > 0) dy = raw * 0.25;

    _jump('dy', dy);
    _jump('dx', _travel.dx * 0.15);
    _to('rot', _travel.dx * 0.04);
    _to('s', 1 - math.min(0.06, math.max(0.0, -dy) / 1500), initial: 1);

    final past = -dy >= _threshold;
    if (past != _pastThreshold) {
      _pastThreshold = past;
      if (past) HapticFeedbackService.selection();
    }
  }

  void _dragEnd(DragEndDetails details) {
    _longPressTimer?.cancel();
    if (_dragging) {
      _drop(details.velocity.pixelsPerSecond);
      return;
    }
    if (!_grabbed) return;
    _grabbed = false;
    _pressed = false;
    if (_paged) {
      _releasePage(details.velocity.pixelsPerSecond.dy);
      return;
    }
    if (_menuOpen || _flying) return;

    if (!_live) {
      _to('s', 1, initial: 1);
      // Held briefly and let go in place: still a tap. A sideways wander
      // that never became a swipe is not.
      if (_travel.distance <= kTouchSlop) widget.onOpen();
      return;
    }
    _live = false;

    final vy = details.velocity.pixelsPerSecond.dy;
    final lift = -_v('dy');
    // Past the line (the bin reads "Let go") always removes. Short of it, a
    // flick only removes once the tile has really travelled: speed alone is
    // not intent.
    if (lift >= _threshold || (lift >= 0.4 * _threshold && vy < -550)) {
      _flyAway(math.min(-600.0, vy));
      return;
    }
    _settle(velocity: lift < 0 ? vy * 0.25 : vy);
  }

  void _dragCancel() {
    _longPressTimer?.cancel();
    if (_dragging) {
      _drop(Offset.zero, cancelled: true);
      return;
    }
    _grabbed = false;
    _pressed = false;
    _live = false;
    if (_paged) {
      _releasePage(null);
      return;
    }
    if (!_flying && !_menuOpen) _settle();
  }

  // ---------------------------------------------------------------- page

  /// Hands an up or down move back to the page's own scroll, carrying the
  /// travel so far so the page picks up exactly under the finger. False when
  /// there is no page that can scroll.
  bool _handToPage(DragUpdateDetails details) {
    final position = Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
    if (position == null ||
        !position.hasContentDimensions ||
        !position.physics.shouldAcceptUserOffset(position)) {
      return false;
    }
    _paged = true;
    _longPressTimer?.cancel();
    _unpress();
    _pagePhysics = position.physics;
    final dy = _travel.dy;
    final start = details.globalPosition - Offset(0, dy);
    late final Drag drag;
    drag = _pageDrag = position.drag(
      DragStartDetails(
        globalPosition: start,
        localPosition: details.localPosition - Offset(0, dy),
        sourceTimeStamp: details.sourceTimeStamp,
      ),
      // The page ends the drag itself when something else takes it over
      // (another touch, a programmatic scroll, the page going away).
      () {
        if (identical(_pageDrag, drag)) _pageDrag = null;
      },
    );
    drag.update(
      DragUpdateDetails(
        globalPosition: details.globalPosition,
        localPosition: details.localPosition,
        sourceTimeStamp: details.sourceTimeStamp,
        delta: Offset(0, dy),
        primaryDelta: dy,
      ),
    );
    return true;
  }

  /// Lets the page's scroll go on its own: a fling at the release speed, or
  /// a plain stop when [velocity] is null (the press was cancelled).
  void _releasePage(double? velocity) {
    _paged = false;
    final drag = _pageDrag;
    final physics = _pagePhysics;
    _pageDrag = null;
    _pagePhysics = null;
    if (drag == null) return;
    if (velocity == null) {
      drag.cancel();
      return;
    }
    // The same fling gate the page's own drag recognizer applies.
    var vy = velocity;
    if (physics != null) {
      vy = vy.abs() < physics.minFlingVelocity
          ? 0.0
          : vy.clamp(-physics.maxFlingVelocity, physics.maxFlingVelocity);
    }
    drag.end(
      DragEndDetails(
        velocity: Velocity(pixelsPerSecond: Offset(0, vy)),
        primaryVelocity: vy,
      ),
    );
  }

  void _settle({double velocity = 0}) {
    _to('dy', 0, velocity: velocity, motion: _spring(520, 30));
    _to('dx', 0);
    _to('rot', 0);
    _to('s', 1, motion: _spring(420, 20), initial: 1);
  }

  // ---------------------------------------------------------------- reorder

  /// Lifts the tile off its slot and hands it to the finger.
  void _startDrag() {
    final reorder = widget.reorder;
    if (reorder == null || !mounted) return;
    _longPressTimer?.cancel();
    _pressTimer?.cancel();
    _pressed = false;

    final box = context.findRenderObject();
    _liftGlobal = box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero)
        : Offset.zero;
    // Whatever the tile was still doing (a neighbour's slide, a landing)
    // folds into where the finger picks it up.
    _dragBase = Offset(_v('dx') + _v('shift'), _v('dy') + _v('shiftY'));
    _jump('shift', 0);
    _jump('shiftY', 0);
    _liftSlot = Offset(widget.slotX, widget.slotY);

    _scrollable = Scrollable.maybeOf(context);
    _liftScroll = _scrollable?.deltaToScrollOrigin ?? Offset.zero;
    _scrollable?.position.addListener(_onScroll);
    final scrollable = _scrollable;
    _autoScroller = scrollable == null
        ? null
        : EdgeDraggingAutoScroller(
            scrollable,
            velocityScalar: _kAutoScrollVelocity,
          );

    _landing++;
    setState(() {
      _dragging = true;
      _floating = true;
    });
    _portal.show();
    updateKeepAlive();

    HapticFeedbackService.medium();
    _to('s', _kLift, motion: const CupertinoMotion.snappy(), initial: 1);
    _to('rot', 0);
    reorder.onStart();
    _applyDrag();
  }

  /// Puts the lifted tile under the finger: its travel, plus however far the
  /// list scrolled underneath, minus however far its own slot moved.
  void _applyDrag({bool report = true}) {
    final reorder = widget.reorder;
    if (!_dragging || reorder == null) return;
    final rail = reorder.axis == SpaceReorderAxis.horizontal;
    final lean = 16.w;
    final travel = rail
        ? Offset(_travel.dx, (_travel.dy * 0.15).clamp(-lean, lean))
        : _travel;
    final scroll =
        (_scrollable?.deltaToScrollOrigin ?? Offset.zero) - _liftScroll;
    final slotShift = Offset(widget.slotX, widget.slotY) - _liftSlot;
    final offset = _dragBase + travel + scroll - slotShift;
    _jump('dx', offset.dx);
    _jump('dy', offset.dy);
    if (!report) return;

    final size = Size(widget.shortcut.kind.tileWidth, SpaceMetrics.railHeight);
    reorder.onMove(
      _liftSlot + _dragBase + travel + scroll + size.center(Offset.zero),
    );
    _autoScroller?.startAutoScrollIfNecessary(
      (_liftGlobal + _dragBase + travel) & size,
    );
  }

  void _onScroll() {
    if (!_dragging) return;
    // Scroll positions can move during layout (a row that shrank); report
    // once the frame is done rather than rebuilding the host mid-layout.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted && _dragging) _applyDrag();
      });
      return;
    }
    _applyDrag();
  }

  void _endDragSession() {
    _autoScroller?.stopAutoScroll();
    _autoScroller = null;
    _scrollable?.position.removeListener(_onScroll);
    _scrollable = null;
    _dragging = false;
  }

  /// The drop: the host commits the new order, and the tile springs from
  /// under the finger into its slot at the speed it was let go.
  void _drop(Offset velocity, {bool cancelled = false}) {
    final reorder = widget.reorder;
    final rail = reorder?.axis != SpaceReorderAxis.free;
    _endDragSession();
    _grabbed = false;
    _pressed = false;
    if (cancelled) {
      reorder?.onCancel();
    } else {
      reorder?.onEnd();
    }

    final landing = ++_landing;
    final home = const CupertinoMotion.snappy(snapToEnd: true);
    final landed = Future.wait([
      _to('dx', 0, motion: home, velocity: velocity.dx).orCancel,
      _to('dy', 0, motion: home, velocity: rail ? 0 : velocity.dy).orCancel,
    ]);
    _to('s', 1, motion: _spring(420, 20), initial: 1);
    _to('rot', 0);
    landed.then((_) => _land(landing), onError: (Object _) {});
    setState(() {});
    updateKeepAlive();
  }

  void _land(int landing) {
    if (!mounted || landing != _landing || _dragging) return;
    setState(() => _floating = false);
    _portal.hide();
    updateKeepAlive();
  }

  // ---------------------------------------------------------------- remove

  double get _binOpacity {
    if (_floating && !_flying) return 0;
    final progress = (-_v('dy') / _threshold).clamp(0.0, 1.0);
    return _flying ? _v('bin') : math.max(progress, _v('bin'));
  }

  void _flyAway(double velocity) {
    if (_flying) return;
    // The bin fades from wherever it stood instead of staying lit under a
    // tile that is already gone.
    final bin = _binOpacity;
    _flying = true;
    HapticFeedbackService.light();
    _jump('bin', bin);
    _to('bin', 0);
    _to('dy', -300.w, velocity: velocity, motion: _spring(180, 22));
    _to('op', 0, motion: _spring(300, 30), initial: 1);
    _to('s', 0.86, initial: 1);
    _flyTimer = Timer(const Duration(milliseconds: 170), () async {
      final removed = await widget.onRemove();
      if (!removed && mounted) {
        _flying = false;
        _jump('op', 1, initial: 1);
        _settle();
      }
    });
  }

  // ---------------------------------------------------------------- menu

  Future<void> _openMenu() async {
    if (!mounted || _live || _flying || _menuOpen || _dragging || _paged) {
      return;
    }
    _menuOpen = true;
    _menuTravel = Offset.zero;
    final session = ++_menuSession;
    // Under reduced motion the menu's copy does not lift either, and the
    // tile stays exactly the size of the copy that covers it.
    _to(
      's',
      _reduceMotion ? 1 : _kLift,
      motion: const CupertinoMotion.bouncy(),
      initial: 1,
    );
    // Only a tile that can move (or be pulled out) needs the press to
    // outlive the menu.
    if (_grabbed && (widget.reorder != null || widget.swipeToRemove)) {
      _keepPointerThroughMenu();
    }

    final lift = ++_liftToken;
    final handle = _menuHandle = LibraryContextMenuHandle();
    await showLibraryContextMenu(
      context: context,
      previewBuilder: _preview,
      onPreviewTap: widget.onOpen,
      handle: handle,
      origin: _pressOrigin,
      onPreviewLiftChanged: (lifted) {
        if (mounted && lift == _liftToken) _setUnderMenu(lifted);
      },
      actions: _menuActions(),
    );

    // A menu that stepped aside for a drag must not reset the tile it left.
    if (!mounted || session != _menuSession) return;
    _menuHandle = null;
    _menuOpen = false;
    _grabbed = false;
    _pressed = false;
    if (!_flying) _to('s', 1, initial: 1);
  }

  /// The finger slid on after the menu opened: the menu closes as if its
  /// scrim were tapped and the same press lifts the tile into a drag.
  void _handMenuToDrag() {
    _stepMenuAside();
    _startDrag();
  }

  /// The finger pulled up or down after the menu opened: the menu closes the
  /// same way and the press becomes the throw-out, which only a tile held
  /// this long can start.
  void _handMenuToThrow() {
    _stepMenuAside();
    _live = true;
    _longPressTimer?.cancel();
  }

  void _stepMenuAside() {
    _menuSession++;
    _menuOpen = false;
    _menuHandle?.close();
    _menuHandle = null;
    _revealFromMenu();
  }

  void _setUnderMenu(bool value) {
    if (_underMenu == value) return;
    _underMenu = value;
    _frame.tick();
  }

  /// Paints the tile again at once, ahead of the menu's own report, because
  /// the tile is about to move while the copy is still settling back.
  void _revealFromMenu() {
    _liftToken++;
    _setUnderMenu(false);
  }

  /// A screen reader's long press: the same menu, opening from the tile's
  /// centre.
  void _openMenuFromSemantics() {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      _pressOrigin = box.localToGlobal(box.size.center(Offset.zero));
    }
    unawaited(_openMenu());
  }

  /// Pushing a route cancels every pointer its navigator saw go down
  /// (`NavigatorState._cancelActivePointers`), which would end this press the
  /// moment the menu opens. For the press to turn into a drag later it has to
  /// outlive the menu. The navigator tracks pointers through the `Listener`
  /// at the root of its own subtree; telling that listener this pointer is
  /// done drops it from the set without touching the gesture itself. Should
  /// the navigator ever be built differently this does nothing, and the menu
  /// ends the press exactly as it always did.
  void _keepPointerThroughMenu() {
    final pointer = _pointer;
    if (pointer == null) return;
    final navigator = Navigator.maybeOf(context, rootNavigator: true);
    final listener = navigator?.context.findRenderObject();
    if (listener is RenderPointerListener) {
      listener.onPointerCancel?.call(PointerCancelEvent(pointer: pointer));
    }
  }

  List<LibraryMenuAction> _menuActions() {
    final url = spaceShortcutShareUrl(widget.shortcut);
    final messenger = ScaffoldMessenger.maybeOf(context);

    // A chosen action ends the press that opened the menu, so a finger still
    // resting on the tile cannot turn into a drag while the action runs. An
    // action that moves the tile shows it at once; the rest leave it hidden
    // until the copy above it has settled back.
    FutureOr<void> Function() chosen(
      FutureOr<void> Function() action, {
      bool moves = false,
    }) => () {
      _menuSession++;
      _menuHandle = null;
      _menuOpen = false;
      _grabbed = false;
      _pressed = false;
      if (mounted && moves) _revealFromMenu();
      if (mounted && !_flying) _to('s', 1, initial: 1);
      return action();
    };

    final open = LibraryMenuAction(
      icon: Icons.north_east_rounded,
      label: 'Open',
      onSelected: chosen(widget.onOpen),
    );
    final custom = widget.menuActions;
    if (custom != null) {
      return [
        for (final action in custom(context))
          LibraryMenuAction(
            icon: action.icon,
            label: action.label,
            destructive: action.destructive,
            enabled: action.enabled,
            prominent: action.prominent,
            onSelected: chosen(action.onSelected),
          ),
      ];
    }
    final fen = spaceShortcutFen(widget.shortcut);

    return [
      open,
      if (fen != null)
        LibraryMenuAction(
          icon: Icons.grid_on_rounded,
          label: 'Open in board editor',
          onSelected: chosen(() => _openInEditor(fen)),
        ),
      if (widget.canMoveToFront)
        LibraryMenuAction(
          icon: Icons.first_page_rounded,
          label: 'Move to front',
          onSelected: chosen(widget.onMoveToFront, moves: true),
        ),
      if (url != null) ...[
        LibraryMenuAction(
          icon: Icons.ios_share_rounded,
          label: 'Share',
          onSelected: chosen(() => _share(url)),
        ),
        LibraryMenuAction(
          icon: Icons.link_rounded,
          label: 'Copy link',
          onSelected: chosen(() => _copyLink(url, messenger)),
        ),
      ],
      LibraryMenuAction(
        icon: Icons.delete_outline_rounded,
        label: 'Remove from My Space',
        destructive: true,
        onSelected: chosen(() {
          if (mounted) _flyAway(-700);
        }, moves: true),
      ),
    ];
  }

  void _openInEditor(String fen) {
    if (!mounted) return;
    HapticFeedbackService.navigation();
    unawaited(
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => boardEditorAt(fen))),
    );
  }

  void _copyLink(String url, ScaffoldMessengerState? messenger) {
    Clipboard.setData(ClipboardData(text: url));
    HapticFeedbackService.success();
    if (messenger != null && messenger.mounted) {
      showAppSnackOn(messenger, 'Link copied');
    }
  }

  Future<void> _share(String url) async {
    // iPad anchors the share sheet to the tile it came from.
    final box = mounted ? context.findRenderObject() : null;
    final origin = box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : const Rect.fromLTWH(0, 0, 1, 1);
    try {
      await Share.share(url, sharePositionOrigin: origin);
    } catch (e) {
      debugPrint('[MySpace] share failed: $e');
    }
  }

  /// The lifted copy the focus menu paints over its veil, at the tile's own
  /// on-screen rect and size.
  Widget _preview(BuildContext menuContext) => SizedBox(
    width: widget.shortcut.kind.tileWidth,
    height: SpaceMetrics.railHeight,
    child: SpaceTileContent(
      shortcut: widget.shortcut,
      subtitle: widget.subtitle,
      preview: true,
    ),
  );

  // ---------------------------------------------------------------- build

  /// The only part of the tile a spring frame repaints.
  Widget _paintFace(BuildContext context, Widget? child) {
    final dx = _v('dx') + _v('shift');
    final dy = _v('dy') + _v('shiftY');
    final rot = _v('rot') * math.pi / 180;
    final rawScale = _v('s', 1);
    // Springs only ever approach their target; land on exact identity so the
    // resting tile is never resampled a hair off-scale.
    final scale = (rawScale - 1).abs() < 0.002 ? 1.0 : rawScale;
    final opacity = _underMenu ? 0.0 : _v('op', 1).clamp(0.0, 1.0);

    final transform = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..rotateZ(rot)
      ..scaleByDouble(scale, scale, 1, 1);

    return Opacity(
      opacity: opacity,
      child: Transform(
        alignment: Alignment.center,
        transform: transform,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final width = widget.shortcut.kind.tileWidth;
    final height = SpaceMetrics.railHeight;
    final shareUrl = spaceShortcutShareUrl(widget.shortcut);
    final face = ListenableBuilder(
      listenable: _frame,
      builder: _paintFace,
      child: _content,
    );

    return OverlayPortal(
      controller: _portal,
      // Lifted, the face rides in the overlay above its neighbours, pinned to
      // this slot by the layer link so it tracks every scroll and slide.
      overlayChildBuilder: (_) => Positioned(
        left: 0,
        top: 0,
        child: IgnorePointer(
          child: CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            child: SizedBox(width: width, height: height, child: face),
          ),
        ),
      ),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Keyed: the bin and the anchor come and go under a live drag,
            // and an unkeyed sibling appearing first would rebuild the tile
            // below it, tearing down the recognizer that owns the drag.
            Positioned.fill(
              key: const ValueKey('bin'),
              child: IgnorePointer(
                child: ListenableBuilder(
                  listenable: _frame,
                  builder: (context, _) {
                    final bin = _binOpacity;
                    if (bin <= 0.001) return const SizedBox.shrink();
                    return _Bin(
                      t: bin,
                      armed: !_flying && -_v('dy') >= _threshold,
                    );
                  },
                ),
              ),
            ),
            if (_floating)
              Positioned.fill(
                key: const ValueKey('anchor'),
                child: CompositedTransformTarget(
                  link: _link,
                  child: const SizedBox.expand(),
                ),
              ),
            Positioned.fill(
              key: const ValueKey('tile'),
              child: Listener(
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: (_) => _unpress(),
                onPointerCancel: (_) => _unpress(),
                child: RawGestureDetector(
                  behavior: HitTestBehavior.opaque,
                  gestures: {
                    TapGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                          TapGestureRecognizer
                        >(() => TapGestureRecognizer(debugOwner: this), (r) {
                          r.onTap = () {
                            if (_flying || _menuOpen || _dragging) return;
                            widget.onOpen();
                          };
                        }),
                    if (widget.holdToGrab)
                      DelayedMultiDragGestureRecognizer:
                          GestureRecognizerFactoryWithHandlers<
                            DelayedMultiDragGestureRecognizer
                          >(
                            () => DelayedMultiDragGestureRecognizer(
                              delay: kSpaceTileGrabDelay,
                              debugOwner: this,
                            ),
                            (r) => r.onStart = _onGrab,
                          )
                    else
                      LongPressGestureRecognizer:
                          GestureRecognizerFactoryWithHandlers<
                            LongPressGestureRecognizer
                          >(
                            () => LongPressGestureRecognizer(
                              duration: kSpaceTileLongPress,
                              debugOwner: this,
                            ),
                            (r) => r.onLongPressStart = (details) {
                              _pressOrigin = details.globalPosition;
                              unawaited(_openMenu());
                            },
                          ),
                  },
                  // Every gesture has a screen-reader route: tap opens, a
                  // long press brings up the full menu, and each action the
                  // menu offers is also a custom action, announced by the
                  // reader itself (so no hint spelling out finger moves).
                  child: Semantics(
                    button: true,
                    label: widget.shortcut.title,
                    onTap: widget.onOpen,
                    onLongPress: _openMenuFromSemantics,
                    onLongPressHint: 'Show options',
                    customSemanticsActions: widget.menuActions != null
                        ? {
                            // Opening is the tile's own tap.
                            for (final action in widget.menuActions!(context))
                              if (action.label != 'Open' &&
                                  action.label != 'Open game')
                                CustomSemanticsAction(
                                  label: action.label,
                                ): () =>
                                    unawaited(Future.sync(action.onSelected)),
                          }
                        : {
                            if (spaceShortcutFen(widget.shortcut)
                                case final fen?)
                              const CustomSemanticsAction(
                                label: 'Open in board editor',
                              ): () =>
                                  _openInEditor(fen),
                            if (widget.canMoveToFront)
                              const CustomSemanticsAction(
                                label: 'Move to front',
                              ): () =>
                                  widget.onMoveToFront(),
                            for (final move
                                in (widget.reorder?.semanticMoves ??
                                        const <String, VoidCallback>{})
                                    .entries)
                              CustomSemanticsAction(label: move.key):
                                  move.value,
                            if (shareUrl != null) ...{
                              const CustomSemanticsAction(label: 'Share'): () =>
                                  unawaited(_share(shareUrl)),
                              const CustomSemanticsAction(
                                label: 'Copy link',
                              ): () => _copyLink(
                                shareUrl,
                                ScaffoldMessenger.maybeOf(context),
                              ),
                            },
                            const CustomSemanticsAction(
                              label: 'Remove from My Space',
                            ): () =>
                                _flyAway(-700),
                          },
                    // While lifted the face lives in the overlay; the slot
                    // keeps the gesture and stays empty beneath it.
                    child: _floating ? const SizedBox.expand() : face,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FrameTicker extends ChangeNotifier {
  void tick() => notifyListeners();
}

class _TileDrag extends Drag {
  _TileDrag(this._state);

  final _SpaceTileState _state;

  @override
  void update(DragUpdateDetails details) {
    if (_state.mounted) _state._dragUpdate(details);
  }

  @override
  void end(DragEndDetails details) {
    if (_state.mounted) _state._dragEnd(details);
  }

  @override
  void cancel() {
    if (_state.mounted) _state._dragCancel();
  }
}

/// Revealed in the tile's slot as it lifts: a bin and a word, grey while the
/// tile would still come back, red with "Let go" once releasing removes it.
class _Bin extends StatelessWidget {
  const _Bin({required this.t, required this.armed});

  final double t;
  final bool armed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // textSecondary clears AA for 12pt text on the page in both themes
    // (about 5.6:1 light, 5.9:1 dark); the old 55% ink read 3.8:1 in light.
    final ink = armed ? colors.danger : colors.textSecondary;
    final scale = 0.7 + 0.3 * t;
    return Opacity(
      opacity: t.clamp(0.0, 1.0),
      child: Padding(
        padding: EdgeInsets.only(bottom: 18.w),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 26.w,
                  height: 28.w,
                  child: SpaceGlyph(SpaceGlyphKind.trash, size: 28.w, ink: ink),
                ),
                SizedBox(height: 6.w),
                Text(
                  armed ? 'Let go' : 'Remove',
                  style: spaceText(
                    context,
                    size: 12,
                    line: 16,
                    weight: FontWeight.w700,
                    color: ink,
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
