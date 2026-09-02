import 'package:chessever2/services/review_prompt_service.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    PackageInfo.setMockInitialValues(
      appName: 'ChessEver',
      packageName: 'com.chessEver.app',
      version: '34.10.1',
      buildNumber: '3408',
      buildSignature: '',
    );
  });

  testWidgets(
    'drawer-style pop still opens the form and relays after the host unmounts',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (homeContext) {
              ResponsiveHelper.init(homeContext);
              return Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(homeContext).push(
                        MaterialPageRoute<void>(
                          builder: (drawerContext) {
                            return Scaffold(
                              body: Center(
                                child: TextButton(
                                  onPressed:
                                      () =>
                                          ReviewPromptService.instance
                                              .openSidebarDirectFeedback(
                                                drawerContext,
                                              ),
                                  child: const Text('Feedback'),
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                    child: const Text('Open drawer'),
                  ),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open drawer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Feedback'));
      await tester.pumpAndSettle();

      expect(find.text('Your Feedback'), findsOneWidget);
      expect(find.text('Feedback'), findsNothing);

      await tester.enterText(find.byType(TextField), 'Clocks are unclear.');
      await tester.pump();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      // The old bug returned before send when the drawer context was
      // unmounted. Getting here with the form gone means the relay ran;
      // widget tests have no bot token, so Telegram logs "Not configured".
      expect(find.text('Your Feedback'), findsNothing);
      expect(find.text('Open drawer'), findsOneWidget);
    },
  );
}
