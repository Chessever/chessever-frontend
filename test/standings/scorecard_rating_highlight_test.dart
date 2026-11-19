import 'dart:io';
import 'dart:ui' as ui;

import 'package:chessever2/screens/standings/providers/player_ratings_provider.dart';
import 'package:chessever2/screens/standings/score_card_screen.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  testWidgets(
    'rating outlines preserve surface and text and distinguish a filter',
    (tester) async {
      final preview = Platform.environment['SCORECARD_PREVIEW'];
      if (preview != null) {
        final fonts = FontLoader('InterDisplay');
        for (final weight in ['Regular', 'Medium', 'Bold']) {
          fonts.addFont(rootBundle.load('assets/fonts/Inter-$weight.otf'));
        }
        await fonts.load();
      }
      await tester.binding.setSurfaceSize(const Size(393, 851));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final boundary = GlobalKey();
      var taps = 0;
      Widget row({required String? eventPool, required String? filter}) => Row(
        children: [
          for (final (pool, label, icon) in [
            ('standard', 'Classical', PngAsset.classicalIcon),
            ('rapid', 'Rapid', PngAsset.rapidIcon),
            ('blitz', 'Blitz', PngAsset.blitzIcon),
          ])
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: ScorecardRatingDisplay(
                  label: label,
                  playerName: 'Preview player',
                  timeControlType: pool,
                  assetPath: icon,
                  eventFormat: pool == eventPool,
                  selected: pool == filter,
                  onTap: () => taps++,
                ),
              ),
            ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            allRatingsProvider.overrideWith(
              (ref, request) async => const AllRatingsResult(
                standard: 2780,
                rapid: 2742,
                blitz: 2765,
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: Builder(
                  builder: (context) {
                    ResponsiveHelper.init(context);
                    return RepaintBoundary(
                      key: boundary,
                      child: ColoredBox(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Rapid event',
                                style: TextStyle(fontFamily: 'InterDisplay'),
                              ),
                              const SizedBox(height: 8),
                              row(eventPool: 'rapid', filter: null),
                              const SizedBox(height: 14),
                              const Text(
                                'Mixed event · Classical filter active',
                                style: TextStyle(fontFamily: 'InterDisplay'),
                              ),
                              const SizedBox(height: 8),
                              row(eventPool: null, filter: 'standard'),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      if (preview != null) {
        await tester.runAsync(() async {
          final context = boundary.currentContext!;
          for (final asset in [
            PngAsset.classicalIcon,
            PngAsset.rapidIcon,
            PngAsset.blitzIcon,
          ]) {
            await precacheImage(AssetImage(asset), context);
          }
        });
      }
      await tester.pumpAndSettle();
      BoxDecoration box(String label, int index) => tester
          .widgetList<Container>(
            find.ancestor(
              of: find.text(label).at(index),
              matching: find.byType(Container),
            ),
          )
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .first;
      final neutral = box('Classical', 0);
      final cue = box('Rapid', 0);
      final active = box('Classical', 1);
      expect(cue.color, neutral.color);
      expect(active.color, neutral.color);
      final cueBorder = (cue.border as Border).top;
      final activeBorder = (active.border as Border).top;
      expect(cueBorder.color.a, greaterThan(0));
      expect(activeBorder.color.a, greaterThan(cueBorder.color.a));
      expect(activeBorder.color.a, lessThan(1));
      expect(
        tester.widget<Text>(find.text('2780').first).style!.color,
        AppColors.dark.textPrimary,
      );
      expect(
        tester.widget<Text>(find.text('2780').last).style!.color,
        AppColors.dark.textPrimary,
      );
      await tester.tap(find.text('Rapid').first);
      expect(taps, 1);
      if (preview != null) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File(preview).writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    },
  );
}
