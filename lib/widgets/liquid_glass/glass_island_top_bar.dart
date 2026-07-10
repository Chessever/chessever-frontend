import 'package:flutter/material.dart';

/// Compact single-row island chrome host.
///
/// Keeps top control density low: one row of floating islands, minimal
/// vertical padding — no multi-line solid topbar slab.
class GlassIslandTopBar extends StatelessWidget {
  const GlassIslandTopBar({
    super.key,
    this.leading,
    this.trailing = const [],
    this.center,
    this.horizontalPadding = 12,
    this.topPadding,
    this.height = 44,
  });

  final Widget? leading;
  final List<Widget> trailing;
  final Widget? center;
  final double horizontalPadding;
  final double? topPadding;
  final double height;

  @override
  Widget build(BuildContext context) {
    final top =
        topPadding ?? MediaQuery.viewPaddingOf(context).top + 6;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        top,
        horizontalPadding,
        6,
      ),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            if (leading != null) leading!,
            if (center != null) ...[
              if (leading != null) const SizedBox(width: 8),
              Expanded(child: center!),
            ] else
              const Spacer(),
            for (var i = 0; i < trailing.length; i++) ...[
              if (i > 0 || center != null || leading != null)
                const SizedBox(width: 8),
              trailing[i],
            ],
          ],
        ),
      ),
    );
  }
}
