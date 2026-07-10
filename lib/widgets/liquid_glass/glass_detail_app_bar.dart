import 'package:chessever2/widgets/liquid_glass/glass_back_button.dart';
import 'package:chessever2/widgets/liquid_glass/glass_island_top_bar.dart';
import 'package:chessever2/widgets/liquid_glass/glass_title_chip.dart';
import 'package:flutter/material.dart';

/// Preferred-size glass island app bar for detail screens.
///
/// Title is a compact [GlassTitleChip] beside the back button — never a
/// full-bleed centered title line.
class GlassDetailAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const GlassDetailAppBar({
    super.key,
    this.title,
    this.titleText,
    this.leading,
    this.actions,
    @Deprecated('Titles sit beside the back chip; centering is ignored.')
    this.centerTitle = false,
    this.height = 44,
  });

  /// Custom title widget (e.g. rich text chip). Prefer [titleText] for plain labels.
  final Widget? title;
  final String? titleText;
  final Widget? leading;
  final List<Widget>? actions;
  final bool centerTitle;
  final double height;

  @override
  Size get preferredSize => Size.fromHeight(height + 12);

  @override
  Widget build(BuildContext context) {
    final titleWidget =
        title ??
        (titleText != null && titleText!.trim().isNotEmpty
            ? GlassTitleChip(label: titleText!.trim())
            : null);

    return GlassIslandTopBar(
      height: height,
      topPadding: 0,
      leading: leading ?? const GlassBackButton(),
      title: titleWidget,
      trailing: actions ?? const [],
    );
  }
}
