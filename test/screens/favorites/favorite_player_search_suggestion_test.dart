import 'package:chessever2/screens/favorites/widgets/favorite_player_search_suggestion.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _gadir = PlayerStandingModel(
  countryCode: 'AZE',
  title: 'GM',
  name: 'Guseinov, Gadir',
  score: 2612,
  scoreChange: 0,
  matchScore: null,
  fideId: 13400630,
);

const _aivars = PlayerStandingModel(
  countryCode: 'CZE',
  title: 'GM',
  name: 'Guseinov, Aivars',
  score: 2410,
  scoreChange: 0,
  matchScore: null,
  fideId: 11600234,
);

Future<void> _pumpSuggestion(
  WidgetTester tester, {
  required List<PlayerStandingModel> results,
  List<PlayerStandingModel> favorites = const [],
  FavoritePlayerSearchSurface surface = FavoritePlayerSearchSurface.favorites,
}) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        favoritePlayerSearchProvider.overrideWith(
          (ref, query) async => results,
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: FavoritePlayerSearchSuggestion(
                query: 'guseinov',
                favorites: favorites,
                surface: surface,
                onAdd: (_) async {},
                onOpenPlayer: (_) {},
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  test('cancels a pending global lookup when its query is replaced', () async {
    final calls = <String>[];
    final container = ProviderContainer(
      overrides: [
        favoritePlayerSearchFetcherProvider.overrideWithValue((query) async {
          calls.add(query);
          return const [];
        }),
      ],
    );
    addTearDown(container.dispose);

    final first = container.listen(
      favoritePlayerSearchProvider('gu'),
      (_, __) {},
      fireImmediately: true,
    );
    first.close();
    final second = container.listen(
      favoritePlayerSearchProvider('gus'),
      (_, __) {},
      fireImmediately: true,
    );

    await Future<void>.delayed(const Duration(milliseconds: 350));

    expect(calls, ['gus']);
    second.close();
  });

  testWidgets('shows every matching player as an add choice', (tester) async {
    await _pumpSuggestion(tester, results: const [_gadir, _aivars]);

    expect(find.text('Looking for a player?'), findsOneWidget);
    expect(
      find.text('Choose a player to add to your favorites.'),
      findsOneWidget,
    );
    expect(find.text('Guseinov, Gadir'), findsOneWidget);
    expect(find.text('Guseinov, Aivars'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border_rounded), findsNWidgets(2));
  });

  testWidgets('does not offer an already-favorited player again', (
    tester,
  ) async {
    await _pumpSuggestion(
      tester,
      results: const [_gadir, _aivars],
      favorites: const [_gadir],
    );

    expect(find.text('Guseinov, Gadir'), findsNothing);
    expect(find.text('Guseinov, Aivars'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
  });

  testWidgets(
    'games surface explains when matched players are already favorites',
    (tester) async {
      await _pumpSuggestion(
        tester,
        results: const [_gadir],
        favorites: const [_gadir],
        surface: FavoritePlayerSearchSurface.games,
      );

      expect(find.text('No games found for this player.'), findsOneWidget);
      expect(find.text('Looking for a player?'), findsNothing);
    },
  );

  testWidgets('shows spelling guidance when global player search is empty', (
    tester,
  ) async {
    await _pumpSuggestion(tester, results: const []);

    expect(find.text('No player found'), findsOneWidget);
    expect(
      find.text('Check the spelling or try another name.'),
      findsOneWidget,
    );
  });
}
