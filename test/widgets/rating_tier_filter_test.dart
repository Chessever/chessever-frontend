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
}
