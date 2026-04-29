import 'dart:async';

import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/game_stream_repository.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:dartchess/dartchess.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// A fake that satisfies the GameRepository type without touching Supabase.
/// getGamePgn() never completes, keeping parseMoves() suspended so we can
/// assert on the initial placeholder state.
class _NeverResolvingGameRepository implements GameRepository {
  @override
  Future<String?> getGamePgn(String gameId) => Completer<String?>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// GamebaseRepository whose methods return null / empty by default.
class _FakeGamebaseRepository extends GamebaseRepository {
  _FakeGamebaseRepository()
    : super(Dio(), baseUrl: 'http://localhost', apiKey: 'test');

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// GameStreamRepository that returns empty streams (no Supabase Realtime).
class _FakeGameStreamRepository extends GameStreamRepository {
  _FakeGameStreamRepository([Stream<Map<String, dynamic>?>? updates])
    : _updates = updates ?? const Stream.empty();

  final Stream<Map<String, dynamic>?> _updates;

  @override
  Stream<Map<String, dynamic>?> subscribeToGameUpdates(String gameId) =>
      _updates;

  @override
  Stream<String?> subscribeToPgn(String gameId) => const Stream.empty();

  @override
  Stream<String?> subscribeToLastMove(String gameId) => const Stream.empty();

  @override
  Stream<String?> subscribeToFen(String gameId) => const Stream.empty();

  @override
  Stream<String?> subscribeToStatus(String gameId) => const Stream.empty();
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

GamesTourModel _dummyGame({
  String? fen,
  String? pgn,
  String? lastMove,
  GameStatus gameStatus = GameStatus.ongoing,
}) {
  final player = PlayerCard(
    name: 'Player',
    federation: 'TR',
    title: '',
    rating: 0,
    countryCode: 'TR',
    team: null,
  );
  return GamesTourModel(
    gameId: 'test-game-1',
    whitePlayer: player,
    blackPlayer: player,
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: gameStatus,
    roundId: 'r1',
    tourId: 't1',
    fen: fen,
    pgn: pgn,
    lastMove: lastMove,
  );
}

ProviderContainer _createContainer({Stream<Map<String, dynamic>?>? updates}) {
  return ProviderContainer(
    overrides: [
      engineSettingsProviderNew.overrideWith(
        () => _FakeEngineSettingsNotifier(),
      ),
      gameRepositoryProvider.overrideWithValue(_NeverResolvingGameRepository()),
      gamebaseRepositoryProvider.overrideWithValue(_FakeGamebaseRepository()),
      gameStreamRepositoryProvider.overrideWithValue(
        _FakeGameStreamRepository(updates),
      ),
    ],
  );
}

Future<void> _waitFor(
  ProviderContainer container,
  ChessBoardProviderParams params,
  bool Function() condition,
) async {
  for (var i = 0; i < 50; i++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }

  final state = container.read(chessBoardScreenProviderNew(params)).valueOrNull;
  fail('Timed out waiting for board state. Last state: $state');
}

class _FakeEngineSettingsNotifier extends AsyncNotifier<EngineSettings>
    implements EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async => const EngineSettings();

  // Stub remaining methods required by EngineSettingsNotifierNew.
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Live FEN placeholder initialization', () {
    test('ongoing game with valid FEN seeds analysisState.position', () {
      // Use a mid-game FEN where dartchess won't normalise away the en-passant
      // square (no legal en-passant capture exists after 1.e4, so dartchess
      // strips it). A Sicilian position avoids that ambiguity.
      const fen =
          'rnbqkbnr/pp1ppppp/8/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2';
      final game = _dummyGame(fen: fen);
      final container = _createContainer();
      addTearDown(container.dispose);

      final params = ChessBoardProviderParams(game: game, index: 0);
      final stateAsync = container.read(chessBoardScreenProviderNew(params));
      final state = stateAsync.value;

      expect(
        state,
        isNotNull,
        reason: 'Initial state should be data, not loading',
      );
      expect(state!.isLoadingMoves, isTrue);

      // The placeholder position should match the FEN we provided.
      expect(state.position, isNotNull);
      expect(state.position!.fen, fen);

      // analysisState should also be seeded.
      expect(state.analysisState.position.fen, fen);
    });

    test('ongoing game with null FEN falls back to Chess.initial', () {
      final game = _dummyGame(fen: null);
      final container = _createContainer();
      addTearDown(container.dispose);

      final params = ChessBoardProviderParams(game: game, index: 0);
      final state = container.read(chessBoardScreenProviderNew(params)).value;

      expect(state, isNotNull);
      expect(state!.position, isNull);
      expect(state.analysisState.position, Chess.initial);
    });

    test('ongoing game with blank FEN falls back to Chess.initial', () {
      final game = _dummyGame(fen: '   ');
      final container = _createContainer();
      addTearDown(container.dispose);

      final params = ChessBoardProviderParams(game: game, index: 0);
      final state = container.read(chessBoardScreenProviderNew(params)).value;

      expect(state, isNotNull);
      expect(state!.position, isNull);
      expect(state.analysisState.position, Chess.initial);
    });

    test('finished game with valid FEN does not seed placeholder', () {
      const fen =
          'rnbqkbnr/pp1ppppp/8/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2';
      final game = _dummyGame(fen: fen, gameStatus: GameStatus.whiteWins);
      final container = _createContainer();
      addTearDown(container.dispose);

      final params = ChessBoardProviderParams(game: game, index: 0);
      final state = container.read(chessBoardScreenProviderNew(params)).value;

      expect(state, isNotNull);
      expect(state!.position, isNull);
      expect(state.analysisState.position, Chess.initial);
    });

    test('ongoing game with invalid FEN falls back to Chess.initial', () {
      final game = _dummyGame(fen: 'not-a-valid-fen');
      final container = _createContainer();
      addTearDown(container.dispose);

      final params = ChessBoardProviderParams(game: game, index: 0);
      final state = container.read(chessBoardScreenProviderNew(params)).value;

      expect(state, isNotNull);
      expect(state!.position, isNull);
      expect(state.analysisState.position, Chess.initial);
    });

    test(
      'streamed move does not advance board while viewing an older move',
      () async {
        const afterE4 =
            'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';
        const afterE4E5 =
            'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2';
        const afterNf3 =
            'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2';
        const pgnAfterE4E5 = '''
[Event "Live Test"]
[Result "*"]

1. e4 e5 *
''';
        const pgnAfterNf3 = '''
[Event "Live Test"]
[Result "*"]

1. e4 e5 2. Nf3 *
''';

        final controller = StreamController<Map<String, dynamic>?>();
        addTearDown(controller.close);

        final game = _dummyGame(
          fen: afterE4E5,
          pgn: pgnAfterE4E5,
          lastMove: 'e7e5',
        );
        final container = _createContainer(updates: controller.stream);

        // Keep evaluation work out of this provider unit test.
        container.read(currentlyVisiblePageIndexProvider.notifier).state = 99;

        final params = ChessBoardProviderParams(game: game, index: 0);
        final subscription = container.listen(
          chessBoardScreenProviderNew(params),
          (_, __) {},
          fireImmediately: true,
        );
        addTearDown(() async {
          subscription.close();
          await Future<void>.delayed(Duration.zero);
          container.dispose();
        });

        await _waitFor(container, params, () {
          final state =
              container.read(chessBoardScreenProviderNew(params)).valueOrNull;
          return state != null &&
              !state.isLoadingMoves &&
              state.analysisState.game != null &&
              state.analysisState.currentMoveIndex == 1;
        });

        final notifier = container.read(
          chessBoardScreenProviderNew(params).notifier,
        );
        await notifier.moveBackward();

        var state =
            container.read(chessBoardScreenProviderNew(params)).valueOrNull!;
        expect(state.analysisState.currentMoveIndex, 0);
        expect(state.analysisState.position.fen, afterE4);
        expect(
          state.currentMoveIndex,
          1,
          reason:
              'The legacy top-level index remains stale after analysis navigation.',
        );

        controller.add({
          'fen': afterNf3,
          'pgn': pgnAfterNf3,
          'last_move': 'g1f3',
          'status': '*',
        });

        await _waitFor(container, params, () {
          final state =
              container.read(chessBoardScreenProviderNew(params)).valueOrNull;
          return state?.moveSans.length == 3;
        });

        state =
            container.read(chessBoardScreenProviderNew(params)).valueOrNull!;
        expect(state.position!.fen, afterNf3);
        expect(state.moveSans, ['e4', 'e5', 'Nf3']);
        expect(state.analysisState.currentMoveIndex, 0);
        expect(state.analysisState.position.fen, afterE4);
        expect(state.hasUnseenMoves, isTrue);
      },
    );
  });
}
