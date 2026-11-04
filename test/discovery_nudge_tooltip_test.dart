import 'package:chessever2/services/discovery_dots/discovery_dot.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/adaptive_window.dart';
import 'package:chessever2/widgets/discovery_nudge_tooltip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  testWidgets(
    'nudge anchors in the safe Navigator and retains its page after fold',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(844, 700);
      tester.view.viewPadding = const FakeViewPadding(left: 64);
      addTearDown(tester.view.reset);
      final targetKey = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            builder: (context, child) => AdaptiveWindowScope(child: child!),
            home: Builder(
              builder: (context) => Scaffold(
                body: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 100),
                    child: TextButton(
                      key: targetKey,
                      onPressed: () {
                        final box =
                            targetKey.currentContext!.findRenderObject()
                                as RenderBox;
                        showDiscoveryNudgeTooltip(
                          context,
                          target: box.localToGlobal(Offset.zero) & box.size,
                          messages: const [
                            DiscoveryNudgeMessage(body: 'First tip'),
                            DiscoveryNudgeMessage(body: 'Second tip'),
                          ],
                        );
                      },
                      child: const Text('Open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final anchor = tester.getRect(find.byKey(targetKey));
      final tooltip = tester.getRect(find.byType(DiscoveryNudgeTooltip));
      expect(tooltip.center.dx, closeTo(anchor.center.dx, 1));
      await tester.tap(find.byTooltip('Next message'));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(393, 852);
      tester.view.viewPadding = const FakeViewPadding();
      await tester.pumpAndSettle();
      expect(find.text('2/2'), findsOneWidget);
      expect(find.text('Second tip'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close message'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final light in [false, true]) {
    testWidgets('tooltip stack fits small screen and large text (light=$light)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return Scaffold(
                  body: TextButton(
                    onPressed: () => showDiscoveryNudgeTooltip(
                      context,
                      messages: [
                        DiscoveryNudgeMessage(
                          body:
                              'A detailed tip with enough text to exercise the message reading area on a small phone with large text enabled and a visible See action.',
                          actionUrl: Uri.parse('https://chessever.com/reports'),
                        ),
                        const DiscoveryNudgeMessage(body: 'Second tip'),
                      ],
                    ),
                    child: const Text('Open'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('1/2'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final see = tester.getRect(find.text('See'));
      expect(see.right, lessThanOrEqualTo(320));
      expect(see.bottom, lessThanOrEqualTo(568));
      await tester.tap(find.byTooltip('Next message'));
      await tester.pumpAndSettle();
      expect(find.text('2/2'), findsOneWidget);
      expect(find.text('See'), findsNothing);
      await tester.tap(find.byTooltip('Previous message'));
      await tester.pumpAndSettle();
      expect(find.text('1/2'), findsOneWidget);
      await tester.tap(find.byTooltip('Close message'));
      await tester.pumpAndSettle();
      expect(find.text('1/2'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
