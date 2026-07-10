import 'package:flutter/material.dart';

/// Compact single-row island chrome host.
///
/// Layout (left → right):
/// - [leading] — usually [GlassBackButton] or avatar island
/// - [title] — compact title chip (content-sized, not full-bleed)
/// - [center] — optional expanded slot (e.g. island search)
/// - [trailing] — action islands on the right
///
/// Keeps top control density low: one row of floating islands — no multi-line
/// solid topbar slab, no full-width title claiming the whole line.
class GlassIslandTopBar extends StatelessWidget {
  const GlassIslandTopBar({
    super.key,
    this.leading,
    this.title,
    this.trailing = const [],
    this.center,
    this.horizontalPadding = 12,
    this.topPadding,
    this.height = 44,
  });

  final Widget? leading;

  /// Compact title / chip cluster beside [leading] (not expanded full-width).
  final Widget? title;

  final List<Widget> trailing;
  final Widget? center;
  final double horizontalPadding;
  final double? topPadding;
  final double height;

  @override
  Widget build(BuildContext context) {
    final top = topPadding ?? MediaQuery.viewPaddingOf(context).top + 6;
    final hasLeading = leading != null;
    final hasTitle = title != null;
    final hasCenter = center != null;
    final hasTrailing = trailing.isNotEmpty;

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
            if (hasLeading) leading!,
            if (hasTitle) ...[
              if (hasLeading) const SizedBox(width: 8),
              // Flexible + loose: grows only as needed, ellipsizes under pressure.
              Flexible(
                fit: FlexFit.loose,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: title!,
                ),
              ),
            ],
            if (hasCenter) ...[
              if (hasLeading || hasTitle) const SizedBox(width: 8),
              Expanded(child: center!),
            ] else if (hasTrailing)
              const Spacer(),
            for (var i = 0; i < trailing.length; i++) ...[
              if (i > 0 || hasCenter || hasTitle || hasLeading)
                const SizedBox(width: 8),
              trailing[i],
            ],
          ],
        ),
      ),
    );
  }
}
