import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Atomic provider for streaming white clock updates
final gameWhiteClockStreamProvider = AutoDisposeStreamProvider.family<
  int?,
  String
>((ref, gameId) {
  print('🔥 WhiteClockStream: Setting up stream for game $gameId');
  return Supabase.instance.client
      .from('games')
      .stream(primaryKey: ['id'])
      .eq('id', gameId)
      .map((data) {
        final clockValue =
            data.isEmpty
                ? null
                : (data.first['last_clock_white'] as num?)?.round();
        print(
          '🔥 WhiteClockStream: Game $gameId white clock update: $clockValue',
        );
        return clockValue;
      });
});

// Atomic provider for streaming black clock updates
final gameBlackClockStreamProvider = AutoDisposeStreamProvider.family<
  int?,
  String
>((ref, gameId) {
  print('🔥 BlackClockStream: Setting up stream for game $gameId');
  return Supabase.instance.client
      .from('games')
      .stream(primaryKey: ['id'])
      .eq('id', gameId)
      .map((data) {
        final clockValue =
            data.isEmpty
                ? null
                : (data.first['last_clock_black'] as num?)?.round();
        print(
          '🔥 BlackClockStream: Game $gameId black clock update: $clockValue',
        );
        return clockValue;
      });
});

// Atomic provider for streaming last move time
final gameLastMoveTimeStreamProvider = AutoDisposeStreamProvider.family<
  DateTime?,
  String
>((ref, gameId) {
  print('🔥 LastMoveTimeStream: Setting up stream for game $gameId');
  return Supabase.instance.client
      .from('games')
      .stream(primaryKey: ['id'])
      .eq('id', gameId)
      .map((data) {
        if (data.isEmpty) return null;
        final timeStr = data.first['last_move_time'] as String?;
        final parsedTime = timeStr != null ? DateTime.tryParse(timeStr) : null;
        print(
          '🔥 LastMoveTimeStream: Game $gameId last move time update: $parsedTime',
        );
        return parsedTime;
      });
});
