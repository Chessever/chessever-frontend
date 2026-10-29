import 'package:chessever2/screens/for_you/discovery/models/report_game_type.dart';
import 'package:chessever2/screens/for_you/discovery/reports_share.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/report_type_chips.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('dev.fluttercommunity.plus/share');
  final shares = <String>[];
  setUp(() {
    shares.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          shares.add((call.arguments as Map)['text'] as String);
          return 'success';
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.darkTheme,
    home: Builder(
      builder: (context) {
        ResponsiveHelper.init(context);
        return Scaffold(body: child);
      },
    ),
  );

  testWidgets(
    'every Reports type shares its own tab without changing selection',
    (tester) async {
      var selections = 0;
      await tester.pumpWidget(
        host(
          ReportTypeChips(
            selected: ReportGameType.comeback,
            onSelected: (_) => selections++,
            onLongPress: showReportsShareMenu,
          ),
        ),
      );
      for (final type in <ReportGameType?>[null, ...ReportGameType.values]) {
        final chip = find.byKey(ValueKey('report_type_${type?.key ?? 'all'}'));
        await tester.ensureVisible(chip);
        await tester.pumpAndSettle();
        await tester.longPress(chip);
        await tester.pumpAndSettle();
        expect(find.text('Share'), findsOneWidget);
        expect(selections, 0);
        await tester.tap(find.text('Share'));
        await tester.pumpAndSettle();
        expect(shares.last, reportsShareUri(type).toString());
      }
      final chip = find.byKey(const ValueKey('report_type_comeback'));
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      expect(selections, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a date heading shares the selected Reports type and day without collapsing',
    (tester) async {
      var toggles = 0;
      await tester.pumpWidget(
        host(
          ReportsDateShareHeader(
            date: '2026-10-28',
            type: ReportGameType.comeback,
            dateLabel: 'Oct 28',
            isExpanded: true,
            onToggle: () => toggles++,
          ),
        ),
      );
      await tester.tap(find.text('Oct 28'));
      expect(toggles, 1);
      await tester.longPress(find.text('Oct 28'));
      await tester.pumpAndSettle();
      expect(toggles, 1);
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(shares, [
        'https://chessever.com/app/reports/comeback?date=2026-10-28',
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unknown report dates offer no fake date link', (tester) async {
    await tester.pumpWidget(
      host(
        const ReportsDateShareHeader(
          date: null,
          type: null,
          dateLabel: 'Unknown date',
          isExpanded: true,
        ),
      ),
    );
    await tester.longPress(find.text('Unknown date'));
    await tester.pumpAndSettle();
    expect(find.text('Share'), findsNothing);
    expect(shares, isEmpty);
  });
}
