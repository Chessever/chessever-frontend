import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/widgets/liquid_glass/glass_back_button.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Preferred-size glass app bar island for detail screens on [GlassScaffold].
///
/// Transparent layout container + glass action buttons (package iOS 26 pattern).
class GlassDetailAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const GlassDetailAppBar({
    super.key,
    this.title,
    this.titleText,
    this.leading,
    this.actions,
    this.centerTitle = true,
    this.height = 44,
  });

  final Widget? title;
  final String? titleText;
  final Widget? leading;
  final List<Widget>? actions;
  final bool centerTitle;
  final double height;

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    return GlassAppBar(
      preferredSize: preferredSize,
      centerTitle: centerTitle,
      backgroundColor: Colors.transparent,
      title:
          title ??
          (titleText != null
              ? Text(
                titleText!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.textMdRegular.copyWith(
                  color: context.colors.textPrimary,
                ),
              )
              : null),
      leading: leading ?? const GlassBackButton(),
      actions: actions,
    );
  }
}
