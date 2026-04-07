import 'package:chessever2/repository/supabase/game/game_stream_multiplexer.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Repository provider for game streaming.
final gameStreamRepositoryProvider = AutoDisposeProvider<GameStreamRepository>((
  ref,
) {
  final multiplexer = ref.watch(gameStreamMultiplexerProvider);
  return GameStreamRepository(multiplexer);
});

/// Repository for streaming individual game updates from Supabase Realtime.
class GameStreamRepository {
  final GameStreamMultiplexer _multiplexer;

  GameStreamRepository(this._multiplexer);

  /// Subscribe to PGN updates for a specific game
  Stream<String?> subscribeToPgn(String gameId) {
    return _multiplexer.subscribeToGame(gameId)
        .map((data) => data?['pgn'] as String?);
  }

  /// Subscribe to last move updates for a specific game
  Stream<String?> subscribeToLastMove(String gameId) {
    return _multiplexer.subscribeToGame(gameId)
        .map((data) => data?['last_move'] as String?);
  }

  /// Subscribe to FEN updates for a specific game
  Stream<String?> subscribeToFen(String gameId) {
    return _multiplexer.subscribeToGame(gameId)
        .map((data) => data?['fen'] as String?);
  }

  /// Subscribe to status updates for a specific game
  Stream<String?> subscribeToStatus(String gameId) {
    return _multiplexer.subscribeToGame(gameId)
        .map((data) => data?['status'] as String?);
  }

  /// Comprehensive game streaming - includes ALL game data in one stream.
  Stream<Map<String, dynamic>?> subscribeToGameUpdates(String gameId) {
    return _multiplexer.subscribeToGame(gameId);
  }
}
