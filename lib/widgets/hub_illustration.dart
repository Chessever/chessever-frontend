import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// Local 768px artwork with no network dependency or animated loading swap.
/// The parent HubTile supplies clipping and the theme-aware readability ramp.
class HubIllustration extends StatelessWidget {
  const HubIllustration({
    super.key,
    required this.asset,
    this.alignment = Alignment.topCenter,
  });

  final String asset;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: Opacity(
        opacity: context.isLightTheme ? .32 : 1,
        child: Image.asset(
          asset,
          fit: BoxFit.cover,
          alignment: alignment,
          cacheWidth: 768,
          filterQuality: FilterQuality.medium,
        ),
      ),
    ),
  );
}
