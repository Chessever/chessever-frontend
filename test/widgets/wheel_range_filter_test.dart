import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/game_filter/wheel_range_filter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _WheelRangeFilterHarness extends StatefulWidget {
  const _WheelRangeFilterHarness();

  @override
  State<_WheelRangeFilterHarness> createState() =>
      _WheelRangeFilterHarnessState();
}

class _WheelRangeFilterHarnessState extends State<_WheelRangeFilterHarness> {
  RangeValues range = const RangeValues(1900, 2100);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);

          return Scaffold(
            body: Column(
              children: [
                Text('${range.start.round()}-${range.end.round()}'),
                WheelRangeFilter(
                  minValue: 1800,
                  maxValue: 2200,
                  currentStart: range.start,
                  currentEnd: range.end,
                  divisions: 8,
                  onChanged: (values) {
                    setState(() {
                      range = values;
                    });
                  },
                ),
              ],
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
    'keyboard editing updates the range without controller or lifecycle exceptions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const _WheelRangeFilterHarness());
      await tester.pumpAndSettle();

      expect(find.text('1900-2100'), findsOneWidget);

      await tester.tap(find.text('1900').first);
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), '2000');
      await tester.pump();
      _expectNoFlutterExceptions(tester);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('2000-2100'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      _expectNoFlutterExceptions(tester);
    },
  );
}
