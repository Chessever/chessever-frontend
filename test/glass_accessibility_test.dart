import 'dart:math' as math;

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/widgets/liquid_glass/glass_back_button.dart';
import 'package:chessever2/widgets/liquid_glass/glass_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

void main() {
  testWidgets('custom motion resolves to zero when Reduce Motion is enabled', (
    tester,
  ) async {
    Duration? resolved;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              resolved = GlassMotion.resolveDuration(
                context,
                const Duration(milliseconds: 220),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(resolved, Duration.zero);
  });

  testWidgets('default glass back control meets mobile tap guidelines', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      LiquidGlassWidgets.wrap(
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Center(child: GlassBackButton(onPressed: () {})),
          ),
        ),
      ),
    );

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
  });

  test('inactive navigation text has 4.5:1 contrast in both themes', () {
    expect(
      _contrast(AppColors.light.tabInactive, AppColors.light.background),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(AppColors.dark.tabInactive, AppColors.dark.background),
      greaterThanOrEqualTo(4.5),
    );
  });
}

double _contrast(Color foreground, Color background) {
  final lighter = math.max(_luminance(foreground), _luminance(background));
  final darker = math.min(_luminance(foreground), _luminance(background));
  return (lighter + 0.05) / (darker + 0.05);
}

double _luminance(Color color) {
  double linearize(double component) =>
      component <= 0.04045
          ? component / 12.92
          : math.pow((component + 0.055) / 1.055, 2.4).toDouble();

  return 0.2126 * linearize(color.r) +
      0.7152 * linearize(color.g) +
      0.0722 * linearize(color.b);
}
