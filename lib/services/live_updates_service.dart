import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LiveUpdatesService {
  LiveUpdatesService._();

  static final LiveUpdatesService instance = LiveUpdatesService._();
  static const MethodChannel _liveActivitiesChannel = MethodChannel(
    'com.chessever/live_activities',
  );

  bool _setupDone = false;
  String? _activeGameId;

  /// Returns the currently active Live Activity game ID, if any.
  String? get activeGameId => _activeGameId;

  /// Returns true if a Live Activity is currently active.
  bool get isActive => _activeGameId != null;

  Future<void> setup() async {
    if (_setupDone) return;
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.iOS) return;

    try {
      OneSignal.LiveActivities.setupDefault();
      _setupDone = true;
    } catch (_) {
      // Live Activities not available on this device/OS.
    }
  }

  Future<void> startLiveActivity({
    required String activityId,
    required Map<String, dynamic> attributes,
    required Map<String, dynamic> content,
  }) async {
    /*
    await setup();
    if (kIsWeb) return;

    final gameId = attributes['game_id'] as String?;
    if (gameId == null || gameId.isEmpty) return;
    var started = false;

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        debugPrint('[LiveUpdates] Starting iOS Live Activity: $activityId');
        final response = await _liveActivitiesChannel
            .invokeMethod<Map<Object?, Object?>>('startDefaultVerified', {
              'activityId': activityId,
              'attributes': attributes,
              'content': content,
            });

        final startedOnDevice = response?['ok'] == true;
        if (startedOnDevice) {
          _activeGameId = gameId;
          started = true;
          debugPrint(
            '[LiveUpdates] iOS Live Activity persisted for game: $gameId',
          );
          debugPrint('[LiveUpdates] Native state: ${response?['activity']}');
        } else {
          debugPrint(
            '[LiveUpdates] iOS Live Activity did not persist for game: $gameId',
          );
          debugPrint('[LiveUpdates] Native debug state: $response');
        }
      } catch (e, st) {
        debugPrint('[LiveUpdates] iOS Live Activity failed: $e');
        debugPrintStack(stackTrace: st);
      }
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      // Android: We register the subscription in Supabase
      // The edge function will send live notifications via collapse_id
      _activeGameId = gameId;
      started = true;
      debugPrint(
        '[LiveUpdates] Android live subscription registered for game: $gameId',
      );
    }

    // Register subscription in Supabase for server-side dispatch
    if (started) {
      await _registerSubscription(gameId, enabled: true);
    }
    */
  }

  Future<void> endLiveActivity(String activityId) async {
    /*
    if (kIsWeb) return;

    final gameId = _activeGameId;

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        debugPrint('[LiveUpdates] Ending iOS Live Activity: $activityId');
        await OneSignal.LiveActivities.exitLiveActivity(activityId);
        debugPrint('[LiveUpdates] iOS Live Activity ended');
      } catch (e) {
        debugPrint('[LiveUpdates] iOS Live Activity end failed: $e');
      }
    }

    _activeGameId = null;
    await _registerSubscription(gameId, enabled: false);
    */
  }

  /// Convenience method to start live updates for a game when app goes to background.
  Future<void> startForGame({
    required String gameId,
    required String userId,
    required String playerWhite,
    required String playerBlack,
    String? whiteTitle,
    String? blackTitle,
    String? whiteFed,
    String? blackFed,
    String? whitePhoto,
    String? blackPhoto,
    String? fen,
    String? lastMove,
    DateTime? lastMoveTime,
    int? whiteClockSeconds,
    int? blackClockSeconds,
    String? eventName,
    String? roundName,
    int? whiteFideId,
    int? blackFideId,
    int? boardThemeIndex,
    int? pieceStyleIndex,
  }) async {
    try {
      final activityId = 'live:$gameId:$userId';
      debugPrint(
        '[LiveUpdates] Preparing to start live activity for game: $gameId (activityId: $activityId)',
      );

      final attributes = {
        'game_id': gameId,
        'player_white': playerWhite,
        'player_black': playerBlack,
        if (boardThemeIndex != null) 'board_theme_index': boardThemeIndex,
        if (pieceStyleIndex != null) 'piece_style_index': pieceStyleIndex,
        if (whiteTitle != null) 'white_title': whiteTitle,
        if (blackTitle != null) 'black_title': blackTitle,
        if (whiteFed != null) 'white_fed': whiteFed,
        if (blackFed != null) 'black_fed': blackFed,
        if (whitePhoto != null) 'white_photo': whitePhoto,
        if (blackPhoto != null) 'black_photo': blackPhoto,
        if (eventName != null) 'event_name': eventName,
        if (roundName != null) 'round_name': roundName,
        if (whiteFideId != null) 'white_fide_id': whiteFideId,
        if (blackFideId != null) 'black_fide_id': blackFideId,
      };
      final content = <String, dynamic>{
        'game_id': gameId,
        'player_white': playerWhite,
        'player_black': playerBlack,
        if (boardThemeIndex != null) 'board_theme_index': boardThemeIndex,
        if (pieceStyleIndex != null) 'piece_style_index': pieceStyleIndex,
        if (whiteTitle != null) 'white_title': whiteTitle,
        if (blackTitle != null) 'black_title': blackTitle,
        if (whiteFed != null) 'white_fed': whiteFed,
        if (blackFed != null) 'black_fed': blackFed,
        if (whitePhoto != null) 'white_photo': whitePhoto,
        if (blackPhoto != null) 'black_photo': blackPhoto,
        'fen': fen ?? '',
        'last_move': lastMove ?? '',
        'last_move_uci': lastMove ?? '',
        if (lastMoveTime != null)
          'last_move_time': lastMoveTime.toUtc().toIso8601String(),
        if (whiteClockSeconds != null) 'white_clock_seconds': whiteClockSeconds,
        if (blackClockSeconds != null) 'black_clock_seconds': blackClockSeconds,
        if (eventName != null) 'event_name': eventName,
        if (roundName != null) 'round_name': roundName,
        if (whiteFideId != null) 'white_fide_id': whiteFideId,
        if (blackFideId != null) 'black_fide_id': blackFideId,
      };

      await startLiveActivity(
        activityId: activityId,
        attributes: attributes,
        content: content,
      );
    } catch (e, st) {
      debugPrint('[LiveUpdates] Error in startForGame: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  /// Stop live updates for the current game.
  Future<void> stopForGame(String gameId, String userId) async {
    final activityId = 'live:$gameId:$userId';
    await endLiveActivity(activityId);
  }

  Future<void> _registerSubscription(
    String? gameId, {
    required bool enabled,
  }) async {
    if (gameId == null) return;

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final platform = _platformLabel();
      if (platform == null) return;

      await Supabase.instance.client
          .from('user_live_game_subscriptions')
          .upsert({
            'user_id': userId,
            'game_id': gameId,
            'platform': platform,
            'enabled': enabled,
            if (enabled) 'started_at': null,
          }, onConflict: 'user_id,game_id,platform');
    } catch (e) {
      debugPrint('[LiveUpdates] Failed to register subscription: $e');
    }
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
