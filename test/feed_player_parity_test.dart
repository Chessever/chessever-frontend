import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/miniatures/miniatures_models.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/repository/supabase/chess_player/chess_player_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/screens/feed/audio/feed_sfx.dart';
import 'package:chessever2/screens/feed/logic/feed_codec.dart';
import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/screens/feed/providers/feed_eval_provider.dart';
import 'package:chessever2/screens/feed/widgets/feed_clip.dart';
import 'package:chessever2/screens/feed/widgets/feed_move_sound.dart';
import 'package:chessever2/screens/feed/widgets/feed_sfx_provider.dart';
import 'package:chessever2/screens/gamebase/models/gamebase_player.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A Feed board and a game card built from the same source row must show the
/// same players: the same row widget ([PlayerFirstRowDetailWidget]), the same
/// model, and on screen the same title, name, rating and flag, including the
/// titles the row looks up when the source left them out.
///
/// One case per Feed source: annotated and decisive top boards and followed
/// players' games (all `GamesTourModel.fromGame` of a Supabase row), Gamebase
/// miniatures (`GamebaseMiniature.toGamesTourModel`, which carries no
/// titles), and a page read back from the first-page cache. The Feed has no
/// countrymen or likes source; those surfaces are game cards already.
void main() {
  const pgn = '1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6 4. Qxf7# 1-0';

  Games supabaseRow({
    required String id,
    required Player white,
    required Player black,
    String? pgnText,
  }) => Games(
    id: id,
    roundId: 'round-1',
    roundSlug: 'round-1',
    tourId: 'tour-1',
    tourSlug: 'test-open-2026',
    players: [white, black],
    status: '1-0',
    pgn: pgnText ?? pgn,
    lastMove: 'h5f7',
  );

  Player player(
    String name, {
    String title = 'GM',
    int rating = 2800,
    int fideId = 0,
    String fed = 'NOR',
  }) => Player(
    name: name,
    title: title,
    rating: rating,
    fideId: fideId,
    fed: fed,
    clock: 0,
    team: '',
  );

  final cases = <String, GamesTourModel Function()>{
    'annotated top board': () => GamesTourModel.fromGame(
      supabaseRow(
        id: 'annotated',
        white: player('Carlsen, Magnus', fideId: 1503014),
        black: player('Nakamura, Hikaru', fideId: 2016192, fed: 'USA'),
        pgnText:
            '1. e4 { [%eval 0.3] } e5 { [%eval 0.3] } 2. Bc4 Nc6 '
            '3. Qh5 Nf6 4. Qxf7# 1-0',
      ),
    ),
    'decisive top board': () => GamesTourModel.fromGame(
      supabaseRow(
        id: 'decisive',
        white: player('Firouzja, Alireza', fideId: 12573981, fed: 'FRA'),
        black: player('Gukesh D', title: 'GM', fideId: 46616543, fed: 'IND'),
      ),
    ),
    // The row names no title for the followed player: the card and the Feed
    // both look it up by FIDE id.
    'followed player': () => GamesTourModel.fromGame(
      supabaseRow(
        id: 'favorite',
        white: player('Caruana, Fabiano', title: '', fideId: 2020009, fed: ''),
        black: player('So, Wesley', fideId: 5202213, fed: 'USA'),
      ),
    ),
    // Miniatures carry no titles at all: both look them up in Gamebase.
    'miniature': () => const GamebaseMiniature(
      gameId: '00000000-0000-0000-0000-00000000abcd',
      plyCount: 7,
      finalMoveNumber: 4,
      result: 'W',
      timeControl: 'BLITZ',
      isOnline: false,
      event: 'Titled Arena',
      eco: 'C20',
      whiteName: 'Carlsen, Magnus',
      blackName: 'Nakamura, Hikaru',
      whiteElo: 2830,
      blackElo: 2802,
      whitePlayerId: 'gb-white',
      blackPlayerId: 'gb-black',
      whiteFed: 'NOR',
      blackFed: 'USA',
    ).toGamesTourModel().copyWith(pgn: pgn),
  };

  for (final entry in cases.entries) {
    testWidgets('${entry.key}: the Feed rows are the game card rows', (
      tester,
    ) async {
      final game = entry.value();
      await _pumpBoth(tester, game);
      _expectSameRows(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  }

  testWidgets('a cached page keeps every player field the card shows', (
    tester,
  ) async {
    final game = cases['annotated top board']!();
    final item = _item(game);
    final restored = decodeFlowFeedCache(
      encodeFlowFeedCache([item]),
      now: DateTime(2026, 9, 24),
    ).single;
    for (final (a, b) in [
      (restored.game.whitePlayer, game.whitePlayer),
      (restored.game.blackPlayer, game.blackPlayer),
    ]) {
      expect(a.name, b.name);
      expect(a.title, b.title);
      expect(a.rating, b.rating);
      expect(a.countryCode, b.countryCode);
      expect(a.federation, b.federation);
      expect(a.fideId, b.fideId);
      expect(a.gamebasePlayerId, b.gamebasePlayerId);
    }
    await _pumpBoth(tester, restored.game);
    _expectSameRows(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}

void _expectSameRows(WidgetTester tester) {
  final card = find.byKey(const ValueKey('card'));
  final feed = find.byKey(const ValueKey('feed'));
  List<PlayerFirstRowDetailWidget> rowsIn(Finder host) => tester
      .widgetList<PlayerFirstRowDetailWidget>(
        find.descendant(
          of: host,
          matching: find.byType(PlayerFirstRowDetailWidget),
        ),
      )
      .toList();

  final cardRows = rowsIn(card);
  final feedRows = rowsIn(feed);
  expect(cardRows, hasLength(2));
  expect(feedRows, hasLength(2));

  for (final white in [true, false]) {
    final a = cardRows.firstWhere((r) => r.isWhitePlayer == white);
    final b = feedRows.firstWhere((r) => r.isWhitePlayer == white);
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
  }

  // What is actually on screen: the same title + name + rating lines, and a
  // flag wherever the card draws one.
  Set<String> lines(Finder host) => {
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

  final cardLines = lines(card);
  expect(cardLines, isNotEmpty);
  // The name lines (the result column's "1" / "0" aside) lead with the
  // title, looked up where the source had none.
  final names = cardLines.where((line) => line.length > 3).toList();
  expect(names, hasLength(2));
  final results = cardLines.where((line) => line.length <= 3).toSet();
  expect(results, isNotEmpty, reason: 'the card prints the finished result');
  final feedLines = lines(feed);
  expect(feedLines, containsAll(names));
  // The clip opens on the first move, so its rows hold the result back
  // until the replay reaches the end.
  expect(feedLines.intersection(results), isEmpty);
  for (final line in names) {
    expect(line, startsWith('GM '), reason: 'title shown: $line');
  }
  int flags(Finder host) => find
      .descendant(of: host, matching: find.byType(FederationFlag))
      .evaluate()
      .length;
  expect(flags(feed), flags(card));
  expect(flags(card), 2);
}

FeedItem _item(GamesTourModel game) {
  final parsed = PgnGame.parsePgn(game.pgn!);
  Position position = PgnGame.startingPosition(parsed.headers);
  final plies = <FeedPly>[FeedPly(fen: position.fen)];
  for (final node in parsed.moves.mainline()) {
    final move = position.parseSan(node.san)!;
    position = position.play(move);
    plies.add(FeedPly(fen: position.fen, san: node.san, uci: move.uci));
  }
  return FeedItem(
    game: game,
    plies: plies,
    reason: '',
    eventLabel: 'Test Open 2026',
    result: '1-0',
  );
}

Future<void> _pumpBoth(WidgetTester tester, GamesTourModel game) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(393 * 3, 1500 * 3);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final sfx = _SilentSfx();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        engineSettingsProviderNew.overrideWith(_Settings.new),
        eventNoSpoilersProvider.overrideWith(_MemoryNoSpoilers.new),
        chessPlayerRepositoryProvider.overrideWithValue(_ChessPlayers()),
        gamebaseRepositoryProvider.overrideWithValue(_Gamebase()),
        boardSettingsProviderNew.overrideWith(_BoardSettings.new),
        likedGamesProvider.overrideWith(_NoLikes.new),
        spaceShortcutsProvider.overrideWith(_NoShortcuts.new),
        currentUserProvider.overrideWithValue(null),
        feedSfxProvider.overrideWithValue(sfx),
        feedMoveSoundProvider.overrideWithValue(FeedMoveSound(sfx)),
        feedCachedEvalProvider.overrideWith((ref, fen) async => null),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: Column(
                children: [
                  KeyedSubtree(
                    key: const ValueKey('card'),
                    child: ChessBoardFromFENNew(
                      gamesTourModel: game,
                      onChanged: () {},
                      pinnedIds: const [],
                      onPinToggle: (_) {},
                    ),
                  ),
                  Expanded(
                    child: KeyedSubtree(
                      key: const ValueKey('feed'),
                      child: FeedClip(
                        item: _item(game),
                        isCurrent: false,
                        isVisible: false,
                        onRequestNext: () {},
                        onScrollLock: (_) {},
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
  // Settings, No Spoilers and the row lookups resolve.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Neither surface draws an eval bar here, so no engine is asked.
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

/// `chess_players` by FIDE id: the followed player's title and flag.
class _ChessPlayers implements ChessPlayerRepository {
  @override
  Future<ChessPlayer?> getPlayerByFideId(int fideId) async => switch (fideId) {
    2020009 => const ChessPlayer(
      fideid: 2020009,
      name: 'Caruana, Fabiano',
      title: 'GM',
      rating: 2795,
      country: 'USA',
    ),
    _ => null,
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Gamebase players by id: the miniature's titles.
class _Gamebase implements GamebaseRepository {
  @override
  Future<GamebasePlayer?> getPlayerById(String id) async => switch (id) {
    'gb-white' => const GamebasePlayer(
      id: 'gb-white',
      fideId: '',
      name: 'Carlsen, Magnus',
      gender: PlayerGender.male,
      fed: 'NOR',
      title: 'GM',
    ),
    'gb-black' => const GamebasePlayer(
      id: 'gb-black',
      fideId: '',
      name: 'Nakamura, Hikaru',
      gender: PlayerGender.male,
      fed: 'USA',
      title: 'GM',
    ),
    _ => null,
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BoardSettings extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

class _NoLikes extends LikedGamesNotifier {
  @override
  Future<List<SavedAnalysis>> build() async => const [];
}

class _NoShortcuts extends SpaceShortcutsNotifier {
  @override
  Future<List<SpaceShortcut>> build() async => const [];
}

class _SilentSfx implements FeedSfx {
  @override
  bool muted = true;

  @override
  bool boardSoundEnabled = false;

  @override
  Future<void> warmUp() async {}

  @override
  void playGameEnd(FeedItem item) {}

  @override
  void playSwipe() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
