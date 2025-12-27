import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Shared stream manager that uses batched Realtime channels for multiple games.
/// This solves the "ChannelRateLimitReached: Too many channels" issue by
/// batching game subscriptions into shared channels (max 100 games per channel).
///
/// Example:
/// - 50 games  → 1 channel (instead of 50)
/// - 150 games → 2 channels (instead of 150)
/// - 300 games → 3 channels (instead of 300)
class SharedGameStreamManager {
  static const int _maxGamesPerChannel = 100;

  final SupabaseClient _client;
  final List<RealtimeChannel> _channels = [];
  final Set<String> _subscribedGameIds = {};
  final Map<String, StreamController<Map<String, dynamic>>> _gameControllers =
      {};
  bool _isRebuilding = false;
  Timer? _rebuildDebounceTimer;

  SharedGameStreamManager(this._client);

  /// Get a stream for a specific game - creates/joins shared channel
  Stream<Map<String, dynamic>?> getGameStream(String gameId) {
    if (!_gameControllers.containsKey(gameId)) {
      _gameControllers[gameId] =
          StreamController<Map<String, dynamic>>.broadcast();
      _subscribedGameIds.add(gameId);
      _scheduleRebuild();
    }
    return _gameControllers[gameId]!.stream;
  }

  /// Unsubscribe from a specific game
  void removeGameStream(String gameId) {
    final controller = _gameControllers.remove(gameId);
    controller?.close();
    _subscribedGameIds.remove(gameId);
    // Don't rebuild immediately on removal - wait for debounce
    _scheduleRebuild();
  }

  /// Debounce channel rebuilds to avoid rapid recreation during scrolling
  void _scheduleRebuild() {
    _rebuildDebounceTimer?.cancel();
    _rebuildDebounceTimer = Timer(const Duration(milliseconds: 100), () {
      _rebuildChannels();
    });
  }

  Future<void> _rebuildChannels() async {
    if (_isRebuilding) return;
    _isRebuilding = true;

    try {
      // Unsubscribe all old channels
      for (final channel in _channels) {
        await _client.removeChannel(channel);
      }
      _channels.clear();

      if (_subscribedGameIds.isEmpty) {
        _isRebuilding = false;
        return;
      }

      // Batch game IDs into groups of 100 (Supabase inFilter limit)
      final gameIdsList = _subscribedGameIds.toList();
      final batches = <List<String>>[];

      for (var i = 0; i < gameIdsList.length; i += _maxGamesPerChannel) {
        final end = (i + _maxGamesPerChannel < gameIdsList.length)
            ? i + _maxGamesPerChannel
            : gameIdsList.length;
        batches.add(gameIdsList.sublist(i, end));
      }

      print(
        '🔄 SharedGameStreamManager: Subscribing to ${gameIdsList.length} games '
        'using ${batches.length} channel(s) (was ${gameIdsList.length} channels before fix)',
      );

      // Create one channel per batch
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      for (var batchIndex = 0; batchIndex < batches.length; batchIndex++) {
        final batch = batches[batchIndex];
        final channel = _client
            .channel('shared-games-$timestamp-$batchIndex')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'games',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.inFilter,
                column: 'id',
                value: batch,
              ),
              callback: (payload) {
                final newRecord = payload.newRecord;
                final gameId = newRecord['id'] as String?;

                if (gameId != null && _gameControllers.containsKey(gameId)) {
                  // Transform to match the expected format
                  final gameData = {
                    'pgn': newRecord['pgn'] as String?,
                    'fen': newRecord['fen'] as String?,
                    'last_move': newRecord['last_move'] as String?,
                    'last_move_time': newRecord['last_move_time'] as String?,
                    'last_clock_white': newRecord['last_clock_white'] as num?,
                    'last_clock_black': newRecord['last_clock_black'] as num?,
                    'status': newRecord['status'] as String?,
                    'players': newRecord['players'],
                  };
                  _gameControllers[gameId]!.add(gameData);
                }
              },
            )
            .subscribe((status, error) {
          if (error != null) {
            print(
              '❌ SharedGameStreamManager: Channel $batchIndex error: $error',
            );
          } else {
            print(
              '✅ SharedGameStreamManager: Channel $batchIndex ($status) - ${batch.length} games',
            );
          }
        });

        _channels.add(channel);
      }
    } finally {
      _isRebuilding = false;
    }
  }

  void dispose() {
    _rebuildDebounceTimer?.cancel();
    for (final channel in _channels) {
      _client.removeChannel(channel);
    }
    _channels.clear();
    for (final controller in _gameControllers.values) {
      controller.close();
    }
    _gameControllers.clear();
    _subscribedGameIds.clear();
    print('🗑️ SharedGameStreamManager: Disposed');
  }
}

/// Global provider for the shared game stream manager.
/// This is a singleton that manages ONE Realtime channel for all game card subscriptions.
final sharedGameStreamManagerProvider = Provider<SharedGameStreamManager>((
  ref,
) {
  final manager = SharedGameStreamManager(Supabase.instance.client);
  ref.onDispose(() => manager.dispose());
  return manager;
});

// Repository provider (kept for backward compatibility - used by full chessboard view)
final gameStreamRepositoryProvider = AutoDisposeProvider<_GameStreamRepository>(
  (ref) {
    return _GameStreamRepository();
  },
);

// Repository (used for single-game views like the chessboard screen)
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

  Stream<String?> subscribeToStatus(String gameId) {
    return Supabase.instance.client
        .from('games')
        .stream(primaryKey: ['id'])
        .eq('id', gameId)
        .map((data) => data.isEmpty ? null : data.first['status'] as String?);
  }

  // Comprehensive game streaming - includes ALL game data in one stream
  Stream<Map<String, dynamic>?> subscribeToGameUpdates(String gameId) {
    return Supabase.instance.client
        .from('games')
        .stream(primaryKey: ['id'])
        .eq('id', gameId)
        .map((data) {
          if (data.isEmpty) return null;
          final game = data.first;
          return {
            'pgn': game['pgn'] as String?, // Include PGN to eliminate need for separate stream
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
