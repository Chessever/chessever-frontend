import 'package:chessever2/chat/botvinnik_icon.dart';
import 'package:chessever2/chat/chat_screen.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Botvinnik artwork's own teal (BotvinnikMark.teal), which
/// [BlendMode.modulate] multiplies by the tint.
const _artTeal = BotvinnikMark.teal;

Color _modulate(Color art, Color tint) => Color.from(
  alpha: 1,
  red: art.r * tint.r,
  green: art.g * tint.g,
  blue: art.b * tint.b,
);

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

Future<T> _under<T>(
  WidgetTester tester,
  ThemeData theme,
  T Function(BuildContext context) read,
) async {
  late T value;
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      // Swapping themes between reads must not lerp through the old one.
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

Future<ColorFilter?> _iconFilter(
  WidgetTester tester,
  ThemeData theme, {
  bool showShadow = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      themeAnimationDuration: Duration.zero,
      home: Scaffold(
        body: Center(child: BotvinnikIcon(size: 40, showShadow: showShadow)),
      ),
    ),
  );
  return tester.widget<SvgPicture>(find.byType(SvgPicture)).colorFilter;
}

void main() {
  group('BotvinnikIcon', () {
    testWidgets('dark keeps the brand cyan tint', (tester) async {
      expect(
        await _iconFilter(tester, AppTheme.darkTheme),
        const ColorFilter.mode(kPrimaryColor, BlendMode.modulate),
      );
    });

    testWidgets('light uses the paper tint, not colorScheme.primary', (
      tester,
    ) async {
      expect(
        await _iconFilter(tester, AppTheme.lightTheme),
        const ColorFilter.mode(BotvinnikIcon.paperTint, BlendMode.modulate),
      );
    });

    test('the paper tint keeps the mark and its face legible', () {
      final body = _modulate(_artTeal, BotvinnikIcon.paperTint);
      // The mark on the app bar (#E2ECEC) and the page surface.
      _expectContrast(
        body,
        AppColors.light.background,
        min: 3,
        what: 'Botvinnik body on background',
      );
      _expectContrast(
        body,
        AppColors.light.surface,
        min: 3,
        what: 'Botvinnik body on surface',
      );
      // The black glasses and mouth drawn on the body.
      _expectContrast(
        const Color(0xFF000000),
        body,
        min: 3,
        what: 'Botvinnik features on the body',
      );
      // Why not the accent-text teal: it drowns the face.
      expect(
        wcagContrast(
          const Color(0xFF000000),
          _modulate(_artTeal, AppColors.light.accentText),
        ),
        lessThan(3),
      );
    });

    testWidgets('draws the mark bare in both themes, no bloom', (tester) async {
      for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
        await _iconFilter(tester, theme, showShadow: true);
        final boxes = find.ancestor(
          of: find.byType(ClipRRect),
          matching: find.byType(DecoratedBox),
        );
        final shadowed = tester
            .widgetList<DecoratedBox>(boxes)
            .map((box) => box.decoration)
            .whereType<BoxDecoration>()
            .where((d) => d.boxShadow?.isNotEmpty ?? false);
        expect(shadowed, isEmpty, reason: '${theme.brightness} bloom');
      }
    });
  });

  group('chat surfaces', () {
    testWidgets('light answer links and code read on the answer bubble', (
      tester,
    ) async {
      final sheet = await _under(
        tester,
        AppTheme.lightTheme,
        chatMarkdownStyleSheet,
      );
      final bubble = AppTheme.lightTheme.colorScheme.surfaceContainerHigh;
      _expectContrast(sheet.a!.color!, bubble, min: 4.5, what: 'link');
      final block = (sheet.codeblockDecoration! as BoxDecoration).color!;
      _expectContrast(sheet.code!.color!, block, min: 4.5, what: 'code');
      expect(block, isNot(bubble), reason: 'a code block must read as one');
    });

    testWidgets('dark links take the brand ink, the rest stays stock', (
      tester,
    ) async {
      final (sheet, stock) = await _under(
        tester,
        AppTheme.darkTheme,
        (context) => (
          chatMarkdownStyleSheet(context),
          MarkdownStyleSheet.fromTheme(Theme.of(context)),
        ),
      );
      expect(sheet.a!.color, AppColors.dark.accentText);
      _expectContrast(
        sheet.a!.color!,
        AppTheme.darkTheme.colorScheme.surfaceContainerHigh,
        min: 4.5,
        what: 'dark link on the answer bubble',
      );
      expect(sheet.code, stock.code);
      expect(sheet.codeblockDecoration, stock.codeblockDecoration);
    });

    testWidgets('online dot clears 3:1 on the light app bar', (tester) async {
      final dot = await _under(tester, AppTheme.lightTheme, chatOnlineDotColor);
      _expectContrast(
        dot,
        AppTheme.lightTheme.appBarTheme.backgroundColor!,
        min: 3,
        what: 'online dot',
      );
      expect(
        await _under(tester, AppTheme.darkTheme, chatOnlineDotColor),
        const Color(0xff35c759),
      );
    });

    test('the BOTVINNIK label and spinners read on every chat surface', () {
      final scheme = AppTheme.lightTheme.colorScheme;
      for (final surface in [
        scheme.surface,
        scheme.surfaceContainerHigh,
        scheme.surfaceContainerLow,
      ]) {
        _expectContrast(
          AppColors.light.accentText,
          surface,
          min: 4.5,
          what: 'accentText on $surface',
        );
      }
      // Dark: accentText is the historic cyan, so nothing moves.
      expect(AppColors.dark.accentText, kPrimaryColor);
    });
  });
}
