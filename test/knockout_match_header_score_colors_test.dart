import 'dart:math' as math;

import 'package:chessever2/screens/tour_detail/games_tour/utils/knockout_match_detector.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/match_header_widget.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpMatchHeader(
    WidgetTester tester, {
    required double player1Score,
    required double player2Score,
    bool hideScores = false,
    Brightness brightness = Brightness.dark,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final match = MatchHeaderModel(
      matchKey: 'carlsen-firouzja',
      player1: 'Magnus Carlsen',
      player2: 'Alireza Firouzja',
      player1Score: player1Score,
      player2Score: player2Score,
      games: const [],
      roundName: 'Final',
      isComplete: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme:
              brightness == Brightness.light
                  ? AppTheme.lightTheme
                  : AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: MatchHeader(match: match, hideScores: hideScores),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Color? scoreColor(WidgetTester tester, String score) {
    final text = tester.widget<Text>(find.text(score));
    return text.style?.color;
  }

  /// WCAG 2.1 relative luminance / contrast, so the light palette is held to
  /// the readable-text bar rather than to a hard-coded swatch. The score is
  /// small text, so AA is 4.5:1. `AppColors.brand` and `AppColors.danger` are
  /// byte-identical across both palettes and land at 2.29:1 and 3.43:1 on the
  /// light card — asserting on the constants alone would never notice.
  double relativeLuminance(Color color) {
    double channel(double value) =>
        value <= 0.04045
            ? value / 12.92
            : math.pow((value + 0.055) / 1.055, 2.4).toDouble();

    return 0.2126 * channel(color.r) +
        0.7152 * channel(color.g) +
        0.0722 * channel(color.b);
  }

  double contrastRatio(Color foreground, Color background) {
    final a = relativeLuminance(foreground);
    final b = relativeLuminance(background);
    final lighter = math.max(a, b);
    final darker = math.min(a, b);
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// The old score badge was a `Container` filled with the brand colour at
  /// 20% alpha. Asserting on the nearest ancestor `Container` instead would
  /// pass on a pill that merely lost its fill, and would trip over the card
  /// surface the header itself paints.
  bool hasTintedScorePill(WidgetTester tester) {
    final tint = kPrimaryColor.withValues(alpha: 0.2);
    return tester.widgetList<Container>(find.byType(Container)).any((
      container,
    ) {
      final decoration = container.decoration;
      return decoration is BoxDecoration && decoration.color == tint;
    });
  }

  testWidgets('decisive match paints winner cyan and loser red', (
    tester,
  ) async {
    await pumpMatchHeader(tester, player1Score: 4, player2Score: 1);

    expect(scoreColor(tester, '4.0'), kPrimaryColor);
    expect(scoreColor(tester, '1.0'), kRedColor);
  });

  testWidgets('score numbers have no tinted background', (tester) async {
    await pumpMatchHeader(tester, player1Score: 4, player2Score: 1);

    expect(hasTintedScorePill(tester), isFalse);
  });

  testWidgets('tied match paints both scores neutral white', (tester) async {
    await pumpMatchHeader(tester, player1Score: 2, player2Score: 2);

    final scoreTexts = tester.widgetList<Text>(find.text('2.0')).toList();
    expect(scoreTexts, hasLength(2));
    expect(
      scoreTexts.every((text) => text.style?.color == kWhiteColor),
      isTrue,
    );
  });

  testWidgets('light theme keeps both decisive scores readable', (
    tester,
  ) async {
    await pumpMatchHeader(
      tester,
      player1Score: 4,
      player2Score: 1,
      brightness: Brightness.light,
    );

    final surface = AppColors.light.surface;
    final leader = scoreColor(tester, '4.0')!;
    final trailer = scoreColor(tester, '1.0')!;

    expect(contrastRatio(leader, surface), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(trailer, surface), greaterThanOrEqualTo(4.5));
    // Still two distinguishable states, not one legible colour twice.
    expect(leader, isNot(trailer));
  });

  testWidgets('dark theme keeps both decisive scores readable', (tester) async {
    await pumpMatchHeader(tester, player1Score: 4, player2Score: 1);

    final surface = AppColors.dark.surface;

    expect(
      contrastRatio(scoreColor(tester, '4.0')!, surface),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrastRatio(scoreColor(tester, '1.0')!, surface),
      greaterThanOrEqualTo(4.5),
    );
  });

  testWidgets('tied match stays neutral on the light palette', (tester) async {
    await pumpMatchHeader(
      tester,
      player1Score: 2,
      player2Score: 2,
      brightness: Brightness.light,
    );

    final scoreTexts = tester.widgetList<Text>(find.text('2.0')).toList();
    expect(scoreTexts, hasLength(2));
    expect(
      scoreTexts.every(
        (text) => text.style?.color == AppColors.light.textPrimary,
      ),
      isTrue,
    );
  });

  testWidgets('no spoilers hides only the match score numbers', (tester) async {
    await pumpMatchHeader(
      tester,
      player1Score: 2,
      player2Score: 1,
      hideScores: true,
    );

    expect(find.text('Magnus Carlsen'), findsOneWidget);
    expect(find.text('Alireza Firouzja'), findsOneWidget);
    expect(find.text('2.0'), findsNothing);
    expect(find.text('1.0'), findsNothing);
  });
}
