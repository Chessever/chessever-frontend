import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/screens/onboarding/onboarding_flow_screen.dart';
import 'package:chessever2/screens/onboarding/player_selection_screen.dart';
import 'package:chessever2/screens/players/providers/player_providers.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/adaptive_window.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fixtures/duo_window_matrix.dart';

class _Country extends StateNotifier<AsyncValue<Country>>
    implements SelectedCountryNotifier {
  _Country() : super(AsyncData(CountryService().findByCode('US')!));

  @override
  String getCountryName(String code) => CountryService().findByCode(code)!.name;

  @override
  void selectCountry(String countryCode) {
    state = AsyncData(CountryService().findByCode(countryCode)!);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Players extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>>
    implements PlayerPaginationNotifier {
  _Players() : super(const AsyncData([]));

  @override
  Future<void> initFirstPage() async {}

  @override
  Future<void> setCountry(String? countryCode) async {}

  @override
  Future<void> setSearchQuery(String query) async {}

  @override
  Future<void> fetchNextPage() async {}

  @override
  bool get isFetching => false;

  @override
  bool get hasMore => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Favorites extends FavoritePlayersNotifierNew {
  @override
  Future<List<FavoritePlayer>> build() async => const [];
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://placeholder.supabase.co',
      publishableKey: 'placeholder-publishable-key',
    );
  });

  for (final light in [false, true]) {
    testWidgets(
      '${light ? 'light' : 'dark'} actual five-page onboarding retains the current step in every Duo state and transition',
      (tester) async {
        addTearDown(tester.view.reset);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.6;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        for (final start in duoWindowCases) {
          applyDuoWindow(tester, start);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                countryDropdownProvider.overrideWith((ref) => _Country()),
                onboardingPlayerProvider.overrideWith((ref) => _Players()),
                favoritePlayersProviderNew.overrideWith(_Favorites.new),
              ],
              child: MaterialApp(
                theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
                builder: (_, child) => AdaptiveWindowScope(child: child!),
                home: const OnboardingFlowScreen(),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 1200));
          final pageView = tester.widget<PageView>(find.byType(PageView));
          final controller = pageView.controller!;
          final route = ModalRoute.of(
            tester.element(find.byType(OnboardingFlowScreen)),
          );
          final container = ProviderScope.containerOf(
            tester.element(find.byType(OnboardingFlowScreen)),
          );
          container.read(countryDropdownProvider.notifier).selectCountry('JP');
          container.read(onboardingSelectedFideIdsProvider.notifier).state = {
            '1503014',
          };
          for (var page = 0; page < 5; page++) {
            tester.view.viewInsets = const FakeViewPadding();
            controller.jumpToPage(page);
            await tester.pump(const Duration(milliseconds: 1200));
            if (page == 2) {
              await tester.enterText(find.byType(TextField), 'Carlsen');
              tester.view.viewInsets = const FakeViewPadding(bottom: 300);
              await tester.pump(const Duration(milliseconds: 500));
            }
            for (final end in duoWindowCases) {
              applyDuoWindow(tester, start);
              await tester.pump();
              applyDuoWindow(tester, end, mirrorInsets: true);
              await tester.pump(const Duration(milliseconds: 1200));
              expect(
                tester.takeException(),
                isNull,
                reason: 'step $page: ${start.name} to ${end.name}',
              );
              expect(controller.page, closeTo(page, .001));
              expect(
                ModalRoute.of(
                  tester.element(find.byType(OnboardingFlowScreen)),
                ),
                same(route),
              );
              expect(
                container
                    .read(countryDropdownProvider)
                    .requireValue
                    .countryCode,
                'JP',
              );
              expect(container.read(onboardingSelectedFideIdsProvider), {
                '1503014',
              });
              if (page == 2) {
                expect(find.text('Carlsen'), findsOneWidget);
                expect(container.read(playerSearchQueryProvider), 'Carlsen');
              }
              final action = find.text(switch (page) {
                0 => 'Get Started',
                4 => 'Create free account',
                _ => 'Continue',
              });
              // Each page uses its own vertical scroll surface. EnsureVisible
              // proves its existing action can be reached in short landscapes.
              final actionElement = tester.element(action.last);
              final vertical = Scrollable.maybeOf(
                actionElement,
                axis: Axis.vertical,
              );
              if (vertical != null) {
                await vertical.position.ensureVisible(
                  actionElement.findRenderObject()!,
                  alignment: .5,
                );
              }
              await tester.pump(const Duration(milliseconds: 500));
              expect(
                action.hitTestable(),
                findsOneWidget,
                reason: 'step $page: ${end.name} action',
              );
              expect(controller.page, closeTo(page, .001));
              expect(tester.takeException(), isNull);
            }
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      },
    );
  }
}
