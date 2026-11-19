import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/game_filter/rating_tier_filter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RatingTierFilterHarness extends StatefulWidget {
  const _RatingTierFilterHarness();

  @override
  State<_RatingTierFilterHarness> createState() =>
      _RatingTierFilterHarnessState();
}

class _RatingTierFilterHarnessState extends State<_RatingTierFilterHarness> {
  int? selectedMinRating;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);

          return Scaffold(
            body: Center(
              child: SizedBox(
                width: 240,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(selectedMinRating?.toString() ?? 'none'),
                    RatingTierFilter(
                      selectedMinRating: selectedMinRating,
                      onChanged: (value) {
                        setState(() => selectedMinRating = value);
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

void _expectNoFlutterExceptions(WidgetTester tester) {
  final exceptions = <Object>[];
  Object? exception;
  while ((exception = tester.takeException()) != null) {
    exceptions.add(exception!);
  }

  expect(exceptions, isEmpty, reason: exceptions.join('\n'));
}

void main() {
  testWidgets(
    'rating tier chips fit narrow filter dialogs and toggle selection',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(280, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const _RatingTierFilterHarness());
      await tester.pumpAndSettle();

      expect(find.text('GM'), findsOneWidget);
      expect(find.text('+2500'), findsOneWidget);
      expect(find.text('IM'), findsOneWidget);
      expect(find.text('+2400'), findsOneWidget);
      _expectNoFlutterExceptions(tester);

      await tester.tap(find.text('GM'));
      await tester.pumpAndSettle();

      expect(find.text('2500'), findsOneWidget);
      _expectNoFlutterExceptions(tester);

      await tester.tap(find.text('GM'));
      await tester.pumpAndSettle();

      expect(find.text('none'), findsOneWidget);
      _expectNoFlutterExceptions(tester);
    },
  );

  testWidgets('an odd tier list leads with a full-width row, the rest in '
      'pairs; 2700 is kept, not settled on GM', (tester) async {
    const tiers = [
      RatingTier(label: 'Super GM', subtitle: '+2700', minRating: 2700),
      RatingTier(label: 'GM', subtitle: '+2500', minRating: 2500),
      RatingTier(label: 'IM', subtitle: '+2400', minRating: 2400),
      RatingTier(label: 'FM', subtitle: '+2300', minRating: 2300),
      RatingTier(label: 'CM', subtitle: '+2200', minRating: 2200),
    ];
    int? picked = 2700;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: Center(
                child: SizedBox(
                  width: 300,
                  child: StatefulBuilder(
                    builder: (context, setState) => RatingTierFilter(
                      tierOptions: tiers,
                      selectedMinRating: picked,
                      onChanged: (value) => setState(() => picked = value),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    Rect chip(String label) => tester.getRect(
      find.ancestor(
        of: find.text(label),
        matching: find.byType(AnimatedContainer),
      ),
    );
    final top = chip('Super GM');
    final gm = chip('GM');
    final im = chip('IM');
    final fm = chip('FM');
    expect(top.width, moreOrLessEquals(gm.width + im.width + 8.w, epsilon: 1));
    expect(top.bottom, lessThan(gm.top));
    expect(gm.top, im.top);
    expect(fm.top, greaterThan(gm.bottom));
    expect(RatingTierFilter.normalizeMinRating(2700, among: tiers), 2700);
    expect(RatingTierFilter.normalizeMinRating(2700), 2500);

    await tester.tap(find.text('GM'));
    await tester.pump();
    expect(picked, 2500);
    _expectNoFlutterExceptions(tester);
  });
}
