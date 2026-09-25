import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/widgets/player_initials_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const double _text = 4.5;
const double _ui = 3.0;

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

/// The ECO category hues (eco_filter_dropdown.dart) and the gold bullet
/// glyph: saturated colours other surfaces draw as text or icon ink.
const _ecoHues = [
  Color(0xFF6366F1),
  Color(0xFFF59E0B),
  Color(0xFF10B981),
  Color(0xFF8B5CF6),
  Color(0xFFEC4899),
];

/// SmartEventCard.levelColors.
const _smartEventHues = [
  kPrimaryColor,
  Color(0xFF38BDF8),
  Color(0xFFA3E635),
  Color(0xFFF97316),
  Color(0xFFF472B6),
  Color(0xFF22C55E),
];

/// Resolves [read] under [theme], with a real BuildContext.
Future<T> _under<T>(
  WidgetTester tester,
  ThemeData theme,
  T Function(BuildContext context) read,
) async {
  late T value;
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      themeAnimationDuration: Duration.zero,
      home: Builder(
        builder: (context) {
          value = read(context);
          return const SizedBox();
        },
      ),
    ),
  );
  return value;
}

void main() {
  group('light ColorScheme sits on the mint palette', () {
    final scheme = AppTheme.lightTheme.colorScheme;

    test('primary is the accent-text teal, never brand cyan', () {
      expect(scheme.primary, AppColors.light.accentText);
      expect(scheme.primary, isNot(kPrimaryColor));
    });

    test('primary reads as text on paper and carries its own label', () {
      _expectContrast(
        scheme.primary,
        scheme.surface,
        min: _text,
        what: 'primary on surface',
      );
      _expectContrast(
        scheme.primary,
        scheme.surfaceContainerHigh,
        min: _text,
        what: 'primary on surfaceContainerHigh',
      );
      _expectContrast(
        scheme.primary,
        scheme.surfaceContainerHighest,
        min: _text,
        what: 'primary on surfaceContainerHighest (selected drawer tile)',
      );
      _expectContrast(
        scheme.onPrimary,
        scheme.primary,
        min: _text,
        what: 'onPrimary on primary (filled buttons, send)',
      );
    });

    test('onSurfaceVariant is AA on every container step', () {
      for (final entry in {
        'surface': scheme.surface,
        'surfaceContainerLowest': scheme.surfaceContainerLowest,
        'surfaceContainerLow': scheme.surfaceContainerLow,
        'surfaceContainer': scheme.surfaceContainer,
        'surfaceContainerHigh': scheme.surfaceContainerHigh,
        'surfaceContainerHighest': scheme.surfaceContainerHighest,
      }.entries) {
        _expectContrast(
          scheme.onSurfaceVariant,
          entry.value,
          min: _text,
          what: 'onSurfaceVariant on ${entry.key}',
        );
        _expectContrast(
          scheme.onSurface,
          entry.value,
          min: _text,
          what: 'onSurface on ${entry.key}',
        );
      }
    });

    test('containers carry their own ink', () {
      _expectContrast(
        scheme.onPrimaryContainer,
        scheme.primaryContainer,
        min: _text,
        what: 'onPrimaryContainer (user bubble text)',
      );
      _expectContrast(
        scheme.onSecondaryContainer,
        scheme.secondaryContainer,
        min: _text,
        what: 'onSecondaryContainer',
      );
      _expectContrast(
        scheme.tertiary,
        scheme.surfaceContainerHighest,
        min: _ui,
        what: 'tertiary warning icon',
      );
      _expectContrast(
        scheme.error,
        scheme.surface,
        min: _text,
        what: 'error on surface',
      );
    });

    test('no stock M3 blue-grey or purple is left in the scheme', () {
      final seeded = ColorScheme.fromSeed(
        seedColor: kPrimaryColor,
        brightness: Brightness.light,
      );
      expect(scheme.surfaceContainerLow, isNot(seeded.surfaceContainerLow));
      expect(scheme.surfaceContainerHigh, isNot(seeded.surfaceContainerHigh));
      expect(scheme.primaryContainer, isNot(seeded.primaryContainer));
      expect(scheme.tertiary, isNot(seeded.tertiary));
    });
  });

  group('dark ColorScheme keeps its palette', () {
    final scheme = AppTheme.darkTheme.colorScheme;
    final seeded = ColorScheme.fromSeed(
      seedColor: kPrimaryColor,
      brightness: Brightness.dark,
    );

    test('keeps the brand roles', () {
      expect(scheme.primary, kPrimaryColor);
      expect(scheme.surface, kBlack2Color);
      expect(scheme.surfaceContainerHighest, kBlack3Color);
      expect(scheme.error, kRedColor);
    });

    // Dark mode ships exactly as it did before the light-mode work (user
    // rule: existing designs must not change), so these stay on HEAD values.
    test('filled-button labels keep the shipped white', () {
      expect(scheme.onPrimary, kWhiteColor);
    });

    test('tertiary stays on the seed', () {
      expect(scheme.tertiary, seeded.tertiary);
      expect(scheme.onTertiary, seeded.onTertiary);
    });

    test('keeps the seeded container roles', () {
      expect(scheme.surfaceContainerHigh, seeded.surfaceContainerHigh);
      expect(scheme.surfaceContainerLow, seeded.surfaceContainerLow);
      expect(scheme.primaryContainer, seeded.primaryContainer);
      expect(scheme.onSurfaceVariant, seeded.onSurfaceVariant);
    });
  });

  test('the light dialog dim is palette ink at a partial alpha', () {
    for (final stop in radialOverlayGradientLight.colors) {
      // #0E1A1C at a partial alpha: the palette's ink, never black.
      expect(stop.withValues(alpha: 1), AppColors.light.textPrimary);
      expect(stop.a, lessThan(0.4));
    }
  });

  group('accentInk', () {
    testWidgets('lifts saturated hues to AA on paper', (tester) async {
      final inks = await _under(
        tester,
        AppTheme.lightTheme,
        (context) => [
          for (final hue in [
            ..._ecoHues,
            ..._smartEventHues,
            const Color(0xFFFFD700),
          ])
            (hue, context.accentInk(hue)),
        ],
      );
      for (final (hue, ink) in inks) {
        _expectContrast(
          ink,
          AppColors.light.background,
          min: _text,
          what: 'accentInk($hue) on background',
        );
      }
    });

    testWidgets('is the identity in dark', (tester) async {
      final inks = await _under(
        tester,
        AppTheme.darkTheme,
        (context) => [
          for (final hue in [..._ecoHues, ..._smartEventHues])
            (hue, context.accentInk(hue)),
        ],
      );
      for (final (hue, ink) in inks) {
        expect(ink, hue);
      }
    });

    testWidgets('level ink holds on its own tinted facet', (tester) async {
      // SmartEventCard's smartEventAccentInk: the hue as ink, measured
      // against the darkest facet it lands on (~21% of the hue over the
      // surface), not just the plain background.
      Color facetOf(Color hue) => Color.alphaBlend(
        hue.withValues(alpha: 0.21),
        AppColors.light.surface,
      );
      final inks = await _under(
        tester,
        AppTheme.lightTheme,
        (context) => [
          for (final hue in _smartEventHues)
            (hue, context.accentInk(hue, on: facetOf(hue))),
        ],
      );
      for (final (hue, ink) in inks) {
        _expectContrast(
          ink,
          facetOf(hue),
          min: _text,
          what: 'level $hue on facet',
        );
      }
    });
  });

  group('title badge ink', () {
    const titles = [
      'GM',
      'IM',
      'FM',
      'CM',
      'NM',
      'WGM',
      'WIM',
      'WFM',
      'WCM',
      'WNM',
      '??',
    ];

    testWidgets('every badge label is AA on its fill in light', (tester) async {
      final pairs = await _under(
        tester,
        AppTheme.lightTheme,
        (context) => [
          for (final title in titles)
            (title, titleBadgeFill(context, getTitleBadgeColor(title))),
        ].map((e) => (e.$1, e.$2, titleBadgeInk(context, e.$2))).toList(),
      );
      for (final (title, fill, ink) in pairs) {
        _expectContrast(ink, fill, min: _text, what: '$title badge label');
      }
    });

    testWidgets('light keeps each hue unless no label can read on it', (
      tester,
    ) async {
      final fills = await _under(
        tester,
        AppTheme.lightTheme,
        (context) => {
          for (final title in titles)
            title: titleBadgeFill(context, getTitleBadgeColor(title)),
        },
      );
      // Gold, green and bronze read with ink or white as they are.
      for (final title in ['GM', 'IM', 'FM', 'WIM', 'WFM']) {
        expect(fills[title], getTitleBadgeColor(title), reason: title);
      }
      // Violet (CM) cannot reach 4.5:1 with either label, so it deepens.
      expect(fills['CM'], isNot(getTitleBadgeColor('CM')));
    });

    testWidgets('dark keeps the shipped badges: every hue, white labels', (
      tester,
    ) async {
      final pairs = await _under(
        tester,
        AppTheme.darkTheme,
        (context) => [
          for (final title in titles)
            (title, titleBadgeFill(context, getTitleBadgeColor(title))),
        ].map((e) => (e.$1, e.$2, titleBadgeInk(context, e.$2))).toList(),
      );
      for (final (title, fill, ink) in pairs) {
        expect(fill, getTitleBadgeColor(title), reason: '$title fill');
        expect(ink, const Color(0xFFFFFFFF), reason: '$title label');
      }
    });
  });
}
