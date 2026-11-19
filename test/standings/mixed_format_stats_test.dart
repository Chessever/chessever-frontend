import 'package:chessever2/screens/player_profile/widgets/performance_stats_row.dart';
import 'package:chessever2/screens/standings/utils/fide_rating_change.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/time_control_glyph.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'each format uses ordinary game points and sums Elo before rounding',
    () {
      expect(
        summarizeScorecardFormat([
          (opponentRating: 2500, score: 1, ratingChange: 2.4),
          (opponentRating: 2600, score: 0, ratingChange: -0.8),
        ]),
        (performance: 2550, ratingDiff: 2, score: 1.0, totalGames: 2),
      );
      expect(
        summarizeScorecardFormat([
          (opponentRating: 2500, score: 0.5, ratingChange: null),
        ]),
        (performance: 2500, ratingDiff: null, score: 0.5, totalGames: 1),
      );
      expect(summarizeScorecardFormat([]), (
        performance: null,
        ratingDiff: null,
        score: 0.0,
        totalGames: 0,
      ));
    },
  );

  testWidgets('mixed-format stat slots show help until a format is chosen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 851));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Future<void> show(PerformanceStatsRow row) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return row;
            },
          ),
        ),
      ),
    );
    const all = PerformanceStatsRow(
      score: 23,
      totalGames: 15,
      showCombinedEstimates: true,
      performanceRating: 2722,
      ratingDiff: 10,
    );
    await show(all);
    expect(find.text('≈2722'), findsOneWidget);
    expect(find.text('≈+10'), findsOneWidget);
    expect(find.text('Performance'), findsOneWidget);
    expect(find.text('Rating'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsNWidgets(2));
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text('23/15'), findsOneWidget);
    expect(find.text('-'), findsNothing);
    expect(find.text('vs. Expected'), findsNothing);
    final label = find.text('Rating');
    final icons = find.byIcon(Icons.info_outline);
    final icon = icons.last;
    expect(tester.getCenter(icon).dx, greaterThan(tester.getCenter(label).dx));
    expect(tester.getCenter(icon).dy, closeTo(tester.getCenter(label).dy, 1));
    for (final target in [
      icons.first,
      icon,
      label,
      find.text('Performance'),
      find.text('≈2722'),
      find.text('≈+10'),
    ]) {
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(find.text('Combined estimates'), findsOneWidget);
      final instruction = find.text(
        'Tap a rating box above to see that format’s stats.',
      );
      final caveat = find.text(
        'Combined stats are estimates, not official Elo changes.',
      );
      expect(instruction, findsOneWidget);
      expect(caveat, findsOneWidget);
      expect(
        tester.getTopLeft(instruction).dy,
        lessThan(tester.getTopLeft(caveat).dy),
      );
      final glyphs = find.byType(TimeControlGlyph);
      expect(
        tester.widgetList<TimeControlGlyph>(glyphs).map((glyph) => glyph.asset),
        [PngAsset.classicalIcon, PngAsset.rapidIcon, PngAsset.blitzIcon],
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }
    await show(
      const PerformanceStatsRow(
        score: 2.5,
        totalGames: 3,
        performanceRating: 2701,
        ratingDiff: 4,
      ),
    );
    expect(find.byIcon(Icons.info_outline), findsNothing);
    expect(find.text('2701'), findsOneWidget);
    expect(find.text('+4'), findsOneWidget);
    expect(find.text('2.5/3'), findsOneWidget);
    expect(find.text('23/15'), findsNothing);
    await show(all);
    expect(find.text('Performance'), findsOneWidget);
    expect(find.text('Rating'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsNWidgets(2));
    expect(find.text('23/15'), findsOneWidget);
    await show(const PerformanceStatsRow(score: 2.5, totalGames: 3));
    expect(find.byIcon(Icons.info_outline), findsNothing);
    expect(find.text('2.5/3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
