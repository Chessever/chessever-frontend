import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'
    show
        FabEndOffsetX,
        FabFloatOffsetY,
        ScaffoldPrelayoutGeometry,
        StandardFabLocation;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:motor/motor.dart';

/// Chrome that steps out of the way while the reader reads: reading down a
/// list sends the bars away, heading back up brings them back, each time on
/// one spring ([scrollChromeMotion]). The bars never follow the finger
/// part-way; the direction of the reader's scroll decides, and the spring
/// does the moving.
///
/// One controller per screen. A [ScrollChromeRegion] around the screen's
/// scrolling content feeds it; [CollapsingChrome] (bars) and [SlidingFabs]
/// (floating buttons) follow it, all on its one [value], so the top bar, the
/// bottom bar and the buttons always move as one.
///
/// What moves it, and what never does:
///
/// * the outermost vertical list of the region, by the reader's own scroll:
///   their drag and the coast after it. Never a horizontal scroll, a list
///   nested in another, or a list too short to need the room ([minRange]);
/// * heading up by [listTravel] brings the bars back; heading down by as
///   much sends them away, once the list is past its top region (the top
///   bar's height): a thumb wobbling on the glass, short of [listTravel]
///   either way, never pumps them;
/// * the top is always home: any scroll of the reader's that finds the list
///   at its top ([topSlack]), pulled past it, or pulling against it, brings
///   the bars back, a coast reaching the top included;
/// * the bounce at either end never moves them: past the end only a finger
///   pushing for more counts (heading down); the list easing back from past
///   an end, and anything its coast does after a bounce (a page landing
///   under it restarts it), are the list's rubber band, not the reader.
///   Except a flick up out of the end bounce: a coast the reader's finger
///   sent up, running on up the content, is the reader heading up;
/// * the app moving the list (a jump, a restore, keeping the reader's place
///   as rows arrive) never moves it, unless that scroll ends at the top or
///   carries the reader a screen or more; a switch of tab or page, a new
///   list and a list put back at its top bring it back;
/// * a focused text field ([held], or any field in the region), reduced
///   motion and a screen reader keep it shown;
/// * a paged region ([ScrollChromeRegion.paged]) follows the direction of
///   travel by whole pages instead: it leaves as the reader pages on and
///   comes back the moment they drag back, even when the page then springs
///   back to where it was.
///
/// Why the spring carries the list: the bar folds out of the layout, so the
/// list's viewport grows by exactly what the bar gives up, which would push
/// the content down by as much under the reader. So each step of the spring
/// puts the list back by what the bar moved ([ScrollPosition.correctBy]), in
/// the same frame the bar resizes: the content stays where the reader's
/// finger (or coast) has it while the bars slide over it, as under a
/// floating header. Done from the scroll notifications rather than physics,
/// so it holds for every list, whatever physics it brings.
class ScrollChromeController extends ChangeNotifier
    implements ValueListenable<double> {
  ScrollChromeController({required TickerProvider vsync})
    : _motion = BoundedSingleMotionController(
        motion: scrollChromeMotion,
        vsync: vsync,
        initialValue: 1,
      ) {
    _motion.addListener(_onMotion);
  }

  final BoundedSingleMotionController _motion;

  /// The value at the last notification, to measure each spring step by.
  double _lastValue = 1;

  /// The list a spring step is carrying the bar over, while it does: the one
  /// the reader's scroll is on. Each step of the spring that moves the top
  /// bar puts the list back by as much, so the bar slides over a list that
  /// keeps flowing under the finger (or its coast) instead of being yanked
  /// by the bar's height. Null for the app's own moves (a tab switch, a
  /// scroll to the top), where the list may move.
  ScrollPosition? _carried;

  /// Spring steps not yet given back to [_carried], in [value] units.
  double _pendingStep = 0;

  void _onMotion() {
    final v = value;
    final step = v - _lastValue;
    _lastValue = v;
    if (_carried != null && step != 0) _pendingStep += step;
    notifyListeners();
  }

  /// Gives the spring's pending steps back to the list. Run from the top
  /// bar's own layout ([CollapsingChrome]), which in every frame comes after
  /// all the animations have ticked and before the list lays out: so a
  /// fling's simulation (which writes the list's offset on its own tick) can
  /// never overwrite the correction, and the list lays out with it, restarting
  /// its fling from there.
  void _flushCarry() {
    final list = _carried;
    final step = _pendingStep;
    _pendingStep = 0;
    if (list != null && step != 0) _give(list, step);
    if (!_motion.isAnimating) _carried = null;
  }

  /// Moves [list] so its content holds still on screen while the chrome
  /// changes by [step] (negative leaving), never out of the range it is
  /// about to have.
  void _give(ScrollPosition list, double step) {
    if (_topExtent <= 0 || !_live(list) || !list.hasContentDimensions) return;
    final by = _carryFor(list, step);
    if (by == 0) return;
    list.correctBy(by);
    _see(list);
  }

  /// How far to move [list] for a spring step of [step] (see [_give]).
  ///
  /// Leaving gives the list room at its top, so it is put back by as much,
  /// but never above its first row: near the top the list goes up with the
  /// bar instead (a short first scroll is never undone by the list springing
  /// back). At its end it also follows the bottom bar down, by the room that
  /// bar gives up, instead of bouncing back down after it. Coming back takes
  /// room, so the list is pushed on, the content holding still wherever the
  /// list is, a few rows from its top included. Only a list at its top
  /// ([topSlack]) stays there and comes down with the bar, its first row
  /// under it: there the move is the point.
  ///
  /// A list past either end is in its bounce, which its physics brings
  /// back: it is left alone. Pulled into its range mid-bounce it would
  /// restart as a fling at the bounce's speed and run off the other way.
  double _carryFor(ScrollPosition list, double step) {
    final pixels = list.pixels;
    if (pixels < list.minScrollExtent - 0.5 ||
        pixels > list.maxScrollExtent + 0.5) {
      return 0;
    }
    final top = _topExtent;
    final anchor = _anchorOf(list);
    // What the list's viewport gains (negative: loses) as the bars move.
    final grow = -(top + _bottomFold) * step;
    var by = _holdStill(top, anchor, step);
    if (step < 0) {
      final maxAfter = list.maxScrollExtent - (1 - anchor) * grow;
      final minAfter = list.minScrollExtent + anchor * grow;
      by = math.min(by, maxAfter - pixels);
      by = math.max(by, math.min(0.0, minAfter - pixels));
    } else if (pixels - list.minScrollExtent <= topSlack) {
      by = 0;
    }
    return by;
  }

  /// The correction that keeps a list's content still on screen while the
  /// chrome changes by [step]: the top bar moves the viewport's top edge,
  /// and a viewport anchored part-way down ([RenderViewport.anchor], as
  /// ScrollablePositionedList anchors its list) moves its anchor with the
  /// viewport's height too.
  double _holdStill(double top, double anchor, double step) =>
      top * step - anchor * (top + _bottomFold) * step;

  /// A list that scrolls less than this never moves the chrome: there is
  /// nothing to make room for. The floor of [minRange].
  static const double minScrollRange = 160;

  /// A list that scrolls less than this never moves the chrome: at least
  /// [minScrollRange], and never less than the bars' own travel and a
  /// little more, so a list never runs out of room part-way through
  /// folding them.
  double get minRange =>
      math.max(minScrollRange, _topExtent + _bottomFold + 48);

  /// How far the reader's scroll (their drag, and the coast after it) has to
  /// run one way before the bars go that way: past a thumb's wobble, so a
  /// reader resting on the glass never pumps them. Counted afresh each time
  /// the scroll turns round.
  static const double listTravel = 10;

  /// How close to its top a list counts as at its top, where the bars are
  /// always home.
  static const double topSlack = 4;

  /// How long a list has to stay too short to scroll before the chrome comes
  /// back for it, so a list that empties for a moment (a skeleton swapped,
  /// a section hiding itself while it reloads) never flashes the bars.
  static const Duration shortGrace = Duration(milliseconds: 150);

  /// How much of the chrome is on screen: 1 shown, 0 gone.
  @override
  double get value {
    // A spring only approaches its end; parked a hair short, a bar would
    // still take taps and be announced. The ends are exact.
    final v = _motion.value;
    if (v <= 1e-3) return 0;
    if (v >= 1 - 1e-3) return 1;
    return v;
  }

  /// The top bar's height: what the list's viewport gains with it gone, and
  /// the top region of a list, where reading down leaves the bars shown.
  /// Reported by the [CollapsingChrome] at the top; 0 with no top bar.
  double get extent => _topExtent;
  double _topExtent = 0;

  /// The bottom bar's height, reported by the [CollapsingChrome] at the
  /// bottom; 0 with no bottom bar. With no top bar, the bottom bar alone
  /// leaves with the list.
  double _bottomExtent = 0;

  /// What the bottom bar hands the list's viewport as it folds away: its
  /// height when it folds out of the layout, 0 when it slides over the
  /// content ([CollapsingChrome.overlay]) or reports nothing.
  double _bottomFold = 0;

  /// Where the chrome is headed: the value it rests at, or the one its
  /// spring is carrying it to. A region asks for a side only when it is not
  /// already headed there, so a finger holding still never restarts the
  /// spring.
  double _aim = 1;

  /// The bars' height: 0 with no bar to move.
  double get _travel => _topExtent > 0 ? _topExtent : _bottomExtent;

  /// Off, the chrome stays shown and no scroll moves it (a screen reader is
  /// navigating, a search field has the keyboard, a page has nothing to
  /// read).
  bool get enabled => _enabled;
  bool _enabled = true;
  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    // Set from a build: the chrome comes back after it, never during it.
    if (!value) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_enabled && !_disposed) show(animate: false);
      });
    }
  }

  bool _disposed = false;

  /// Held, the chrome stays shown whatever the region allows: a field on
  /// the bar has the keyboard. Set by the page that owns the field.
  ///
  /// A [ScrollChromeRegion] also holds the chrome by itself while any text
  /// field inside it has focus, so a page needs this only for a field that
  /// sits outside its region.
  bool get held => _held;
  bool _held = false;
  set held(bool value) {
    if (_held == value) return;
    _held = value;
    if (value) _showAfterFrame();
  }

  /// A text field inside the region has focus (see [ScrollChromeRegion]):
  /// the keyboard is up, and the chrome holds still while it is.
  bool _typing = false;
  void _setTyping(bool value) {
    if (_typing == value || _disposed) return;
    _typing = value;
    if (value) _showAfterFrame();
  }

  /// Held by the page ([held]) or by a focused field in the region.
  bool get _holding => _held || _typing;

  void _showAfterFrame() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_holding && !_disposed) show();
    });
  }

  /// The region pages rather than scrolls (see [ScrollChromeRegion.paged]).
  bool _paged = false;

  /// In a paged region, the page the pager stood on at the last
  /// notification, rounded the way [PageView] reports its page.
  int? _page;

  /// In a paged region, the page the current scroll started on.
  int _fromPage = 0;

  /// In a paged region, the furthest the current scroll has gone on and
  /// back since it last turned round, in pixels from the first page.
  double _peak = 0;
  double _trough = 0;

  /// In a paged region, the way the reader is heading: 1 on, -1 back, 0 not
  /// decided yet. Decided only by real travel ([pagedTurn]), so a finger
  /// wobbling in place never flips it.
  int _heading = 0;

  /// How far a reader paging through a paged region has to move one way
  /// before it counts as heading that way: past a finger's wobble, well
  /// short of a page.
  static const double pagedTurn = 32;

  /// How far into the next page (or the one before) a paged region's
  /// scroll has to come before the chrome treats the page as turned: past
  /// the halfway line [PageView] counts by, so a finger held on that line
  /// never flips the chrome back and forth.
  static const double pagedCommit = 0.6;

  /// Settles snap instead of springing.
  bool reduceMotion = false;

  void _reportExtent(
    VerticalDirection edge,
    double height, {
    required bool folds,
  }) {
    if (edge == VerticalDirection.up) {
      final was = _topExtent;
      _topExtent = height;
      // A bar arriving (or one withdrawn) is not a resize.
      if (folds && was > 0 && height > 0) _holdThroughResize(height - was);
    } else {
      _bottomExtent = height;
      _bottomFold = folds ? height : 0;
    }
  }

  /// The top bar's height changed by [delta] (a row growing in under the
  /// title, a header swapped for another) while it is part-way out. What
  /// shows of it changes by [value] of that, which would push the list's
  /// content by as much under the reader's finger: the list being scrolled
  /// (or carried by a spring) is moved with it, so the content holds still.
  ///
  /// Run from the bar's own layout, which comes before the list's in the
  /// frame, like [_flushCarry]. Shown, the bar's growth is the page's own
  /// layout and moves the content as any header would; gone, nothing of it
  /// shows.
  void _holdThroughResize(double delta) {
    final v = value;
    if (delta.abs() < 0.5 || v <= 0 || v >= 1) return;
    final list = _moving ?? _carried;
    if (!_live(list) || !list!.hasContentDimensions) return;
    final pixels = list.pixels;
    // A list in its bounce is left to its physics.
    if (pixels < list.minScrollExtent - 0.5 ||
        pixels > list.maxScrollExtent + 0.5) {
      return;
    }
    final shown = v * delta;
    // The viewport's top moves by what shows; an anchored viewport's anchor
    // moves with its height too ([_holdStill]).
    var by = shown * (1 - _anchorOf(list));
    // Never out of the range the list is about to have: growing, the bar
    // takes viewport (more room at the end); shrinking, it gives some.
    by = math.max(by, list.minScrollExtent - pixels);
    by = math.min(by, list.maxScrollExtent + math.max(0.0, shown) - pixels);
    if (by.abs() < 0.01) return;
    list.correctBy(by);
    _see(list);
  }

  void _setNow(double value) {
    final next = value.clamp(0.0, 1.0);
    _aim = next;
    // A finger (or the app) takes over from a spring carrying the list.
    _carried = null;
    _pendingStep = 0;
    if (_motion.isAnimating) _motion.stop(canceled: true);
    if ((_motion.value - next).abs() < 1e-6) return;
    // Notifies through the listener in the constructor.
    _motion.value = next;
  }

  /// Springs the chrome to [target] on [scrollChromeMotion] (motor). With
  /// [carry], each spring step that moves the top bar is given back to that
  /// list (see [_carried]).
  void _settleTo(double target, {ScrollPosition? carry}) {
    if (reduceMotion) {
      final from = value;
      _setNow(target);
      // No spring to carry the list: give it the whole step at once.
      if (carry != null && carry.hasPixels) _give(carry, target - from);
      return;
    }
    if ((value - target).abs() < 1e-3 && !_motion.isAnimating) {
      _setNow(target);
      return;
    }
    _aim = target;
    // Steps the spring has not yet given back belong to the list it was
    // carrying, never to another.
    if (!identical(carry, _carried)) _pendingStep = 0;
    _carried = carry;
    _motion.animateTo(target);
  }

  /// Springs the chrome to [target] unless it is already there or on its
  /// way: what a region asks for, frame after frame, as the reader scrolls
  /// or pages. Sending it away waits on [enabled] and [held] like [hide].
  void _headFor(double target) {
    if (target < 1 && (!_enabled || _holding)) return;
    if (_aim == target && (_motion.isAnimating || value == target)) return;
    _settleTo(target);
  }

  /// Brings the chrome back (a tab switch, a scroll to the top).
  void show({bool animate = true}) => animate ? _settleTo(1) : _setNow(1);

  /// Sends the chrome away.
  void hide({bool animate = true}) {
    if (!_enabled || _holding) return;
    animate ? _settleTo(0) : _setNow(0);
  }

  /// Springs the chrome to [target] over the list [notification] came from,
  /// carrying that list with it, unless it is already there or on its way:
  /// asked frame after frame as the reader scrolls, it never restarts the
  /// spring.
  void _settleOver(ScrollNotification notification, double target) {
    if (target < 1 && (!_enabled || _holding)) return;
    if (_aim == target && (_motion.isAnimating || value == target)) return;
    _settleTo(target, carry: _positionOf(notification));
  }

  bool _movable(ScrollMetrics metrics) {
    if (!_enabled || _holding || _travel <= 0) return false;
    if (metrics.axis != Axis.vertical) return false;
    if (axisDirectionIsReversed(metrics.axisDirection)) return false;
    if (!metrics.hasContentDimensions) return false;
    // The range as it would be with the chrome shown: hiding the bars grew
    // the viewport by what they gave up (the top bar above the list, the
    // bottom bar under it), which shrank the range by as much. Counting both
    // keeps the answer the same all the way through a hide, so the bars
    // never stop part-way.
    final range =
        metrics.maxScrollExtent -
        metrics.minScrollExtent +
        (1 - value) * (_topExtent + _bottomFold);
    return range >= minRange;
  }

  /// What is moving the list in the current scroll.
  _Mover _mover = _Mover.none;

  /// The list the current scroll is on.
  ScrollPosition? _moving;

  /// The way the reader's scroll is running: 1 down the list, -1 back up, 0
  /// not yet. Every scroll starts at 0.
  int _runWay = 0;

  /// How far the reader's scroll has run [_runWay] since it last turned.
  double _run = 0;

  /// The current scroll's coast has been past an end: the rest of it is the
  /// list's rubber band (or its fling restarted from inside the bounce, by
  /// a page landing or the bars resizing the list), not the reader heading
  /// anywhere, unless the reader's finger sent it up ([_fingerWay]).
  bool _bounced = false;

  /// The way the reader's finger is heading in the current scroll, past an
  /// end included: 1 down the list, -1 back up, 0 not yet. Set by its first
  /// move, turned only by [listTravel] of travel the other way, so a wobble
  /// at the let-go never turns it. Tells a flick up out of the end bounce
  /// (the reader heading up) from the bounce's own rebound.
  int _fingerWay = 0;

  /// How far the finger has come back against [_fingerWay] since it last
  /// went that way.
  double _fingerBack = 0;

  /// How far the app has moved the list in the current scroll no finger
  /// started.
  double _appTravel = 0;

  /// Per list: where the chrome last saw it (or put it). A list whose
  /// metrics arrive somewhere else was moved without a scroll (a settle,
  /// a correction); one with none here is new.
  final Expando<double> _seen = Expando<double>('scrollChromeSeen');

  /// The pending check that a list too short to scroll is still too short
  /// ([shortGrace]) before the chrome comes back for it.
  Timer? _shortTimer;
  ScrollPosition? _shortList;

  void _see(ScrollPosition? list) {
    if (list != null && list.hasPixels) _seen[list] = list.pixels;
  }

  /// Nothing is moving the chrome or the list it reads: no finger, no
  /// fling, no app scroll, no spring.
  bool _isIdle() {
    if (_mover != _Mover.none && !_live(_moving)) {
      // The list went away mid-scroll (its page was rebuilt): the scroll
      // ended with it.
      _mover = _Mover.none;
      _moving = null;
    }
    return _mover == _Mover.none && !_motion.isAnimating;
  }

  /// The list's size changed without a scroll (it was filtered, a page
  /// loaded or went away, it was rebuilt or put back at its top).
  ///
  /// * A new list, or one the app moved to its top without scrolling it,
  ///   brings the chrome back: at the top the bars are home.
  /// * One that can no longer scroll enough to need the room brings the
  ///   chrome back once it has stayed that way for [shortGrace]: with
  ///   nothing to scroll, the reader could never bring it back by scrolling
  ///   up; a list that empties for a moment never flashes the bars.
  bool handleMetrics(ScrollMetricsNotification notification) {
    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical ||
        axisDirectionIsReversed(metrics.axisDirection)) {
      return false;
    }
    if (_paged) {
      // A pager with a single page has nowhere to page back from.
      if (value < 1 &&
          metrics.hasContentDimensions &&
          metrics.maxScrollExtent - metrics.minScrollExtent < 1) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (!_disposed && value < 1) show();
        });
      }
      return false;
    }
    final list = _positionOf(notification);
    if (list == null) return false;
    final seen = _seen[list];
    if (value >= 1 ||
        _holding ||
        !_enabled ||
        !metrics.hasContentDimensions ||
        !metrics.hasPixels) {
      _see(list);
      return false;
    }
    if (!_movable(metrics)) {
      // Where it was seen is kept: a list that comes back long at its top
      // was still put there without a scroll.
      _checkShortSoon(list);
      return false;
    }
    final top = metrics.minScrollExtent + 0.5;
    if (metrics.pixels <= top && (seen == null || seen > top)) {
      // Put at its top without a scroll, or new. While something is still
      // moving, the next metrics look again.
      if (_isIdle()) {
        _see(list);
        _whenOutOfFrame(show);
      }
      return false;
    }
    _see(list);
    return false;
  }

  void _checkShortSoon(ScrollPosition? list) {
    if (list == null) return;
    _shortList = list;
    _shortTimer ??= Timer(shortGrace, _checkShort);
  }

  void _checkShort() {
    _shortTimer = null;
    final list = _shortList;
    if (_disposed || list == null) return;
    if (value >= 1 ||
        _holding ||
        !_enabled ||
        !_live(list) ||
        !list.hasContentDimensions ||
        _movable(list)) {
      _shortList = null;
      return;
    }
    if (!_isIdle()) {
      // The reader (or the app) is still moving it: look again after.
      _shortTimer = Timer(shortGrace, _checkShort);
      return;
    }
    _shortList = null;
    show();
  }

  /// Runs [action] now, or after the frame when called from inside one
  /// (a build or a layout must never start the bars moving).
  void _whenOutOfFrame(VoidCallback action) {
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) action();
      });
      SchedulerBinding.instance.scheduleFrame();
      return;
    }
    action();
  }

  /// Reads one scroll notification. Returns false so it keeps bubbling.
  bool handle(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical ||
        axisDirectionIsReversed(metrics.axisDirection)) {
      return false;
    }
    if (_paged) {
      _onPage(notification);
      return false;
    }
    final list = _positionOf(notification);
    switch (notification) {
      case ScrollStartNotification(:final dragDetails):
        _begin(dragDetails != null ? _Mover.finger : _Mover.app, list);
      case ScrollUpdateNotification():
        _onUpdate(notification, metrics, list);
      case OverscrollNotification():
        _onOverscroll(notification, metrics, list);
      case ScrollEndNotification():
        _end(notification, metrics);
      case UserScrollNotification(direction: ScrollDirection.idle):
        _end(notification, metrics);
      default:
        break;
    }
    _see(list);
    return false;
  }

  void _begin(_Mover mover, ScrollPosition? list) {
    _mover = mover;
    _moving = list;
    _runWay = 0;
    _run = 0;
    _bounced = false;
    _fingerWay = 0;
    _fingerBack = 0;
    _appTravel = 0;
  }

  /// Runs [d] of the finger's own travel (positive down the list) into
  /// [_fingerWay].
  void _noteFinger(double d) {
    if (d.abs() < _noise) return;
    final way = d > 0 ? 1 : -1;
    if (_fingerWay == 0 || way == _fingerWay) {
      _fingerWay = way;
      _fingerBack = 0;
      return;
    }
    _fingerBack += d.abs();
    if (_fingerBack >= listTravel) {
      _fingerWay = way;
      _fingerBack = 0;
    }
  }

  /// Notes who moves the list this step: a finger on it, or the coast it
  /// left behind. Returns whether the step is the reader's own.
  bool _byReader(bool finger, ScrollPosition? list) {
    if (finger) {
      if (_mover != _Mover.finger) _begin(_Mover.finger, list);
      return true;
    }
    // The finger has let go and the list coasts on: still the reader's.
    if (_mover == _Mover.finger) _mover = _Mover.fling;
    return _mover == _Mover.fling;
  }

  void _onUpdate(
    ScrollUpdateNotification notification,
    ScrollMetrics m,
    ScrollPosition? list,
  ) {
    final delta = notification.scrollDelta ?? 0;
    final finger = notification.dragDetails != null;
    if (!_byReader(finger, list)) {
      _appTravel += delta.abs();
      return;
    }
    if (!m.hasPixels || !m.hasContentDimensions) return;
    if (finger) _noteFinger(delta);
    if (_atTop(m)) {
      // At the top, or pulled past it, the bars are home: a coast arriving
      // there brings them on its first arrival.
      _settleOver(notification, 1);
      return;
    }
    // A coast's first step can be pure rounding (1e-13 either way): no
    // travel at all, never a turn.
    if (delta.abs() < _noise) return;
    final from = m.pixels - delta;
    final pastEnd = m.pixels > m.maxScrollExtent || from > m.maxScrollExtent;
    if (finger) {
      // Past the end, a push for more is the reader heading on; easing back
      // in the bounce is the list's rubber band.
      if (pastEnd && delta < 0) return;
    } else if (pastEnd || from < m.minScrollExtent) {
      // A coast past an end is in its bounce.
      _bounced = true;
      return;
    } else if (_bounced && !(delta < 0 && _fingerWay < 0)) {
      // Back in the content after a bounce: the bounce settling, or its
      // rebound restarted there (a page landing, the bars resizing the
      // list). Unless the reader's finger sent the coast up: a flick up
      // out of the end bounce is the reader heading up.
      return;
    }
    _track(notification, m, delta);
  }

  /// The list pushed against an end it does not bounce at: by a finger, or
  /// by its coast.
  void _onOverscroll(
    OverscrollNotification notification,
    ScrollMetrics m,
    ScrollPosition? list,
  ) {
    final finger = notification.dragDetails != null;
    if (!_byReader(finger, list)) return;
    final overscroll = notification.overscroll;
    if (finger) _noteFinger(overscroll);
    if (overscroll < 0) {
      // Against the top: home.
      _settleOver(notification, 1);
    } else if (overscroll > 0) {
      // Against the end: a finger pushing for more heads on; a coast
      // stopping there is its bounce.
      if (finger) {
        _track(notification, m, overscroll);
      } else {
        _bounced = true;
      }
    }
  }

  /// Less travel than this in a step is rounding, not movement.
  static const double _noise = 1e-6;

  /// Whether [m] is at its top (within [topSlack]) or pulled past it.
  static bool _atTop(ScrollMetrics m) =>
      m.pixels <= m.minScrollExtent + topSlack;

  /// Runs [d] of the reader's travel (positive down the list) and, once
  /// it has run [listTravel] one way, springs the bars that way: back when
  /// heading up; away when heading down, if the list can take them away and
  /// is past its top region (the top bar's height and a turn's travel, so
  /// the list it carries is never put back at its top, where the bars would
  /// be home again, and a reader turning straight back never finds the
  /// content sliding under the returning bar).
  void _track(ScrollNotification notification, ScrollMetrics m, double d) {
    final way = d > 0 ? 1 : -1;
    if (way != _runWay) {
      _runWay = way;
      _run = 0;
    }
    _run += d.abs();
    if (_run < listTravel) return;
    if (way < 0) {
      _settleOver(notification, 1);
    } else if (_movable(m) &&
        m.pixels - m.minScrollExtent > _topExtent + 2 * topSlack + listTravel) {
      _settleOver(notification, 0);
    }
  }

  /// A scroll ended: the finger let go without a fling, a coast came to
  /// rest, or the app's own scroll is done.
  void _end(ScrollNotification notification, ScrollMetrics m) {
    final mover = _mover;
    _mover = _Mover.none;
    _moving = null;
    switch (mover) {
      case _Mover.finger:
      case _Mover.fling:
        // The reader came to rest at the top: home.
        if (m.hasPixels && m.hasContentDimensions && _atTop(m)) {
          _settleOver(notification, 1);
        }
      case _Mover.app:
        // The app's own scroll: home when it ends at the top, or when it
        // has carried the reader a screen or more. Its small moves (keeping
        // a field in view, holding the reader's place as rows arrive, an
        // edit grid scrolling under a lifted card) never move the bars.
        if (value < 1 &&
            m.hasPixels &&
            m.hasContentDimensions &&
            (m.pixels <= m.minScrollExtent + 0.5 ||
                (m.hasViewportDimension &&
                    _appTravel >= m.viewportDimension))) {
          show();
        }
      case _Mover.none:
        break;
    }
    // Never left part-way.
    final v = value;
    if (v > 0 && v < 1 && !_motion.isAnimating) {
      _settleOver(notification, v >= 0.5 ? 1 : 0);
    }
  }

  /// A paged region ([ScrollChromeRegion.paged]): the chrome follows the
  /// reader's direction of travel and never takes any of the drag (paging
  /// stays exact). Both ways settle on [scrollChromeMotion].
  ///
  /// * On: once the reader's scroll is heading on and has come
  ///   [pagedCommit] of the way into the next page, the page has turned and
  ///   the chrome goes. A swipe that gives up before then and springs back
  ///   leaves it where it was.
  /// * Back: the moment the reader's finger has travelled [pagedTurn] back,
  ///   the chrome comes back, wherever the page then settles (the reader
  ///   who only wanted the bars lets the post spring back under them). So
  ///   does a fling that carries the scroll [pagedCommit] into the page
  ///   before, the first page, and a pull at the top.
  /// * The way is decided by travel, never by a line: a finger wobbling on
  ///   the halfway mark, or on the commit line, moves nothing.
  ///
  /// Only the reader's own paging sends it away: the app turning a page on
  /// its own (an autoplay advancing) leaves it be, and the app going back
  /// shows it.
  void _onPage(ScrollNotification notification) {
    // The pager itself, not a scroll inside one of its pages.
    if (notification.depth != 0) return;
    final m = notification.metrics;
    if (!m.hasContentDimensions || !m.hasPixels || !m.hasViewportDimension) {
      return;
    }
    final viewport = m.viewportDimension;
    if (viewport <= 0) return;
    // How far from the first page, held to the pages: a bounce past either
    // end is the pager's rubber band, not travel.
    final at =
        m.pixels.clamp(m.minScrollExtent, m.maxScrollExtent) -
        m.minScrollExtent;
    final page = (at / viewport).round();

    switch (notification) {
      case ScrollStartNotification(:final dragDetails):
        _fromDrag = dragDetails != null;
        _page = page;
        _fromPage = page;
        _peak = at;
        _trough = at;
        _heading = 0;
      case OverscrollNotification(:final overscroll):
        // A pull at the first page (its refresh) is at home already.
        if (overscroll < 0) _headFor(1);
      case ScrollEndNotification():
        // Settled on the first page, or on a page before the one the scroll
        // started on: home.
        if (page == 0 || page < _fromPage) _headFor(1);
        _fromDrag = false;
        _heading = 0;
        _page = page;
        _fromPage = page;
      case ScrollUpdateNotification(:final dragDetails):
        if (dragDetails != null) _fromDrag = true;
        if (!_fromDrag) {
          // The app turning pages: back, or onto the first page, shows.
          final was = _page ?? page;
          _page = page;
          if (page < was || page == 0) _headFor(1);
          return;
        }
        _page = page;
        _follow(at, viewport, finger: dragDetails != null);
      default:
        break;
    }
  }

  /// In a paged region, the current scroll began with a finger on the
  /// pager: updates with no finger after it are its fling.
  bool _fromDrag = false;

  /// One step of the reader's paging (their drag, or the fling after it),
  /// [at] pixels from the first page. See [_onPage].
  void _follow(double at, double viewport, {required bool finger}) {
    if (at > _peak) _peak = at;
    if (at < _trough) _trough = at;
    // The scroll has carried the page before this one in: turned back.
    final turnedBack = at <= (_fromPage - pagedCommit) * viewport;
    if (_heading <= 0 && at - _trough >= pagedTurn) {
      _heading = 1;
      _peak = at;
    } else if (_heading >= 0 &&
        _peak - at >= pagedTurn &&
        // A page springing back from a swipe that gave up is not the
        // reader heading back; their finger, or a fling into the page
        // before, is.
        (finger || turnedBack)) {
      _heading = -1;
      _trough = at;
    }
    if (_heading < 0 || turnedBack) {
      _headFor(1);
    } else if (_heading > 0 && at >= (_fromPage + pagedCommit) * viewport) {
      // On, and into the next page far enough that the page has turned.
      _headFor(0);
    }
  }

  static ScrollPosition? _positionOf(Notification notification) {
    final BuildContext? context = switch (notification) {
      ScrollNotification(:final context) => context,
      ScrollMetricsNotification(:final context) => context,
      _ => null,
    };
    return context?.findAncestorStateOfType<ScrollableState>()?.position;
  }

  /// Whether [list] still belongs to a mounted scrollable.
  static bool _live(ScrollPosition? list) =>
      list != null &&
      list.hasPixels &&
      list.context.notificationContext != null;

  /// Where [list]'s viewport anchors its scroll offset, as a share of its
  /// height from the top: 0 for every ordinary list, the item alignment for
  /// a ScrollablePositionedList. Found by walking down from the scrollable
  /// to its viewport (a handful of single-child boxes).
  static double _anchorOf(ScrollPosition list) {
    final context = list.context.notificationContext;
    if (context == null) return 0;
    // A list taken out of the tree earlier in this frame (its page rebuilt
    // while a spring still carries it) is still reachable until the frame
    // ends, and has no render object to ask.
    var active = true;
    assert(() {
      active = context is! Element || context.debugIsActive;
      return true;
    }());
    if (!active) return 0;
    RenderObject? node = context.findRenderObject();
    for (var depth = 0; node != null && depth < 16; depth++) {
      if (node is RenderViewport) return node.anchor;
      if (node is RenderAbstractViewport) return 0;
      RenderObject? only;
      var children = 0;
      node.visitChildren((child) {
        children++;
        only = child;
      });
      if (children != 1) return 0;
      node = only;
    }
    return 0;
  }

  @override
  void dispose() {
    _disposed = true;
    _carried = null;
    _pendingStep = 0;
    _shortTimer?.cancel();
    _shortTimer = null;
    _shortList = null;
    _moving = null;
    _motion
      ..removeListener(_onMotion)
      ..dispose();
    super.dispose();
  }
}

/// What is moving a list in the current scroll ([ScrollChromeController]).
enum _Mover {
  /// No scroll is under way.
  none,

  /// A finger is on the list.
  finger,

  /// The finger has let go and the list coasts on: a fling, or the list
  /// springing back from past an end. Still the reader's scroll.
  fling,

  /// The app, with no finger: a jump, a restore, an animated scroll.
  app,
}

/// A [ScrollChromeController] owned by a hook widget.
ScrollChromeController useScrollChromeController() {
  final vsync = useSingleTickerProvider();
  final controller = useMemoized(() => ScrollChromeController(vsync: vsync));
  useEffect(() => controller.dispose, [controller]);
  return controller;
}

/// The spring every piece of scroll chrome settles on: critically damped,
/// so a bar never overshoots into the content it uncovers.
const CupertinoMotion scrollChromeMotion = CupertinoMotion.smooth(
  duration: Duration(milliseconds: 260),
  snapToEnd: true,
);

/// Provides a [ScrollChromeController] to the subtree, so a screen's pages
/// can reach the chrome they scroll under.
class ScrollChromeScope extends InheritedWidget {
  const ScrollChromeScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final ScrollChromeController controller;

  static ScrollChromeController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ScrollChromeScope>()?.controller;

  @override
  bool updateShouldNotify(ScrollChromeScope oldWidget) =>
      controller != oldWidget.controller;
}

/// The scrolling content under a screen's chrome. Every vertical list in
/// [child] drives the chrome by the way the reader scrolls it: their drags
/// and the coasts after them. Horizontal scrolls (a page swipe, a carousel)
/// never move it, and nor does a vertical list nested inside another one
/// (a list inside a card, a page's own scroll inside a pager): only the
/// outermost vertical list in the region reads as the page.
///
/// While a text field inside the region has focus the keyboard is up, and
/// the chrome holds still, shown. With a screen reader the chrome stays
/// shown and nothing moves it; with reduced motion it still moves, snapping
/// where it would spring.
class ScrollChromeRegion extends StatefulWidget {
  const ScrollChromeRegion({
    super.key,
    required this.controller,
    required this.child,
    this.enabled = true,
    this.paged = false,
  });

  final ScrollChromeController controller;
  final Widget child;

  /// Off, the chrome stays shown (search with the keyboard up, a page with
  /// nothing to scroll).
  final bool enabled;

  /// The region pages through whole screens (Feed) rather than scrolling a
  /// list: the chrome follows the direction of travel, leaving once the
  /// reader has paged on and coming back the moment they drag back, and
  /// never takes any of the drag. Content under it keeps its size: its
  /// pages are laid out clear of the bars, which slide over them.
  final bool paged;

  @override
  State<ScrollChromeRegion> createState() => _ScrollChromeRegionState();
}

class _ScrollChromeRegionState extends State<ScrollChromeRegion> {
  /// Per scrollable: whether it sits inside another vertical scrollable of
  /// this region. Worked out once per scrollable, on its first notification.
  Expando<bool> _nested = Expando<bool>('scrollChromeNested');

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(ScrollChromeRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller._setTyping(false);
      _nested = Expando<bool>('scrollChromeNested');
      _onFocus();
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocus);
    widget.controller._setTyping(false);
    super.dispose();
  }

  /// A text field in this region took focus or let it go.
  void _onFocus() {
    if (!mounted) return;
    final focused = FocusManager.instance.primaryFocus?.context;
    final typing =
        focused != null &&
        focused.mounted &&
        focused.findAncestorStateOfType<EditableTextState>() != null &&
        _encloses(focused);
    widget.controller._setTyping(typing);
  }

  /// Whether [descendant] sits inside this region.
  bool _encloses(BuildContext descendant) {
    final region = context;
    var inside = false;
    descendant.visitAncestorElements((element) {
      if (element == region) {
        inside = true;
        return false;
      }
      return true;
    });
    return inside;
  }

  /// Whether the scrollable that sent a notification from [origin] is
  /// nested inside another vertical scrollable of this region.
  bool _isNested(BuildContext? origin) {
    final scrollable = origin?.findAncestorStateOfType<ScrollableState>();
    if (scrollable == null) return false;
    final known = _nested[scrollable];
    if (known != null) return known;
    final region = context;
    var nested = false;
    scrollable.context.visitAncestorElements((element) {
      if (element == region) return false;
      if (element is StatefulElement) {
        final state = element.state;
        if (state is ScrollableState &&
            axisDirectionToAxis(state.widget.axisDirection) == Axis.vertical) {
          nested = true;
          return false;
        }
      }
      return true;
    });
    _nested[scrollable] = nested;
    return nested;
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final controller = widget.controller
      ..reduceMotion = reduceMotion
      .._paged = widget.paged
      // Reduced motion only drops the springs (the bars snap): on Android
      // it is on whenever the animator scale is 0, which many battery
      // savers set, and the bars must still step away there. A screen
      // reader keeps them shown.
      ..enabled = widget.enabled && !MediaQuery.accessibleNavigationOf(context);
    return ScrollChromeScope(
      controller: controller,
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) =>
            !_isNested(notification.context) &&
            controller.handleMetrics(notification),
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) =>
              !_isNested(notification.context) &&
              controller.handle(notification),
          child: widget.child,
        ),
      ),
    );
  }
}

/// A bar that folds out of the layout at its screen edge as the chrome
/// leaves, handing its height to the content beside it.
///
/// [edge] is the side it leaves through: a top bar slides up behind the
/// status bar, a bottom bar slides down past the home indicator. It is never
/// faded and never leaves the tree; fully gone, it is laid out but not
/// painted, and out of the semantics tree. A top bar's height is the travel
/// that takes the chrome out ([ScrollChromeController.extent]).
///
/// With [overlay] the bar keeps its place in the layout and only slides
/// away, clipped at its own edge: for a bar over content laid out to stay
/// clear of it (Feed's pages), which must never change size while the bar
/// moves. On screen the two look the same.
class CollapsingChrome extends StatelessWidget {
  const CollapsingChrome({
    super.key,
    required this.controller,
    required this.child,
    this.edge = VerticalDirection.up,
    this.overlay = false,
    this.reportsExtent = true,
  });

  final ScrollChromeController controller;
  final Widget child;
  final VerticalDirection edge;
  final bool overlay;

  /// Off, the bar's height never counts: it is not the chrome's travel, and
  /// no list makes room for it ([ScrollChromeController.minRange]). For an
  /// [overlay] bar over content that already keeps clear of it.
  ///
  /// A bar that only changes shape with the chrome and never leaves (a
  /// dock that shrinks) needs neither: it listens to the controller's
  /// [ScrollChromeController.value] itself and reports nothing.
  final bool reportsExtent;

  /// Whether [context] is inside a [CollapsingChrome]: a bar there already
  /// leaves with it, and must not fold a second time.
  static bool encloses(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_InsideCollapsingChrome>() != null;

  @override
  Widget build(BuildContext context) {
    final top = edge == VerticalDirection.up;
    return AnimatedBuilder(
      animation: controller,
      child: _ReportHeight(
        controller: controller,
        edge: edge,
        folds: !overlay,
        reports: reportsExtent,
        child: RepaintBoundary(child: _InsideCollapsingChrome(child: child)),
      ),
      builder: (context, child) {
        final f = controller.value;
        final away = 1 - f;
        final bar = ExcludeSemantics(
          excluding: f <= 0,
          child: IgnorePointer(
            ignoring: f <= 0,
            child: ClipRect(
              child: overlay
                  ? FractionalTranslation(
                      translation: Offset(0, top ? -away : away),
                      child: child,
                    )
                  : Align(
                      alignment: top
                          ? Alignment.bottomCenter
                          : Alignment.topCenter,
                      heightFactor: f,
                      child: child,
                    ),
            ),
          ),
        );
        // The top bar lays out above the list, after the frame's animations:
        // the one place a spring step can be given back to the list safely.
        return top ? _CarryFlush(controller: controller, child: bar) : bar;
      },
    );
  }
}

/// Marks the subtree of a [CollapsingChrome] ([CollapsingChrome.encloses]).
class _InsideCollapsingChrome extends InheritedWidget {
  const _InsideCollapsingChrome({required super.child});

  @override
  bool updateShouldNotify(_InsideCollapsingChrome oldWidget) => false;
}

/// Floating buttons that slide down off the screen with the chrome and come
/// back up with it. They keep their place in the layout, so nothing under
/// them moves; while away they take no taps.
///
/// With [ride] they never leave: they ride down [ride] as the chrome goes
/// (over a dock that shrinks by as much but stays) and back up as it comes,
/// in view, tappable and announced the whole way.
class SlidingFabs extends StatelessWidget {
  const SlidingFabs({
    super.key,
    required this.controller,
    required this.child,
    this.ride,
  });

  final ScrollChromeController? controller;
  final Widget child;

  /// How far the buttons ride down with the chrome gone, instead of
  /// leaving. Their slot is [ride] taller than the buttons, reaching down to
  /// where they stand with the chrome gone, so a tap anywhere on them lands
  /// at every point of the ride. Put the slot there with
  /// `floatingActionButtonLocation: RidingFabLocation(ride)`: the buttons
  /// then rest exactly where [StandardFabLocation]'s end-float corner puts
  /// them (without it they rest [ride] higher).
  final double? ride;

  @override
  Widget build(BuildContext context) {
    final chrome = controller;
    if (chrome == null) return child;
    final ride = this.ride;
    // Off the bottom of the window, measured from where the buttons really
    // sit: the Scaffold strips the safe-area inset inside its button slot,
    // so a distance built from the inset stopped short and left the buttons
    // peeking at the rounded corner.
    final window = ride == null ? MediaQuery.sizeOf(context).height : 0.0;
    return AnimatedBuilder(
      animation: chrome,
      child: child,
      builder: (context, child) {
        final shown = chrome.value;
        // One shape either way, so the buttons keep their state when a
        // screen starts or stops riding.
        return IgnorePointer(
          ignoring: ride == null && shown < 0.5,
          child: ExcludeSemantics(
            excluding: ride == null && shown <= 0,
            child: _SlideDown(
              fraction: 1 - shown,
              window: window,
              ride: ride,
              child: child!,
            ),
          ),
        );
      },
    );
  }
}

/// Reports its child's laid-out height to the controller as the [edge]
/// bar's (and whether it [folds] out of the layout), and withdraws it when
/// it leaves the tree. With [reports] off it reports nothing.
class _ReportHeight extends SingleChildRenderObjectWidget {
  const _ReportHeight({
    required this.controller,
    required this.edge,
    required this.folds,
    required this.reports,
    required Widget super.child,
  });

  final ScrollChromeController controller;
  final VerticalDirection edge;
  final bool folds;
  final bool reports;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderReportHeight(controller, edge, folds: folds, reports: reports);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderReportHeight renderObject,
  ) {
    renderObject.update(controller, edge, folds: folds, reports: reports);
  }
}

class _RenderReportHeight extends RenderProxyBox {
  _RenderReportHeight(
    this._controller,
    this._edge, {
    required this._folds,
    required this._reports,
  });

  ScrollChromeController _controller;
  VerticalDirection _edge;
  bool _folds;
  bool _reports;

  void update(
    ScrollChromeController controller,
    VerticalDirection edge, {
    required bool folds,
    required bool reports,
  }) {
    if (identical(controller, _controller) &&
        edge == _edge &&
        folds == _folds &&
        reports == _reports) {
      return;
    }
    _withdraw();
    _controller = controller;
    _edge = edge;
    _folds = folds;
    _reports = reports;
    if (hasSize) _report();
  }

  void _report() {
    if (_reports) {
      _controller._reportExtent(_edge, size.height, folds: _folds);
    }
  }

  void _withdraw() {
    if (_reports && !_controller._disposed) {
      _controller._reportExtent(_edge, 0, folds: false);
    }
  }

  @override
  void performLayout() {
    super.performLayout();
    _report();
  }

  @override
  void detach() {
    _withdraw();
    super.detach();
  }
}

/// Gives the chrome's pending spring steps back to the list it carries, at
/// the start of the top bar's layout ([ScrollChromeController._flushCarry]).
class _CarryFlush extends SingleChildRenderObjectWidget {
  const _CarryFlush({required this.controller, required Widget super.child});

  final ScrollChromeController controller;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCarryFlush(controller);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCarryFlush renderObject,
  ) {
    renderObject.controller = controller;
  }
}

class _RenderCarryFlush extends RenderProxyBox {
  _RenderCarryFlush(this.controller);

  ScrollChromeController controller;

  @override
  void performLayout() {
    if (!controller._disposed) controller._flushCarry();
    super.performLayout();
  }
}

/// Where a Scaffold stands buttons that ride a dock ([SlidingFabs.ride]):
/// the end-float corner, lowered by [ride]. The buttons' slot, [ride]
/// taller than they are, then reaches from where they stand with the chrome
/// shown (exactly where the end-float corner puts them) down to where they
/// stand with it gone.
class RidingFabLocation extends StandardFabLocation
    with FabEndOffsetX, FabFloatOffsetY {
  const RidingFabLocation(this.ride);

  /// The [SlidingFabs.ride] of the buttons in the slot.
  final double ride;

  @override
  double getOffsetY(
    ScaffoldPrelayoutGeometry scaffoldGeometry,
    double adjustment,
  ) => super.getOffsetY(scaffoldGeometry, adjustment) + ride;

  @override
  bool operator ==(Object other) =>
      other is RidingFabLocation && other.ride == ride;

  @override
  int get hashCode => ride.hashCode;

  @override
  String toString() => 'RidingFabLocation($ride)';
}

/// Moves [child] down by [fraction] of the way from where it sits to just
/// past the bottom of the window, without changing its layout. Fully away,
/// the buttons and their one-light shadow are wholly off the screen.
///
/// With [ride], [child] moves down [fraction] of [ride] instead, inside a
/// box [ride] taller than it, so it takes taps at every point of the ride.
class _SlideDown extends SingleChildRenderObjectWidget {
  const _SlideDown({
    required this.fraction,
    required this.window,
    this.ride,
    required Widget super.child,
  });

  final double fraction;

  /// The window's height, in the same logical pixels as the layout.
  final double window;

  final double? ride;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSlideDown(fraction: fraction, window: window, ride: ride);

  @override
  void updateRenderObject(BuildContext context, _RenderSlideDown renderObject) {
    renderObject
      ..fraction = fraction
      ..window = window
      ..ride = ride;
  }
}

class _RenderSlideDown extends RenderProxyBox {
  _RenderSlideDown({
    required this._fraction,
    required this._window,
    this._ride,
  });

  /// Past the window's edge by the buttons' one-light glass shadow (at most
  /// 6 blur, 2 down) with room to spare, so no smear is left behind.
  static const double _shadowReach = 16;

  double _fraction;
  set fraction(double value) {
    if (value == _fraction) return;
    _fraction = value;
    markNeedsPaint();
  }

  double _window;
  set window(double value) {
    if (value == _window) return;
    _window = value;
    markNeedsPaint();
  }

  double? _ride;
  set ride(double? value) {
    if (value == _ride) return;
    _ride = value;
    markNeedsLayout();
  }

  double get _dy {
    if (_fraction <= 0 || !attached || !hasSize) return 0;
    final ride = _ride;
    if (ride != null) return _fraction * ride;
    final top = localToGlobal(Offset.zero).dy;
    final travel = math.max(0.0, _window - top + _shadowReach);
    return _fraction * travel;
  }

  @override
  void performLayout() {
    final ride = _ride;
    final child = this.child;
    if (ride == null || child == null) {
      super.performLayout();
      return;
    }
    child.layout(constraints.loosen(), parentUsesSize: true);
    size = constraints.constrain(
      Size(child.size.width, child.size.height + ride),
    );
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final ride = _ride;
    final child = this.child;
    if (ride == null || child == null) {
      return super.computeDryLayout(constraints);
    }
    final inner = child.getDryLayout(constraints.loosen());
    return constraints.constrain(Size(inner.width, inner.height + ride));
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      super.computeMinIntrinsicHeight(width) + (_ride ?? 0);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      super.computeMaxIntrinsicHeight(width) + (_ride ?? 0);

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    context.paintChild(child, offset.translate(0, _dy));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return result.addWithPaintOffset(
      offset: Offset(0, _dy),
      position: position,
      hitTest: (result, transformed) =>
          child?.hitTest(result, position: transformed) ?? false,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(0, _dy, 0, 1);
  }
}
