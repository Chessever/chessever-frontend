import 'package:flutter/material.dart';

/// Dismisses the software keyboard when the user taps outside the focused
/// editable field. Wrap the navigator (MaterialApp.builder) so dialogs,
/// sheets, and routes all get the same behavior.
///
/// Uses a [Listener] rather than a [GestureDetector] so taps on buttons,
/// chips, and lists still land on those widgets while also unfocusing.
class DismissKeyboard extends StatelessWidget {
  const DismissKeyboard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: dismissKeyboardIfPointerOutsideFocus,
      child: child,
    );
  }
}

/// Unfocuses the current leaf focus when [event] is outside that widget.
/// No-ops when nothing editable is focused, so tapping a field to open
/// the keyboard is not cancelled by the same pointer down.
void dismissKeyboardIfPointerOutsideFocus(PointerDownEvent event) {
  final focus = FocusManager.instance.primaryFocus;
  if (focus == null || !focus.hasFocus) return;
  if (focus is FocusScopeNode) return;
  if (_pointerHitsFocusedEditable(focus, event.position)) return;
  focus.unfocus();
}

bool _pointerHitsFocusedEditable(FocusNode focus, Offset globalPosition) {
  final ctx = focus.context;
  if (ctx == null) return false;

  var hits = _globalHitsBox(ctx.findRenderObject(), globalPosition);

  ctx.visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is TextField || widget is TextFormField) {
      hits = _globalHitsBox(element.findRenderObject(), globalPosition);
      return false;
    }
    return true;
  });

  return hits;
}

bool _globalHitsBox(RenderObject? renderObject, Offset globalPosition) {
  if (renderObject is! RenderBox ||
      !renderObject.hasSize ||
      !renderObject.attached) {
    return false;
  }
  final local = renderObject.globalToLocal(globalPosition);
  return renderObject.paintBounds.contains(local);
}
