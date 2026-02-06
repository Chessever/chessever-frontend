import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/notification_preferences_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/services/live_updates_service.dart';
import 'package:chessever2/services/push_notifications_service.dart';
import 'package:chessever2/services/fide_photo_service.dart';
import 'package:chessever2/utils/string_utils.dart';
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
      // Respect global live game updates preference
      final prefs = ref.read(notificationPreferencesProvider).valueOrNull;
      if (prefs != null && !prefs.liveGameUpdates) {
        state = const AsyncData(false);
        return;
      }

      final granted =
          await PushNotificationsService.instance.requestPermissionWithDialog();
      if (!granted) {
        state = const AsyncData(false);
        return;
      }

      final whitePhoto = await FidePhotoService.getPhotoUrlOrNull(
        game.whitePlayer.fideId?.toString(),
      );
      final blackPhoto = await FidePhotoService.getPhotoUrlOrNull(
        game.blackPlayer.fideId?.toString(),
      );

      await LiveUpdatesService.instance.startLiveActivity(
        activityId: _activityId(game.gameId, user.id),
        attributes: {'game_id': game.gameId},
        content: _buildLiveContent(game, whitePhoto, blackPhoto),
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

  Map<String, dynamic> _buildLiveContent(
    GamesTourModel game,
    String? whitePhoto,
    String? blackPhoto,
  ) {
    final boardSettings = ref.read(boardSettingsProviderNew).valueOrNull;
    final boardThemeIndex = boardSettings?.boardThemeIndex ?? 0;
    final pieceStyleIndex = boardSettings?.pieceStyleIndex ?? 0;

    return {
      'game_id': game.gameId,
      'player_white': game.whitePlayer.name,
      'player_black': game.blackPlayer.name,
      'board_theme_index': boardThemeIndex,
      'piece_style_index': pieceStyleIndex,
      if (game.whitePlayer.title.isNotEmpty)
        'white_title': game.whitePlayer.title,
      if (game.blackPlayer.title.isNotEmpty)
        'black_title': game.blackPlayer.title,
      if (game.whitePlayer.federation.isNotEmpty)
        'white_fed': game.whitePlayer.federation,
      if (game.blackPlayer.federation.isNotEmpty)
        'black_fed': game.blackPlayer.federation,
      if (whitePhoto != null) 'white_photo': whitePhoto,
      if (blackPhoto != null) 'black_photo': blackPhoto,
      'fen': game.fen,
      'last_move': game.lastMove,
      'status': game.gameStatus.name,
      if (game.roundSlug != null && game.roundSlug!.isNotEmpty)
        'round_name': StringUtils.formatRoundLabel(game.roundSlug),
      if (game.tourSlug != null && game.tourSlug!.isNotEmpty)
        'event_name': StringUtils.slugToTitle(game.tourSlug!),
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
