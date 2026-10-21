import 'package:flutter/widgets.dart';

/// Each mounted game page owns its menu endpoint. The board and app bar can
/// share actions without leaking a callback to another page in the PageView.
class BoardGameMenuController {
  Object? _owner;
  ValueChanged<Offset>? _open;

  void attach(Object owner, ValueChanged<Offset> open) {
    _owner = owner;
    _open = open;
  }

  void detach(Object owner) {
    if (!identical(owner, _owner)) return;
    _owner = null;
    _open = null;
  }

  void showAt(Offset globalPosition) => _open?.call(globalPosition);
}

class BoardGameMenuHost extends StatefulWidget {
  const BoardGameMenuHost({super.key, required this.child});

  final Widget child;

  static BoardGameMenuController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_BoardGameMenuScope>()
      ?.controller;

  @override
  State<BoardGameMenuHost> createState() => _BoardGameMenuHostState();
}

class _BoardGameMenuHostState extends State<BoardGameMenuHost> {
  final _controller = BoardGameMenuController();

  @override
  Widget build(BuildContext context) =>
      _BoardGameMenuScope(controller: _controller, child: widget.child);
}

class _BoardGameMenuScope extends InheritedWidget {
  const _BoardGameMenuScope({required this.controller, required super.child});

  final BoardGameMenuController controller;

  @override
  bool updateShouldNotify(_BoardGameMenuScope oldWidget) =>
      controller != oldWidget.controller;
}

/// Keeps a popup beside its trigger while respecting safe areas and small
/// landscape windows. The child may scroll when its rows exceed the viewport.
class BoardMenuPositionDelegate extends SingleChildLayoutDelegate {
  const BoardMenuPositionDelegate({
    required this.anchor,
    required this.padding,
  });

  final Offset anchor;
  final EdgeInsets padding;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(
        Size(
          (constraints.maxWidth - padding.horizontal).clamp(0, 280).toDouble(),
          (constraints.maxHeight - padding.vertical)
              .clamp(0, double.infinity)
              .toDouble(),
        ),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
    (anchor.dx - childSize.width)
        .clamp(
          padding.left,
          (size.width - padding.right - childSize.width).clamp(
            padding.left,
            double.infinity,
          ),
        )
        .toDouble(),
    (anchor.dy + 4)
        .clamp(
          padding.top,
          (size.height - padding.bottom - childSize.height).clamp(
            padding.top,
            double.infinity,
          ),
        )
        .toDouble(),
  );

  @override
  bool shouldRelayout(BoardMenuPositionDelegate oldDelegate) =>
      anchor != oldDelegate.anchor || padding != oldDelegate.padding;
}
