import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/screens/favorites/widgets/favorite_player_search_suggestion.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/most_liked_controls.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/standings/score_card_screen.dart';
import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:chessever2/screens/streaks/providers/streak_providers.dart';
import 'package:chessever2/screens/streaks/streak_player_screen.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Long-press -> shared focus menu on the people surfaces: the right rows on
/// each, pins that land in My Space, and a board-card long-press that a
/// player name inside the card never steals.

/// Store double: in memory, never touches SQLite or Supabase.
class _FakeSpaceShortcuts extends SpaceShortcutsNotifier {
  List<SpaceShortcut> get _list => state.valueOrNull ?? const [];

  @override
  Future<List<SpaceShortcut>> build() async => const [];

  @override
  Future<bool> add(SpaceShortcut draft) async {
    if (_list.any((s) => s.key == draft.key)) return false;
    state = AsyncData([draft, ..._list]);
    return true;
  }

  @override
  Future<SpaceShortcut?> removeTarget(
    SpaceShortcutKind kind,
    String targetId,
  ) async {
    final key = SpaceShortcut.keyFor(kind, targetId);
    SpaceShortcut? hit;
    for (final s in _list) {
      if (s.key == key) hit = s;
    }
    state = AsyncData([
      for (final s in _list)
        if (s.key != key) s,
    ]);
    return hit;
  }

  @override
  Future<void> markOpened(String id) async {}
}

Widget _app(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: [
      spaceShortcutsProvider.overrideWith(_FakeSpaceShortcuts.new),
      playerPhotoProvider.overrideWith((ref, fideId) async => null),
      ...overrides,
    ],
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return Scaffold(body: child);
        },
      ),
    ),
  );
}

void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

List<SpaceShortcut> _pinned(WidgetTester tester) {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(Scaffold).first),
  );
  return container.read(spaceShortcutsProvider).valueOrNull ?? const [];
}

void main() {
  testWidgets('favourites suggestion row lifts into the player focus menu', (
    tester,
  ) async {
    _tallView(tester);
    await tester.pumpWidget(
      _app(
        SingleChildScrollView(
          child: FavoritePlayerSearchSuggestion(
            query: 'mamed',
            favorites: const [],
            surface: FavoritePlayerSearchSurface.favorites,
            onAdd: (_) async {},
            onOpenPlayer: (_) {},
          ),
        ),
        overrides: [
          favoritePlayerSearchFetcherProvider.overrideWithValue(
            (_) async => [
              {
                'fideId': '13401319',
                'name': 'Mamedyarov, Shakhriyar',
                'title': 'GM',
                'rating': 2740,
                'fed': 'AZE',
              },
            ],
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Mamedyarov, Shakhriyar'));
    await tester.pumpAndSettle();

    for (final label in [
      'Open profile',
      'Add player to My Space',
      'Add Games tab to My Space',
      'Share profile',
      'Add to favorites',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }

    await tester.tap(find.text('Add player to My Space'));
    await tester.pumpAndSettle();
    expect(
      _pinned(tester).map((s) => s.key),
      contains(SpaceShortcut.keyFor(SpaceShortcutKind.player, '13401319')),
    );

    // The same row now offers the removal.
    await tester.longPress(find.text('Mamedyarov, Shakhriyar').first);
    await tester.pumpAndSettle();
    expect(find.text('Remove player from My Space'), findsOneWidget);
  });

  testWidgets('most-liked player row opens the player focus menu', (
    tester,
  ) async {
    _tallView(tester);
    await tester.pumpWidget(
      _app(
        MostLikedPlayersList(
          players: [
            MostLikedPlayer(
              rank: 1,
              player: PlayerCard(
                name: 'Carlsen, Magnus',
                federation: 'NOR',
                title: 'GM',
                rating: 2830,
                countryCode: 'NOR',
                team: null,
                fideId: 1503014,
              ),
              games: 3,
              likes: 12,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Carlsen, Magnus'));
    await tester.pumpAndSettle();

    for (final label in [
      'Open profile',
      'Add player to My Space',
      'Add Games tab to My Space',
      'Share profile',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }

    await tester.tap(find.text('Add Games tab to My Space'));
    await tester.pumpAndSettle();
    expect(
      _pinned(tester).map((s) => s.key),
      contains(SpaceShortcut.keyFor(SpaceShortcutKind.playerGames, '1503014')),
    );
  });

  testWidgets('streak card recent game row pins and opens the game', (
    tester,
  ) async {
    _tallView(tester);
    final opened = <String>[];
    await tester.pumpWidget(
      _app(
        const StreakPlayerScreen(fideId: 8603677),
        overrides: [
          playerStreaksProvider.overrideWith((ref, id) => _ding()),
          streakOpenGameProvider.overrideWithValue((id) async {
            opened.add(id);
            return true;
          }),
        ],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    final row = find.byKey(const ValueKey('streak-recent-c-w2'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.longPress(row);
    await tester.pumpAndSettle();

    expect(find.text('Open game'), findsOneWidget);
    expect(find.text('Add to My Space'), findsOneWidget);

    await tester.tap(find.text('Add to My Space'));
    await tester.pumpAndSettle();
    final pinned = _pinned(
      tester,
    ).firstWhere((s) => s.kind == SpaceShortcutKind.game);
    expect(pinned.targetId, 'c-w2');
    expect(pinned.title, 'Ding – Rival');

    await tester.longPress(row);
    await tester.pumpAndSettle();
    expect(find.text('Remove from My Space'), findsOneWidget);
    await tester.tap(find.text('Open game'));
    await tester.pumpAndSettle();
    expect(opened, ['c-w2']);
  });

  group('board player name', () {
    Future<int Function()> pumpRow(
      WidgetTester tester, {
      bool? nameMenu,
    }) async {
      _tallView(tester);
      var cardLongPresses = 0;
      final game = GamesTourModel(
        gameId: 'focus-name-test',
        source: GameSource.supabase,
        whitePlayer: PlayerCard(
          name: 'Carlsen, Magnus',
          federation: 'NOR',
          title: 'GM',
          rating: 2830,
          countryCode: 'NOR',
          team: null,
          fideId: 1503014,
        ),
        blackPlayer: PlayerCard(
          name: 'Nakamura, Hikaru',
          federation: 'USA',
          title: 'GM',
          rating: 2790,
          countryCode: 'USA',
          team: null,
        ),
        whiteTimeDisplay: '--:--',
        blackTimeDisplay: '--:--',
        whiteClockCentiseconds: 0,
        blackClockCentiseconds: 0,
        gameStatus: GameStatus.ongoing,
        roundId: 'r1',
        tourId: 't1',
        fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      );
      await tester.pumpWidget(
        _app(
          Center(
            // Stands in for a board card: its own long-press is the game menu.
            child: GestureDetector(
              onLongPress: () => cardLongPresses++,
              child: SizedBox(
                width: 360,
                height: 40,
                child: PlayerFirstRowDetailWidget(
                  playerView: PlayerView.gridView,
                  isWhitePlayer: true,
                  gamesTourModel: game,
                  showClock: false,
                  nameMenu: nameMenu,
                ),
              ),
            ),
          ),
          overrides: [
            engineSettingsProviderNew.overrideWith(
              () => _TestEngineSettingsNotifier(
                const EngineSettings(showEngineAnalysis: false),
              ),
            ),
            eventNoSpoilersProvider.overrideWith(
              (ref, tourId) =>
                  _TestEventNoSpoilersController(ref: ref, tourId: tourId),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();
      return () => cardLongPresses;
    }

    testWidgets('inside a board card the card keeps its long-press', (
      tester,
    ) async {
      final cardLongPresses = await pumpRow(tester);
      await tester.longPress(
        find.textContaining('Carlsen', findRichText: true),
      );
      await tester.pumpAndSettle();

      expect(cardLongPresses(), 1);
      expect(find.text('Add player to My Space'), findsNothing);
    });

    testWidgets('on the focused board the name opens the player menu', (
      tester,
    ) async {
      final cardLongPresses = await pumpRow(tester, nameMenu: true);
      await tester.longPress(
        find.textContaining('Carlsen', findRichText: true),
      );
      await tester.pumpAndSettle();

      expect(cardLongPresses(), 0);
      for (final label in [
        'Open scorecard',
        'Add player to My Space',
        'Add Games tab to My Space',
        'Share profile',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });
  });

  test('a scorecard pins as a link only for its event-scoped share URL', () {
    const url =
        'https://chessever.com/broadcast/olympiad-2026/AbCdEf12/player/1503014';
    final draft = scorecardSpaceDraft(
      shareUrl: url,
      playerName: 'Carlsen, Magnus',
      eventName: 'Olympiad 2026',
    );
    expect(draft, isNotNull);
    expect(draft!.kind, SpaceShortcutKind.link);
    expect(draft.targetId, url);
    expect(draft.subtitle, 'Scorecard · Olympiad 2026');

    // The profile fallback is the player's own pin, not a scorecard.
    expect(
      scorecardSpaceDraft(
        shareUrl: 'https://chessever.com/player/1503014',
        playerName: 'Carlsen, Magnus',
      ),
      isNull,
    );
    expect(scorecardSpaceDraft(shareUrl: null, playerName: 'X'), isNull);
  });
}

Map<String, dynamic> _game(
  String id,
  String result, {
  required String day,
  String? round,
  int streakAfter = 0,
}) => {
  'game_id': id,
  'result': result,
  'game_day': day,
  'round_name': ?round,
  'tour_name': 'Olympiad 2026',
  'opponent_name': 'Rival, Some',
  'streak_after': streakAfter,
  'color': 'white',
};

/// Ding Liren: three classical wins in a row after a loss.
PlayerStreaks _ding() {
  return PlayerStreaks.fromJson(
    {
      'fide_id': 8603677,
      'name': 'Ding, Liren',
      'title': 'GM',
      'fed': 'CHN',
      'rating': 2733,
    },
    [
      {
        'time_class': 'standard',
        'current_streak': 3,
        'best_streak': 9,
        'streak_start_game_day': '2026-09-13',
        'games': [
          _game('c-loss', 'loss', day: '2026-09-12', round: 'Round 9'),
          for (var i = 1; i <= 3; i++)
            _game(
              'c-w$i',
              'win',
              day: '2026-09-${(12 + i).toString().padLeft(2, '0')}',
              round: 'Round $i',
              streakAfter: i,
            ),
        ],
      },
    ],
  )!;
}

class _TestEventNoSpoilersController extends EventNoSpoilersController {
  _TestEventNoSpoilersController({required super.ref, required super.tourId});

  @override
  Future<void> load() async {
    state = const EventNoSpoilersState(enabled: false, isLoading: false);
  }
}

class _TestEngineSettingsNotifier extends EngineSettingsNotifierNew {
  _TestEngineSettingsNotifier(this.settings);

  final EngineSettings settings;

  @override
  Future<EngineSettings> build() async => settings;
}
