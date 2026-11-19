import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:motor/motor.dart';

/// Chrome that steps out of the way while the reader reads, the way X,
/// Instagram and every browser do it: scrolling down a list pushes the top
/// bar up off the screen with the finger, pixel for pixel; scrolling back up
/// pulls it back the same way. When the finger lets go between the two, the
/// bar settles on whichever side is nearer.
///
/// One controller per screen. A [ScrollChromeRegion] around the screen's
/// scrolling content feeds it; [CollapsingChrome] (bars) and [SlidingFabs]
/// (floating buttons) follow it, all on its one [value], so the top bar, the
/// bottom bar and the buttons always move as one.
///
/// What moves it, and what never does:
///
/// * the outermost vertical list of the region, by drag, fling and let-go;
///   never a horizontal scroll, a list nested in another, or a list too
///   short to need the room ([minScrollRange]);
/// * a let-go or a fling always settles it fully shown or fully gone;
/// * a pull at the top, or the bounce at either end, never moves it;
/// * the app moving the list any real distance, and a switch of tab or
///   page, bring it back;
/// * a focused text field ([held], or any field in the region), reduced
///   motion and a screen reader keep it shown;
/// * a paged region ([ScrollChromeRegion.paged]) follows the direction of
///   travel instead, taking none of the drag: it leaves as the reader pages
///   on and comes back the moment they drag back, even when the page then
///   springs back to where it was.
///
/// Why the drag is spent on the bar first: the bar folds out of the layout,
/// so the list's viewport grows by exactly what the bar gives up. If the list
/// scrolled as well, its content would travel twice as far as the finger. So
/// while the bar is moving, each step of the drag goes to the bar and the
/// list is put back where it was ([ScrollPosition.correctBy]), in the same
/// frame the bar resizes: the content follows the finger exactly, as under a
/// floating header. Done from the scroll notifications rather than physics,
/// so it holds for every list, whatever physics it brings (bouncing physics
/// never hands a drag on to its parent).
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

  /// The list a spring step is carrying the bar over, while it does: a
  /// fling's or a let-go's. Each step of the spring that moves the top bar
  /// puts the list back by as much, so the bar slides away over a list that
  /// keeps flowing under the finger's fling (or holds still after a let-go)
  /// instead of being yanked by the bar's height. Null for the app's own
  /// moves (a tab switch, a scroll to the top), where the list may move.
  ScrollPosition? _carried;

  /// Spring steps not yet given back to [_carried], in pixels.
  double _pendingCarry = 0;

  void _onMotion() {
    final v = value;
    final step = v - _lastValue;
    _lastValue = v;
    if (_carried != null && step != 0 && _topExtent > 0) {
      _pendingCarry += step * _topExtent;
    }
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
    final by = _pendingCarry;
    _pendingCarry = 0;
    if (list != null && by != 0 && list.hasPixels) {
      // Hiding gives the list room at its top, so it is put back by as much;
      // coming back takes room, so it is pushed on. Near the top the list
      // has nothing to give: there it moves with the bar.
      final room = list.pixels - list.minScrollExtent;
      if (by < 0 || room > _topExtent) list.correctBy(by);
    }
    if (!_motion.isAnimating) _carried = null;
  }

  /// A list that scrolls less than this never moves the chrome: there is
  /// nothing to make room for.
  static const double minScrollRange = 160;

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

  /// The top bar's height: the finger travel that takes it all the way out.
  /// Reported by the [CollapsingChrome] at the top; 0 with no top bar.
  double get extent => _topExtent;
  double _topExtent = 0;

  /// The bottom bar's height, reported by the [CollapsingChrome] at the
  /// bottom; 0 with no bottom bar. With no top bar, the bottom bar alone
  /// follows the list, over this much travel.
  double _bottomExtent = 0;

  /// Where the chrome is headed: the value it rests at, or the one its
  /// spring is carrying it to. A paged region asks for a side only when it
  /// is not already headed there, so a finger holding still on a line never
  /// restarts the spring.
  double _aim = 1;

  /// The travel that takes the chrome all the way out.
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

  void _reportExtent(VerticalDirection edge, double height) {
    if (edge == VerticalDirection.up) {
      _topExtent = height;
    } else {
      _bottomExtent = height;
    }
  }

  void _setNow(double value) {
    final next = value.clamp(0.0, 1.0);
    _aim = next;
    // A finger (or the app) takes over from a spring carrying the list.
    _carried = null;
    _pendingCarry = 0;
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
      if (carry != null && carry.hasPixels && _topExtent > 0) {
        final by = (target - from) * _topExtent;
        if (by < 0 || carry.pixels - carry.minScrollExtent > _topExtent) {
          carry.correctBy(by);
        }
      }
      return;
    }
    if ((value - target).abs() < 1e-3 && !_motion.isAnimating) {
      _setNow(target);
      return;
    }
    _aim = target;
    _carried = carry;
    _motion.animateTo(target);
  }

  /// Springs the chrome to [target] unless it is already there or on its
  /// way: what a paged region asks for, frame after frame, as the reader
  /// pages. Sending it away waits on [enabled] and [held] like [hide].
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
  /// carrying that list with it.
  void _settleOver(ScrollNotification notification, double target) {
    if (target < 1 && (!_enabled || _holding)) return;
    _settleTo(target, carry: _positionOf(notification));
  }

  bool _movable(ScrollMetrics metrics) {
    if (!_enabled || _holding || _travel <= 0) return false;
    if (metrics.axis != Axis.vertical) return false;
    if (axisDirectionIsReversed(metrics.axisDirection)) return false;
    // The range as it would be with the chrome shown: hiding the bars grew
    // the viewport by what they gave up (the top bar above the list, the
    // bottom bar under it), which shrank the range by as much. Counting both
    // keeps the answer the same all the way through a hide, so the bars
    // never stop part-way.
    final range =
        metrics.maxScrollExtent -
        metrics.minScrollExtent +
        (1 - value) * (_topExtent + _bottomExtent);
    return range >= minScrollRange;
  }

  /// The current scroll session began with a finger on the list: updates
  /// with no finger after it are its fling. A scroll that began without one
  /// is the app moving the list (a restore, a jump to a round, a scroll to
  /// the top), which never sends the chrome away and, once it has moved the
  /// list any real distance ([_jumpToShow]), brings it back.
  bool _fromDrag = false;

  /// This scroll went past the end of the list: what follows is the list
  /// springing back, down to its very last frame, not the reader heading up.
  bool _pastEnd = false;

  /// How far the app has moved the list in the current scroll that no finger
  /// started.
  double _jumped = 0;

  /// The distance an app's own scroll has to cover before it brings the
  /// chrome back: a bar's height, so the small nudges a list gives itself
  /// (keeping a field in view, holding its place as rows load) never do.
  double get _jumpToShow => _topExtent > 0 ? _topExtent : 48;

  /// The list's size changed without a scroll (it was filtered, a page
  /// loaded or went away). One that can no longer scroll enough to need the
  /// room brings the chrome back: with nothing to scroll, the reader could
  /// never bring it back by scrolling up.
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
    if (value < 1 && !_holding && _enabled && !_movable(metrics)) {
      // Not from within a layout pass that is sizing the bars: after it.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_disposed && value < 1) show();
      });
    }
    return false;
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
    if (notification is ScrollStartNotification) {
      _fromDrag = notification.dragDetails != null;
      _pastEnd = false;
      _jumped = 0;
    } else if (notification is ScrollUpdateNotification) {
      _onUpdate(notification, metrics);
    } else if (notification is ScrollEndNotification ||
        (notification is UserScrollNotification &&
            notification.direction == ScrollDirection.idle)) {
      if (notification is ScrollEndNotification) {
        _fromDrag = false;
        _pastEnd = false;
        _jumped = 0;
      }
      final v = value;
      if (v > 0 && v < 1 && !_motion.isAnimating) {
        // Let go between the two: the bar settles on the nearer side and the
        // list holds still under it. Never left part-way.
        _settleOver(notification, v >= 0.5 ? 1 : 0);
      }
    } else if (notification is OverscrollNotification &&
        notification.overscroll < 0) {
      if (value < 1) show();
    }
    return false;
  }

  void _onUpdate(ScrollUpdateNotification notification, ScrollMetrics m) {
    // At the top (or pulled past it) the chrome is always home.
    if (m.pixels <= m.minScrollExtent + 0.5) {
      if (value < 1) show();
      return;
    }
    final delta = notification.scrollDelta ?? 0;
    if (delta == 0 || !_movable(m)) return;

    if (notification.dragDetails == null) {
      // Springing back from a pull past the end is the list settling, not
      // the reader heading back up: the bars stay away.
      if (m.pixels > m.maxScrollExtent) _pastEnd = true;
      if (_motion.isAnimating || _pastEnd) return;
      if (_fromDrag) {
        // A fling carries the chrome the rest of the way, in the fling's
        // direction: the bar springs away while the list flows on under it,
        // or back while the list flows back.
        if (delta < 0 && value < 1) {
          _settleOver(notification, 1);
        } else if (delta > 0 && value > 0) {
          _settleOver(notification, 0);
        }
        return;
      }
      // The app moving the list itself: towards the top, or any real
      // distance, brings the chrome back. The list may move: not carried.
      _jumped += delta.abs();
      if (value < 1 && (delta < 0 || _jumped >= _jumpToShow)) show();
      return;
    }
    _fromDrag = true;

    // Bouncing past the end: leave the bars where they are, so the finger
    // turning round in the bounce never pulls them back in.
    if (m.pixels > m.maxScrollExtent) {
      _pastEnd = true;
      return;
    }
    if (_topExtent <= 0) {
      // Only a bottom bar: it leaves from under the list, which never moves
      // the content, so it simply follows the finger.
      _setNow(value - delta / _bottomExtent);
      return;
    }
    final extent = _topExtent;
    final double take;
    if (delta > 0) {
      // Reading on: the bar goes first.
      take = math.min(delta, value * extent);
      if (take <= 0) return;
      _setNow(value - take / extent);
      _putListBack(notification, -take);
    } else {
      // Heading back: the bar comes back first, wherever the list is.
      take = math.min(-delta, (1 - value) * extent);
      if (take <= 0) return;
      _setNow(value + take / extent);
      _putListBack(notification, take);
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

  static ScrollPosition? _positionOf(ScrollNotification notification) =>
      notification.context
          ?.findAncestorStateOfType<ScrollableState>()
          ?.position;

  /// Undoes [by] of the list's last step: the bar took it.
  static void _putListBack(ScrollNotification notification, double by) {
    final position = _positionOf(notification);
    if (position == null || !position.hasPixels) return;
    position.correctBy(by);
  }

  @override
  void dispose() {
    _disposed = true;
    _carried = null;
    _pendingCarry = 0;
    _motion
      ..removeListener(_onMotion)
      ..dispose();
    super.dispose();
  }
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
/// [child] drives the chrome: its drags (the bar takes its share first), its
/// flings and its let-gos. Horizontal scrolls (a page swipe, a carousel)
/// never move it, and nor does a vertical list nested inside another one
/// (a list inside a card, a page's own scroll inside a pager): only the
/// outermost vertical list in the region reads as the page.
///
/// While a text field inside the region has focus the keyboard is up, and
/// the chrome holds still, shown. With reduced motion or a screen reader the
/// chrome stays shown and nothing moves it.
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
      ..enabled =
          widget.enabled &&
          !reduceMotion &&
          !MediaQuery.accessibleNavigationOf(context);
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
  });

  final ScrollChromeController controller;
  final Widget child;
  final VerticalDirection edge;
  final bool overlay;

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
class SlidingFabs extends StatelessWidget {
  const SlidingFabs({super.key, required this.controller, required this.child});

  final ScrollChromeController? controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final chrome = controller;
    if (chrome == null) return child;
    // Off the bottom of the window, measured from where the buttons really
    // sit: the Scaffold strips the safe-area inset inside its button slot,
    // so a distance built from the inset stopped short and left the buttons
    // peeking at the rounded corner.
    final window = MediaQuery.sizeOf(context).height;
    return AnimatedBuilder(
      animation: chrome,
      child: child,
      builder: (context, child) {
        final shown = chrome.value;
        return IgnorePointer(
          ignoring: shown < 0.5,
          child: ExcludeSemantics(
            excluding: shown <= 0,
            child: _SlideDown(
              fraction: 1 - shown,
              window: window,
              child: child!,
            ),
          ),
        );
      },
    );
  }
}

/// Reports its child's laid-out height to the controller as the [edge]
/// bar's, and withdraws it when it leaves the tree.
class _ReportHeight extends SingleChildRenderObjectWidget {
  const _ReportHeight({
    required this.controller,
    required this.edge,
    required Widget super.child,
  });

  final ScrollChromeController controller;
  final VerticalDirection edge;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderReportHeight(controller, edge);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderReportHeight renderObject,
  ) {
    renderObject.update(controller, edge);
  }
}

class _RenderReportHeight extends RenderProxyBox {
  _RenderReportHeight(this._controller, this._edge);

  ScrollChromeController _controller;
  VerticalDirection _edge;

  void update(ScrollChromeController controller, VerticalDirection edge) {
    if (identical(controller, _controller) && edge == _edge) return;
    _controller._reportExtent(_edge, 0);
    _controller = controller;
    _edge = edge;
    if (hasSize) _controller._reportExtent(_edge, size.height);
  }

  @override
  void performLayout() {
    super.performLayout();
    _controller._reportExtent(_edge, size.height);
  }

  @override
  void detach() {
    if (!_controller._disposed) _controller._reportExtent(_edge, 0);
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

/// Moves [child] down by [fraction] of the way from where it sits to just
/// past the bottom of the window, without changing its layout. Fully away,
/// the buttons and their one-light shadow are wholly off the screen.
class _SlideDown extends SingleChildRenderObjectWidget {
  const _SlideDown({
    required this.fraction,
    required this.window,
    required Widget super.child,
  });

  final double fraction;

  /// The window's height, in the same logical pixels as the layout.
  final double window;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSlideDown(fraction: fraction, window: window);

  @override
  void updateRenderObject(BuildContext context, _RenderSlideDown renderObject) {
    renderObject
      ..fraction = fraction
      ..window = window;
  }
}

class _RenderSlideDown extends RenderProxyBox {
  _RenderSlideDown({required double fraction, required double window})
    : _fraction = fraction,
      _window = window;

  /// Past the window's edge by the buttons' shadow (10 blur, 4 down), so no
  /// smear is left behind.
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

  double get _dy {
    if (_fraction <= 0 || !attached || !hasSize) return 0;
    final top = localToGlobal(Offset.zero).dy;
    final travel = math.max(0.0, _window - top + _shadowReach);
    return _fraction * travel;
  }

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
