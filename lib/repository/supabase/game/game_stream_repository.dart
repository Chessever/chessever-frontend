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
}
