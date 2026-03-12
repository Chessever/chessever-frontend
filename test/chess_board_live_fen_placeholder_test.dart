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

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

GamesTourModel _dummyGame({
  String? fen,
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
  );
}

ProviderContainer _createContainer() {
  return ProviderContainer(
    overrides: [
      engineSettingsProviderNew.overrideWith(
        () => _FakeEngineSettingsNotifier(),
      ),
      gameRepositoryProvider
          .overrideWithValue(_NeverResolvingGameRepository()),
      gamebaseRepositoryProvider
          .overrideWithValue(_FakeGamebaseRepository()),
      gameStreamRepositoryProvider
          .overrideWithValue(_FakeGameStreamRepository()),
    ],
  );
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

      expect(state, isNotNull, reason: 'Initial state should be data, not loading');
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
      final state =
          container.read(chessBoardScreenProviderNew(params)).value;

      expect(state, isNotNull);
      expect(state!.position, isNull);
      expect(state.analysisState.position, Chess.initial);
    });

    test('ongoing game with blank FEN falls back to Chess.initial', () {
      final game = _dummyGame(fen: '   ');
      final container = _createContainer();
      addTearDown(container.dispose);

      final params = ChessBoardProviderParams(game: game, index: 0);
      final state =
          container.read(chessBoardScreenProviderNew(params)).value;

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
      final state =
          container.read(chessBoardScreenProviderNew(params)).value;

      expect(state, isNotNull);
      expect(state!.position, isNull);
      expect(state.analysisState.position, Chess.initial);
    });

    test('ongoing game with invalid FEN falls back to Chess.initial', () {
      final game = _dummyGame(fen: 'not-a-valid-fen');
      final container = _createContainer();
      addTearDown(container.dispose);

      final params = ChessBoardProviderParams(game: game, index: 0);
      final state =
          container.read(chessBoardScreenProviderNew(params)).value;

      expect(state, isNotNull);
      expect(state!.position, isNull);
      expect(state.analysisState.position, Chess.initial);
    });
  });
}
