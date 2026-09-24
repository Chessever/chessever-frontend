import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';

/// Canonical icon for every entry point that opens the shared Board workspace.
///
/// The art is a white and #868686 checker drawn for the dark stage. On paper
/// the white squares vanish (about 1.1:1) and the grey ones barely clear
/// 3:1, so light mode remaps the two tones onto the theme's inks: the light
/// squares take [AppColors.divider], the dark ones [AppColors.textSecondary]
/// (about 6:1 on the page). Dark draws the original colours untouched.
class BoardNavigationIcon extends StatelessWidget {
  const BoardNavigationIcon({
    required this.size,
    this.semanticsLabel = 'Board',
    super.key,
  });

  final double size;
  final String semanticsLabel;

  /// The art's two square tones, per channel.
  static const int _artLight = 0xFF;
  static const int _artDark = 0x86;

  /// The 4x5 colour matrix of a per-channel linear map taking the art's
  /// light squares to [light] and its dark squares to [dark]. Alpha passes
  /// through.
  @visibleForTesting
  static List<double> paperMatrix({required Color light, required Color dark}) {
    List<double> channel(double to255Light, double to255Dark, int index) {
      final k = (to255Light - to255Dark) / (_artLight - _artDark);
      final c = to255Light - _artLight * k;
      final row = List<double>.filled(5, 0);
      row[index] = k;
      row[4] = c;
      return row;
    }

    return <double>[
      ...channel(light.r * 255, dark.r * 255, 0),
      ...channel(light.g * 255, dark.g * 255, 1),
      ...channel(light.b * 255, dark.b * 255, 2),
      0, 0, 0, 1, 0, //
    ];
  }

  @override
  Widget build(BuildContext context) {
    final icon = SvgWidget(
      SvgAsset.analysisBoard,
      semanticsLabel: semanticsLabel,
      width: size,
      height: size,
      preserveOriginalColors: true,
    );
    if (!context.isLightTheme) return icon;
    final colors = context.colors;
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(
        paperMatrix(light: colors.divider, dark: colors.textSecondary),
      ),
      child: icon,
    );
  }
}
