import 'dart:math' as math;

import 'package:chessever2/screens/feed/widgets/feed_drag_handoff.dart';
import 'package:chessever2/screens/feed/widgets/feed_layout.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/widgets.dart';

/// Keeps a playable board and its controls reachable in a short local viewport.
///
/// Normal pages retain their exact geometry. A post in a short window scrolls
/// within a readable column. At either edge its drag continues on the enclosing
/// PageView, including the first page's existing pull-to-refresh gesture
/// ([FeedDragHandoff]).
class FeedPageViewport extends StatefulWidget {
  const FeedPageViewport({required this.builder, super.key});

  /// A page shorter than this scrolls its post in a readable column.
  static const double shortWindow = 500;

  final LayoutWidgetBuilder builder;

  @override
  State<FeedPageViewport> createState() => _FeedPageViewportState();
}

class _FeedPageViewportState extends State<FeedPageViewport> {
  final ScrollController _content = ScrollController();

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // A folded landscape window can lose its wide aspect ratio after the
      // navigation rail and system-safe edge take their space. Its remaining
      // height still needs the same scrollable post and edge handoff.
      final shortWindow = constraints.maxHeight < FeedPageViewport.shortWindow;
      final width = shortWindow
          ? math.min(420.0, constraints.maxWidth)
          : constraints.maxWidth;
      final height = shortWindow
          ? math.max(
              constraints.maxHeight,
              FeedLayout.naturalHeight(
                    width,
                    MediaQuery.textScalerOf(context),
                    evalWidth: 20.w,
                  ) +
                  96,
            )
          : constraints.maxHeight;
      return Align(
        alignment: Alignment.topCenter,
        child: FeedDragHandoff(
          enabled: shortWindow,
          child: SingleChildScrollView(
            controller: _content,
            primary: false,
            physics: shortWindow
                ? const ClampingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            child: SizedBox(
              width: width,
              height: height,
              child: LayoutBuilder(builder: widget.builder),
            ),
          ),
        ),
      );
    },
  );
}
