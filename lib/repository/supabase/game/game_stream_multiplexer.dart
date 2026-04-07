import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final gameStreamMultiplexerProvider = Provider<GameStreamMultiplexer>((ref) {
  final multiplexer = GameStreamMultiplexer();
  ref.onDispose(() {
    multiplexer.dispose();
  });
  return multiplexer;
});

class GameStreamMultiplexer {
  final Map<String, StreamController<Map<String, dynamic>?>> _controllers = {};
  RealtimeChannel? _channel;
  int _listenerCount = 0;

  Stream<Map<String, dynamic>?> subscribeToGame(String gameId) {
    if (!_controllers.containsKey(gameId)) {
      _controllers[gameId] = StreamController<Map<String, dynamic>?>.broadcast(
        onListen: () {
          _listenerCount++;
          _checkSubscription();
        },
        onCancel: () {
          _listenerCount--;
          _checkSubscription();
        },
      );
    }
    return _controllers[gameId]!.stream;
  }

  void _checkSubscription() {
    if (_listenerCount > 0 && _channel == null) {
      _startSubscription();
    } else if (_listenerCount == 0 && _channel != null) {
      _stopSubscription();
    }
  }

  void _startSubscription() {
    debugPrint('GameStreamMultiplexer: Starting global game updates subscription');
    _channel = Supabase.instance.client.channel('public:games:multiplexer');
    _channel!
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'games',
        callback: (payload) {
          final newRecord = payload.newRecord;
          final gameId = newRecord['id'] as String?;
          if (gameId != null && _controllers.containsKey(gameId)) {
            _controllers[gameId]!.add(newRecord);
          }
        },
      )
      .subscribe();
  }

  void _stopSubscription() {
    debugPrint('GameStreamMultiplexer: Stopping global game updates subscription');
    _channel?.unsubscribe();
    _channel = null;
  }

  void dispose() {
    _stopSubscription();
    for (final controller in _controllers.values) {
      controller.close();
    }
    _controllers.clear();
  }
}
