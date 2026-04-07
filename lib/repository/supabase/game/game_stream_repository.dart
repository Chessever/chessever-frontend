import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Repository provider for game streaming.
/// Each subscription creates its own Realtime channel that auto-disposes when the widget
/// is scrolled out of view (via Riverpod's autoDispose).
final gameStreamRepositoryProvider = AutoDisposeProvider<GameStreamRepository>((
  ref,
) {
  return GameStreamRepository();
});

/// Repository for streaming individual game updates from Supabase Realtime.
/// Uses Supabase's .stream() which creates individual channels per game.
/// Riverpod's autoDispose handles cleanup when widgets are disposed.
class GameStreamRepository {
  /// Subscribe to PGN updates for a specific game
  Stream<String?> subscribeToPgn(String gameId) {
    return Supabase.instance.client
        .from('games')
        .stream(primaryKey: ['id'])
        .eq('id', gameId)
        .map((data) => data.isEmpty ? null : data.first['pgn'] as String?);
  }

  /// Subscribe to last move updates for a specific game
  Stream<String?> subscribeToLastMove(String gameId) {
    return Supabase.instance.client
        .from('games')
        .stream(primaryKey: ['id'])
        .eq('id', gameId)
        .map(
          (data) => data.isEmpty ? null : data.first['last_move'] as String?,
        );
  }

  /// Subscribe to FEN updates for a specific game
  Stream<String?> subscribeToFen(String gameId) {
    return Supabase.instance.client
        .from('games')
        .stream(primaryKey: ['id'])
        .eq('id', gameId)
        .map((data) => data.isEmpty ? null : data.first['fen'] as String?);
  }

  /// Subscribe to status updates for a specific game
  Stream<String?> subscribeToStatus(String gameId) {
    return Supabase.instance.client
        .from('games')
        .stream(primaryKey: ['id'])
        .eq('id', gameId)
        .map((data) => data.isEmpty ? null : data.first['status'] as String?);
  }

  /// Comprehensive game streaming - includes ALL game data in one stream.
  /// This is the primary method used by game cards for live updates.
  /// Each call creates an individual Realtime channel for this game.
  Stream<Map<String, dynamic>?> subscribeToGameUpdates(String gameId) {
    return Supabase.instance.client
        .from('games')
        .stream(primaryKey: ['id'])
        .eq('id', gameId)
        .map((data) {
          if (data.isEmpty) return null;
          final game = data.first;
          return {
            'pgn': game['pgn'] as String?,
            'fen': game['fen'] as String?,
            'last_move': game['last_move'] as String?,
            'last_move_time': game['last_move_time'] as String?,
            'last_clock_white': game['last_clock_white'] as num?,
            'last_clock_black': game['last_clock_black'] as num?,
            'status': game['status'] as String?,
            'players': game['players'],
          };
        });
  }
}
