import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// The zinc and red inks the Favorites and Countrymen tabs share.
///
/// Dark keeps the historic Tailwind literals exactly. On paper those read at
/// 2.1:1 (zinc-400), 4.0:1 (zinc-500) and 3.1:1 (red-500), so light mode
/// swaps in the theme's secondary, tertiary and danger inks, which all clear
/// 4.5:1 on the light background.
extension CollectionInks on BuildContext {
  /// Supporting copy: subtitles, counts, meta lines.
  Color get collectionMutedInk =>
      isLightTheme ? colors.textSecondary : const Color(0xFFA1A1AA);

  /// The quietest readable line: footers, hints.
  Color get collectionSubtleInk =>
      isLightTheme ? colors.textTertiary : const Color(0xFF71717A);

  /// Errors, the active-filter mark and the favourite heart.
  Color get collectionAlertInk =>
      isLightTheme ? colors.danger : const Color(0xFFEF4444);
}
