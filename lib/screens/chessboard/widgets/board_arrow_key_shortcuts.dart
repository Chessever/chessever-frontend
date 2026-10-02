import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoSlider;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// How long an arrow key stays down before it starts scrubbing. The scrub's
/// first step lands one repeater interval later, about half a second after the
/// press: the classic keyboard "delay until repeat".
const Duration kBoardArrowKeyHoldDelay = Duration(milliseconds: 350);

/// Hardware-keyboard parity with the board's previous/next buttons: a press is
/// a tap, and a held key is the same accelerating scrub as a long-press.
///
/// Does not request focus: touch, text editing and accessibility keep their own
/// focus. The visible board handles plain arrows before focus traversal can
/// reinterpret them as selecting controls or scrolling the game pager.
///
/// The hold is timed here instead of following the OS key repeat. iPadOS never
/// sends repeat events to Flutter, and Android's repeat rate is not the board's
/// cadence, so native repeats are swallowed and never step.
class BoardArrowKeyShortcuts extends StatefulWidget {
  const BoardArrowKeyShortcuts({
    super.key,
    required this.isActivePage,
    required this.onPrevious,
    required this.onNext,
    this.onHoldPreviousStart,
    this.onHoldPreviousEnd,
    this.onHoldNextStart,
    this.onHoldNextEnd,
    required this.child,
  });

  final bool isActivePage;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onHoldPreviousStart;
  final VoidCallback? onHoldPreviousEnd;
  final VoidCallback? onHoldNextStart;
  final VoidCallback? onHoldNextEnd;
  final Widget child;

  @override
  State<BoardArrowKeyShortcuts> createState() => _BoardArrowKeyShortcutsState();
}

class _BoardArrowKeyShortcutsState extends State<BoardArrowKeyShortcuts>
    with WidgetsBindingObserver {
  /// The arrow whose key-down this board took and that is still down.
  LogicalKeyboardKey? _heldKey;
  Timer? _holdTimer;

  /// Stops the scrub the held key started. Captured at the start so a rebuild
  /// that swaps the callbacks cannot strand a running scrub.
  VoidCallback? _endHold;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reading the route and ticker mode here subscribes to both, so a held key
    // lets go the moment this board is covered or hidden.
    if (!_isOnScreen) _releaseKey(duringBuild: true);
  }

  @override
  void didUpdateWidget(covariant BoardArrowKeyShortcuts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isActivePage) _releaseKey(duringBuild: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // iOS cancels a press when the app is left mid-hold and never reports the
    // key-up, so backgrounding has to end the scrub itself.
    if (state != AppLifecycleState.resumed) _releaseKey();
  }

  @override
  void deactivate() {
    _detach();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _attach();
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  void _attach() {
    FocusManager.instance.addEarlyKeyEventHandler(_handleKey);
    WidgetsBinding.instance.addObserver(this);
  }

  void _detach() {
    _releaseKey(duringBuild: true);
    FocusManager.instance.removeEarlyKeyEventHandler(_handleKey);
    WidgetsBinding.instance.removeObserver(this);
  }

  bool get _hasCurrentRoute {
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return false;
    // A nested navigator's current route can still sit under a covered outer
    // route. Check each containing navigator as well.
    var navigator = Navigator.maybeOf(context);
    while (navigator != null) {
      final parentRoute = ModalRoute.of(navigator.context);
      if (parentRoute != null && !parentRoute.isCurrent) return false;
      navigator = navigator.context.findAncestorStateOfType<NavigatorState>();
    }
    return true;
  }

  bool get _isOnScreen =>
      TickerMode.valuesOf(context).enabled && _hasCurrentRoute;

  bool get _editableControlHasFocus {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    bool isEditable(Widget widget) =>
        widget is EditableText ||
        widget is TextField ||
        widget is Slider ||
        widget is RangeSlider ||
        widget is CupertinoSlider ||
        widget is SelectableRegion;
    if (isEditable(focusContext.widget)) return true;
    var editable = false;
    focusContext.visitAncestorElements((element) {
      editable = isEditable(element.widget);
      return !editable;
    });
    return editable;
  }

  /// Whether a fresh arrow press belongs to this board right now.
  bool get _ownsArrows {
    if (!mounted || !widget.isActivePage) return false;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isShiftPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return false;
    }
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      return false;
    }
    return _isOnScreen && !_editableControlHasFocus;
  }

  KeyEventResult _handleKey(KeyEvent event) {
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowLeft &&
        key != LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.ignored;
    }
    if (event is KeyUpEvent) {
      // A release follows its press, wherever focus or the route went since.
      if (_heldKey != key) return KeyEventResult.ignored;
      _releaseKey();
      return KeyEventResult.handled;
    }
    if (event is KeyRepeatEvent) {
      return _heldKey == key ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    // Synthesized downs only resync key state after a reconnect.
    if (event.synthesized || !_ownsArrows) return KeyEventResult.ignored;

    _releaseKey();
    final step = key == LogicalKeyboardKey.arrowLeft
        ? widget.onPrevious
        : widget.onNext;
    step?.call();
    _heldKey = key;
    _holdTimer = Timer(kBoardArrowKeyHoldDelay, _beginHold);
    // Disabled arrows are a no-op, not a request to move focus or scroll.
    return KeyEventResult.handled;
  }

  void _beginHold() {
    _holdTimer = null;
    final key = _heldKey;
    if (key == null ||
        !_ownsArrows ||
        !HardwareKeyboard.instance.logicalKeysPressed.contains(key)) {
      return;
    }
    final isLeft = key == LogicalKeyboardKey.arrowLeft;
    final start = isLeft ? widget.onHoldPreviousStart : widget.onHoldNextStart;
    if (start == null) return;
    _endHold = isLeft ? widget.onHoldPreviousEnd : widget.onHoldNextEnd;
    start();
  }

  void _releaseKey({bool duringBuild = false}) {
    _holdTimer?.cancel();
    _holdTimer = null;
    _heldKey = null;
    final end = _endHold;
    _endHold = null;
    if (end == null) return;
    // Ending a scrub restarts the engine, which writes provider state, and
    // providers cannot be written while the tree is building.
    if (duringBuild) {
      scheduleMicrotask(end);
    } else {
      end();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
