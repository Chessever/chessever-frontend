import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/notification_settings/notif_category_tile.dart';
import 'package:chessever2/widgets/notification_settings/notif_filter_chip.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:chessever2/widgets/scroll_to_top_button.dart';
import 'package:chessever2/widgets/time_control_glyph.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

final _themes = {'light': AppTheme.lightTheme, 'dark': AppTheme.darkTheme};

void _expectContrast(
  Color fg,
  Color bg, {
  required double min,
  required String what,
}) {
  final ratio = wcagContrast(fg, bg);
  expect(
    ratio,
    greaterThanOrEqualTo(min),
    reason: '$what reads ${ratio.toStringAsFixed(2)}:1, needs $min:1',
  );
}

/// Pumps [child] under [theme] on a phone [width] wide at [textScale], with
/// the responsive units initialised.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  required ThemeData theme,
  double width = 393,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = Size(width, 852);
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      themeAnimationDuration: Duration.zero,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Center(child: child),
            ),
          );
        },
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
}

Package _package(String id, PackageType type, double price, String label) =>
    Package(
      id,
      type,
      StoreProduct(id, '', '', price, label, 'USD'),
      const PresentedOfferingContext('default', null, null),
    );

final _monthly = _package(r'$rc_monthly', PackageType.monthly, 4.99, r'$4.99');
final _annual = _package(r'$rc_annual', PackageType.annual, 39.99, r'$39.99');

/// The opaque fill a translucent [fill] shows over [ground].
Color _over(Color fill, Color ground) => Color.alphaBlend(fill, ground);

void main() {
  group('paywall plan cards', () {
    for (final entry in _themes.entries) {
      for (final (width, scale) in [(393.0, 1.0), (360.0, 1.3)]) {
        testWidgets(
          '${entry.key} ${width.toInt()}dp @${scale}x: one grid, no ragged rows',
          (tester) async {
            await _pump(
              tester,
              paywallPricingForTest(
                selectedPlan: ValueNotifier(PlanType.annual),
                monthlyPackage: _monthly,
                annualPackage: _annual,
              ),
              theme: entry.value,
              width: width,
              textScale: scale,
            );
            expect(tester.takeException(), isNull);

            Rect card(String title) => tester.getRect(
              find
                  .ancestor(
                    of: find.text(title),
                    matching: find.byType(AnimatedContainer),
                  )
                  .first,
            );
            final monthly = card('Monthly');
            final annual = card('Annual');
            expect(monthly.height, annual.height, reason: 'equal heights');
            expect(monthly.top, annual.top);

            // The billed prices share a baseline (to a sub-pixel: at 1.3x
            // the test font's square glyphs make FittedBox shrink each price
            // by a slightly different factor).
            expect(
              tester.getRect(find.text(r'$4.99')).bottom,
              moreOrLessEquals(
                tester.getRect(find.text(r'$39.99')).bottom,
                epsilon: 0.5,
              ),
            );
            // The savings note is plain type, not a floating pill.
            expect(find.text('BEST VALUE'), findsNothing);
            expect(find.text('Save 33%'), findsOneWidget);
          },
        );
      }

      testWidgets('${entry.key}: note and per-month line read on the card', (
        tester,
      ) async {
        await _pump(
          tester,
          paywallPricingForTest(
            selectedPlan: ValueNotifier(PlanType.annual),
            monthlyPackage: _monthly,
            annualPackage: _annual,
          ),
          theme: entry.value,
        );
        final context = tester.element(find.text('Annual'));
        final colors = context.colors;
        final fill = _over(
          kPrimaryColor.withValues(alpha: 0.15),
          colors.surface,
        );
        final note = tester.widget<Text>(find.text('Save 33%'));
        _expectContrast(note.style!.color!, fill, min: 4.5, what: 'note');
        final perMonth = tester.widget<Text>(find.textContaining('/mo').last);
        _expectContrast(
          _over(perMonth.style!.color!, fill),
          fill,
          min: 4.5,
          what: 'per-month line',
        );
      });
    }
  });

  group('notification time-control cards', () {
    for (final entry in _themes.entries) {
      testWidgets('${entry.key}: no bloom or tint, off marks clear 3:1', (
        tester,
      ) async {
        await _pump(
          tester,
          NotifCategoryTile(
            label: 'Favorite players',
            enabled: true,
            onToggle: () {},
            interactive: true,
            classical: true,
            onClassical: () {},
            rapid: false,
            onRapid: () {},
            blitz: false,
            onBlitz: () {},
          ),
          theme: entry.value,
        );
        final context = tester.element(find.text('Blitz'));
        final colors = context.colors;
        final light = context.isLightTheme;

        for (final label in ['Classical', 'Rapid', 'Blitz']) {
          final box =
              tester
                      .widget<AnimatedContainer>(
                        find
                            .ancestor(
                              of: find.text(label),
                              matching: find.byType(AnimatedContainer),
                            )
                            .first,
                      )
                      .decoration!
                  as BoxDecoration;
          expect(box.boxShadow ?? const [], isEmpty, reason: '$label bloom');
          expect(box.color, colors.surface, reason: '$label tinted fill');
        }

        // The faintest mark is the blue bolt; at the off opacity it still
        // clears 3:1 on the card.
        final off = tester
            .widget<AnimatedOpacity>(
              find
                  .ancestor(
                    of: find.byType(TimeControlGlyph).last,
                    matching: find.byType(AnimatedOpacity),
                  )
                  .first,
            )
            .opacity;
        final bolt = light ? const Color(0xFF0F6ECA) : const Color(0xFF1389FD);
        _expectContrast(
          _over(bolt.withValues(alpha: off), colors.surface),
          colors.surface,
          min: 3,
          what: 'off bolt',
        );
        expect(
          TimeControlGlyph.resolve(PngAsset.blitzIcon, light: light),
          light ? PngAsset.blitzIconLight : PngAsset.blitzIcon,
        );

        // The selected check reads on its ring colour.
        final check = tester.widget<Icon>(
          find.descendant(
            of: find
                .ancestor(
                  of: find.text('Classical'),
                  matching: find.byType(AnimatedContainer),
                )
                .first,
            matching: find.byIcon(Icons.check),
          ),
        );
        final ring = light ? colors.accentText : kPrimaryColor;
        _expectContrast(check.color!, ring, min: 3, what: 'check mark');
      });
    }
  });

  group('brand-fill controls', () {
    for (final entry in _themes.entries) {
      testWidgets('${entry.key}: selected filter chip label clears AA', (
        tester,
      ) async {
        await _pump(
          tester,
          NotifFilterChip(label: 'Rapid', selected: true, onTap: () {}),
          theme: entry.value,
        );
        final label = tester.widget<Text>(find.text('Rapid'));
        _expectContrast(
          label.style!.color!,
          kPrimaryColor,
          min: 4.5,
          what: 'chip label',
        );
      });

      testWidgets('${entry.key}: scroll-to-top arrow reads, one tight shadow', (
        tester,
      ) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);
        await _pump(
          tester,
          SizedBox(
            height: 600,
            child: Stack(
              children: [
                ListView.builder(
                  controller: controller,
                  itemExtent: 100,
                  itemCount: 40,
                  itemBuilder: (_, i) => Text('$i'),
                ),
                Align(
                  alignment: Alignment.bottomRight,
                  child: ScrollToTopButton(scrollController: controller),
                ),
              ],
            ),
          ),
          theme: entry.value,
        );
        controller.jumpTo(1200);
        await tester.pump(const Duration(milliseconds: 600));

        final icon = tester.widget<Icon>(
          find.byIcon(Icons.keyboard_arrow_up_rounded),
        );
        _expectContrast(icon.color!, kPrimaryColor, min: 3, what: 'arrow');
        final box =
            tester
                    .widget<Container>(
                      find
                          .ancestor(
                            of: find.byIcon(Icons.keyboard_arrow_up_rounded),
                            matching: find.byType(Container),
                          )
                          .first,
                    )
                    .decoration!
                as BoxDecoration;
        expect(box.boxShadow, hasLength(1));
        expect(box.boxShadow!.single.blurRadius, lessThanOrEqualTo(4));
        expect(box.boxShadow!.single.offset.dy, greaterThan(0));
      });
    }

    test('dialog actions: every fill and label pair clears AA', () {
      // Shorebird / billing / paywall actions: brand fill + inkOnAccent in
      // both themes; the ready-to-restart green per theme.
      for (final colors in [AppColors.dark, AppColors.light]) {
        _expectContrast(
          colors.inkOnAccent,
          colors.brand,
          min: 4.5,
          what: 'brand action',
        );
      }
      _expectContrast(
        AppColors.dark.inkOnAccent,
        AppColors.dark.success,
        min: 4.5,
        what: 'dark ready action',
      );
      _expectContrast(
        AppColors.light.surface,
        AppColors.light.successStrong,
        min: 4.5,
        what: 'light ready action',
      );
    });
  });
}
