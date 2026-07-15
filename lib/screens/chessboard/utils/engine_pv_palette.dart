import 'package:flutter/material.dart';

/// Stable colors for ranked engine principal variations.
///
/// Keeping this palette shared prevents the analysis board and Opening
/// Explorer from assigning different colors to the same engine-line rank.
const List<Color> enginePvVariantPalette = <Color>[
  Color.fromARGB(180, 152, 179, 154), // Green - first variation.
  Color.fromARGB(180, 100, 149, 237), // Blue - second variation.
  Color.fromARGB(180, 255, 165, 0), // Orange - third variation.
  Color.fromARGB(180, 255, 105, 180), // Pink - fourth variation.
  Color.fromARGB(180, 147, 112, 219), // Purple - fifth variation.
];

/// Returns the base hue for [variantIndex], cycling after the fifth line.
Color enginePvVariantBaseColor(int variantIndex) {
  final safeIndex = variantIndex < 0 ? 0 : variantIndex;
  return enginePvVariantPalette[safeIndex % enginePvVariantPalette.length];
}

/// Returns the display color for a ranked engine line.
Color enginePvVariantColor(int variantIndex, {required bool isSelected}) {
  return enginePvVariantBaseColor(
    variantIndex,
  ).withValues(alpha: isSelected ? 0.95 : 0.7);
}
