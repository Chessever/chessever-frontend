import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/countrymen/countrymen_tab_screen.dart';
import 'package:chessever2/screens/countrymen/provider/countrymen_mode_provider.dart';
import 'package:chessever2/screens/favorites/favorite_players_provider.dart';
import 'package:chessever2/screens/favorites/favorites_tab_screen.dart';
import 'package:chessever2/screens/favorites/provider/favorites_mode_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/liquid_glass/glass_back_button.dart';
import 'package:chessever2/widgets/liquid_glass/glass_full_screen_page.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

void main() {
  final themes = <(String, ThemeData)>[
    ('light', AppTheme.lightTheme),
    ('dark', AppTheme.darkTheme),
  ];

  for (final theme in themes) {
    testWidgets(
      'Favorites is full-screen and overflow-free on a narrow ${theme.$1} phone',
      (tester) async {
        await _pumpHub(
          tester,
          theme: theme.$2,
          size: const Size(320, 700),
          overrides: <Override>[
            selectedFavoritesModeProvider.overrideWith(
              (_) => FavoritesScreenMode.favorites,
            ),
            favoritePlayersNotifierProvider.overrideWith(
              _EmptyFavoritePlayersNotifier.new,
            ),
          ],
          child: const FavoritesTabScreen(
            initialMode: FavoritesScreenMode.favorites,
          ),
        );

        _expectFullScreenHub(
          tester,
          rootKey: E2eIds.favoritesRoot,
          segmentsKey: 'favorites-segments',
          expectedViewportHeight: 700,
        );
      },
    );

    testWidgets(
      'Countrymen is full-screen and overflow-free on a ${theme.$1} tablet',
      (tester) async {
        final country = CountryService().findByCode('US')!;
        await _pumpHub(
          tester,
          theme: theme.$2,
          size: const Size(1024, 900),
          overrides: <Override>[
            selectedCountrymenModeProvider.overrideWith(
              (_) => CountrymenScreenMode.events,
            ),
            countryDropdownProvider.overrideWith((ref) {
              final notifier = SelectedCountryNotifier(ref);
              notifier.state = AsyncValue<Country>.data(country);
              return notifier;
            }),
            groupBroadcastRepositoryProvider.overrideWithValue(
              _EmptyGroupBroadcastRepository(),
            ),
          ],
          child: const CountrymenTabScreen(),
        );

        _expectFullScreenHub(
          tester,
          rootKey: E2eIds.countrymenRoot,
          segmentsKey: 'countrymen-segments',
          expectedViewportHeight: 900,
        );
        expect(find.bySemanticsLabel('Choose country'), findsOneWidget);
      },
    );
  }
}

class _EmptyFavoritePlayersNotifier extends FavoritePlayersNotifier {
  @override
  Future<FavoritePlayersState> build() async =>
      const FavoritePlayersState(players: <Never>[]);
}

class _EmptyGroupBroadcastRepository implements GroupBroadcastRepository {
  @override
  Future<List<GroupBroadcast>> getGroupBroadcastsByCountry({
    required String countryName,
    String? countryCode,
    String? searchQuery,
    int limit = 30,
    int offset = 0,
  }) async => const <GroupBroadcast>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpHub(
  WidgetTester tester, {
  required ThemeData theme,
  required Size size,
  required List<Override> overrides,
  required Widget child,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: LiquidGlassWidgets.wrap(
        child: MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2),
                  disableAnimations: true,
                ),
                child: child,
              );
            },
          ),
        ),
      ),
    ),
  );

  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void _expectFullScreenHub(
  WidgetTester tester, {
  required String rootKey,
  required String segmentsKey,
  required double expectedViewportHeight,
}) {
  expect(find.byKey(e2eKey(rootKey)), findsOneWidget);
  expect(find.byType(GlassFullScreenPage), findsOneWidget);
  expect(find.byType(AppBar), findsNothing);
  expect(find.byType(SliverAppBar), findsNothing);
  expect(find.byType(SliverPersistentHeader), findsNothing);

  expect(tester.getSize(find.byType(PageView)).height, expectedViewportHeight);
  expect(
    tester.getSize(find.byKey(ValueKey<String>(segmentsKey))).height,
    greaterThanOrEqualTo(48),
  );
  expect(
    tester.getSize(find.byType(GlassBackButton)).shortestSide,
    greaterThanOrEqualTo(48),
  );
  expect(tester.takeException(), isNull);
}
