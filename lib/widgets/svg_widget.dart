import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/icons/analysis_board_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class SvgWidget extends StatelessWidget {
  const SvgWidget(
    this.path, {
    required this.height,
    required this.width,
    this.semanticsLabel,
    this.colorFilter,
    this.fallback,
    this.preserveOriginalColors = false,
    super.key,
  });

  final String path;
  final double height;
  final double width;
  final String? semanticsLabel;
  final ColorFilter? colorFilter;
  final Widget? fallback;

  /// Opt-out for assets that ship with intentional multi-colour artwork
  /// (brand/flag/illustrative icons). When true, the light-theme automatic
  /// recolour is skipped even if [colorFilter] is null.
  final bool preserveOriginalColors;

  @override
  Widget build(BuildContext context) {
    // The bundled SVG icons all have white/light tints baked in so they read
    // on the dark theme. In light theme that becomes white-on-light-grey,
    // which is the most common contrast bug across the app. Default to
    // tinting them with `iconPrimary` whenever no explicit colorFilter is
    // provided. Dark theme keeps the asset's original colours.
    final effectiveFilter = colorFilter ??
        (context.isLightTheme && !preserveOriginalColors
            ? ColorFilter.mode(
                context.colors.iconPrimary,
                BlendMode.srcIn,
              )
            : null);
    return RepaintBoundary(
      child: SvgPicture.asset(
        path,
        semanticsLabel: semanticsLabel,
        height: height,
        width: width,
        colorFilter: effectiveFilter,
        errorBuilder:
            (context, obj, _) => fallback ?? AnalysisBoardIcon(size: height),
      ),
    );
  }
}
