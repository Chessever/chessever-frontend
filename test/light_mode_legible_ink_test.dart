import 'dart:math' as math;

import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/chessboard/game_review/classification_style.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/screens/chessboard/models/like_tag.dart';
import 'package:chessever2/screens/chessboard/utils/legible_ink.dart';
import 'package:chessever2/screens/chessboard/widgets/context_pop_up_menu.dart';
import 'package:chessever2/screens/chessboard/widgets/nag_display.dart';
import 'package:chessever2/screens/library/widgets/swipe_action_card.dart';
import 'package:chessever2/screens/my_likes/widgets/date_section_header.dart';
import 'package:chessever2/screens/settings/widgets/engine_settings_body.dart';
import 'package:chessever2/screens/settings/widgets/settings_primitives.dart';
import 'package:chessever2/services/lichess_move_annotations_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// WCAG 2.x contrast; a translucent foreground is composited first.
double contrast(Color foreground, Color background) {
  final bg = background.a < 1
      ? Color.alphaBlend(background, Colors.white)
      : background;
  final fg = Color.alphaBlend(foreground, bg);
  final l1 = fg.computeLuminance();
  final l2 = bg.computeLuminance();
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

const AppColors light = AppColors.light;
const AppColors dark = AppColors.dark;

void expectAtLeast(
  Color ink,
  Color surface,
  double min, {
  required String what,
}) {
  final ratio = contrast(ink, surface);
  expect(
    ratio,
    greaterThanOrEqualTo(min),
    reason: '$what reads ${ratio.toStringAsFixed(2)}:1, needs $min:1',
  );
}

/// Every NAG code the notation can render.
const List<int> kRenderedNags = [
  1, 2, 3, 4, 5, 6, 7, 10, 13, 14, 15, 16, 17, 18, 19, 22, 32, 36, 40, 44, //
  132, 138, 140, 146,
];

/// The ECO badge fills of the player profile repertoire.
const List<Color> kEcoFills = [
  Color(0xFF4A90A4),
  Color(0xFF8B4513),
  Color(0xFF6B8E23),
  Color(0xFF8B008B),
  Color(0xFFB8860B),
];

/// The folder colour presets of the save sheet.
const List<Color> kFolderPresets = [
  Color(0xFF0FB4E5),
  Color(0xFF10B981),
  Color(0xFFF59E0B),
  Color(0xFFEF4444),
  Color(0xFF8B5CF6),
  Color(0xFFEC4899),
  Color(0xFF06B6D4),
  Color(0xFFF97316),
];

/// The pale variation-depth tints of the notation rails.
const List<Color> kVariationDepth = [
  Color(0xFFE9EDCC),
  Color(0xFFD6E3BC),
  Color(0xFFBFD3CB),
  Color(0xFFA6C2DA),
  Color(0xFF8EB2CB),
];

/// Builds [probe] under [theme] and hands back its context.
Future<BuildContext> pumpContext(WidgetTester tester, ThemeData theme) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return captured;
}

void main() {
  group('legibleHueInkOn', () {
    test('darkens every board palette hue to AA on the paper background', () {
      final hues = <String, Color>{
        for (final t in LichessMoveAnnotationType.values)
          'annotation ${t.name}': moveAnnotationColor(t),
        for (final tag in kLikeTags) 'tag ${tag.label}': tag.color,
        for (final nag in kRenderedNags)
          if (getNagDisplay(nag) != null)
            'nag \$$nag': getNagDisplay(nag)!.color,
        for (final c in kFolderPresets) 'folder $c': c,
        for (final c in kVariationDepth) 'depth $c': c,
        'amber star': Colors.amber,
      };
      for (final surface in [light.background, light.surface]) {
        for (final entry in hues.entries) {
          expectAtLeast(
            legibleHueInkOn(entry.value, surface),
            surface,
            4.5,
            what: '${entry.key} on $surface',
          );
        }
      }
    });

    test('holds for 200 seeded hues, and keeps hue and saturation', () {
      final random = math.Random(42);
      for (var i = 0; i < 200; i++) {
        final hue = HSLColor.fromAHSL(
          1,
          random.nextDouble() * 360,
          0.2 + random.nextDouble() * 0.8,
          0.3 + random.nextDouble() * 0.65,
        );
        final ink = legibleHueInkOn(hue.toColor(), light.background);
        expectAtLeast(ink, light.background, 4.5, what: 'seed $i');
        final inkHsl = HSLColor.fromColor(ink);
        // Lightness is the only thing that moves (8-bit rounding aside).
        expect(inkHsl.lightness, lessThanOrEqualTo(hue.lightness + 0.01));
        if (inkHsl.saturation > 0.05 && inkHsl.lightness > 0.05) {
          final dh = (inkHsl.hue - hue.hue).abs();
          expect(math.min(dh, 360 - dh), lessThan(6), reason: 'seed $i hue');
        }
      }
    });

    test('re-inking against the current-move plate keeps SAN at AA', () {
      // The notation's current-move plate on paper: ink at 8% on the page.
      final plate = Color.alphaBlend(
        light.textPrimary.withValues(alpha: 0.08),
        light.background,
      );
      for (final t in LichessMoveAnnotationType.values) {
        final ink = legibleHueInkOn(moveAnnotationColor(t), light.background);
        expectAtLeast(
          legibleHueInkOn(ink, plate),
          plate,
          4.5,
          what: '${t.name} on the current plate',
        );
      }
    });

    test('a hue that already clears the floor comes back unchanged', () {
      const deep = Color(0xFF26408B);
      expect(legibleHueInkOn(deep, light.background), deep);
    });

    test('keeps the caller alpha and still clears the floor', () {
      final ink = legibleHueInkOn(
        const Color(0xFFE9EDCC).withValues(alpha: 0.9),
        light.background,
      );
      expect(ink.a, closeTo(0.9, 0.001));
      expectAtLeast(ink, light.background, 4.5, what: 'translucent depth');
    });
  });

  group('theme-aware palette ink', () {
    testWidgets('dark returns every palette untouched', (tester) async {
      final context = await pumpContext(tester, AppTheme.darkTheme);
      for (final t in LichessMoveAnnotationType.values) {
        expect(moveAnnotationInk(context, t), moveAnnotationColor(t));
      }
      for (final c in GameMoveClassification.values) {
        expect(classificationInk(context, c), classificationColor(c));
      }
      for (final nag in kRenderedNags) {
        final d = getNagDisplay(nag);
        if (d == null) continue;
        expect(nagInk(context, d), d.color);
      }
      for (final tag in kLikeTags) {
        expect(tag.inkIn(context), tag.color);
      }
      expect(
        legibleHueInk(context, const Color(0xFFE9EDCC)),
        const Color(0xFFE9EDCC),
      );
      expect(labelOnFill(context, const Color(0xFF8B4513)), Colors.white);
    });

    testWidgets('light classification, NAG and tag ink clear AA', (
      tester,
    ) async {
      final context = await pumpContext(tester, AppTheme.lightTheme);
      for (final surface in [light.background, light.surface]) {
        for (final t in LichessMoveAnnotationType.values) {
          expectAtLeast(
            moveAnnotationInk(context, t),
            surface,
            4.5,
            what: 'annotation ${t.name}',
          );
        }
        for (final c in GameMoveClassification.values) {
          expectAtLeast(
            classificationInk(context, c),
            surface,
            4.5,
            what: 'classification ${c.name}',
          );
        }
      }
      for (final nag in kRenderedNags) {
        final d = getNagDisplay(nag);
        if (d == null) continue;
        expectAtLeast(
          nagInk(context, d),
          light.background,
          4.5,
          what: 'NAG ${d.symbol}',
        );
      }
      for (final tag in kLikeTags) {
        expectAtLeast(
          tag.inkIn(context),
          light.surfaceRecessed,
          3,
          what: 'tag ${tag.label} on the recessed well',
        );
      }
      // The raw palette is what light used to paint as text.
      expect(
        contrast(
          moveAnnotationColor(LichessMoveAnnotationType.brilliant),
          light.background,
        ),
        lessThan(4.5),
      );
    });

    testWidgets('labelOnFill reads on every filled badge in light', (
      tester,
    ) async {
      final context = await pumpContext(tester, AppTheme.lightTheme);
      final fills = <Color>[
        ...kEcoFills,
        light.danger,
        const Color(0xFFEA45D8), // !? badge
        const Color(0xFF9AA3AD), // evaluation slate
        const Color(0xFF4E5B4F), // □ badge
        kPrimaryColor, // eval bar label plate
      ];
      for (final fill in fills) {
        expectAtLeast(labelOnFill(context, fill), fill, 4.5, what: 'on $fill');
      }
    });
  });

  group('InkColorMapper', () {
    test('re-inks white, keeps alpha, darkens accents against the surface', () {
      final mapper = InkColorMapper(
        light.iconPrimary,
        on: light.surfaceRecessed,
      );
      expect(
        mapper.substitute(null, 'path', 'fill', const Color(0xFFFFFFFF)),
        light.iconPrimary,
      );
      final halfWhite = mapper.substitute(
        null,
        'path',
        'stroke',
        const Color(0x80FFFFFF),
      );
      expect(
        halfWhite.toARGB32() & 0x00FFFFFF,
        light.iconPrimary.toARGB32() & 0x00FFFFFF,
      );
      expect(halfWhite.a, closeTo(0x80 / 255, 0.01));

      const green = Color(0xFF1EB53A); // active.svg arrow
      final arrow = mapper.substitute(null, 'path', 'fill', green);
      expect(contrast(green, light.surfaceRecessed), lessThan(3));
      expectAtLeast(arrow, light.surfaceRecessed, 3, what: 'active arrow');

      // Without a surface, accents pass through untouched.
      expect(
        InkColorMapper(light.iconPrimary).substitute(null, 'p', 'fill', green),
        green,
      );
    });

    test('equality tracks ink and surface (the svg cache key)', () {
      expect(
        InkColorMapper(light.iconPrimary, on: light.surface),
        InkColorMapper(light.iconPrimary, on: light.surface),
      );
      expect(
        InkColorMapper(light.iconPrimary, on: light.surface) ==
            InkColorMapper(light.iconPrimary, on: light.background),
        isFalse,
      );
    });

    testWidgets('menu glyphs are re-inked on paper and untouched in dark', (
      tester,
    ) async {
      Future<ColorMapper?> mapperUnder(ThemeData theme) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return const Scaffold(
                  body: SizedBox(
                    width: 200,
                    child: MenuItemContent(
                      text: 'Pin',
                      iconAsset: SvgAsset.pin,
                    ),
                  ),
                );
              },
            ),
          ),
        );
        // Let the MaterialApp theme cross-fade settle on the new brightness.
        await tester.pumpAndSettle();
        final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
        return (picture.bytesLoader as SvgAssetLoader).colorMapper;
      }

      final lightMapper = await mapperUnder(AppTheme.lightTheme);
      expect(lightMapper, isA<InkColorMapper>());
      expect((lightMapper! as InkColorMapper).ink, light.iconPrimary);
      expect(await mapperUnder(AppTheme.darkTheme), isNull);
    });
  });

  group('settings switches', () {
    Future<void> pumpEngineSettings(
      WidgetTester tester,
      ThemeData theme,
    ) async {
      tester.view.physicalSize = const Size(393, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            engineSettingsProviderNew.overrideWith(
              () => _FakeEngineSettingsNotifier(const EngineSettings()),
            ),
          ],
          child: MaterialApp(
            theme: theme,
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return Scaffold(
                  body: SingleChildScrollView(
                    child: EngineSettingsBody(trackPersist: (_) {}),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('light: every enabled switch clears 3:1 in both states', (
      tester,
    ) async {
      await pumpEngineSettings(tester, AppTheme.lightTheme);
      final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
      expect(switches, isNotEmpty);
      for (final s in switches.where((s) => s.onChanged != null)) {
        final on = {WidgetState.selected};
        final off = <WidgetState>{};
        final onThumb = s.thumbColor!.resolve(on)!;
        final onTrack = s.trackColor!.resolve(on)!;
        final offThumb = s.thumbColor!.resolve(off)!;
        final offTrack = Color.alphaBlend(
          s.trackColor!.resolve(off)!,
          light.surface,
        );
        expectAtLeast(onTrack, light.surface, 3, what: 'ON track on card');
        expectAtLeast(onThumb, onTrack, 3, what: 'ON thumb on track');
        expectAtLeast(offThumb, offTrack, 3, what: 'OFF thumb on track');
        expect(
          onThumb == offThumb,
          isFalse,
          reason: 'ON and OFF share a thumb',
        );
      }
    });

    testWidgets('dark: the shared pair is the historic cyan', (tester) async {
      final context = await pumpContext(tester, AppTheme.darkTheme);
      final on = {WidgetState.selected};
      expect(settingsSwitchThumb(context).resolve(on), kPrimaryColor);
      expect(
        settingsSwitchTrack(context).resolve(on),
        kPrimaryColor.withValues(alpha: 0.35),
      );
      expect(
        settingsSwitchThumb(context).resolve(<WidgetState>{}),
        dark.textSecondary.withValues(alpha: 0.6),
      );
    });
  });

  group('swipe action reveal', () {
    /// Drags the card open without releasing and returns the label's ink.
    Future<Color> revealedLabelInk(
      WidgetTester tester,
      ThemeData theme,
      Color fill,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 320,
                    child: SwipeActionCard(
                      dismissKey: const ValueKey('swipe'),
                      icon: Icons.add_rounded,
                      label: 'Act',
                      backgroundColor: fill,
                      onAction: () async {},
                      // Opaque, so the drag lands on the card.
                      child: const ColoredBox(
                        color: Color(0xFF808080),
                        child: SizedBox(height: 72, width: 320),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(SwipeActionCard)),
      );
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(-20, 0));
        await tester.pump();
      }
      final label = tester.widget<Text>(find.text('Act'));
      final icon = tester.widget<Icon>(find.byIcon(Icons.add_rounded));
      expect(icon.color, label.style!.color, reason: 'icon and label share');
      await gesture.up();
      await tester.pumpAndSettle();
      return label.style!.color!;
    }

    testWidgets('light: the label reads on every action fill', (tester) async {
      final fills = <String, Color>{
        'remove (danger)': light.danger,
        'add (green)': kGreenColor,
        'add (deep green)': light.successStrong,
      };
      for (final entry in fills.entries) {
        final ink = await revealedLabelInk(
          tester,
          AppTheme.lightTheme,
          entry.value,
        );
        expectAtLeast(ink, entry.value, 4.5, what: entry.key);
      }
    });

    testWidgets('dark: the label stays the page ink', (tester) async {
      for (final fill in [kRedColor, kGreenColor]) {
        final ink = await revealedLabelInk(tester, AppTheme.darkTheme, fill);
        expect(ink, dark.textPrimary);
      }
    });
  });

  test('explorer turning-point dots clear 3:1 on the paper plate', () {
    const turn = Color(0xFFC55A1E);
    expect(contrast(turn, light.surfaceRecessed), lessThan(3));
    expectAtLeast(
      legibleHueInkOn(turn, light.surfaceRecessed, minContrast: 3),
      light.surfaceRecessed,
      3,
      what: 'turning point dot',
    );
  });

  testWidgets('date header chevron and count read on the recessed plate', (
    tester,
  ) async {
    Future<void> pumpHeader(ThemeData theme) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return const Scaffold(
                body: DateSectionHeader(
                  dateLabel: 'Today',
                  gameCount: 3,
                  isExpanded: false,
                  onToggle: _noop,
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpHeader(AppTheme.lightTheme);
    final chevron = tester.widget<Icon>(find.byType(Icon).last);
    expectAtLeast(
      chevron.color!,
      light.surfaceRecessed,
      3,
      what: 'date header chevron',
    );
    final container = tester.widget<Container>(find.byType(Container).first);
    final shadow = (container.decoration! as BoxDecoration).boxShadow!.single;
    expect(shadow.color, light.shadow, reason: 'tight tinted contact shadow');
    expect(shadow.blurRadius, lessThanOrEqualTo(4));

    await pumpHeader(AppTheme.darkTheme);
    final darkChevron = tester.widget<Icon>(find.byType(Icon).last);
    expect(darkChevron.color, dark.textPrimary.withValues(alpha: 0.5));
  });
}

class _FakeEngineSettingsNotifier extends EngineSettingsNotifierNew {
  _FakeEngineSettingsNotifier(this.settings);

  final EngineSettings settings;

  @override
  Future<EngineSettings> build() async => settings;
}

void _noop() {}
