import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/screens/my_likes/my_likes_hub_screen.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/widgets/space_avatar.dart';
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

    expect(find.byType(SpacePlayerAvatar), findsWidgets);
    expect(find.text('GM 2830 · 2 liked games'), findsOneWidget);
    await tester.tap(find.text('Carlsen, Magnus'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(picked, ['Carlsen, Magnus']);
    expect(tester.takeException(), isNull);
  });
}
