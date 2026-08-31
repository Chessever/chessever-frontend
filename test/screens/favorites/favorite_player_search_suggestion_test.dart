import 'package:chessever2/screens/favorites/widgets/favorite_player_search_suggestion.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/figma_player_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _mamedyarov = PlayerStandingModel(
  countryCode: 'AZE',
  title: 'GM',
  name: 'Mamedyarov, Shakhriyar',
  score: 2740,
  scoreChange: 0,
  matchScore: null,
  fideId: 13401319,
);

Map<String, dynamic> _row({
  required String fideId,
  required String name,
  String? title,
  int rating = 2600,
  String fed = 'AZE',
}) => <String, dynamic>{
  'fideId': fideId,
  'name': name,
  'title': title,
  'rating': rating,
  'fed': fed,
};

void main() {
  Widget host({
    required FavoritePlayerSearchFetcher fetcher,
    required String query,
    List<PlayerStandingModel> favorites = const [],
    FavoritePlayerSearchSurface surface = FavoritePlayerSearchSurface.favorites,
    void Function(PlayerStandingModel)? onAdd,
    void Function(PlayerStandingModel)? onOpen,
  }) {
    return ProviderScope(
      overrides: [
        favoritePlayerSearchFetcherProvider.overrideWithValue(fetcher),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: SingleChildScrollView(
                child: FavoritePlayerSearchSuggestion(
                  query: query,
                  favorites: favorites,
                  surface: surface,
                  onAdd: (player) async => onAdd?.call(player),
                  onOpenPlayer: (player) => onOpen?.call(player),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// The debounce is a real delay inside the provider.
  Future<void> settleSearch(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  testWidgets('offers matching players the user does not follow yet', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        query: 'carl',
        fetcher:
            (_) async => [
              _row(
                fideId: '1503014',
                name: 'Carlsen, Magnus',
                title: 'GM',
                rating: 2839,
                fed: 'NOR',
              ),
            ],
      ),
    );
    await settleSearch(tester);

    expect(find.text('Not following yet'), findsOneWidget);
    // Rendered with the same card the Favorites list uses, not a bespoke row.
    expect(find.byType(FigmaPlayerCard), findsOneWidget);
    expect(find.text('Carlsen, Magnus'), findsOneWidget);
  });

  testWidgets('never offers a player who is already a favourite', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        query: 'mamed',
        favorites: const [_mamedyarov],
        fetcher:
            (_) async => [
              _row(
                fideId: '13401319',
                name: 'Mamedyarov, Shakhriyar',
                title: 'GM',
              ),
            ],
      ),
    );
    await settleSearch(tester);

    expect(find.byType(FigmaPlayerCard), findsNothing);
    expect(find.text('Already in your favorites'), findsOneWidget);
  });

  testWidgets('matches an existing favourite by name when ids differ', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        query: 'mamed',
        // Saved before a FIDE id was recorded.
        favorites: const [
          PlayerStandingModel(
            countryCode: 'AZE',
            name: 'mamedyarov,   shakhriyar',
            score: 0,
            scoreChange: 0,
            matchScore: null,
          ),
        ],
        fetcher:
            (_) async => [
              _row(fideId: '13401319', name: 'Mamedyarov, Shakhriyar'),
            ],
      ),
    );
    await settleSearch(tester);

    expect(find.byType(FigmaPlayerCard), findsNothing);
  });

  testWidgets('says the Games surface has no games rather than no player', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        query: 'mamed',
        favorites: const [_mamedyarov],
        surface: FavoritePlayerSearchSurface.games,
        fetcher:
            (_) async => [
              _row(fideId: '13401319', name: 'Mamedyarov, Shakhriyar'),
            ],
      ),
    );
    await settleSearch(tester);

    expect(find.text('No games yet'), findsOneWidget);
  });

  testWidgets('drops rows with no FIDE id and de-duplicates repeats', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        query: 'ding',
        fetcher:
            (_) async => [
              _row(fideId: '', name: 'Unidentifiable Player'),
              _row(fideId: '8603677', name: 'Ding, Liren'),
              _row(fideId: '8603677', name: 'Ding, Liren'),
            ],
      ),
    );
    await settleSearch(tester);

    expect(find.byType(FigmaPlayerCard), findsOneWidget);
    expect(find.text('Unidentifiable Player'), findsNothing);
  });

  testWidgets('does not search on a single letter', (tester) async {
    var callCount = 0;
    await tester.pumpWidget(
      host(
        query: 'c',
        fetcher: (_) async {
          callCount++;
          return const [];
        },
      ),
    );
    await settleSearch(tester);

    expect(callCount, 0);
    expect(find.text('Keep typing'), findsOneWidget);
  });

  testWidgets('surfaces a failed lookup instead of an empty list', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(query: 'carl', fetcher: (_) async => throw Exception('offline')),
    );
    await settleSearch(tester);

    expect(find.text('Could not search players'), findsOneWidget);
  });
}
