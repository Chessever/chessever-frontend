import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Repository provider
final gameStreamRepositoryProvider = AutoDisposeProvider<_GameStreamRepository>(
  (ref) {
    return _GameStreamRepository();
  },
);

// Repository
class _GameStreamRepository {
  Stream<String?> subscribeToPgn(String gameId) {
    return Supabase.instance.client
        .from('games')
        .stream(primaryKey: ['id'])
        .eq('id', gameId)
        .map((data) => data.isEmpty ? null : data.first['pgn'] as String?);
  }

  Stream<String?> subscribeToLastMove(String gameId) {
    return Supabase.instance.client
        .from('games')
        .stream(primaryKey: ['id'])
        .eq('id', gameId)
        .map(
          (data) => data.isEmpty ? null : data.first['last_move'] as String?,
        );
  }

  Stream<String?> subscribeToFen(String gameId) {
    return Supabase.instance.client
        .from('games')
        .stream(primaryKey: ['id'])
        .eq('id', gameId)
        .map((data) => data.isEmpty ? null : data.first['fen'] as String?);
  }

  // New comprehensive game streaming for clock updates
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
