part of 'search_mode.dart';

/// Runs a page's full-page search: wrap the page's `Scaffold` in it.
///
/// It owns, so the page does not:
/// - the searching flag ([SearchModeController.isSearching]) and the one
///   spring timeline t the whole morph runs on, interruptible and
///   reversible (closing while it opens turns it round from where it is);
/// - system back (it closes the search before the page);
/// - focus: requested at the tap, so the keyboard rises with the morph;
///   dropped as the search closes, so it falls with it;
/// - the keyboard put away with nothing typed (Done, a drag, a tap on the
///   empty field's clear button, Android back that only hides it): the
///   search closes with it, the same morph as the chevron's. With words in
///   the field only the keyboard goes; the results stay. A route, sheet or
///   dialog taking the focus, the app leaving the screen, a finger still on
///   the page or the glass still flying in never close it;
/// - [chrome]: shown on open and close, held while the field has focus;
/// - the query: [onChanged] on every keystroke, [onQuery] once it settles
///   for [debounce] (an empty query at once), and on close it is cleared in
///   the same tick ([onChanged] and [onQuery] get '' when they had
///   something, [SearchModeController.query] reads '', then [onClose]
///   runs). The field's words stay on screen only to fade out with it, and
///   the field is emptied once the close lands;
/// - the morph itself: the search button's own glass, as painted at the
///   tap, is lifted into a layer above the page and flies into the field
///   while the page's header gives way to the search header; closing plays
///   it back into the button.
///
/// If the glass cannot fly (reduced motion, no search button, the field
/// never laid out) everything lands at once, fully visible.
///
/// ## Adopting it on a page
///
/// ```dart
/// // State fields (the page already has `_chrome`):
/// final SearchModeController _search = SearchModeController();
/// // dispose(): _search.dispose();
///
/// SearchModeHost(
///   controller: _search,
///   chrome: _chrome,
///   debounce: const Duration(milliseconds: 200),
///   onChanged: (q) => ref.read(standingsSearchQueryProvider.notifier).state = q,
///   onQuery: (q) {
///     final games = ref.read(gamesTourScreenProvider.notifier);
///     q.isEmpty ? games.clearSearch() : games.searchGamesEnhanced(q);
///   },
///   child: Scaffold(
///     floatingActionButton: SlidingFabs(
///       controller: _chrome,
///       // Keep the buttons while searching: the host hides them, and the
///       // glass flies back into the search button on close.
///       child: InkFabStack(children: [
///         if (anyLive) LiveFirstCapsule(on: liveFirst, liveCount: liveCount, onTap: pressLiveFirst),
///         const SearchInkFab(key: ValueKey('event_search_fab'), label: 'Search games'),
///       ]),
///     ),
///     body: Column(children: [
///       SizedBox(height: MediaQuery.viewPaddingOf(context).top + 4.h),
///       CollapsingChrome(
///         controller: _chrome,
///         child: SearchModeHeaderSlot(
///           header: normalHeader, // title row + tabs, back = PageBackButton
///           search: SearchModeHeader(
///             hintText: 'Search games',
///             closeKey: const ValueKey('event_search_close'),
///             // Optional: the toolbar's controls, Filters last.
///             trailing: [
///               SearchModeFilterButton(
///                 count: filter.activeFilterCount,
///                 onTap: openFilters,
///               ),
///             ],
///           ),
///         ),
///       ),
///       Expanded(
///         child: ScrollChromeRegion(
///           controller: _chrome,
///           child: ListenableBuilder(
///             listenable: _search,
///             builder: (context, _) => PageView(
///               physics: _search.pagePhysics(),
///               children: tabs,
///             ),
///           ),
///         ),
///       ),
///     ]),
///   ),
/// )
/// ```
///
/// Delete from the page: its `_searching` flag, `_openSearch` /
/// `_closeSearch`, its search `FocusNode` and the listener holding the chrome,
/// its search `PopScope`, its private search header, the ternary swapping the
/// headers, and the `if (searching) return SizedBox.shrink()` in its floating
/// buttons. A page with its own `PopScope` (unsaved changes) should let pops
/// through untouched while [SearchModeController.isSearching].
class SearchModeHost extends StatefulWidget {
  const SearchModeHost({
    super.key,
    required this.controller,
    required this.child,
    this.chrome,
    this.onQuery,
    this.onChanged,
    this.onOpen,
    this.onClose,
    this.debounce = const Duration(milliseconds: 300),
  });

  final SearchModeController controller;

  /// The page, its `Scaffold` included (the glass flies over the floating
  /// buttons too).
  final Widget child;

  /// The page's scroll chrome: shown as the search opens and closes, held
  /// while the field has the keyboard.
  final ScrollChromeController? chrome;

  /// Runs the search: the trimmed query once typing settles for [debounce],
  /// an empty query at once (the field cleared), and '' as the search closes
  /// if anything had been searched (then [SearchModeController.isSearching]
  /// is already false).
  final ValueChanged<String>? onQuery;

  /// Every keystroke, as typed (instant filters), and '' as the search
  /// closes if the field held anything.
  final ValueChanged<String>? onChanged;

  /// After the search opens.
  final VoidCallback? onOpen;

  /// After the search closes, once the query is cleared.
  final VoidCallback? onClose;

  final Duration debounce;

  @override
  State<SearchModeHost> createState() => _SearchModeHostState();
}

/// How the keyboard went away while the search was open.
enum _Dismissal {
  /// The field lost focus (Done, a drag that dismisses it, the page
  /// putting it away).
  blurred,

  /// The keyboard went down under a field that kept its focus (Android
  /// back, which only hides it).
  hidden,
}

class _SearchModeHostState extends State<SearchModeHost>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final BoundedSingleMotionController _motion =
      BoundedSingleMotionController(
        motion: SearchModeMotion.morph,
        vsync: this,
        initialValue: widget.controller.isSearching ? 1 : 0,
      );
  late final _Flight _flight = _Flight(this);
  late final Animation<double> _siblingOpacity = _Window(
    _motion,
    0,
    SearchModeMotion.siblingsOutEnd,
    from: 1,
    to: 0,
  );
  late final Animation<double> _siblingScale = _Window(
    _motion,
    0,
    SearchModeMotion.siblingsOutEnd,
    from: 1,
    to: SearchModeMotion.siblingScale,
  );
  late final Animation<double> _badgeOpacity = _Window(
    _motion,
    0,
    SearchModeMotion.badgeOutEnd,
    from: 1,
    to: 0,
  );
  late final Animation<double> _pageHeaderOpacity = _Window(
    _motion,
    0,
    SearchModeMotion.headerOutEnd,
    from: 1,
    to: 0,
  );
  late final Animation<double> _searchContent = _Window(
    _motion,
    SearchModeMotion.searchInStart,
    1,
  );
  late final Animation<double> _fieldContent = _Window(
    _motion,
    SearchModeMotion.fieldInStart,
    1,
  );

  /// The search button's disc is not drawn: the glass carries it, or the
  /// search is open.
  bool _fabHidden = false;
  bool _reduceMotion = false;

  /// Set while the host moves the spring itself, so its own notifications
  /// are not read as the spring's.
  bool _parking = false;

  /// The glass has landed; the field (or the button) takes over after this
  /// frame.
  bool _landing = false;

  /// Every search button under the host, in the order they registered. A
  /// page has one; tab bodies kept alive in a `PageView` may each hold
  /// theirs, so the glass leaves from the one tapped and lands on one in
  /// view.
  final List<_ButtonKeys> _buttons = <_ButtonKeys>[];

  /// The button the glass is flying from or to.
  _ButtonKeys? _flightButton;
  GlobalKey? _fieldFrame;
  GlobalKey? _fieldIcon;

  /// The chrome this host is holding while the field has focus.
  ScrollChromeController? _heldChrome;

  Timer? _debounce;
  String _lastText = '';
  String _lastDispatched = '';
  bool _muted = false;
  bool _orphanCheck = false;

  /// The field still shows a closed search's words, fading out with it.
  bool _leftover = false;

  /// The spring is started after the frame the morph begins in ([_fly]).
  bool _kickoffQueued = false;

  /// The field held focus at its last focus change.
  bool _fieldFocused = false;

  /// The view the page is drawn in, and the keyboard's inset over it in
  /// physical pixels: read from the view itself, under whatever MediaQuery
  /// the page (or a shell around it) reshapes.
  FlutterView? _view;
  double _keyboardInset = 0;

  /// Fingers down on the page.
  final Set<int> _pointers = <int>{};

  /// The keyboard went away while the search was open: the search closes
  /// after it once it is safe to tell ([_settleDismissal]).
  _Dismissal? _dismissal;
  bool _dismissCheckQueued = false;

  /// Since the field last lost focus: its magnifier's tint glides back to
  /// rest over [SearchMotion.accent] from then.
  final Stopwatch _sinceBlur = Stopwatch();

  @override
  void initState() {
    super.initState();
    _motion.addListener(_onTick);
    WidgetsBinding.instance.addObserver(this);
    _attach(widget.controller);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final view = View.maybeOf(context);
    if (view != _view) {
      _view = view;
      _keyboardInset = view?.viewInsets.bottom ?? 0;
    }
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion && _flight.active) {
      // Reduced motion turned on mid-flight: land, after this build.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_flight.active) return;
        _snapTo(widget.controller.isSearching ? 1 : 0);
        setState(() {});
      });
    }
  }

  @override
  void didUpdateWidget(SearchModeHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _detach(oldWidget.controller);
      _attach(widget.controller);
      _snapTo(widget.controller.isSearching ? 1 : 0);
    } else if (oldWidget.chrome != widget.chrome) {
      _syncHold();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _detach(widget.controller);
    _buttons.clear();
    _flightButton = null;
    _motion
      ..removeListener(_onTick)
      ..dispose();
    _flight.dispose();
    super.dispose();
  }

  void _attach(SearchModeController controller) {
    assert(
      controller._host == null || controller._host == this,
      'A SearchModeController drives one SearchModeHost at a time.',
    );
    controller._host = this;
    controller._timeline.parent = _motion;
    controller.focusNode.addListener(_onFocus);
    controller.text.addListener(_onText);
    _fieldFocused = controller.focusNode.hasFocus;
    _syncHold();
    _lastText = controller.text.text;
    _lastDispatched = '';
    _fabHidden = controller.isSearching;
    if (controller.isSearching && _motion.value != 1) {
      _parking = true;
      _motion.value = 1;
      _parking = false;
    }
  }

  void _detach(SearchModeController controller) {
    if (controller._host == this) controller._host = null;
    controller._timeline.parent = controller.isSearching
        ? kAlwaysCompleteAnimation
        : kAlwaysDismissedAnimation;
    controller.focusNode.removeListener(_onFocus);
    controller.text.removeListener(_onText);
    _dismissal = null;
    _dropLeftover(controller);
    // Its field no longer speaks for this page's chrome.
    _releaseHold();
  }

  // The search buttons and the field report where they are.

  void _registerButton(GlobalKey disc, GlobalKey glyph) {
    _buttons
      ..removeWhere((button) => button.disc == disc)
      ..add(_ButtonKeys(disc, glyph));
  }

  void _unregisterButton(GlobalKey disc) {
    _buttons.removeWhere((button) => button.disc == disc);
    // A flight still heading for it lands at once (_scheduleOrphanCheck).
  }

  /// The button the glass should leave from or land on: the one [tapped],
  /// else the one it already flies with while it is in view, else the last
  /// registered in view. Null when none is laid out in the page's bounds.
  _ButtonKeys? _pickButton({GlobalKey? tapped}) {
    if (tapped != null) {
      for (final button in _buttons) {
        if (button.disc == tapped && _box(button.disc) != null) return button;
      }
    }
    final current = _flightButton;
    if (current != null &&
        _buttons.contains(current) &&
        _inView(current.disc)) {
      return current;
    }
    for (final button in _buttons.reversed) {
      if (_inView(button.disc)) return button;
    }
    return null;
  }

  /// [disc] is laid out with its centre inside the page (not a tab kept
  /// alive off to the side).
  bool _inView(GlobalKey disc) {
    final box = _box(disc);
    if (box == null) return false;
    final page = context.findRenderObject();
    if (page is! RenderBox || !page.attached || !page.hasSize) return true;
    final bounds = MatrixUtils.transformRect(
      page.getTransformTo(null),
      Offset.zero & page.size,
    );
    return bounds.contains(box.localToGlobal(box.size.center(Offset.zero)));
  }

  void _attachField(GlobalKey frame, GlobalKey icon) {
    _fieldFrame = frame;
    _fieldIcon = icon;
  }

  void _detachField(GlobalKey frame) {
    if (_fieldFrame != frame) return;
    _fieldFrame = null;
    _fieldIcon = null;
  }

  /// [key]'s laid-out box, or null when it has none in the tree this frame.
  static RenderBox? _box(GlobalKey? key) {
    final context = key?.currentContext;
    if (context == null || !_inTree(context)) return null;
    final object = context.findRenderObject();
    return object is RenderBox && object.attached && object.hasSize
        ? object
        : null;
  }

  /// An element taken out of the tree in this frame's build still answers
  /// to its key until the frame ends (after paint), and asserts if asked
  /// for its render object; the render object itself is already detached,
  /// which [_box] checks for in release.
  static bool _inTree(BuildContext context) {
    var active = true;
    assert(() {
      active = context is Element && context.debugIsActive;
      return true;
    }());
    return active;
  }

  // Opening and closing.

  void _open({required bool fromButton, GlobalKey? tapped, bool focus = true}) {
    if (!mounted) return;
    final controller = widget.controller;
    if (controller.isSearching) return;
    _dismissal = null;
    // Turned round in the first instant of a close: the words still fading
    // out go now, a new search starts empty.
    _dropLeftover();
    controller._setSearching(true);
    widget.chrome?.show();
    // At the tap: the field is built in the next frame and takes it as it
    // attaches, so the keyboard rises alongside the glass.
    if (focus) {
      controller.focusNode.requestFocus();
      SchedulerBinding.instance.addPostFrameCallback((_) {
        final node = widget.controller.focusNode;
        if (mounted &&
            widget.controller.isSearching &&
            !node.hasFocus &&
            node.context != null) {
          node.requestFocus();
        }
      });
    }
    // A close still flying turns round from where it is.
    final resting = !_flight.active;
    final button = resting && fromButton ? _pickButton(tapped: tapped) : null;
    final fly = _canFly && (!resting || button != null);
    if (fly) {
      if (resting) _flightButton = button;
      _flight.start(fieldIcon: _flight._brand);
      _fabHidden = true;
      _fly(fromRest: resting);
    } else {
      _snapTo(1);
    }
    widget.onOpen?.call();
    setState(() {});
  }

  /// [fieldIcon] is the tint the field's magnifier is drawn in as the glass
  /// leaves it; by default the focused or the resting one, as the field is.
  void _close({Color? fieldIcon}) {
    if (!mounted) return;
    final controller = widget.controller;
    if (!controller.isSearching) return;
    _dismissal = null;
    final typing = controller.focusNode.hasFocus;
    controller.focusNode.unfocus();
    // Closed first, so a page reading [onQuery]'s '' can tell a close (its
    // [onClose] does the clearing) from a field emptied while searching.
    controller._setSearching(false);
    _clearQuery();
    widget.chrome?.show();
    final resting = !_flight.active;
    final button = resting ? _pickButton() : null;
    final fly =
        _canFly && (!resting || (button != null && _box(_fieldFrame) != null));
    if (fly) {
      if (resting) _flightButton = button;
      // The magnifier leaves the field in the tint the field had.
      _flight.start(
        fieldIcon:
            fieldIcon ?? (typing ? _flight._brand : _flight._iconSecondary),
      );
      _fabHidden = true;
      _fly(fromRest: resting);
    } else {
      _snapTo(0);
    }
    widget.onClose?.call();
    setState(() {});
  }

  /// The glass may fly: motion is on, and the page's tickers run. A page
  /// kept alive out of sight (a shell's other section, its tickers off)
  /// changes at once: a flight there would wait, frozen, and play out the
  /// moment the reader came back to it.
  bool get _canFly =>
      !_reduceMotion && TickerMode.getValuesNotifier(context).value.enabled;

  /// Sends the glass toward the search's state ([SearchModeController
  /// .isSearching]: 1 open, 0 closed).
  ///
  /// From rest the spring starts once this frame is drawn. The frame the
  /// morph begins in is the costly one (the search header and its field are
  /// built, the page rebuilds for its query), and a spring started with it
  /// would spend that time unseen and leap on its first visible frame. The
  /// glass is drawn on its mark through that frame, exactly as the button
  /// (or the field) it lifts off, and moves from the next. Already in
  /// flight, the spring turns round at once, keeping its speed.
  void _fly({required bool fromRest}) {
    if (!fromRest) {
      // A start still waiting reads the target when it runs.
      if (!_kickoffQueued) {
        _motion.animateTo(widget.controller.isSearching ? 1 : 0);
      }
      return;
    }
    // Drawn this frame where the timeline rests (the button, or the field).
    _flight.tick(_motion.value);
    if (_kickoffQueued) return;
    _kickoffQueued = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        _kickoffQueued = false;
        if (!mounted || !_flight.active) return;
        final target = widget.controller.isSearching ? 1.0 : 0.0;
        if (_motion.value == target) {
          // Turned round before it set off: already on its mark.
          _flight.tick(target);
          _land();
          SchedulerBinding.instance.ensureVisualUpdate();
          return;
        }
        _motion.animateTo(target);
      })
      ..ensureVisualUpdate();
  }

  /// Puts the timeline at [target] with no flight.
  void _snapTo(double target) {
    _parking = true;
    _motion.stop(canceled: true);
    _motion.value = target;
    _parking = false;
    _flight.tick(target);
    _flight.end();
    _fabHidden = widget.controller.isSearching;
    if (!widget.controller.isSearching) _dropLeftover();
  }

  void _onTick() {
    if (_parking) return;
    final t = _motion.value;
    _flight.tick(t);
    if (!_flight.active) return;
    final target = widget.controller.isSearching ? 1.0 : 0.0;
    final arrived = target == 1
        ? t >= 1 - SearchModeMotion.arrival
        : t <= SearchModeMotion.arrival;
    if (arrived || !_motion.isAnimating) {
      // On its mark (SearchModeMotion.arrival): parked there, the glass
      // draws this frame exactly as the field (or the button) it becomes,
      // and hands over after it.
      if (_motion.isAnimating || _motion.value != target) {
        _parking = true;
        _motion.stop(canceled: true);
        _motion.value = target;
        _parking = false;
      }
      _flight.tick(target);
      _land();
    }
  }

  /// The glass has arrived and is drawn this frame on its mark: after the
  /// frame, the field (or the button) takes over, so no frame has both or
  /// neither.
  void _land() {
    if (_landing) return;
    _landing = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _landing = false;
      // Turned round in the meantime: still flying.
      if (!mounted || !_flight.active || _motion.isAnimating) return;
      _flight.end();
      final hidden = widget.controller.isSearching;
      // Closed: the field has faded out and gone, its words with it.
      if (!hidden) _dropLeftover();
      if (_fabHidden != hidden) setState(() => _fabHidden = hidden);
    });
  }

  /// An end of the flight never laid out: nothing to fly between. Land
  /// after this frame, everything in view.
  void _scheduleOrphanCheck() {
    if (_orphanCheck) return;
    _orphanCheck = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _orphanCheck = false;
      if (!mounted || !_flight.active) return;
      if (_box(_flightButton?.disc) != null && _box(_fieldFrame) != null) {
        return;
      }
      _snapTo(widget.controller.isSearching ? 1 : 0);
      setState(() {});
    });
  }

  // The keyboard put away.

  void _onFocus() {
    _syncHold();
    final focused = widget.controller.focusNode.hasFocus;
    if (focused == _fieldFocused) return;
    _fieldFocused = focused;
    if (focused) {
      // Back in the field: whatever took the keyboard gave it back.
      _dismissal = null;
    } else if (widget.controller.isSearching) {
      _sinceBlur
        ..reset()
        ..start();
      _queueDismissal(_Dismissal.blurred);
    }
  }

  @override
  void didChangeMetrics() {
    final was = _keyboardInset;
    final inset = _view?.viewInsets.bottom ?? 0;
    _keyboardInset = inset;
    if (inset > 0) {
      // The keyboard is (back) up: it was not put away.
      if (_dismissal == _Dismissal.hidden) _dismissal = null;
      return;
    }
    // Gone from under a field that kept its focus.
    final controller = widget.controller;
    if (was > 0 &&
        _resumed &&
        controller.isSearching &&
        controller.focusNode.hasFocus) {
      _queueDismissal(_Dismissal.hidden);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The keyboard (or the focus, on desktop) goes with the app: not the
    // reader putting it away.
    if (state != AppLifecycleState.resumed) _dismissal = null;
  }

  /// The app is on screen and in front (or has not said otherwise yet).
  static bool get _resumed {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  void _onPointerDown(PointerDownEvent event) => _pointers.add(event.pointer);

  void _onPointerUp(PointerEvent event) {
    // The last finger off the page: what its gesture does (a tap opening a
    // game) runs first, then the keyboard's going is weighed.
    if (_pointers.remove(event.pointer) && _pointers.isEmpty) {
      _scheduleDismissalCheck();
    }
  }

  void _queueDismissal(_Dismissal kind) {
    _dismissal = kind;
    _scheduleDismissalCheck();
  }

  /// Weighs the keyboard's going once it is safe to tell what it was: after
  /// the next frame and the focus changes it brings (a route pushed by the
  /// same tap takes the focus as it is built), and only with no finger on
  /// the page (a drag that put the keyboard away closes the search once it
  /// lets go, never under the finger).
  void _scheduleDismissalCheck() {
    if (_dismissal == null || _dismissCheckQueued || _pointers.isNotEmpty) {
      return;
    }
    _dismissCheckQueued = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        // Queued behind the focus changes this frame's build made (a route
        // taking the focus as it is first built), which apply in a
        // microtask too.
        scheduleMicrotask(() {
          _dismissCheckQueued = false;
          _settleDismissal();
        });
      })
      ..ensureVisualUpdate();
  }

  /// The keyboard went away with nothing typed while this page is in front,
  /// the reader's own doing: the search closes, the glass flying back into
  /// the search button as the chevron sends it.
  void _settleDismissal() {
    final kind = _dismissal;
    if (kind == null || !mounted || _pointers.isNotEmpty) return;
    _dismissal = null;
    final controller = widget.controller;
    // Closed meanwhile, or the glass still flying in from the tap.
    if (!controller.isSearching || _flight.active) return;
    // Words in the field: only the keyboard goes, the results stay.
    if (controller.text.text.trim().isNotEmpty) return;
    if (!_resumed || !(ModalRoute.isCurrentOf(context) ?? true)) return;
    final node = controller.focusNode;
    switch (kind) {
      case _Dismissal.blurred:
        // The focus went up to the page (Done, a drag, the page putting the
        // keyboard away), not into a route, sheet or dialog over it (on
        // this navigator or one above it) or another field.
        if (node.hasFocus || !_focusWentUp(node)) return;
        _close(fieldIcon: _blurredTint());
      case _Dismissal.hidden:
        if (!node.hasFocus || _keyboardInset > 0) return;
        _close();
    }
  }

  /// The primary focus is one of [node]'s ancestors (its scope, the page's,
  /// the navigator's): where an unfocus sends it.
  static bool _focusWentUp(FocusNode node) {
    final primary = FocusManager.instance.primaryFocus;
    return primary == null || node.ancestors.contains(primary);
  }

  /// The field's magnifier as drawn now: it has been gliding from the
  /// focused tint back to rest on [SearchMotion.accent] since the field let
  /// go of its focus, so the glass leaves it in exactly that tint.
  Color _blurredTint() {
    final seconds =
        _sinceBlur.elapsedMicroseconds / Duration.microsecondsPerSecond;
    final lift = SearchMotion.accent
        .createSimulation(start: 1, end: 0)
        .x(seconds)
        .clamp(0.0, 1.0);
    return Color.lerp(_flight._iconSecondary, _flight._brand, lift)!;
  }

  // The query.

  /// Holds [SearchModeHost.chrome] while the field has focus, and lets go of
  /// any chrome it held that is no longer the page's or no longer typed in.
  void _syncHold() {
    final chrome = widget.chrome;
    final typing = widget.controller.focusNode.hasFocus;
    final held = _heldChrome;
    if (held != null && (!typing || held != chrome)) {
      held.held = false;
      _heldChrome = null;
    }
    if (typing && chrome != null && _heldChrome == null) {
      chrome.held = true;
      _heldChrome = chrome;
    }
  }

  void _releaseHold() {
    _heldChrome?.held = false;
    _heldChrome = null;
  }

  void _onText() {
    final value = widget.controller.text.text;
    if (value == _lastText) return;
    _lastText = value;
    if (_muted) return;
    widget.onChanged?.call(value);
    _debounce?.cancel();
    final query = value.trim();
    if (query == _lastDispatched) return;
    if (query.isEmpty || widget.debounce == Duration.zero) {
      _dispatch(query);
      return;
    }
    _debounce = Timer(widget.debounce, () {
      if (!mounted || !widget.controller.isSearching) return;
      if (widget.controller.query != query) return;
      _dispatch(query);
    });
  }

  void _dispatch(String query) {
    _lastDispatched = query;
    widget.onQuery?.call(query);
  }

  /// Clears the query as the search closes, in the same tick: the page hears
  /// '' at once ([SearchModeHost.onChanged], [SearchModeHost.onQuery]) and
  /// [SearchModeController.query] reads ''. The field keeps its words on
  /// screen while they fade out with the rest of it, and is emptied once
  /// the close lands ([_dropLeftover]).
  void _clearQuery() {
    _debounce?.cancel();
    _debounce = null;
    final hadText = widget.controller.text.text.isNotEmpty;
    _leftover = hadText;
    _lastText = '';
    if (hadText) widget.onChanged?.call('');
    if (_lastDispatched.isNotEmpty) _dispatch('');
  }

  /// Empties the field of a closed search's words, silently (the page was
  /// told as it closed). Before reopening too: a new search starts empty.
  void _dropLeftover([SearchModeController? of]) {
    if (!_leftover) return;
    _leftover = false;
    final controller = of ?? widget.controller;
    if (controller.isSearching) return;
    _muted = true;
    controller.text.clear();
    _muted = false;
    _lastText = '';
  }

  /// The field's clear button: empties the field, or with nothing in it,
  /// puts the keyboard away and the search with it (as Done would).
  void _clearField() {
    final controller = widget.controller;
    if (controller.text.text.isNotEmpty) {
      controller.text.clear();
    } else if (controller.isSearching) {
      _close();
    } else {
      controller.focusNode.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    _flight.configure(context);
    final searching = widget.controller.isSearching;
    return SearchModeScope._(
      host: this,
      isSearching: searching,
      searchButtonHidden: _fabHidden,
      child: PopScope(
        // Back from the search closes it, back to the page it searched.
        canPop: !searching,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && widget.controller.isSearching) _close();
        },
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            // Only counts the fingers on the page; hit testing is the
            // page's own.
            Listener(
              onPointerDown: _onPointerDown,
              onPointerUp: _onPointerUp,
              onPointerCancel: _onPointerUp,
              child: widget.child,
            ),
            // A route that cannot pop has no edge swipe on iOS: the swipe
            // the reader reaches for closes the search instead, as back
            // does on Android.
            if (searching && _EdgeSwipeToClose.appliesTo(context))
              PositionedDirectional(
                start: 0,
                top: 0,
                bottom: 0,
                width: _EdgeSwipeToClose.width(context),
                child: _EdgeSwipeToClose(onClose: _close),
              ),
            Positioned.fill(
              child: IgnorePointer(
                child: ExcludeSemantics(child: _FlightLayer(flight: _flight)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The iOS back swipe while a search is open: from the screen's start edge
/// toward its end, it closes the search (the route's own swipe is off while
/// the search holds back). Taps and vertical drags pass through to the page.
class _EdgeSwipeToClose extends StatefulWidget {
  const _EdgeSwipeToClose({required this.onClose});

  final VoidCallback onClose;

  /// Where the route's own swipe would start: the platforms whose pages
  /// slide back under the finger.
  static bool appliesTo(BuildContext context) =>
      switch (Theme.of(context).platform) {
        TargetPlatform.iOS || TargetPlatform.macOS => true,
        _ => false,
      };

  /// The route swipe's own strip (20pt, wider under a side inset).
  static double width(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final side = Directionality.of(context) == TextDirection.rtl
        ? padding.right
        : padding.left;
    return math.max(20.0, side);
  }

  /// Far enough, or fast enough, toward the end edge.
  static const double travel = 56;
  static const double fling = 400;

  @override
  State<_EdgeSwipeToClose> createState() => _EdgeSwipeToCloseState();
}

class _EdgeSwipeToCloseState extends State<_EdgeSwipeToClose> {
  double _travelled = 0;

  double get _sign =>
      Directionality.of(context) == TextDirection.rtl ? -1.0 : 1.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      excludeFromSemantics: true,
      onHorizontalDragStart: (_) => _travelled = 0,
      onHorizontalDragUpdate: (details) =>
          _travelled += details.delta.dx * _sign,
      onHorizontalDragEnd: (details) {
        final speed = (details.primaryVelocity ?? 0) * _sign;
        if (_travelled >= _EdgeSwipeToClose.travel ||
            (_travelled > 0 && speed >= _EdgeSwipeToClose.fling)) {
          HapticFeedbackService.navigation();
          widget.onClose();
        }
        _travelled = 0;
      },
      onHorizontalDragCancel: () => _travelled = 0,
      child: const SizedBox.expand(),
    );
  }
}

/// What a page's search mode offers the widgets inside it: the search
/// button, the floating buttons beside it, the header slot and the search
/// header read it. Pages talk to their [SearchModeController] instead.
class SearchModeScope extends InheritedWidget {
  const SearchModeScope._({
    required this._host,
    required this.isSearching,
    required this.searchButtonHidden,
    required super.child,
  });

  final _SearchModeHostState _host;

  /// The search is open (or opening).
  final bool isSearching;

  /// The search button's disc is not drawn: the flying glass carries it, or
  /// the search is open.
  final bool searchButtonHidden;

  SearchModeController get controller => _host.widget.controller;

  /// The morph's timeline, 0 the page's header to 1 the search.
  Animation<double> get timeline => _host._motion;

  /// Floating buttons beside the search one: fading over the first
  /// [SearchModeMotion.siblingsOutEnd] of the timeline...
  Animation<double> get siblingOpacity => _host._siblingOpacity;

  /// ...and stepping back to [SearchModeMotion.siblingScale].
  Animation<double> get siblingScale => _host._siblingScale;

  /// The search button's own count, on the button's spot.
  Animation<double> get searchButtonBadgeOpacity => _host._badgeOpacity;

  /// The page's own header: out over the first part of the timeline. A
  /// control outside the header that the search header takes over (a list
  /// toolbar's Filters) leaves on it too.
  Animation<double> get pageHeaderOpacity => _host._pageHeaderOpacity;

  /// The search header's controls the page's header does not draw too: in
  /// over the last part of the timeline. A [SearchModeShared] one, which
  /// both headers draw (the way back, a shared Filters), holds still.
  Animation<double> get searchContentOpacity => _host._searchContent;

  /// The field's text, hint and clear button: in as the glass arrives under
  /// them.
  Animation<double> get fieldContentOpacity => _host._fieldContent;

  /// A search button was tapped (the one drawn with [disc]): the glass lifts
  /// off it from where it is.
  void openFromSearchButton({GlobalKey? disc}) =>
      _host._open(fromButton: true, tapped: disc);

  /// Closes the search (the chevron).
  void close() => _host._close();

  /// A search button's drawn disc (inside its press) and its glyph, so the
  /// glass leaves and lands exactly there. One per page; with several (tabs
  /// kept alive), the glass leaves from the one tapped and lands on one in
  /// view.
  void registerSearchButton({
    required GlobalKey disc,
    required GlobalKey glyph,
  }) => _host._registerButton(disc, glyph);

  void unregisterSearchButton(GlobalKey disc) => _host._unregisterButton(disc);

  static SearchModeScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SearchModeScope>();

  @override
  bool updateShouldNotify(SearchModeScope oldWidget) =>
      oldWidget._host != _host ||
      oldWidget.isSearching != isSearching ||
      oldWidget.searchButtonHidden != searchButtonHidden;
}

/// A search button's measured parts.
@immutable
class _ButtonKeys {
  const _ButtonKeys(this.disc, this.glyph);

  final GlobalKey disc;
  final GlobalKey glyph;
}
