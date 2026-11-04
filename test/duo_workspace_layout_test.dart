import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/authentication/auth_screen.dart';
import 'package:chessever2/screens/authentication/auth_screen_provider.dart';
import 'package:chessever2/screens/authentication/auth_screen_state.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/adaptive_window.dart';
import 'package:chessever2/widgets/auth_button.dart';
import 'package:chessever2/widgets/paywall/billing_issue_sheet.dart';
import 'package:chessever2/widgets/paywall/manage_subscription_sheet.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'fixtures/duo_window_matrix.dart';

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
  String getCountryName(String code) => CountryService().findByCode(code)!.name;

  @override
  void selectCountry(String code) {
    state = AsyncData(CountryService().findByCode(code)!);
  }

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
      builder: (_, child) => AdaptiveWindowScope(child: child!),
      home: child,
    ),
  );

  void shortWindow(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 300);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  for (final light in [false, true]) {
    for (final countryPicker in [false, true]) {
      testWidgets(
        '${light ? 'light' : 'dark'} ${countryPicker ? 'country picker' : 'auth'} covers every Duo cold start and directed transition',
        (tester) async {
          shortWindow(tester);
          final widgetType = countryPicker ? CountryPickerWidget : AuthScreen;
          final label = countryPicker ? 'Continue' : 'Continue with Google';
          final states = [
            for (final window in duoWindowCases) (from: window, to: window),
            ...duoWindowTransitions,
          ];
          for (final transition in states) {
            applyDuoWindow(tester, transition.from);
            await tester.pumpWidget(
              host(
                countryPicker
                    ? const CountryPickerWidget()
                    : const AuthScreen(forcedGuestUpgrade: true),
                theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
              ),
            );
            await tester.pump(const Duration(milliseconds: 1200));
            final state = tester.state(find.byType(widgetType));
            final route = ModalRoute.of(
              tester.element(find.byType(widgetType)),
            );
            final container = ProviderScope.containerOf(
              tester.element(find.byType(widgetType)),
            );
            if (countryPicker) {
              container
                  .read(countryDropdownProvider.notifier)
                  .selectCountry('JP');
              await tester.pump();
            }
            for (final window in [transition.from, transition.to]) {
              applyDuoWindow(
                tester,
                window,
                mirrorInsets: window == transition.to,
              );
              await tester.pump(const Duration(milliseconds: 500));
              expect(tester.takeException(), isNull, reason: window.name);
              expect(tester.state(find.byType(widgetType)), same(state));
              expect(
                ModalRoute.of(tester.element(find.byType(widgetType))),
                same(route),
              );
              if (countryPicker) {
                expect(
                  container
                      .read(countryDropdownProvider)
                      .requireValue
                      .countryCode,
                  'JP',
                );
              }
              await tester.ensureVisible(find.text(label));
              await tester.pump(const Duration(milliseconds: 100));
              expect(find.text(label).hitTestable(), findsOneWidget);
              if (!countryPicker) {
                expect(
                  tester.getSize(find.byType(AuthButton).last).height,
                  greaterThanOrEqualTo(44),
                );
              }
              expect(tester.takeException(), isNull, reason: window.name);
            }
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
          }
        },
      );
    }
  }

  for (final light in [false, true]) {
    for (final billing in [false, true]) {
      testWidgets(
        '${light ? 'light' : 'dark'} ${billing ? 'billing' : 'subscription'} sheet retains its route and dismissal across all Duo transitions and a short window',
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
          final route = ModalRoute.of(tester.element(dismiss));
          for (final transition in duoWindowTransitions) {
            for (final window in [transition.from, transition.to]) {
              applyDuoWindow(
                tester,
                window,
                mirrorInsets: window == transition.to,
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull, reason: window.name);
              expect(ModalRoute.of(tester.element(dismiss)), same(route));
              await tester.ensureVisible(dismiss);
              await tester.pumpAndSettle();
              expect(dismiss.hitTestable(), findsOneWidget);
            }
          }
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
