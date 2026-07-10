import 'package:flutter/widgets.dart';

/// Lazily creates home destinations and keeps every visited destination alive.
///
/// Unlike rebuilding a selected child, this preserves each destination's
/// scroll, search, and local route state. Unlike a normal eager IndexedStack,
/// destinations do not start network work until the user first opens them.
class HomeDestinationStack extends StatefulWidget {
  const HomeDestinationStack({
    required this.itemCount,
    required this.currentIndex,
    required this.itemBuilder,
    super.key,
  }) : assert(itemCount > 0),
       assert(currentIndex >= 0 && currentIndex < itemCount);

  final int itemCount;
  final int currentIndex;
  final IndexedWidgetBuilder itemBuilder;

  @override
  State<HomeDestinationStack> createState() => _HomeDestinationStackState();
}

class _HomeDestinationStackState extends State<HomeDestinationStack> {
  late List<Widget?> _destinations;

  @override
  void initState() {
    super.initState();
    _destinations = List<Widget?>.filled(widget.itemCount, null);
  }

  @override
  void didUpdateWidget(covariant HomeDestinationStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.itemCount != oldWidget.itemCount) {
      final previous = _destinations;
      _destinations = List<Widget?>.generate(
        widget.itemCount,
        (index) => index < previous.length ? previous[index] : null,
      );
    }
  }

  Widget _destinationAt(int index) {
    return _destinations[index] ??= KeyedSubtree(
      key: ValueKey<int>(index),
      child: widget.itemBuilder(context, index),
    );
  }

  @override
  Widget build(BuildContext context) {
    _destinationAt(widget.currentIndex);

    return Stack(
      fit: StackFit.expand,
      children: [
        for (var index = 0; index < _destinations.length; index++)
          if (_destinations[index] case final destination?)
            Offstage(
              offstage: index != widget.currentIndex,
              child: TickerMode(
                enabled: index == widget.currentIndex,
                child: ExcludeFocus(
                  excluding: index != widget.currentIndex,
                  child: ExcludeSemantics(
                    excluding: index != widget.currentIndex,
                    child: destination,
                  ),
                ),
              ),
            ),
      ],
    );
  }
}
