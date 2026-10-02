import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoSlider;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A held arrow waits this long, then steps every
/// [kBoardArrowKeyRepeatInterval]: an ordinary keyboard repeat.
const Duration kBoardArrowKeyRepeatDelay = Duration(milliseconds: 400);

/// Shorter than the board's evaluation debounce, so the engine only wakes once
/// the key is let go.
const Duration kBoardArrowKeyRepeatInterval = Duration(milliseconds: 100);

/// Hardware-keyboard parity with the board's enabled previous/next buttons.
///
/// Does not request focus: touch, text editing and accessibility keep their own
/// focus. The visible board handles plain arrows before focus traversal can
/// reinterpret them as moving focus between controls.
///
/// A held arrow repeats the step on this widget's own timer instead of the OS
/// key repeat. iPadOS never sends repeat events to Flutter, and counting
/// Android's on top would step twice, so native repeats are swallowed.
class BoardArrowKeyShortcuts extends StatefulWidget {
  const BoardArrowKeyShortcuts({
    super.key,
    required this.isActivePage,
    required this.onPrevious,
    required this.onNext,
    required this.child,
  });

  final bool isActivePage;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final Widget child;

  @override
  State<BoardArrowKeyShortcuts> createState() => _BoardArrowKeyShortcutsState();
}

class _BoardArrowKeyShortcutsState extends State<BoardArrowKeyShortcuts>
    with WidgetsBindingObserver {
  /// The arrow whose key-down this board took and that is still down.
  LogicalKeyboardKey? _heldKey;
  Timer? _repeatTimer;

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
    if (!_isOnScreen) _releaseKey();
  }

  @override
  void didUpdateWidget(covariant BoardArrowKeyShortcuts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isActivePage) _releaseKey();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // iOS cancels a press when the app is left mid-hold and never reports the
    // key-up, so backgrounding has to stop the repeat itself.
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
    _releaseKey();
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
    if (focusContext == null || !focusContext.mounted) return false;
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

  /// Whether an arrow press belongs to this board right now.
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
      // The timer paces a held arrow, so a native repeat never steps. While
      // the board owns the arrows it never reaches focus traversal either,
      // even for a press this state did not take (the bar remounted mid-hold).
      return _heldKey == key || _ownsArrows
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    // Synthesized downs only resync key state after a reconnect.
    if (event.synthesized || !_ownsArrows) return KeyEventResult.ignored;

    _releaseKey();
    _heldKey = key;
    _step(key);
    _repeatTimer = Timer(kBoardArrowKeyRepeatDelay, _repeat);
    // A disabled arrow is a no-op, not a request to move focus.
    return KeyEventResult.handled;
  }

  /// Runs the arrow's tap callback; false when that arrow is disabled.
  bool _step(LogicalKeyboardKey key) {
    final step = key == LogicalKeyboardKey.arrowLeft
        ? widget.onPrevious
        : widget.onNext;
    step?.call();
    return step != null;
  }

  void _repeat() {
    _repeatTimer = null;
    final key = _heldKey;
    if (key == null) return;
    if (!_ownsArrows ||
        !HardwareKeyboard.instance.logicalKeysPressed.contains(key)) {
      _releaseKey();
      return;
    }
    // At the end of the line there is nothing left to repeat. The key stays
    // taken until it is released.
    if (!_step(key)) return;
    _repeatTimer = Timer(kBoardArrowKeyRepeatInterval, _repeat);
  }

  void _releaseKey() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
    _heldKey = null;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
