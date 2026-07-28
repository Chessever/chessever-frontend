import 'dart:async';
import 'dart:io';

import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/game_stream_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Proves deferred full-event expand can remap PageView index (e.g. 0 → 4)
/// without disposing the live board provider, and that post-open selected-game
/// PGN hydrate reaches that same provider instance.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://placeholder.supabase.co',
      anonKey: 'placeholder-anon-key',
    );
  });

  test(
    'ChessBoardProviderParams identity is gameId-only so index remap reuses provider',
    () {
      final game = _boardGame(id: 'r1-b2', pgn: _shortPgn);
      final at0 = ChessBoardProviderParams(game: game, index: 0);
      final at4 = ChessBoardProviderParams(game: game, index: 4);

      expect(
        at0,
        equals(at4),
        reason: 'family must not remount when expand remaps page index',
      );
      expect(at0.hashCode, at4.hashCode);

      final other = ChessBoardProviderParams(
        game: _boardGame(id: 'other-game', pgn: _shortPgn),
        index: 0,
      );
      expect(at0 == other, isFalse);
    },
  );

  test(
    'chessBoardScreenProviderNew returns the same notifier across index remap',
    () {
      final game = _boardGame(
        id: 'r1-b2',
        pgn: _shortPgn,
        fen: _afterE4Fen,
        lastMove: 'e2e4',
      );
      final container = _boardContainer();
      addTearDown(container.dispose);
      // Avoid auto-eval while no page is "visible" so dispose is clean.
      container.read(currentlyVisiblePageIndexProvider.notifier).state = 99;

      final params0 = ChessBoardProviderParams(game: game, index: 0);
      final params4 = ChessBoardProviderParams(game: game, index: 4);

      final sub = container.listen(
        chessBoardScreenProviderNew(params0),
        (_, __) {},
      );
      addTearDown(sub.close);

      final notifier0 =
          container.read(chessBoardScreenProviderNew(params0).notifier);
      final notifier4 =
          container.read(chessBoardScreenProviderNew(params4).notifier);

      expect(
        identical(notifier0, notifier4),
        isTrue,
        reason: 'expand 0→4 must keep the live board instance',
      );
      expect(notifier0.index, 0);

      notifier0.syncPageIndex(4);
      expect(notifier0.index, 4);
      expect(
        notifier4.index,
        4,
        reason: 'same instance shares the remapped page index',
      );
    },
  );

  test(
    'real expand path: immediate open index 0, expanded index 4, same provider + hydrate apply',
    () async {
      final fullRaw = [
        _rawGame(id: 'r2-b1', roundSlug: 'round-2', boardNr: 1),
        _rawGame(id: 'r2-b2', roundSlug: 'round-2', boardNr: 2),
        _rawGame(id: 'r1-b1', roundSlug: 'round-1', boardNr: 1),
        _rawGame(id: 'r1-b2', roundSlug: 'round-1', boardNr: 2, pgn: _shortPgn),
        _rawGame(id: 'r3-b1', roundSlug: 'round-3', boardNr: 1),
      ];
      final tapped = GamesTourModel.fromGame(
        fullRaw.firstWhere((g) => g.id == 'r1-b2'),
      );

      final container = ProviderContainer(
        overrides: [
          gamesLocalStorage.overrideWith(
            (ref) => _CachedGamesLocalStorage(ref, fullRaw),
          ),
          gameRepositoryProvider.overrideWithValue(
            _HydratingGameRepo(
              _rawGame(
                id: 'r1-b2',
                roundSlug: 'round-1',
                boardNr: 2,
                pgn: _finalPgn,
                fen: _afterNc6Fen,
                lastMove: 'b8c6',
                status: '1-0',
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final launch = container
          .read(gameCardWrapperProvider)
          .debugBeginBoardNavigation(
            orderedGames: [tapped],
            gameIndex: 0,
            viewSource: ChessboardView.forYou,
          );

      expect(launch.immediateIndex, 0);
      expect(launch.immediateGames.single.gameId, 'r1-b2');

      final expanded = await launch.expanded;
      expect(expanded.index, 4);
      expect(expanded.games[expanded.index].gameId, 'r1-b2');
      // Selected-game hydrate ran on the expanded future (not before open).
      expect(expanded.games[expanded.index].pgn, contains('Nc6'));

      // The board would open with params(index: 0) then expand to index 4 —
      // identity must still resolve to one provider for this gameId.
      final openParams = ChessBoardProviderParams(
        game: launch.immediateGames[launch.immediateIndex],
        index: launch.immediateIndex,
      );
      final expandedParams = ChessBoardProviderParams(
        game: expanded.games[expanded.index],
        index: expanded.index,
      );
      expect(openParams, equals(expandedParams));

      final boardContainer = _boardContainer(
        gameRepository: _StaticPgnRepo(_finalPgn),
      );
      addTearDown(boardContainer.dispose);
      boardContainer.read(currentlyVisiblePageIndexProvider.notifier).state =
          99;
      final sub = boardContainer.listen(
        chessBoardScreenProviderNew(openParams),
        (_, __) {},
      );
      addTearDown(sub.close);
      final nOpen =
          boardContainer.read(chessBoardScreenProviderNew(openParams).notifier);
      final nExpanded = boardContainer.read(
        chessBoardScreenProviderNew(expandedParams).notifier,
      );
      expect(identical(nOpen, nExpanded), isTrue);
      nOpen.syncPageIndex(expanded.index);
      expect(nExpanded.index, 4);
      expect(
        identical(
          nOpen,
          boardContainer
              .read(chessBoardScreenProviderNew(expandedParams).notifier),
        ),
        isTrue,
        reason: 'post-expand params must resolve to the open-time provider',
      );

      // Production didUpdateWidget calls applyNavigationGameSnapshot. The
      // method always stashes onto [game] first (sync), then may reparse.
      // Assert the sync stash + identity survival — reparse needs device plugins.
      nExpanded.applyNavigationGameSnapshot(expanded.games[expanded.index]);
      expect(nExpanded.game.pgn, contains('Nc6'));
      expect(identical(nOpen, nExpanded), isTrue);
    },
  );

  test(
    'board didUpdateWidget wires index remap + navigation hydrate into the live provider',
    () {
      // Structural contract on the shipped board screen: expand remount fix.
      final boardSrc = File(
        'lib/screens/chessboard/chess_board_screen_new.dart',
      ).readAsStringSync();
      expect(boardSrc, contains('void didUpdateWidget'));
      expect(boardSrc, contains('syncPageIndex'));
      expect(boardSrc, contains('applyNavigationGameSnapshot'));
      expect(
        boardSrc,
        contains('never remount analysis'),
        reason: 'comment documents the no-remount contract',
      );
      // didUpdateWidget runs inside BuildOwner.buildScope, so the expanded
      // games / page-index provider writes MUST stay deferred past the frame.
      // Inlining them throws "Tried to modify a provider while the widget tree
      // was building" the moment the background expand swaps the games list.
      expect(
        boardSrc,
        contains('_syncExpandedGameProvidersAfterFrame'),
        reason: 'expand provider writes must be post-frame, not inline',
      );

      // CHESSEVER-1TV / 1TW: jumpToPage from didUpdateWidget notifies
      // onPageChanged → _handlePageChange → currentlyVisiblePageIndexProvider
      // during element update. Programmatic jumps must be gated; the expand
      // path must not call jumpToPage(desiredIndex) bare.
      expect(
        boardSrc,
        contains('_isProgrammaticPageJump'),
        reason: 'flag gates build-phase provider writes from jumpToPage',
      );
      expect(
        boardSrc,
        contains('_jumpToPageProgrammatically'),
        reason: 'expand remap must use the suppress wrapper, not bare jump',
      );
      expect(
        boardSrc,
        contains('_jumpToPageProgrammatically(desiredIndex)'),
        reason: 'didUpdateWidget expand path must jump via the wrapper',
      );
      // Bare expand jump is the regression that blacks the frame.
      expect(
        boardSrc.contains('_pageController.jumpToPage(desiredIndex)'),
        isFalse,
        reason:
            'must not jumpToPage(desiredIndex) without _isProgrammaticPageJump',
      );
      expect(
        boardSrc,
        contains('if (_isProgrammaticPageJump)'),
        reason: '_handlePageChange must early-return for programmatic jumps',
      );

      // currentlyVisiblePageIndexProvider write in _handlePageChange must sit
      // AFTER the programmatic-jump guard (not before it).
      final handleStart = boardSrc.indexOf('Future<void> _handlePageChange');
      expect(handleStart, greaterThanOrEqualTo(0));
      // Bound the slice to this method only (next top-level method after it).
      final handleEndCandidate = boardSrc.indexOf(
        '\n  Future<void> ',
        handleStart + 1,
      );
      final handleEnd =
          handleEndCandidate > handleStart
              ? handleEndCandidate
              : (handleStart + 4000).clamp(0, boardSrc.length);
      final handleSlice = boardSrc.substring(handleStart, handleEnd);
      final guardAt = handleSlice.indexOf('if (_isProgrammaticPageJump)');
      final writeAt = handleSlice.indexOf(
        'currentlyVisiblePageIndexProvider.notifier).state = newIndex',
      );
      expect(guardAt, greaterThanOrEqualTo(0), reason: 'guard present');
      expect(writeAt, greaterThanOrEqualTo(0), reason: 'provider write present');
      expect(
        guardAt < writeAt,
        isTrue,
        reason:
            'programmatic-jump guard must precede the provider write so expand '
            'jumpToPage cannot mutate providers during build',
      );

      final providerSrc = File(
        'lib/screens/chessboard/provider/chess_board_screen_provider_new.dart',
      ).readAsStringSync();
      // Identity is gameId-only (index excluded from == / hashCode).
      expect(
        providerSrc,
        contains('game.gameId == other.game.gameId;'),
      );
      expect(
        providerSrc.contains('index == other.index'),
        isFalse,
        reason: 'index must not participate in provider family identity',
      );
      expect(providerSrc, contains('void applyNavigationGameSnapshot'));
      expect(providerSrc, contains('void syncPageIndex'));

      // Notification / deep-link opens hydrate a 1-game list into the full
      // round list. That MUST update the board in place so didUpdateWidget
      // runs syncPageIndex — a key that varies with the list length remounts
      // the screen instead, stranding the gameId-keyed notifier on index 0
      // while the visible-page provider moves, which silently gates off every
      // evaluation ("engine dead when opened from a notification").
      final deepLinkSrc = File(
        'lib/services/deep_link_service.dart',
      ).readAsStringSync();
      expect(
        deepLinkSrc.contains("'deep-link-\${widget.initialGameId}-"),
        isFalse,
        reason: 'deep-link board key must not vary with the games list',
      );
      expect(
        deepLinkSrc,
        contains("ValueKey('deep-link-\${widget.initialGameId}')"),
      );
    },
  );

}

const _shortPgn = '''
[Event "Titled Tuesday"]

1. e4 *
''';

const _finalPgn = '''
[Event "Titled Tuesday"]

1. e4 e5 2. Nf3 Nc6 1-0
''';

const _afterE4Fen =
    'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';
const _afterNc6Fen =
    'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3';

GamesTourModel _boardGame({
  required String id,
  required String pgn,
  String? fen,
  String? lastMove,
  String status = '*',
}) {
  final player = PlayerCard(
    name: 'Player',
    federation: 'USA',
    title: 'GM',
    rating: 2700,
    countryCode: 'USA',
    team: null,
  );
  return GamesTourModel(
    gameId: id,
    whitePlayer: player,
    blackPlayer: player,
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: GameStatus.fromString(status),
    roundId: 'round-1',
    tourId: 'tour-1',
    fen: fen,
    pgn: pgn,
    lastMove: lastMove,
  );
}

Games _rawGame({
  required String id,
  required String roundSlug,
  required int boardNr,
  String? pgn,
  String? fen,
  String? lastMove,
  String status = '*',
}) {
  return Games(
    id: id,
    roundId: roundSlug,
    roundSlug: roundSlug,
    tourId: 'tour-1',
    tourSlug: 'tour-1',
    players: [
      Player(
        name: 'White $id',
        title: 'GM',
        rating: 2700,
        fideId: 1,
        fed: 'USA',
        clock: 0,
        team: '',
      ),
      Player(
        name: 'Black $id',
        title: 'GM',
        rating: 2700,
        fideId: 2,
        fed: 'USA',
        clock: 0,
        team: '',
      ),
    ],
    boardNr: boardNr,
    status: status,
    lastMove: lastMove ?? 'e2e4',
    pgn: pgn,
    fen: fen,
  );
}

ProviderContainer _boardContainer({GameRepository? gameRepository}) {
  return ProviderContainer(
    overrides: [
      engineSettingsProviderNew.overrideWith(
        () => _FakeEngineSettingsNotifier(),
      ),
      gameRepositoryProvider.overrideWithValue(
        gameRepository ?? _NeverResolvingGameRepository(),
      ),
      gamebaseRepositoryProvider.overrideWithValue(_FakeGamebaseRepository()),
      gameStreamRepositoryProvider.overrideWithValue(
        _FakeGameStreamRepository(),
      ),
      chessBoardPersistenceEnabledProvider.overrideWithValue(false),
    ],
  );
}

class _NeverResolvingGameRepository implements GameRepository {
  @override
  Future<String?> getGamePgn(String gameId) => Completer<String?>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _StaticPgnRepo implements GameRepository {
  _StaticPgnRepo(this.pgn);
  final String pgn;

  @override
  Future<String?> getGamePgn(String gameId) async => pgn;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _HydratingGameRepo extends GameRepository {
  _HydratingGameRepo(this.latest);
  final Games latest;

  @override
  Future<Games> getGameWithPGN(String gameId) async => latest;
}

class _FakeGamebaseRepository extends GamebaseRepository {
  _FakeGamebaseRepository()
    : super(Dio(), baseUrl: 'http://localhost', apiKey: 'test');

  @override
  Future<GamebaseGameWithPgn?> getGameWithPgn(String id) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeGameStreamRepository extends GameStreamRepository {
  @override
  Stream<Map<String, dynamic>?> subscribeToGameUpdates(String gameId) =>
      const Stream.empty();

  @override
  Stream<String?> subscribeToPgn(String gameId) => const Stream.empty();

  @override
  Stream<String?> subscribeToLastMove(String gameId) => const Stream.empty();

  @override
  Stream<String?> subscribeToFen(String gameId) => const Stream.empty();

  @override
  Stream<String?> subscribeToStatus(String gameId) => const Stream.empty();
}

class _CachedGamesLocalStorage extends GamesLocalStorage {
  _CachedGamesLocalStorage(super.ref, this._cached);
  final List<Games> _cached;

  @override
  Future<List<Games>> getCachedGames(String tourId) async => _cached;

  @override
  Future<List<Games>> fetchAndSaveGames(
    String tourId, {
    bool forceRefresh = false,
  }) async => _cached;
}

class _FakeEngineSettingsNotifier extends AsyncNotifier<EngineSettings>
    implements EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async => const EngineSettings();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
