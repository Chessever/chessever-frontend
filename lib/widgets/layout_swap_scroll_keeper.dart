import 'package:flutter/widgets.dart';

/// Keeps a list's place when its layout is swapped for another.
///
/// Several feeds render a one-column list on a phone and a grid on a tablet.
/// iPhone Duo switches between the two each time it closes or opens, and the
/// new scrollable used to start back at the top. Item heights differ between
/// the layouts, so a pixel offset means nothing in the other one; the share
/// of the list already scrolled past does, so that is what is carried over.
///
/// Wrap the swapped child and change [layout] whenever the layout changes.
/// [controller] must be the one both layouts attach to.
class LayoutSwapScrollKeeper extends StatefulWidget {
  const LayoutSwapScrollKeeper({
    super.key,
    required this.controller,
    required this.layout,
    required this.child,
  });

  final ScrollController? controller;

  /// Identifies the current layout, e.g. the grid's column count.
  final Object layout;

  final Widget child;

  @override
  State<LayoutSwapScrollKeeper> createState() => _LayoutSwapScrollKeeperState();
}

class _LayoutSwapScrollKeeperState extends State<LayoutSwapScrollKeeper> {
  @override
  void didUpdateWidget(covariant LayoutSwapScrollKeeper oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controller = widget.controller;
    if (oldWidget.layout == widget.layout ||
        controller == null ||
        !identical(controller, oldWidget.controller) ||
        controller.positions.length != 1) {
      return;
    }
    // The outgoing layout is still attached while this rebuilds.
    final outgoing = controller.position;
    if (!outgoing.hasContentDimensions || outgoing.maxScrollExtent <= 0) {
      return;
    }
    final share = (outgoing.pixels / outgoing.maxScrollExtent).clamp(0.0, 1.0);
    if (share == 0) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !identical(controller, widget.controller) ||
          controller.positions.length != 1) {
        return;
      }
      final incoming = controller.position;
      if (!incoming.hasContentDimensions) return;
      controller.jumpTo(
        (incoming.maxScrollExtent * share).clamp(
          incoming.minScrollExtent,
          incoming.maxScrollExtent,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
