import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/services/live_updates_service.dart';
import 'package:chessever2/services/push_notifications_service.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final liveGameSubscriptionProvider = AutoDisposeAsyncNotifierProviderFamily<
    LiveGameSubscriptionNotifier, bool, String>(
  LiveGameSubscriptionNotifier.new,
);

class LiveGameSubscriptionNotifier
    extends AutoDisposeFamilyAsyncNotifier<bool, String> {
  @override
  Future<bool> build(String gameId) async {
    final user = ref.watch(currentUserProvider);
    final platform = _platformLabel();
    if (user == null || platform == null) return false;

    try {
      final data = await Supabase.instance.client
          .from('user_live_game_subscriptions')
          .select('enabled')
          .eq('user_id', user.id)
          .eq('game_id', gameId)
          .eq('platform', platform)
          .eq('enabled', true)
          .limit(1);
      return data.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> setEnabled({
    required bool enabled,
    required GamesTourModel game,
  }) async {
    final user = ref.read(currentUserProvider);
    final platform = _platformLabel();
    if (user == null || platform == null) return;

    state = const AsyncLoading();

    if (enabled) {
      final granted =
          await PushNotificationsService.instance.requestPermissionWithDialog();
      if (!granted) {
        state = const AsyncData(false);
        return;
      }

      await LiveUpdatesService.instance.startLiveActivity(
        activityId: _activityId(game.gameId, user.id),
        attributes: {'game_id': game.gameId},
        content: _buildLiveContent(game),
      );
    } else {
      await LiveUpdatesService.instance.endLiveActivity(
        _activityId(game.gameId, user.id),
      );
    }

    try {
      await Supabase.instance.client
          .from('user_live_game_subscriptions')
          .upsert(
            {
              'user_id': user.id,
              'game_id': game.gameId,
              'platform': platform,
              'enabled': enabled,
              if (enabled) 'started_at': null,
            },
            onConflict: 'user_id,game_id,platform',
          );
    } catch (_) {
      // Ignore server errors for now; Live Activity is still local.
    }

    state = AsyncData(enabled);
  }

  String _activityId(String gameId, String userId) => 'live:$gameId:$userId';

  Map<String, dynamic> _buildLiveContent(GamesTourModel game) {
    return {
      'game_id': game.gameId,
      'player_white': game.whitePlayer.name,
      'player_black': game.blackPlayer.name,
      'fen': game.fen,
      'last_move': game.lastMove,
      'status': game.gameStatus.name,
      'round_name': game.roundSlug,
      'event_name': game.tourSlug,
    };
  }

  String? _platformLabel() {
    if (kIsWeb) return null;
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      default:
        return null;
    }
  }
}
