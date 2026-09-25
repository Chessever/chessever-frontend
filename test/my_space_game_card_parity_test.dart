import 'dart:async';

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/repository/supabase/chess_player/chess_player_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart';
import 'package:chessever2/screens/gamebase/models/gamebase_game.dart';
import 'package:chessever2/screens/gamebase/models/gamebase_player.dart';
import 'package:chessever2/screens/library/utils/load_saved_analysis.dart';
import 'package:chessever2/screens/my_space/models/space_game_card.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_auto_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_game_card_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/sheets/space_add_sources.dart';
import 'package:chessever2/screens/my_space/widgets/space_game_rows.dart';
import 'package:chessever2/screens/my_space/widgets/space_tile_content.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/game_space_shortcut.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/live_game_card_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A game in My Space must read exactly like the app's game card for the
/// same game: the same row widget ([PlayerFirstRowDetailWidget]) fed the same
/// players, so the flag, title, name, rating and result on screen match. One
/// case per way a game reaches My Space: a pin carrying the card snapshot, an
/// older pin with names only (looked up), a liked game, and the add sheet.
void main() {
  group('the card snapshot', () {
    test('survives the jsonb round trip with every field the card shows', () {
      final game = _decisive();
      final draft = gameSpaceShortcutDraft(
        game,
        params: spaceGameCardParams(game),
      )!;
      final back = SpaceShortcut.fromJson(draft.toJson())!;
      final seed = spaceGameCardSeed(back);
      for (final (a, b) in [
        (seed.whitePlayer, game.whitePlayer),
        (seed.blackPlayer, game.blackPlayer),
      ]) {
        expect(a.name, b.name);
        expect(a.title, b.title);
        expect(a.rating, b.rating);
        expect(a.countryCode, b.countryCode);
        expect(a.fideId, b.fideId);
      }
      expect(seed.gameStatus, GameStatus.whiteWins);
      expect(seed.lastMove, game.lastMove);
      expect(seed.fen, game.fen);
      expect(seed.whiteClockSeconds, game.whiteClockSeconds);
      expect(seed.blackTimeDisplay, game.blackTimeDisplay);
      // The plain names stay for search and older builds.
      expect(back.params['white'], 'Carlsen, Magnus');
      expect(back.params['black'], 'Nakamura, Hikaru');
    });

    test('only a live, unknown or missing snapshot is looked up', () {
      // Every draft carries the snapshot; `card: false` is a pin stored by an
      // older build, names only.
      SpaceShortcut pin(GamesTourModel g, {bool card = true}) {
        final draft = gameSpaceShortcutDraft(g)!;
        return card ? draft : _namesOnly(draft);
      }

      expect(spaceGameCardNeedsFetch(pin(_decisive())), isFalse);
      expect(spaceGameCardNeedsFetch(pin(_ongoing())), isTrue);
      expect(spaceGameCardNeedsFetch(pin(_decisive(), card: false)), isTrue);
      // A saved copy never changes: its snapshot is final even mid-game.
      expect(spaceGameCardNeedsFetch(spaceLikedGameFace(_liked())), isFalse);
    });

    test('a liked face is the My Likes card at the final position', () {
      final analysis = _liked();
      final face = spaceLikedGameFace(analysis);
      final seed = spaceGameCardSeed(face);
      final card = savedAnalysisToCardGame(analysis);
      final last = analysis.chessGame.mainline.last;
      expect(face.params['fen'], last.fen);
      expect(seed.fen, last.fen);
      expect(seed.lastMove, last.uci);
      expect(seed.gameStatus, card.gameStatus);
      expect(seed.source, GameSource.savedAnalysis);
      for (final (a, b) in [
        (seed.whitePlayer, card.whitePlayer),
        (seed.blackPlayer, card.blackPlayer),
      ]) {
        expect(a.name, b.name);
        expect(a.title, b.title);
        expect(a.rating, b.rating);
        expect(a.countryCode, b.countryCode);
      }
    });
  });

  group('looking a game up', () {
    test('a broadcast pin reads the game the way opening it does', () async {
      final reads = <List<String>>[];
      final container = ProviderContainer(
        overrides: [
          spaceGameRowsReaderProvider.overrideWithValue(_rows(reads)),
          gamebaseRepositoryProvider.overrideWithValue(_Gamebase()),
        ],
      );
      addTearDown(container.dispose);
      final pin = gameSpaceShortcutDraft(_decisive())!;
      final found = await container.read(
        spaceGameCardProvider(spaceGameRefOf(pin)).future,
      );
      expect(found!.whitePlayer.title, 'GM');
      expect(found.blackPlayer.countryCode, 'USA');
      expect(found.gameStatus, GameStatus.whiteWins);
      expect(found.lastMove, 'h5f7');
      expect(found.fen, _decisiveRow().fen);
      expect(reads, [
        [_decisiveRow().id],
      ]);
    });

    test('the read leaves the PGN behind; the row carries the position', () {
      final columns = kSpaceGameColumns
          .split(RegExp(r'[\s,()]+'))
          .where((c) => c.isNotEmpty)
          .toSet();
      expect(columns, isNot(contains('pgn')));
      expect(
        columns,
        containsAll([
          'id',
          'fen',
          'last_move',
          'players',
          'status',
          'lichess_id',
          'last_clock_white',
          'last_clock_black',
        ]),
      );
    });

    test('every pin still to look up is read in one batch, and each keeps '
        'its snapshot', () async {
      final reads = <List<String>>[];
      final pins = [
        _namesOnly(gameSpaceShortcutDraft(_decisive())!),
        gameSpaceShortcutDraft(_ongoing())!,
        _lichessPin(),
        // Drawn from its snapshot: never looked up, so never read.
        gameSpaceShortcutDraft(_decisive2())!,
      ];
      final notifier = _Pins(pins);
      final container = ProviderContainer(
        overrides: [
          spaceGameRowsReaderProvider.overrideWithValue(_rows(reads)),
          gamebaseRepositoryProvider.overrideWithValue(_Gamebase()),
          spaceShortcutsProvider.overrideWith(() => notifier),
        ],
      );
      addTearDown(container.dispose);
      await container.read(spaceShortcutsProvider.future);

      // The first tile gathers every pin that needs a lookup.
      Future<GamesTourModel?> tile(SpaceShortcut pin) {
        final key = spaceGameCardProvider(spaceGameRefOf(pin));
        container.listen(key, (_, _) {});
        return container.read(key.future);
      }

      final first = await tile(pins[0]);
      expect(reads, hasLength(1));
      expect(reads.single.toSet(), {
        _decisiveRow().id,
        _ongoingRow().id,
        _lichessRow().lichessId,
      });
      // A tile mounting later (a rail scrolled in) reads the same batch.
      final live = await tile(pins[1]);
      final byLichess = await tile(pins[2]);
      expect(reads, hasLength(1));
      expect(first!.whitePlayer.name, 'Carlsen, Magnus');
      expect(live!.gameStatus, GameStatus.ongoing);
      expect(byLichess!.whitePlayer.name, 'Ding, Liren');

      // A pin with no snapshot keeps the looked-up card; a live one that
      // already has one does not rewrite it.
      await Future<void>.delayed(Duration.zero);
      expect(notifier.merged.keys.toSet(), {pins[0].key, pins[2].key});
      for (final params in notifier.merged.values) {
        expect(params[kSpaceGameCardParam], isA<Map>());
      }

      // A game pinned after the batch is read on its own.
      final added = _namesOnly(gameSpaceShortcutDraft(_decisive2())!);
      notifier.pin(added);
      await tile(added);
      expect(reads, hasLength(2));
      expect(reads.last, [_decisive2Row().id]);
    });

    test('a failed read is not kept: the next tile reads again', () async {
      final reads = <List<String>>[];
      var fail = true;
      final container = ProviderContainer(
        overrides: [
          spaceGameRowsReaderProvider.overrideWithValue((ids) async {
            if (fail) {
              reads.add(ids);
              throw Exception('offline');
            }
            return _rows(reads)(ids);
          }),
          gamebaseRepositoryProvider.overrideWithValue(_Gamebase()),
        ],
      );
      addTearDown(container.dispose);
      final ref = spaceGameRefOf(gameSpaceShortcutDraft(_decisive())!);
      final sub = container.listen(spaceGameCardProvider(ref), (_, _) {});
      expect(await container.read(spaceGameCardProvider(ref).future), isNull);
      sub.close();
      await Future<void>.delayed(Duration.zero);
      fail = false;
      container.listen(spaceGameCardProvider(ref), (_, _) {});
      final found = await container.read(spaceGameCardProvider(ref).future);
      expect(found!.gameStatus, GameStatus.whiteWins);
      expect(reads, hasLength(2));
    });

    test('a uuid Supabase does not know falls back to Gamebase', () async {
      final container = ProviderContainer(
        overrides: [
          spaceGameRowsReaderProvider.overrideWithValue(_rows([])),
          gamebaseRepositoryProvider.overrideWithValue(_Gamebase()),
        ],
      );
      addTearDown(container.dispose);
      final found = await container.read(
        spaceGameCardProvider((
          targetId: _gamebaseId,
          gamebase: false,
          analysisId: null,
        )).future,
      );
      expect(found!.source, GameSource.gamebase);
      expect(found.whitePlayer.name, 'Carlsen, Magnus');
      expect(found.whitePlayer.countryCode, 'NOR');
    });

    test('a saved copy comes from My Likes, and a miss is null', () async {
      final reads = <List<String>>[];
      final container = ProviderContainer(
        overrides: [
          likedGamesProvider.overrideWith(() => _Likes([_liked()])),
          libraryRepositoryProvider.overrideWith((ref) => _Library()),
          spaceGameRowsReaderProvider.overrideWithValue(_rows(reads)),
          gamebaseRepositoryProvider.overrideWithValue(_Gamebase()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(likedGamesProvider.future);
      final liked = await container.read(
        spaceGameCardProvider((
          targetId: 'source-1',
          gamebase: false,
          analysisId: 'liked-1',
        )).future,
      );
      expect(liked!.source, GameSource.savedAnalysis);
      expect(liked.fen, _liked().chessGame.mainline.last.fen);
      final missing = await container.read(
        spaceGameCardProvider((
          targetId: 'analysis:gone',
          gamebase: false,
          analysisId: 'gone',
        )).future,
      );
      expect(missing, isNull);
      // A saved copy that is gone opens the game it was saved from.
      final source = await container.read(
        spaceGameCardProvider((
          targetId: _decisiveRow().id,
          gamebase: false,
          analysisId: 'gone',
        )).future,
      );
      expect(source!.gameStatus, GameStatus.whiteWins);
      expect(reads, [
        [_decisiveRow().id],
      ]);
    });
  });

  testWidgets('a pinned tile shows the same rows as the grid card', (
    tester,
  ) async {
    final game = _decisive();
    await _pump(
      tester,
      left: SpaceTileContent(
        shortcut: gameSpaceShortcutDraft(
          game,
          params: spaceGameCardParams(game),
        )!,
      ),
      right: GridChessBoardFromFENNew(
        gamesTourModel: game,
        onChanged: () {},
        pinnedIds: const [],
        onPinToggle: (_) {},
      ),
    );
    _expectSameRows(tester);
    // The flag sits where the card puts it: past the result lane.
    double flagInset(Finder host) {
      final hostLeft = tester.getTopLeft(host).dx;
      return tester
              .getTopLeft(
                find
                    .descendant(of: host, matching: find.byType(FederationFlag))
                    .first,
              )
              .dx -
          hostLeft;
    }

    expect(
      flagInset(find.byKey(const ValueKey('left'))),
      moreOrLessEquals(
        flagInset(find.byKey(const ValueKey('right'))),
        epsilon: 0.5,
      ),
    );
    // The board is the card's own, ending marks and last move included.
    final board = tester.widget<GameCardChessboard>(
      find.descendant(
        of: find.byKey(const ValueKey('left')),
        matching: find.byType(GameCardChessboard),
      ),
    );
    expect(board.gameStatus, GameStatus.whiteWins);
    expect(board.lastMove?.uci, 'h5f7');
    expect(board.fen, game.fen);
    await _settle(tester);
  });

  testWidgets('an older pin holds the card rows in place while it is looked '
      'up, then cross-fades them in', (tester) async {
    final game = _decisive();
    final lookup = Completer<GamesTourModel?>();
    await _pump(
      tester,
      lookup: (key) => lookup.future,
      left: SpaceTileContent(
        shortcut: _namesOnly(gameSpaceShortcutDraft(game)!),
      ),
      right: GridChessBoardFromFENNew(
        gamesTourModel: game,
        onChanged: () {},
        pinnedIds: const [],
        onPinToggle: (_) {},
      ),
    );
    final tile = find.byKey(const ValueKey('left'));
    final card = find.byKey(const ValueKey('right'));
    double left(Finder f) => tester.getTopLeft(f).dx;
    Finder inTile(Finder f) => find.descendant(of: tile, matching: f);
    Finder inCard(Finder f) => find.descendant(of: card, matching: f);
    final standIns = inTile(find.byType(SpaceGamePlayerRowStandIn));
    final slots = inTile(find.byKey(const ValueKey('space-row-flag-slot')));
    RichText standInName(String name) => tester.widget<RichText>(
      inTile(
        find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText() == name,
        ),
      ),
    );
    final cardName = tester.widget<RichText>(
      inCard(
        find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().startsWith('GM Carlsen'),
        ),
      ),
    );
    final boardRect = tester.getRect(inTile(find.byType(GameCardChessboard)));

    // While it loads: the pinned names at the card's own name size, the
    // flag's slot held where the card draws the flag, and no card rows yet.
    expect(standIns, findsNWidgets(2));
    expect(inTile(find.byType(PlayerFirstRowDetailWidget)), findsNothing);
    for (final name in ['Carlsen, Magnus', 'Nakamura, Hikaru']) {
      expect(
        standInName(name).text.style!.fontSize,
        cardName.text.style!.fontSize,
      );
    }
    final cardFlagX =
        left(inCard(find.byType(FederationFlag)).first) - left(card);
    expect(slots, findsNWidgets(2));
    for (final slot in slots.evaluate()) {
      expect(
        tester.getTopLeft(find.byWidget(slot.widget)).dx - left(tile),
        moreOrLessEquals(cardFlagX, epsilon: 0.5),
      );
      expect(
        tester.getSize(find.byWidget(slot.widget)),
        tester.getSize(inCard(find.byType(FederationFlag)).first),
      );
    }
    final nameX = tester
        .getTopLeft(find.byWidget(standInName('Carlsen, Magnus')))
        .dx;
    expect(tester.takeException(), isNull);

    lookup.complete(game);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    // Mid-fade: the card rows are in, over the stand-ins, both partly seen.
    expect(standIns, findsNWidgets(2));
    final rows = inTile(find.byType(PlayerFirstRowDetailWidget));
    expect(rows, findsNWidgets(2));
    final fading = tester.widget<Opacity>(
      find.ancestor(of: rows.first, matching: find.byType(Opacity)).first,
    );
    expect(fading.opacity, inExclusiveRange(0, 1));

    await tester.pump(const Duration(milliseconds: 600));
    expect(standIns, findsNothing);
    _expectSameRows(tester);
    // Nothing moved: the flag landed in its slot, the name where it was,
    // the board where it was.
    expect(
      left(inTile(find.byType(FederationFlag)).first) - left(tile),
      moreOrLessEquals(cardFlagX, epsilon: 0.5),
    );
    final loadedName = inTile(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().startsWith('GM Carlsen'),
      ),
    );
    expect(tester.getTopLeft(loadedName).dx, moreOrLessEquals(nameX));
    expect(tester.getRect(inTile(find.byType(GameCardChessboard))), boardRect);
    await _settle(tester);
  });

  testWidgets('a pin whose game is not found keeps its names in place', (
    tester,
  ) async {
    await _pump(
      tester,
      lookup: (key) async => null,
      left: SpaceTileContent(
        shortcut: _namesOnly(gameSpaceShortcutDraft(_decisive())!),
      ),
    );
    final tile = find.byKey(const ValueKey('left'));
    expect(
      find.descendant(
        of: tile,
        matching: find.byType(SpaceGamePlayerRowStandIn),
      ),
      findsNWidgets(2),
    );
    // The slot stays, empty: no flag is coming.
    for (final slot in tester.widgetList<SizedBox>(
      find.byKey(const ValueKey('space-row-flag-slot')),
    )) {
      expect(slot.child, isNull);
    }
    expect(find.text('Carlsen, Magnus', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _settle(tester);
  });

  testWidgets('a live game tile streams its board, and its rows share the '
      'channel', (tester) async {
    final game = _ongoing();
    final feed = StateProvider<GamesTourModel?>((ref) => null);
    final watched = <LiveGameWatchParams>[];
    await _pump(
      tester,
      lookup: (key) async => game,
      left: SpaceTileContent(
        shortcut: gameSpaceShortcutDraft(
          game,
          params: spaceGameCardParams(game),
        )!,
      ),
      extra: [
        liveGamePositionProvider.overrideWith((ref, params) {
          watched.add(params);
          return ref.watch(feed);
        }),
        liveGameClockProvider.overrideWith((ref, params) => ref.watch(feed)),
      ],
    );
    GameCardChessboard board() => tester.widget<GameCardChessboard>(
      find.descendant(
        of: find.byKey(const ValueKey('left')),
        matching: find.byType(GameCardChessboard),
      ),
    );
    expect(board().fen, game.fen);
    expect(watched, isNotEmpty);
    final key = spaceLiveBatchKey(game);
    expect(key, isNotNull);
    expect(watched.last.batchKey, key);
    expect(watched.last.streamEnabled, isTrue);
    for (final row in tester.widgetList<SpaceGamePlayerRow>(
      find.byType(SpaceGamePlayerRow),
    )) {
      expect(row.liveBatchKey, key);
    }

    // A move arrives: the board follows it.
    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const ValueKey('left'))),
    );
    const afterNc3 =
        'rnbqkbnr/ppp2ppp/4p3/3p4/2PP4/2N5/PP2PPPP/R1BQKBNR b KQkq - 1 3';
    container.read(feed.notifier).state = game.copyWith(
      fen: afterNc3,
      lastMove: 'b1c3',
    );
    await tester.pump();
    expect(board().fen, afterNc3);
    expect(board().lastMove?.uci, 'b1c3');
    expect(board().gameStatus, GameStatus.ongoing);

    // It ends: the board takes the result, and the rows show it.
    container.read(feed.notifier).state = game.copyWith(
      fen: afterNc3,
      lastMove: 'b1c3',
      gameStatus: GameStatus.draw,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(board().gameStatus, GameStatus.draw);
    expect(find.text('½'), findsNWidgets(2));
    await _settle(tester);
  });

  testWidgets('a liked game tile shows the My Likes players at the end', (
    tester,
  ) async {
    final analysis = _liked();
    final card = spaceGameFromAnalysis(analysis);
    await _pump(
      tester,
      left: SpaceTileContent(shortcut: spaceLikedGameFace(analysis)),
      right: GridChessBoardFromFENNew(
        gamesTourModel: card,
        onChanged: () {},
        pinnedIds: const [],
        onPinToggle: (_) {},
      ),
    );
    _expectSameRows(tester, results: {'½'});
    final board = tester.widget<GameCardChessboard>(
      find.descendant(
        of: find.byKey(const ValueKey('left')),
        matching: find.byType(GameCardChessboard),
      ),
    );
    expect(board.fen, analysis.chessGame.mainline.last.fen);
    expect(board.gameStatus, GameStatus.draw);
    await _settle(tester);
  });

  testWidgets('the add sheet lists games with the card rows; a tap toggles', (
    tester,
  ) async {
    final toggled = <SpaceShortcut>[];
    await _pump(
      tester,
      liked: [_liked()],
      left: SizedBox(
        height: 700,
        child: SpaceAddSources(
          section: SpaceSection.games,
          query: '',
          onToggle: (d) async => toggled.add(d),
        ),
      ),
    );
    final rows = tester
        .widgetList<PlayerFirstRowDetailWidget>(
          find.byType(PlayerFirstRowDetailWidget),
        )
        .toList();
    // Two per game: the liked one and the most liked one.
    expect(rows, hasLength(4));
    expect(rows.every((r) => r.playerView == PlayerView.boardView), isTrue);
    // Title, name (shortened to fit the test font's wide glyphs) and rating.
    final lines = _lines(find.byKey(const ValueKey('left')));
    bool shows(String title, String surname, int rating) => lines.any(
      (l) => l.startsWith('$title $surname') && l.endsWith(' $rating'),
    );
    expect(shows('GM', 'Carlsen', 2830), isTrue, reason: '$lines');
    expect(shows('GM', 'Nakamura', 2802), isTrue, reason: '$lines');
    expect(shows('GM', 'Praggnanandhaa', 2758), isTrue, reason: '$lines');
    expect(shows('GM', 'Caruana', 2795), isTrue, reason: '$lines');
    expect(find.byType(FederationFlag), findsNWidgets(4));
    expect(find.text('Sinquefield Cup 2026'), findsOneWidget);

    // The name is not a way into the scorecard here: the row toggles.
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    final before = nav.canPop();
    await tester.tap(find.text('Sinquefield Cup 2026'));
    await tester.pump();
    final name = find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText().startsWith('GM Carlsen'),
    );
    await tester.tap(name, warnIfMissed: false);
    await tester.pump();
    expect(toggled, hasLength(2));
    expect(toggled.every((d) => d.kind == SpaceShortcutKind.game), isTrue);
    expect(nav.canPop(), before);
    // What it adds carries the card snapshot.
    expect(spaceGameHasCard(toggled.first), isTrue);
    await _settle(tester);
  });

  for (final light in [true, false]) {
    testWidgets('tiles and sheet fit at 360pt and 1.3x text, '
        '${light ? 'light' : 'dark'}', (tester) async {
      final game = _decisive();
      await _pump(
        tester,
        width: 360,
        textScale: 1.3,
        light: light,
        liked: [_liked()],
        left: Column(
          children: [
            Row(
              children: [
                SpaceTileContent(
                  shortcut: gameSpaceShortcutDraft(
                    game,
                    params: spaceGameCardParams(game),
                  )!,
                ),
                SpaceTileContent(shortcut: spaceLikedGameFace(_liked())),
              ],
            ),
            SizedBox(
              height: 600,
              child: SpaceAddSources(
                section: SpaceSection.games,
                query: '',
                onToggle: (_) async {},
              ),
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      await _settle(tester);
    });
  }
}

const _gamebaseId = '0b5f3c1e-9d7a-4b1e-8a2c-5d6e7f8a9b0c';

Player _player(String name, String title, int rating, int fideId, String fed) =>
    Player(
      name: name,
      title: title,
      rating: rating,
      fideId: fideId,
      fed: fed,
      clock: 0,
      team: '',
    );

/// The position after 4.Qxf7#, as the row's `fen` column stores it.
const _mateFen =
    'r1bqkb1r/pppp1Qpp/2n2n2/4p3/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 0 4';

/// [pgn] false is the row as My Space reads it: no movetext.
Games _decisiveRow({bool pgn = true}) => Games(
  id: '6a0c1d3e-1111-4a55-9a1b-1234567890ab',
  roundId: 'round-1',
  roundSlug: 'round-5',
  tourId: 'tour-1',
  tourSlug: 'sinquefield-cup-2026',
  players: [
    _player('Carlsen, Magnus', 'GM', 2830, 1503014, 'NOR'),
    _player('Nakamura, Hikaru', 'GM', 2802, 2016192, 'USA'),
  ],
  status: '1-0',
  fen: _mateFen,
  pgn: pgn
      ? '1. e4 {[%clk 1:59:10]} e5 {[%clk 1:58:40]} 2. Bc4 {[%clk 1:57:02]} '
            'Nc6 {[%clk 1:55:12]} 3. Qh5 {[%clk 1:50:01]} Nf6 {[%clk 1:31:30]} '
            '4. Qxf7# {[%clk 1:49:44]} 1-0'
      : null,
  lastMove: 'h5f7',
  lastClockWhite: 6584,
  lastClockBlack: 5490,
);

GamesTourModel _decisive() => GamesTourModel.fromGame(_decisiveRow());

Games _ongoingRow({bool pgn = true}) => Games(
  id: '6a0c1d3e-2222-4a55-9a1b-1234567890ab',
  roundId: 'round-1',
  roundSlug: 'round-5',
  tourId: 'tour-1',
  tourSlug: 'sinquefield-cup-2026',
  players: [
    _player('Firouzja, Alireza', 'GM', 2759, 12573981, 'FRA'),
    _player('Gukesh D', 'GM', 2777, 46616543, 'IND'),
  ],
  status: '*',
  fen: 'rnbqkbnr/ppp2ppp/4p3/3p4/2PP4/8/PP2PPPP/RNBQKBNR w KQkq - 0 3',
  pgn: pgn ? '1. d4 d5 2. c4 e6 *' : null,
  lastMove: 'e7e6',
);

GamesTourModel _ongoing() => GamesTourModel.fromGame(_ongoingRow());

/// A game pinned by its Lichess short id, as a shared link names it.
Games _lichessRow({bool pgn = true}) => Games(
  id: '6a0c1d3e-3333-4a55-9a1b-1234567890ab',
  roundId: 'round-2',
  roundSlug: 'round-6',
  tourId: 'tour-1',
  tourSlug: 'sinquefield-cup-2026',
  lichessId: 'Xy7Qp2Lm',
  players: [
    _player('Ding, Liren', 'GM', 2780, 8603677, 'CHN'),
    _player('Nepomniachtchi, Ian', 'GM', 2770, 4168119, 'FID'),
  ],
  status: '1/2-1/2',
  fen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1',
  pgn: pgn ? '1. e4 1/2-1/2' : null,
  lastMove: 'e2e4',
);

SpaceShortcut _lichessPin() => SpaceShortcut.draft(
  kind: SpaceShortcutKind.game,
  targetId: 'Xy7Qp2Lm',
  title: 'Ding – Nepomniachtchi',
  params: const {'white': 'Ding, Liren', 'black': 'Nepomniachtchi, Ian'},
);

Games _decisive2Row({bool pgn = true}) => Games(
  id: '6a0c1d3e-4444-4a55-9a1b-1234567890ab',
  roundId: 'round-2',
  roundSlug: 'round-6',
  tourId: 'tour-1',
  tourSlug: 'sinquefield-cup-2026',
  players: [
    _player('Caruana, Fabiano', 'GM', 2795, 2020009, 'USA'),
    _player('So, Wesley', 'GM', 2753, 5202213, 'USA'),
  ],
  status: '0-1',
  fen: 'rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3',
  pgn: pgn ? '1. f3 e5 2. g4 Qh4# 0-1' : null,
  lastMove: 'd8h4',
);

GamesTourModel _decisive2() => GamesTourModel.fromGame(_decisive2Row());

/// The pgn-less `games` read, recording the ids of each request.
SpaceGameRowsReader _rows(List<List<String>> reads) => (ids) async {
  reads.add(ids);
  return [
    for (final row in [
      _decisiveRow(pgn: false),
      _ongoingRow(pgn: false),
      _lichessRow(pgn: false),
      _decisive2Row(pgn: false),
    ])
      if (ids.contains(row.id) || ids.contains(row.lichessId)) row,
  ];
};

SavedAnalysis _liked() {
  const pgn =
      '[Event "Tata Steel Masters 2026"]\n[White "Praggnanandhaa R"]\n'
      '[Black "Caruana, Fabiano"]\n[WhiteTitle "GM"]\n[BlackTitle "GM"]\n'
      '[WhiteElo "2758"]\n[BlackElo "2795"]\n[WhiteFed "IND"]\n'
      '[BlackFed "USA"]\n[Result "1/2-1/2"]\n\n'
      '1. d4 Nf6 2. c4 e6 3. Nf3 Bb4+ 4. Bd2 Be7 1/2-1/2';
  return SavedAnalysis(
    id: 'liked-1',
    userId: 'u',
    title: 'Praggnanandhaa vs Caruana',
    sourceGameId: 'source-1',
    chessGame: ChessGame.fromPgn('liked-1', pgn),
    analysisState: const {},
    variationComments: const {},
    lastViewedPosition: -1,
    tags: const [],
    isFavorite: false,
    createdAt: DateTime(2026, 9, 20),
    updatedAt: DateTime(2026, 9, 20),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required Widget left,
  Widget? right,
  Future<GamesTourModel?> Function(SpaceGameRef key)? lookup,
  List<SavedAnalysis> liked = const [],
  double width = 393,
  double textScale = 1,
  bool light = false,
  List<Override> extra = const [],
}) async {
  tester.view.devicePixelRatio = 3;
  // A phone: a taller view reads as a tablet to the grid card.
  tester.view.physicalSize = Size(width * 3, 852 * 3);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        engineSettingsProviderNew.overrideWith(_Settings.new),
        eventNoSpoilersProvider.overrideWith(_MemoryNoSpoilers.new),
        chessPlayerRepositoryProvider.overrideWithValue(_ChessPlayers()),
        gamebaseRepositoryProvider.overrideWithValue(_Gamebase()),
        boardSettingsProviderNew.overrideWith(_BoardSettings.new),
        likedGamesProvider.overrideWith(() => _Likes(liked)),
        spaceShortcutsProvider.overrideWith(_NoShortcuts.new),
        currentUserProvider.overrideWithValue(null),
        spaceGameCardProvider.overrideWith(
          (ref, key) => lookup?.call(key) ?? Future.value(null),
        ),
        mostLikedProvider.overrideWith(
          (ref, q) async => MostLikedResult.ranked([
            MostLikedEntry(
              rank: 1,
              likes: 41,
              game: _decisive(),
              eventName: 'Sinquefield Cup 2026',
            ),
          ]),
        ),
        ...extra,
      ],
      child: MaterialApp(
        theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: SingleChildScrollView(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (right == null)
                      Expanded(
                        child: KeyedSubtree(
                          key: const ValueKey('left'),
                          child: left,
                        ),
                      )
                    else ...[
                      KeyedSubtree(key: const ValueKey('left'), child: left),
                      KeyedSubtree(key: const ValueKey('right'), child: right),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  // Settings, No Spoilers, the likes and the row lookups resolve.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

/// The title + name + rating lines and result labels the rows draw.
Set<String> _lines(Finder host) => {
  for (final element
      in find
          .descendant(
            of: find.descendant(
              of: host,
              matching: find.byType(PlayerFirstRowDetailWidget),
            ),
            matching: find.byType(RichText),
          )
          .evaluate())
    (element.widget as RichText).text.toPlainText(),
}..removeWhere((line) => line.trim().isEmpty);

void _expectSameRows(WidgetTester tester, {Set<String> results = const {}}) {
  final tile = find.byKey(const ValueKey('left'));
  final card = find.byKey(const ValueKey('right'));
  List<PlayerFirstRowDetailWidget> rowsIn(Finder host) => tester
      .widgetList<PlayerFirstRowDetailWidget>(
        find.descendant(
          of: host,
          matching: find.byType(PlayerFirstRowDetailWidget),
        ),
      )
      .toList();

  final tileRows = rowsIn(tile);
  final cardRows = rowsIn(card);
  expect(tileRows, hasLength(2));
  expect(cardRows, hasLength(2));
  for (final white in [true, false]) {
    final a = cardRows.firstWhere((r) => r.isWhitePlayer == white);
    final b = tileRows.firstWhere((r) => r.isWhitePlayer == white);
    expect(b.playerView, a.playerView);
    expect(b.showClock, a.showClock);
    final pa = white
        ? a.gamesTourModel.whitePlayer
        : a.gamesTourModel.blackPlayer;
    final pb = white
        ? b.gamesTourModel.whitePlayer
        : b.gamesTourModel.blackPlayer;
    expect(pb.name, pa.name);
    expect(pb.title, pa.title);
    expect(pb.rating, pa.rating);
    expect(pb.countryCode, pa.countryCode);
    expect(pb.fideId, pa.fideId);
    expect(pb.gamebasePlayerId, pa.gamebasePlayerId);
    expect(b.gamesTourModel.gameStatus, a.gamesTourModel.gameStatus);
  }

  final tileLines = _lines(tile);
  final cardLines = _lines(card);
  expect(tileLines, cardLines);
  final clock = RegExp(r'^\d+:\d\d(:\d\d)?$');
  final names = tileLines
      .where((l) => l.length > 3 && !clock.hasMatch(l))
      .toList();
  expect(names, hasLength(2));
  for (final line in names) {
    expect(line, startsWith('GM '), reason: 'title shown: $line');
    expect(line, matches(RegExp(r' \d{4}$')), reason: 'rating shown: $line');
  }
  Set<String> resultTexts(Finder host) => {
    for (final t in tester.widgetList<Text>(
      find.descendant(
        of: find.descendant(
          of: host,
          matching: find.byType(PlayerFirstRowDetailWidget),
        ),
        matching: find.byType(Text),
      ),
    ))
      if ((t.data ?? '').length <= 2) t.data!,
  };
  expect(resultTexts(tile), resultTexts(card));
  expect(
    resultTexts(tile),
    containsAll(results.isEmpty ? {'1', '0'} : results),
  );
  int flags(Finder host) => find
      .descendant(of: host, matching: find.byType(FederationFlag))
      .evaluate()
      .length;
  expect(flags(tile), 2);
  expect(flags(tile), flags(card));
}

/// Gauges off: neither surface asks an engine.
class _Settings extends EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async => const EngineSettings(
    showEngineGaugeInGrid: false,
    showEngineGaugeOnBoard: false,
  );
}

class _MemoryNoSpoilers extends EventNoSpoilersController {
  _MemoryNoSpoilers(Ref ref, String tourId) : super(ref: ref, tourId: tourId);

  @override
  Future<void> load() async {
    state = const EventNoSpoilersState(enabled: false, isLoading: false);
  }
}

class _ChessPlayers implements ChessPlayerRepository {
  @override
  Future<ChessPlayer?> getPlayerByFideId(int fideId) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Gamebase implements GamebaseRepository {
  @override
  Future<GamebasePlayer?> getPlayerById(String id) async => null;

  @override
  Future<GamebaseGame?> getGameById(String id) async => id == _gamebaseId
      ? GamebaseGame(
          id: _gamebaseId,
          date: DateTime(2024, 1, 20),
          result: GameResult.whiteWins,
          timeControl: TimeControl.classical,
          whitePlayerId: 'gb-w',
          blackPlayerId: 'gb-b',
          data: const {
            'md': {
              'White': 'Carlsen, Magnus',
              'Black': 'Giri, Anish',
              'WhiteFed': 'NOR',
              'BlackFed': 'NED',
              'WhiteElo': 2830,
              'BlackElo': 2760,
              'Result': '1-0',
              'Event': 'Tata Steel Masters 2024',
            },
          },
        )
      : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Library implements LibraryRepository {
  @override
  Future<SavedAnalysis?> getSavedAnalysis(String analysisId) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BoardSettings extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

class _Likes extends LikedGamesNotifier {
  _Likes(this.list);

  final List<SavedAnalysis> list;

  @override
  Future<List<SavedAnalysis>> build() async => list;
}

class _NoShortcuts extends SpaceShortcutsNotifier {
  @override
  Future<List<SpaceShortcut>> build() async => const [];
}

/// My Space's pins, keeping the params each lookup merges into them here
/// instead of on the server.
class _Pins extends SpaceShortcutsNotifier {
  _Pins(this.initial);

  final List<SpaceShortcut> initial;
  final Map<String, Map<String, dynamic>> merged = {};

  @override
  Future<List<SpaceShortcut>> build() async => initial;

  void pin(SpaceShortcut s) => state = AsyncData([...state.value!, s]);

  @override
  Future<void> mergeParams(String key, Map<String, dynamic> values) async {
    merged[key] = values;
  }
}

/// A game pin as an older build stored it: names and ids, no card snapshot.
SpaceShortcut _namesOnly(SpaceShortcut draft) =>
    draft.copyWith(params: {...draft.params}..remove(kSpaceGameCardParam));
