import 'package:flutter/material.dart';

/// Vertical stack of floating liquid-glass islands with **no dead strip**.
///
/// Use for page top chrome: back/title row → segment island → optional tools.
/// Spacing is a tight [gap] (default 6) — never a solid sticky slab.
class GlassIslandStack extends StatelessWidget {
  const GlassIslandStack({
    super.key,
    required this.children,
    this.gap = 6,
    this.topPadding,
    this.bottomPadding = 4,
    this.includeStatusBar = true,
  });

  final List<Widget> children;
  final double gap;

  /// Extra top inset; defaults to status bar + 4 when [includeStatusBar].
  final double? topPadding;
  final double bottomPadding;
  final bool includeStatusBar;

  @override
  Widget build(BuildContext context) {
    final top =
        topPadding ??
        (includeStatusBar
            ? MediaQuery.viewPaddingOf(context).top + 4
            : 0.0);

    final visible = children.where((c) {
      // Drop pure shrink wrappers if any.
      return c is! SizedBox || c.height != 0;
    }).toList();

    return Padding(
      padding: EdgeInsets.only(top: top, bottom: bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0) SizedBox(height: gap),
            visible[i],
          ],
        ],
      ),
    );
  }
}
