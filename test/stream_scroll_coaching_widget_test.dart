import 'package:chessever2/screens/chessboard/widgets/stream_scroll_coaching_host.dart';
import 'package:chessever2/screens/chessboard/utils/stream_scroll_coaching.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'stream_scroll_coaching_test.dart' show Store;

void main() {
  for (final light in [false, true]) {
    testWidgets(
      'lesson fits narrow phone, large text and reduced motion: light=$light',
      (tester) async {
        tester.view.physicalSize = const Size(320, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(1.6),
                  disableAnimations: true,
                ),
                child: Scaffold(
                  body: StreamScrollCoachingLesson(
                    onOk: () {},
                    onDontShowAgain: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('OK').hitTestable(), findsOneWidget);
        expect(find.text("Don't show again").hitTestable(), findsOneWidget);
        expect(
          tester
              .getRect(find.byKey(const ValueKey('stream_scroll_copy')))
              .overlaps(
                tester.getRect(
                  find.byKey(const ValueKey('stream_scroll_pinch')),
                ),
              ),
          isFalse,
        );
      },
    );
  }
  testWidgets(
    'two drags show separate copy/demo; OK removes demo, pulse lasts two seconds',
    (tester) async {
      final coach = StreamScrollCoachingController(Store());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            streamScrollCoachingProvider('a').overrideWith((ref) => coach),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: StreamScrollCoachingHost(
                gameId: 'a',
                active: true,
                child: ListView(children: const [SizedBox(height: 3000)]),
              ),
            ),
          ),
        ),
      );
      await tester.drag(find.byType(ListView), const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(find.text('OK'), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, -100));
      await tester.pump();
      await tester.pump();
      expect(find.text('OK'), findsOneWidget);
      final text = tester.getRect(
        find.byKey(const ValueKey('stream_scroll_copy')),
      );
      final demo = tester.getRect(
        find.byKey(const ValueKey('stream_scroll_pinch')),
      );
      expect(text.overlaps(demo), isFalse);
      expect(
        tester.getCenter(find.text("Don't show again")).dx,
        lessThan(tester.getCenter(find.text('OK')).dx),
      );
      await tester.tap(find.text('OK'));
      await tester.pump();
      expect(find.byKey(const ValueKey('stream_scroll_pinch')), findsNothing);
      expect(coach.pulsing, isTrue);
      await tester.pump(const Duration(milliseconds: 1999));
      expect(coach.pulsing, isTrue);
      await tester.pump(const Duration(milliseconds: 1));
      expect(coach.pulsing, isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
