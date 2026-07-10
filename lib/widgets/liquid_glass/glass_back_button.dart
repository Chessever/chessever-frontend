import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Shared glass back-island used on outer control rows.
///
/// Always uses [useOwnLayer] so the button correctly samples its backdrop when
/// it is not nested under a page-level [LiquidGlassLayer] /
/// [GlassScaffold] isolation scope.
class GlassBackButton extends StatelessWidget {
  const GlassBackButton({
    super.key,
    this.onPressed,
    this.size = 48,
    this.iconSize = 18,
    this.semanticLabel = 'Back button',
  });

  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final action = onPressed ?? () => Navigator.of(context).maybePop();
    return Semantics(
      label: semanticLabel,
      button: true,
      onTap: action,
      child: ExcludeSemantics(
        child: GlassIconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_outlined,
            color: context.colors.iconPrimary,
          ),
          onPressed: action,
          size: size,
          iconSize: iconSize,
          useOwnLayer: true,
        ),
      ),
    );
  }
}
