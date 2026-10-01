import 'package:flutter/cupertino.dart' show CupertinoSlider;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Hardware-keyboard parity with the board's enabled previous/next buttons.
///
/// Does not request focus: touch, text editing and accessibility keep their own
/// focus. The visible board handles plain arrows before focus traversal can
/// reinterpret them as selecting controls or pieces. Native key repeat steps
/// once per repeat event; key-up and synthesized reconnect events never step.
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

class _BoardArrowKeyShortcutsState extends State<BoardArrowKeyShortcuts> {
  @override
  void initState() {
    super.initState();
    FocusManager.instance.addEarlyKeyEventHandler(_handleKey);
  }

  @override
  void deactivate() {
    FocusManager.instance.removeEarlyKeyEventHandler(_handleKey);
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    FocusManager.instance.addEarlyKeyEventHandler(_handleKey);
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_handleKey);
    super.dispose();
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

  KeyEventResult _handleKey(KeyEvent event) {
    if (!mounted ||
        !widget.isActivePage ||
        event.synthesized ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowLeft &&
        key != LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (keyboard.isShiftPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed) ||
        !TickerMode.valuesOf(context).enabled ||
        !_hasCurrentRoute ||
        _editableControlHasFocus) {
      return KeyEventResult.ignored;
    }
    final callback = key == LogicalKeyboardKey.arrowLeft
        ? widget.onPrevious
        : widget.onNext;
    callback?.call();
    // Disabled arrows are a no-op, not a request to move focus/select a piece.
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
