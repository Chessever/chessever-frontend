import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/widgets/board_navigation_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Applies a 4x5 colour matrix to an opaque colour, as the engine would.
Color _apply(List<double> m, Color c) {
  int ch(int row) {
    final v =
        m[row * 5] * c.r * 255 +
        m[row * 5 + 1] * c.g * 255 +
        m[row * 5 + 2] * c.b * 255 +
        m[row * 5 + 4];
    return v.round().clamp(0, 255);
  }

  return Color.fromARGB(255, ch(0), ch(1), ch(2));
}

void main() {
  const light = AppColors.light;

  test('paper filter lands the checker on the theme inks', () {
    final filter = BoardNavigationIcon.paperMatrix(
      light: light.divider,
      dark: light.textSecondary,
    );
    final lightSquare = _apply(filter, const Color(0xFFFFFFFF));
    final darkSquare = _apply(filter, const Color(0xFF868686));

    expect(lightSquare.toARGB32(), light.divider.toARGB32());
    expect(darkSquare.toARGB32(), light.textSecondary.toARGB32());

    // The dark squares outline the board: 3:1 on every paper surface.
    for (final ground in [light.background, light.surface]) {
      expect(wcagContrast(darkSquare, ground), greaterThanOrEqualTo(3));
    }
    // And the checker still reads as a checker.
    expect(wcagContrast(lightSquare, darkSquare), greaterThanOrEqualTo(3));
  });

  Future<void> pump(WidgetTester tester, ThemeData theme) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(body: BoardNavigationIcon(size: 20)),
      ),
    );
    // MaterialApp animates a theme swap; read the settled theme.
    await tester.pumpAndSettle();
  }

  testWidgets('light remaps the art, dark draws it untouched', (tester) async {
    await pump(tester, AppTheme.lightTheme);
    expect(
      find.descendant(
        of: find.byType(BoardNavigationIcon),
        matching: find.byType(ColorFiltered),
      ),
      findsOneWidget,
    );

    await pump(tester, AppTheme.darkTheme);
    expect(
      find.descendant(
        of: find.byType(BoardNavigationIcon),
        matching: find.byType(ColorFiltered),
      ),
      findsNothing,
    );
  });
}
