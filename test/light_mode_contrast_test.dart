import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/screens/library/utils/library_search_bar.dart'
    as library_utils;
import 'package:chessever2/screens/settings/settings_page.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/theme/theme_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/search/gameSearch/enhanced_game_search_widget.dart';
import 'package:chessever2/widgets/search/gameSearch/game_search_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// WCAG 2.x contrast ratio. A translucent foreground is composited over the
/// background first, which is how it actually renders.
double contrast(Color foreground, Color background) {
  final bg = background.a < 1 ? Color.alphaBlend(background, Colors.white) : background;
  final fg = Color.alphaBlend(foreground, bg);
  final l1 = fg.computeLuminance();
  final l2 = bg.computeLuminance();
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

const double kBodyText = 4.5; // WCAG AA, normal text
const double kLargeOrUi = 3.0; // WCAG AA, large text and UI components

const AppColors light = AppColors.light;
const AppColors dark = AppColors.dark;

/// Every paper surface light-mode text is drawn on.
final Map<String, Color> lightSurfaces = {
  'background': light.background,
  'surface': light.surface,
  'surfaceElevated': light.surfaceElevated,
  'popup': light.popup,
};

void expectReadable(
  Color ink,
  Color surface, {
  double min = kBodyText,
  required String what,
}) {
  final ratio = contrast(ink, surface);
  expect(
    ratio,
    greaterThanOrEqualTo(min),
    reason: '$what reads ${ratio.toStringAsFixed(2)}:1, needs $min:1',
  );
}

/// Pumps [child] under [theme] with the responsive units initialised.
Future<void> pumpThemed(
  WidgetTester tester,
  Widget child, {
  ThemeData? theme,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: theme ?? AppTheme.lightTheme,
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

BoxDecoration searchFieldDecoration(WidgetTester tester) {
  final container = tester.widget<AnimatedContainer>(
    find.byType(AnimatedContainer).first,
  );
  return container.decoration! as BoxDecoration;
}

void main() {
  group('light palette tokens', () {
    test('primary, secondary and tertiary ink clear AA on every paper surface',
        () {
      for (final entry in lightSurfaces.entries) {
        expectReadable(light.textPrimary, entry.value,
            what: 'textPrimary on ${entry.key}');
        expectReadable(light.textPrimaryMuted, entry.value,
            what: 'textPrimaryMuted on ${entry.key}');
        expectReadable(light.textSecondary, entry.value,
            what: 'textSecondary on ${entry.key}');
        expectReadable(light.textTertiary, entry.value,
            what: 'textTertiary on ${entry.key}');
        expectReadable(light.tabInactive, entry.value,
            what: 'tabInactive on ${entry.key}');
      }
    });

    test('accent text is AA on paper where raw brand cyan is not', () {
      for (final entry in lightSurfaces.entries) {
        expectReadable(light.accentText, entry.value,
            what: 'accentText on ${entry.key}');
        // Documents why accentText exists: cyan as text fails on paper.
        expect(contrast(light.brand, entry.value), lessThan(kLargeOrUi));
      }
      // Still reads on the brand-tinted plates selected rows sit on.
      final tint = Color.alphaBlend(
        light.brand.withValues(alpha: 0.15),
        light.surface,
      );
      expectReadable(light.accentText, tint, what: 'accentText on brand@15%');
    });

    test('signal colours used as text clear AA on paper', () {
      for (final entry in lightSurfaces.entries) {
        expectReadable(light.danger, entry.value,
            what: 'danger on ${entry.key}');
        expectReadable(light.success, entry.value,
            what: 'success on ${entry.key}');
        expectReadable(light.successStrong, entry.value,
            what: 'successStrong on ${entry.key}');
        expectReadable(light.dangerMuted, entry.value,
            what: 'dangerMuted on ${entry.key}');
        expectReadable(light.titleAccent, entry.value,
            what: 'titleAccent on ${entry.key}');
      }
    });

    test('hints and secondary icons clear the 3:1 UI floor', () {
      for (final entry in lightSurfaces.entries) {
        expectReadable(light.placeholder, entry.value,
            min: kLargeOrUi, what: 'placeholder on ${entry.key}');
        expectReadable(light.iconSecondary, entry.value,
            min: kLargeOrUi, what: 'iconSecondary on ${entry.key}');
      }
    });

    test('ink on a brand fill and inverse ink both read', () {
      expectReadable(light.inkOnAccent, light.brand,
          what: 'inkOnAccent on brand');
      expectReadable(light.textInverse, light.surfaceInverse,
          what: 'textInverse on surfaceInverse');
    });

    test('dark palette is untouched by the light-mode work', () {
      expect(dark.accentText, kPrimaryColor);
      expect(dark.brand, kPrimaryColor);
      expect(dark.danger, kRedColor);
      expect(dark.successStrong, kGreenColor);
      expect(dark.textPrimary, kWhiteColor);
      expect(dark.background, kBackgroundColor);
    });
  });

  group('light ThemeData', () {
    final theme = AppTheme.lightTheme;

    test('has a legible tooltip theme', () {
      final tooltip = theme.tooltipTheme;
      final decoration = tooltip.decoration as BoxDecoration?;
      expect(decoration, isNotNull, reason: 'light theme must set a tooltip');
      expect(tooltip.textStyle?.color, isNotNull);
      expectReadable(tooltip.textStyle!.color!, decoration!.color!,
          what: 'tooltip text on tooltip plate');
    });

    test('text buttons and error ink avoid raw cyan / raw red on paper', () {
      final fg = theme.textButtonTheme.style!.foregroundColor!.resolve({})!;
      expectReadable(fg, light.surface, what: 'TextButton label on surface');
      expectReadable(theme.colorScheme.error, light.surface,
          what: 'colorScheme.error on surface');
    });

    test('scaffold and app bar ink read on the mint background', () {
      expectReadable(theme.appBarTheme.foregroundColor!,
          theme.appBarTheme.backgroundColor!,
          what: 'app bar title');
      expectReadable(theme.colorScheme.onSurface, theme.colorScheme.surface,
          what: 'onSurface on surface');
    });

    test('status bar icons flip dark on the light theme', () {
      final overlay = AppTheme.overlayFor(Brightness.light);
      expect(overlay.statusBarIconBrightness, Brightness.dark);
      expect(overlay.systemNavigationBarIconBrightness, Brightness.dark);
      final darkOverlay = AppTheme.overlayFor(Brightness.dark);
      expect(darkOverlay.statusBarIconBrightness, Brightness.light);
    });
  });

  group('textInk', () {
    testWidgets('lifts faint ink to AA on paper, keeping the order',
        (tester) async {
      final inks = <double, Color>{};
      await pumpThemed(
        tester,
        Builder(
          builder: (context) {
            for (final a in [0.2, 0.3, 0.4, 0.5, 0.6]) {
              inks[a] = context.textInk(a);
            }
            return const SizedBox.shrink();
          },
        ),
      );

      double? previous;
      for (final entry in inks.entries) {
        for (final surface in lightSurfaces.entries) {
          expectReadable(entry.value, surface.value,
              what: 'textInk(${entry.key}) on ${surface.key}');
        }
        if (previous != null) {
          expect(entry.value.a, greaterThan(previous),
              reason: 'a fainter request must still render fainter');
        }
        previous = entry.value.a;
      }
    });

    testWidgets('is exactly textPrimary.withValues(alpha) in dark mode',
        (tester) async {
      final inks = <double, Color>{};
      await pumpThemed(
        tester,
        Builder(
          builder: (context) {
            for (final a in [0.2, 0.4, 0.6]) {
              inks[a] = context.textInk(a);
            }
            return const SizedBox.shrink();
          },
        ),
        theme: AppTheme.darkTheme,
      );
      for (final entry in inks.entries) {
        expect(entry.value, dark.textPrimary.withValues(alpha: entry.key));
      }
    });
  });

  group('P0 search fields', () {
    Future<void> pumpField(
      WidgetTester tester,
      Widget Function(TextEditingController, FocusNode) build, {
      ThemeData? theme,
    }) async {
      final controller = TextEditingController(text: 'Carlsen');
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      await pumpThemed(
        tester,
        SizedBox(width: 360, child: build(controller, focus)),
        theme: theme,
      );
    }

    Widget enhanced(TextEditingController c, FocusNode f) => SearchBarWidget(
          hintText: 'Search games',
          autoFocus: false,
          controller: c,
          focusNode: f,
          onClose: () {},
        );

    Widget libraryUtils(TextEditingController c, FocusNode f) =>
        library_utils.SearchBarWidget(
          hintText: 'Search library',
          autoFocus: false,
          controller: c,
          focusNode: f,
          onClose: () {},
        );

    for (final (name, build) in [
      ('games SearchBarWidget', enhanced),
      ('library SearchBarWidget', libraryUtils),
    ]) {
      testWidgets('$name sits on paper with legible ink in light mode',
          (tester) async {
        await pumpField(tester, build);
        final fill = searchFieldDecoration(tester).color!;
        expect(fill, light.surface, reason: 'no grey[900] slab on paper');

        final field = tester.widget<TextField>(find.byType(TextField));
        expectReadable(field.style!.color!, fill, what: '$name input text');
        expectReadable(field.decoration!.hintStyle!.color!, fill,
            what: '$name hint');

        final icon = tester.widget<Icon>(find.byIcon(Icons.search));
        expectReadable(icon.color!, fill,
            min: kLargeOrUi, what: '$name search glyph');
        // The resting field still has an edge against the mint page.
        final border = searchFieldDecoration(tester).border! as Border;
        expect(border.top.color, light.divider);
      });

      testWidgets('$name keeps its historic dark look', (tester) async {
        await pumpField(tester, build, theme: AppTheme.darkTheme);
        expect(searchFieldDecoration(tester).color, Colors.grey[900]);
        final icon = tester.widget<Icon>(find.byIcon(Icons.search));
        expect(icon.color, Colors.white70);
      });
    }

    testWidgets('empty games search state reads on paper', (tester) async {
      await pumpThemed(tester, const EmptySearchWidget(query: 'zzz'));
      await tester.pump(const Duration(milliseconds: 700));
      final bg = AppTheme.lightTheme.scaffoldBackgroundColor;
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        expectReadable(text.style!.color!, bg,
            what: 'empty-state "${text.data}"');
      }
      final icon = tester.widget<Icon>(find.byIcon(Icons.search_off));
      expectReadable(icon.color!, bg,
          min: kLargeOrUi, what: 'empty-state glyph');
    });
  });

  group('Settings → Appearance', () {
    setUpAll(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    setUp(() async {
      final prefs = await SharedPreferencesService.instance.ensureInitialized();
      await prefs?.remove('app.theme_mode.v1');
    });

    testWidgets('offers Dark / Auto / Light with Dark selected by default',
        (tester) async {
      await pumpThemed(tester, const SettingsAppearanceSection());
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Appearance'), findsOneWidget);
      for (final label in ['Dark', 'Auto', 'Light']) {
        expect(find.text(label), findsOneWidget);
      }
      // A user who never chose sees Dark selected, announced as such.
      expect(
        tester.getSemantics(find.text('Dark')),
        isSemantics(
          label: 'Dark appearance',
          isButton: true,
          isSelected: true,
        ),
      );
      expect(
        tester.getSemantics(find.text('Light')),
        isSemantics(label: 'Light appearance', isSelected: false),
      );
    });

    testWidgets('tapping Light switches the theme mode', (tester) async {
      late WidgetRef capturedRef;
      await pumpThemed(
        tester,
        Consumer(
          builder: (context, ref, _) {
            capturedRef = ref;
            return const SettingsAppearanceSection();
          },
        ),
      );
      expect(capturedRef.read(themeModeProvider), ThemeMode.dark);

      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();
      expect(capturedRef.read(themeModeProvider), ThemeMode.light);

      await tester.tap(find.text('Auto'));
      await tester.pumpAndSettle();
      expect(capturedRef.read(themeModeProvider), ThemeMode.system);
    });

    testWidgets('segment labels clear AA against the track in light mode',
        (tester) async {
      await pumpThemed(tester, const SettingsAppearanceSection());
      await tester.pump(const Duration(milliseconds: 50));

      final track = light.background;
      Color inkOf(String label) =>
          tester.widget<Text>(find.text(label)).style!.color!;
      // Selected label sits on the white thumb, the rest on the inset track.
      expectReadable(inkOf('Dark'), Colors.white, what: 'selected label');
      expectReadable(inkOf('Auto'), track, what: 'unselected Auto');
      expectReadable(inkOf('Light'), track, what: 'unselected Light');
      expectReadable(
        tester.widget<Text>(find.text('Appearance')).style!.color!,
        light.surface,
        what: 'card title',
      );
    });
  });
}
