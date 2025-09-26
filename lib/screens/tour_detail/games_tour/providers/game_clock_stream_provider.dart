import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Atomic provider for streaming white clock updates
final gameWhiteClockStreamProvider = AutoDisposeStreamProvider.family<int?, String>(
  (ref, gameId) {
    return Supabase.instance.client
        .from('games')
        .stream(primaryKey: ['id'])
        .eq('id', gameId)
        .map((data) => data.isEmpty ? null : (data.first['last_clock_white'] as num?)?.round());
  },
);

// Atomic provider for streaming black clock updates
final gameBlackClockStreamProvider = AutoDisposeStreamProvider.family<int?, String>(
  (ref, gameId) {
    return Supabase.instance.client
        .from('games')
        .stream(primaryKey: ['id'])
        .eq('id', gameId)
        .map((data) => data.isEmpty ? null : (data.first['last_clock_black'] as num?)?.round());
  },
);

// Atomic provider for streaming last move time
final gameLastMoveTimeStreamProvider = AutoDisposeStreamProvider.family<DateTime?, String>(
  (ref, gameId) {
    return Supabase.instance.client
        .from('games')
        .stream(primaryKey: ['id'])
        .eq('id', gameId)
        .map((data) {
          if (data.isEmpty) return null;
          final timeStr = data.first['last_move_time'] as String?;
          return timeStr != null ? DateTime.tryParse(timeStr) : null;
        });
  },
);