import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:chessever2/screens/streaks/widgets/wall_class_switch.dart';
import 'package:chessever2/screens/streaks/widgets/wall_common.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

double contrast(Color foreground, Color background) {
  final fg = Color.alphaBlend(foreground, background);
  final l1 = fg.computeLuminance();
  final l2 = background.computeLuminance();
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

const double kUi = 3.0;
const AppColors light = AppColors.light;

Future<void> pumpThemed(
  WidgetTester tester,
  Widget child, {
  required Brightness brightness,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(393, 852);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        // Fresh app per pump: a theme switch would otherwise lerp.
        key: UniqueKey(),
        theme: brightness == Brightness.light
            ? AppTheme.lightTheme
            : AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(body: Center(child: child));
          },
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('Streak wall', () {
    test('dark fire is untouched; the light ramp clears 3:1 at its floor', () {
      expect(kWallFire, const [
        Color(0xFFE4552A),
        Color(0xFFF59A3C),
        Color(0xFFFFB454),
        Color(0xFFFFE08A),
      ]);
      expect(kWallFireLight, hasLength(kWallFire.length));
      for (final c in kWallFireLight) {
        // 0.76 is the faintest square the runs chart paints on paper.
        expect(
          contrast(c.withValues(alpha: 0.76), light.surface),
          greaterThanOrEqualTo(kUi),
        );
      }
      // The dark core yellow would vanish on the light card.
      expect(contrast(kWallFire.last, light.surface), lessThan(1.5));
    });

    testWidgets('palette follows the theme', (tester) async {
      late BuildContext captured;
      Widget probe() => Builder(
        builder: (context) {
          captured = context;
          return const SizedBox();
        },
      );
      await pumpThemed(tester, probe(), brightness: Brightness.dark);
      expect(wallFirePalette(captured), same(kWallFire));
      await pumpThemed(tester, probe(), brightness: Brightness.light);
      expect(wallFirePalette(captured), same(kWallFireLight));
    });

    Future<void> pumpSwitch(WidgetTester tester, Brightness brightness) {
      return pumpThemed(
        tester,
        SizedBox(
          width: 360,
          child: WallClassSwitch(
            selected: StreakTimeClass.standard,
            counts: const {
              StreakTimeClass.standard: 12,
              StreakTimeClass.rapid: 8,
              StreakTimeClass.blitz: 5,
            },
            onChanged: (_) {},
          ),
        ),
        brightness: brightness,
      );
    }

    List<String> drawnAssets(WidgetTester tester) => tester
        .widgetList<Image>(find.byType(Image))
        .map((i) => (i.image as AssetImage).assetName)
        .toList();

    testWidgets('class glyphs draw their paper twins on the light track', (
      tester,
    ) async {
      await pumpSwitch(tester, Brightness.light);
      expect(drawnAssets(tester), [
        PngAsset.classicalIconLight,
        PngAsset.rapidIconLight,
        PngAsset.blitzIconLight,
      ]);
      expect(find.byType(ColorFiltered), findsNothing);
    });

    testWidgets('dark draws the class glyphs as shipped', (tester) async {
      await pumpSwitch(tester, Brightness.dark);
      expect(drawnAssets(tester), [
        PngAsset.classicalIcon,
        PngAsset.rapidIcon,
        PngAsset.blitzIcon,
      ]);
      expect(find.byType(ColorFiltered), findsNothing);
    });
  });
}
