import 'dart:async';

import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/screens/my_likes/my_likes_hub_screen.dart';
import 'package:chessever2/screens/my_likes/provider/my_likes_provider.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/widgets/figma_player_card.dart';
import 'package:chessever2/widgets/game_filter/game_filter_dialog.dart';
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

SavedAnalysis _like(
  String id, {
  required String white,
  required String black,
  String event = 'Sinquefield Cup 2026',
  int whiteFide = 0,
  int blackFide = 0,
  DateTime? at,
}) {
  final pgn =
      '[Event "$event"]\n[White "$white"]\n[Black "$black"]\n'
      '[Result "1-0"]\n[WhiteElo "2830"]\n[BlackElo "2790"]\n'
      '[WhiteTitle "GM"]\n[BlackTitle "GM"]\n'
      '${whiteFide > 0 ? '[WhiteFideId "$whiteFide"]\n' : ''}'
      '${blackFide > 0 ? '[BlackFideId "$blackFide"]\n' : ''}'
      '\n1. e4 e5 2. Nf3 Nc6 1-0';
  return SavedAnalysis(
    id: id,
    userId: 'u1',
    title: '$white vs $black',
    chessGame: ChessGame.fromPgn(id, pgn),
    analysisState: const {},
    variationComments: const {},
    lastViewedPosition: -1,
    tags: const [],
    isFavorite: false,
    createdAt: at ?? DateTime(2026, 9, 24),
    updatedAt: DateTime(2026, 9, 24),
  );
}

final _likes = [
  _like(
    'a',
    white: 'Carlsen, Magnus',
    black: 'Caruana, Fabiano',
    whiteFide: 1503014,
    blackFide: 2020009,
  ),
  _like(
    'b',
    white: 'Gukesh D',
    black: 'Carlsen, Magnus',
    whiteFide: 46616543,
    blackFide: 1503014,
    event: 'Norway Chess 2026',
    at: DateTime(2026, 9, 25),
  ),
  _like('c', white: 'Nakamura, Hikaru', black: 'So, Wesley'),
];

class _Likes extends LikedGamesNotifier {
  @override
  Future<List<SavedAnalysis>> build() async => _likes;
}

class _Store extends SpaceShortcutsNotifier {
  @override
  Future<List<SpaceShortcut>> build() async => const [];
}

/// The full list the hub reads for its landing page and Players, still on
/// its way (or failed) while the Games page's own view has its data.
class _PendingLikes extends LikedGamesNotifier {
  @override
  Future<List<SavedAnalysis>> build() =>
      Completer<List<SavedAnalysis>>().future;
}

/// The hub over [_likes]. The Games view matches nothing, so the page under
/// the search draws its no-match state instead of game cards. [bottomInset]
/// is the home indicator's; [embedded] puts the hub's tabs inside a parent
/// screen, as My Space does.
Future<ProviderContainer> _pumpHub(
  WidgetTester tester, {
  bool embedded = false,
  double bottomInset = 0,
  LikedGamesNotifier Function() likes = _Likes.new,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(bottom: bottomInset);
  tester.view.viewPadding = FakeViewPadding(bottom: bottomInset);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        likedGamesProvider.overrideWith(likes),
        spaceShortcutsProvider.overrideWith(_Store.new),
        playerPhotoProvider.overrideWith((ref, id) async => null),
        myLikesViewProvider.overrideWith(
          (ref) async => MyLikesData(
            sections: const [],
            openableAnalyses: const [],
            totalLiked: _likes.length,
            visibleCount: 0,
          ),
        ),
        myLikesTagCountsProvider.overrideWith((ref) async => const {}),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: embedded
                  ? const Scaffold(body: MyLikesHubScreen(embedded: true))
                  : const MyLikesHubScreen(),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return ProviderScope.containerOf(
    tester.element(find.byType(MyLikesHubScreen)),
  );
}

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

final _fab = find.byKey(const ValueKey('event_view_search_fab'));
final _field = find.byKey(const ValueKey('my_likes_search'));
final _close = find.byKey(const ValueKey('event_view_search_close'));
final _filters = find.byKey(const ValueKey('my_likes_filters'));
final _showAll = find.byKey(const ValueKey('my_likes_show_all'));

void main() {
  test('players: one entry per FIDE id, most liked first', () {
    final players = myLikesPlayers(_likes);
    expect(players.first.name, 'Carlsen, Magnus');
    expect(players.first.games, 2);
    expect(players.first.fideId, 1503014);
    expect(players.first.title, 'GM');
    expect(players.map((p) => p.name), [
      'Carlsen, Magnus',
      'Caruana, Fabiano',
      'Gukesh D',
      'Nakamura, Hikaru',
      'So, Wesley',
    ]);
  });

  test('players: a game naming a player without the FIDE id another game '
      'carries counts for that same player, keyed once', () {
    final players = myLikesPlayers([
      ..._likes,
      _like('d', white: 'Magnus Carlsen', black: 'Ding, Liren'),
    ]);
    final carlsen = players.where((p) => p.fideId == 1503014).single;
    expect(carlsen.games, 3);
    expect(carlsen.key, 'f1503014');
    expect(players.where((p) => p.name == 'Magnus Carlsen'), isEmpty);
    expect(players.map((p) => p.key).toSet(), hasLength(players.length));
  });

  test('events: by the name the card shows, most liked first', () {
    final events = myLikesEvents(_likes);
    expect(events.first.name, 'Sinquefield Cup 2026');
    expect(events.first.games, 2);
    expect(events.map((e) => e.name), [
      'Sinquefield Cup 2026',
      'Norway Chess 2026',
    ]);
  });

  testWidgets('the Players page shows faces, and picking one asks for that '
      "player's games", (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final picked = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          likedGamesProvider.overrideWith(_Likes.new),
          spaceShortcutsProvider.overrideWith(_Store.new),
          playerPhotoProvider.overrideWith((ref, id) async => null),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(body: MyLikesPlayersPage(onPick: picked.add));
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(FigmaPlayerCard), findsWidgets);
    final card = tester
        .widgetList<FigmaPlayerCard>(find.byType(FigmaPlayerCard))
        .first;
    expect(card.player.name, 'Carlsen, Magnus');
    expect(card.player.score, 2830);
    expect(card.player.title, 'GM');
    expect(card.rank, 1);
    expect(find.text('2 liked games'), findsOneWidget);
    await tester.tap(find.text('Carlsen, Magnus'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(picked, ['Carlsen, Magnus']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Games has no search row: its floating button opens the search '
      "in the header's place, filters beside the field, and back clears it", (
    tester,
  ) async {
    final container = await _pumpHub(tester);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('No matching games'), findsOneWidget);
    expect(_fab, findsOneWidget);
    expect(tester.widget<SearchInkFab>(_fab).badgeCount, 0);

    await tester.tap(_fab);
    await _frames(tester);
    // The field takes the header and the tabs' place, cursor in it, over the
    // same list; nothing floats while searching. The header waits under the
    // field (kept as it was left) and the button the glass left stays laid
    // out for it to come back to, both out of reach.
    expect(_field, findsOneWidget);
    expect(tester.widget<TextField>(_field).focusNode!.hasFocus, isTrue);
    expect(find.text('Players').hitTestable(), findsNothing);
    expect(find.text('No matching games'), findsOneWidget);
    expect(_fab.hitTestable(), findsNothing);
    // The filters the old row carried sit beside the field.
    expect(_filters.hitTestable(), findsOneWidget);

    await tester.enterText(_field, 'Caruana');
    await tester.pump(const Duration(milliseconds: 450));
    expect(container.read(myLikesFilterProvider).searchQuery, 'Caruana');

    await tester.tap(_filters);
    await _frames(tester);
    expect(find.byType(GameFilterDialog), findsOneWidget);
    // Back leaves the dialog first; the search stays open under it.
    await tester.binding.handlePopRoute();
    await _frames(tester);
    expect(find.byType(GameFilterDialog), findsNothing);
    expect(_field, findsOneWidget);
    expect(container.read(myLikesFilterProvider).searchQuery, 'Caruana');

    await tester.tap(_close);
    await _frames(tester);
    expect(_field, findsNothing);
    expect(find.text('Players').hitTestable(), findsOneWidget);
    expect(_fab.hitTestable(), findsOneWidget);
    expect(container.read(myLikesFilterProvider).searchQuery, '');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the filter glyph takes what was typed at once, not 400ms '
      'later', (tester) async {
    final container = await _pumpHub(tester);
    await tester.tap(_fab);
    await _frames(tester);
    await tester.enterText(_field, 'Nakamura');
    await tester.pump(const Duration(milliseconds: 100));
    // Still inside the typing pause: nothing searched yet.
    expect(container.read(myLikesFilterProvider).searchQuery, '');

    await tester.tap(_filters);
    await tester.pump();
    expect(container.read(myLikesFilterProvider).searchQuery, 'Nakamura');
    await _frames(tester);
    expect(find.byType(GameFilterDialog), findsOneWidget);
    await tester.binding.handlePopRoute();
    await _frames(tester);
    // The pause that was cut short never fires a second search later.
    await tester.pump(const Duration(milliseconds: 500));
    expect(container.read(myLikesFilterProvider).searchQuery, 'Nakamura');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a player picked on Players narrows Games under their name, '
      'with one tap back to every like', (tester) async {
    final container = await _pumpHub(tester);
    await tester.tap(find.text('Players'));
    await _frames(tester);
    // Players has nothing to type into.
    expect(_fab, findsNothing);
    await tester.tap(find.text('Carlsen, Magnus'));
    await _frames(tester);

    expect(tester.widget<PageView>(find.byType(PageView)).controller!.page, 0);
    expect(
      container.read(myLikesFilterProvider).searchQuery,
      'Carlsen, Magnus',
    );
    // The search stays closed, so the list itself says whose games these
    // are; the button counts filters only.
    expect(_field, findsNothing);
    expect(find.text('Games of Carlsen, Magnus'), findsOneWidget);
    expect(_showAll.hitTestable(), findsOneWidget);
    expect(tester.widget<SearchInkFab>(_fab).badgeCount, 0);

    await tester.tap(_showAll);
    await _frames(tester);
    expect(container.read(myLikesFilterProvider).searchQuery, '');
    expect(find.text('Games of Carlsen, Magnus'), findsNothing);
    expect(find.text('Players'), findsOneWidget);

    // Picked again, the search opens on the name, and back lets go of it.
    await tester.tap(find.text('Players'));
    await _frames(tester);
    await tester.tap(find.text('Carlsen, Magnus'));
    await _frames(tester);
    await tester.tap(_fab);
    await _frames(tester);
    expect(
      tester.widget<TextField>(_field).controller!.text,
      'Carlsen, Magnus',
    );

    await tester.binding.handlePopRoute();
    await _frames(tester);
    expect(_field, findsNothing);
    expect(container.read(myLikesFilterProvider).searchQuery, '');
    expect(find.text('Games of Carlsen, Magnus'), findsNothing);
    expect(tester.widget<SearchInkFab>(_fab).badgeCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Filters in the header, with the search closed, keep a '
      'picked player', (tester) async {
    final container = await _pumpHub(tester);
    await tester.tap(find.text('Players'));
    await _frames(tester);
    await tester.tap(find.text('Carlsen, Magnus'));
    await _frames(tester);
    expect(_field, findsNothing);

    await tester.tap(find.byKey(const ValueKey('event_view_filters')));
    await _frames(tester);
    expect(find.byType(GameFilterDialog), findsOneWidget);
    expect(
      container.read(myLikesFilterProvider).searchQuery,
      'Carlsen, Magnus',
    );
    await tester.binding.handlePopRoute();
    await _frames(tester);
    expect(find.text('Games of Carlsen, Magnus'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('typing in the search lets go of the picked player', (
    tester,
  ) async {
    final container = await _pumpHub(tester);
    await tester.tap(find.text('Players'));
    await _frames(tester);
    await tester.tap(find.text('Carlsen, Magnus'));
    await _frames(tester);
    await tester.tap(_fab);
    await _frames(tester);
    await tester.enterText(_field, 'Gukesh');
    await tester.pump(const Duration(milliseconds: 450));
    expect(container.read(myLikesFilterProvider).searchQuery, 'Gukesh');
    expect(find.text('Games of Carlsen, Magnus'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the search button follows the Games page, not the full list '
      'still on its way', (tester) async {
    await _pumpHub(tester, likes: _PendingLikes.new);
    expect(tester.widget<PageView>(find.byType(PageView)).controller!.page, 0);
    expect(find.text('No matching games'), findsOneWidget);
    expect(_fab, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the list ends clear of the search button over the home '
      'indicator', (tester) async {
    await _pumpHub(tester, bottomInset: 34);
    // The room itself (the keyed end may be a sliver around it).
    final end = find
        .descendant(
          of: find.byKey(
            const ValueKey('my_likes_list_end'),
            skipOffstage: false,
          ),
          matching: find.byType(SizedBox, skipOffstage: false),
          matchRoot: true,
          skipOffstage: false,
        )
        .first;
    // From the button's top to the screen's bottom: what the list's end
    // must clear once it is scrolled all the way up.
    final covered = 844 - tester.getTopLeft(_fab).dy;
    expect(covered, greaterThan(34));
    expect(tester.getSize(end).height, greaterThanOrEqualTo(covered));
    expect(tester.takeException(), isNull);
  });

  testWidgets('embedded, the hub offers no floating search: Games keeps its '
      'own row', (tester) async {
    await _pumpHub(tester, embedded: true);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(SearchInkFab), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
