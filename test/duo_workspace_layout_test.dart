import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/authentication/auth_screen.dart';
import 'package:chessever2/screens/authentication/auth_screen_provider.dart';
import 'package:chessever2/screens/authentication/auth_screen_state.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/auth_button.dart';
import 'package:chessever2/widgets/paywall/billing_issue_sheet.dart';
import 'package:chessever2/widgets/paywall/manage_subscription_sheet.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _Subscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _Subscription()
    : super(SubscriptionState(isSubscribed: true, provider: 'stripe'));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Country extends StateNotifier<AsyncValue<Country>>
    implements SelectedCountryNotifier {
  _Country() : super(AsyncData(CountryService().findByCode('US')!));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth extends StateNotifier<AuthScreenState>
    implements AuthScreenNotifier {
  _Auth() : super(const AuthScreenState());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Widget host(Widget child, {ThemeData? theme}) => ProviderScope(
    overrides: [
      subscriptionProvider.overrideWith((ref) => _Subscription()),
      countryDropdownProvider.overrideWith((ref) => _Country()),
      authScreenProvider.overrideWith((ref) => _Auth()),
    ],
    child: MaterialApp(
      theme: theme ?? AppTheme.darkTheme,
      builder: (context, child) {
        ResponsiveHelper.init(context);
        return child!;
      },
      home: child,
    ),
  );

  void shortWindow(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 300);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  testWidgets(
    'auth keeps its route state and reachable actions while folding',
    (tester) async {
      shortWindow(tester);
      await tester.pumpWidget(host(const AuthScreen(forcedGuestUpgrade: true)));
      await tester.pump(const Duration(milliseconds: 500));
      final authState = tester.state(find.byType(AuthScreen));
      for (final size in const [
        Size(600, 300),
        Size(720, 560),
        Size(393, 852),
      ]) {
        tester.view.physicalSize = size;
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull, reason: '$size');
        expect(tester.state(find.byType(AuthScreen)), same(authState));
        await tester.ensureVisible(find.text('Continue with Google'));
        await tester.pump(const Duration(milliseconds: 100));
        final button = find.byType(AuthButton).last;
        expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final light in [false, true]) {
    for (final billing in [false, true]) {
      testWidgets(
        '${light ? 'light' : 'dark'} ${billing ? 'billing' : 'subscription'} sheet scrolls to dismissal in a short window',
        (tester) async {
          shortWindow(tester);
          await tester.pumpWidget(
            host(
              Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => billing
                        ? showBillingIssueSheet(context: context)
                        : showManageSubscriptionSheet(context),
                    child: const Text('Open'),
                  ),
                ),
              ),
              theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final dismiss = find.text(billing ? 'Remind me later' : 'Done');
          await tester.ensureVisible(dismiss);
          await tester.pumpAndSettle();
          await tester.tap(dismiss);
          await tester.pumpAndSettle();
          expect(find.text('Open'), findsOneWidget);
          expect(dismiss, findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
