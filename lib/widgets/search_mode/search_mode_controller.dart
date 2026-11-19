part of 'search_mode.dart';

/// The one spring and the one choreography every part of a search mode
/// moves on. Everything reads the same timeline value t (0 the page's own
/// header, 1 the search), so the morph plays backwards exactly by running t
/// back, and a reversal mid-way is just the spring turning round.
abstract final class SearchModeMotion {
  /// The timeline: critically damped (no overshoot into the field), long
  /// enough for the eye to follow the glass across the page.
  static const CupertinoMotion morph = CupertinoMotion.smooth(
    duration: Duration(milliseconds: 280),
    snapToEnd: true,
  );

  /// The glass travels over [arrival, 1 - arrival] of t and is parked at
  /// either end, so it lands in the same time however far it flies: about
  /// 333ms from the tap (60Hz), moving about a pixel a frame as it stops
  /// over the longest flight (the button's corner to the top of a 393x852
  /// phone). A critically damped spring's own last hundredth would take
  /// another ~150ms of sub-pixel creep across the page.
  static const double arrival = 0.006;

  /// The page's own header leaves over [0, headerOutEnd] of t, sliding up
  /// by [headerSlide] as it fades.
  static const double headerOutEnd = 0.4;
  static const double headerSlide = 6;

  /// The search header's controls the page's header does not draw too (the
  /// chevron on a page with no way back, a control only the search has)
  /// arrive over [searchInStart, 1 - arrival]: whole the frame the glass
  /// lands. The ones both headers draw (each a [SearchModeShared]: the way
  /// back, a shared Filters) hold still through the morph.
  static const double searchInStart = 0.6;

  /// The field's text, hint and clear button arrive over [fieldInStart,
  /// 1 - arrival]: later than those controls, because they sit on the glass,
  /// which only reaches the header in the last stretch of its flight (a
  /// straight line from the button's corner). In time that is the last
  /// ~45% of the morph (about 175ms to 333ms), the spring being quick at
  /// first and slow to settle.
  static const double fieldInStart = 0.9;

  /// Floating buttons beside the search one step back over [0,
  /// siblingsOutEnd], shrinking to [siblingScale] as they fade.
  static const double siblingsOutEnd = 0.3;
  static const double siblingScale = 0.9;

  /// The search button's own count fades over [0, badgeOutEnd]: it stays on
  /// the button's spot while the glass flies, so it leaves at once and comes
  /// back only as the glass lands.
  static const double badgeOutEnd = 0.15;

  /// Where the glass is along its flight at timeline [t]: 0 the button, 1
  /// the field.
  static double glassAt(double t) => _window(t, arrival, 1 - arrival);
}

/// The state of one page's search: whether it is open, the query and the
/// field's focus, and the spring timeline the morph runs on.
///
/// Created and disposed by the page (like a `ScrollChromeController`) and
/// handed to its [SearchModeHost], which drives it. It notifies when
/// [isSearching] changes, never per frame; read [timeline] for motion.
class SearchModeController extends ChangeNotifier {
  SearchModeController({String text = ''})
    : text = TextEditingController(text: text),
      focusNode = FocusNode(debugLabel: 'Search mode field');

  /// The field's words. As the search closes they stay only while the
  /// field fades out, and the host empties it once the close lands: read
  /// [query] for what is being searched.
  final TextEditingController text;

  /// The search field's focus. The host requests it as the search opens
  /// (the keyboard rises with the morph) and drops it as it closes.
  final FocusNode focusNode;

  /// The search is open (or opening). Flips at the tap; the morph follows
  /// on [timeline].
  bool get isSearching => _searching;
  bool _searching = false;

  /// What is being searched, trimmed: '' from the tap that closes the
  /// search, while the field's words fade out.
  String get query => _searching ? text.text.trim() : '';

  /// 0 the page's own header, 1 the search: one spring, interruptible and
  /// reversible. Stable for the controller's life.
  Animation<double> get timeline => _timeline;
  final ProxyAnimation _timeline = ProxyAnimation(kAlwaysDismissedAnimation);

  /// [physics] for the page's `PageView` while the search is closed, and a
  /// lock while it is open: a search belongs to the tab it opened on.
  ScrollPhysics? pagePhysics([ScrollPhysics? physics]) =>
      _searching ? const NeverScrollableScrollPhysics() : physics;

  _SearchModeHostState? _host;

  /// Opens the search from code (a shortcut, a deep link). With no search
  /// button to lift the glass from, the header springs straight to the
  /// search; a close in flight turns round instead.
  void open() {
    final host = _host;
    if (host != null) {
      host._open(fromButton: false);
    } else {
      _setSearching(true);
    }
  }

  /// Closes the search: the query is cleared in the same tick (the field's
  /// words fade out with it), the keyboard goes, and the glass flies back
  /// into the search button.
  void close() {
    final host = _host;
    if (host != null) {
      host._close();
    } else if (_searching) {
      focusNode.unfocus();
      text.clear();
      _setSearching(false);
    }
  }

  void _setSearching(bool value) {
    if (_searching == value) return;
    _searching = value;
    notifyListeners();
  }

  /// The glass is in flight (between the search button and the field).
  @visibleForTesting
  bool get debugFlightActive => _host?._flight.active ?? false;

  /// The search button's disc is not drawn (the glass carries it, or the
  /// search is open).
  @visibleForTesting
  bool get debugSearchButtonHidden => _host?._fabHidden ?? false;

  /// How many times a piece of the flying glass has been painted.
  @visibleForTesting
  int get debugGlassPaintCount => _host?._flight.debugPaintCount ?? 0;

  /// The flying glass's last painted bounds, in global coordinates.
  @visibleForTesting
  Rect? get debugGlassRect => _host?._flight.debugLastRect;

  /// The flying glass's last painted material: its fill and edge land on
  /// the field's own.
  @visibleForTesting
  GlassLook? get debugGlassLook => _host?._flight.debugLastLook;

  @override
  void dispose() {
    _host = null;
    _timeline.parent = kAlwaysDismissedAnimation;
    text.dispose();
    focusNode.dispose();
    super.dispose();
  }
}

/// [parent] read over a window of its range: 0 below [begin], 1 above
/// [end], straight between (then mapped onto [from]..[to]). A plain linear
/// reading of the spring's own value, not an easing curve: the spring is the
/// only motion.
class _Window extends Animation<double> with AnimationWithParentMixin<double> {
  _Window(this.parent, this.begin, this.end, {this.from = 0, this.to = 1});

  @override
  final Animation<double> parent;
  final double begin;
  final double end;
  final double from;
  final double to;

  @override
  double get value {
    final v = ((parent.value - begin) / (end - begin)).clamp(0.0, 1.0);
    return from + (to - from) * v;
  }
}

double _window(double t, double begin, double end) =>
    ((t - begin) / (end - begin)).clamp(0.0, 1.0);
