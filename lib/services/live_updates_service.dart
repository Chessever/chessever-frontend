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

  /// Game IDs with an active Live Activity, OLDEST first. Capped at
  /// [_maxActive]; starting one beyond the cap evicts the oldest (FIFO).
  final List<String> _activeGameIds = <String>[];

  /// Max concurrent Live Activities. Hard cap of 1 — only ever ONE live card at
  /// a time; starting a new one evicts (ends) the previous.
  static const int _maxActive = 1;

  /// Most-recently-started active game (kept for back-compat callers).
  String? get activeGameId =>
      _activeGameIds.isEmpty ? null : _activeGameIds.last;

  /// All active Live Activity game IDs, oldest first.
  List<String> get activeGameIds => List.unmodifiable(_activeGameIds);

  /// Returns true if any Live Activity is currently active.
  bool get isActive => _activeGameIds.isNotEmpty;

  void _trackActiveGame(String gameId) {
    _activeGameIds.remove(gameId); // dedup → move to most-recent
    _activeGameIds.add(gameId);
  }

  /// Evicts the oldest active Live Activity (ending it) until there is room for
  /// [newGameId]. No-op if [newGameId] is already tracked (it's a refresh).
  Future<void> _evictOldestIfNeeded(String newGameId) async {
    if (_activeGameIds.contains(newGameId)) return;
    while (_activeGameIds.length >= _maxActive) {
      final oldest = _activeGameIds.first;
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        // stopForGame → endLiveActivity removes it from the list + disables sub.
        await stopForGame(oldest, userId);
      } else {
        _activeGameIds.remove(oldest);
      }
    }
  }

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
    await setup();
    if (kIsWeb) return;

    final gameId = attributes['game_id'] as String?;
    if (gameId == null || gameId.isEmpty) return;

    // Cap concurrent Live Activities at [_maxActive]; evict the oldest first.
    await _evictOldestIfNeeded(gameId);

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
          _trackActiveGame(gameId);
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
      // Android: post a local live notification immediately (mirrors the iOS
      // on-device Live Activity start) so the widget shows the viewed position
      // even for a finished game. The edge function then keeps it updated via
      // push using the same per-game notification id.
      try {
        await _liveActivitiesChannel.invokeMethod('startLocalLiveActivity', {
          'content': content,
        });
      } catch (e) {
        debugPrint('[LiveUpdates] Android local live notification failed: $e');
      }
      _trackActiveGame(gameId);
      started = true;
      debugPrint(
        '[LiveUpdates] Android live notification started for game: $gameId',
      );
    }

    // Register subscription in Supabase for server-side dispatch
    if (started) {
      await _registerSubscription(gameId, enabled: true);
    }
  }

  Future<void> endLiveActivity(String activityId) async {
    if (kIsWeb) return;

    // activityId format: 'live:<gameId>:<userId>'.
    final parts = activityId.split(':');
    final gameId =
        parts.length >= 2
            ? parts[1]
            : (_activeGameIds.isEmpty ? null : _activeGameIds.last);

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        debugPrint('[LiveUpdates] Ending iOS Live Activity: $activityId');
        await OneSignal.LiveActivities.exitLiveActivity(activityId);
        debugPrint('[LiveUpdates] iOS Live Activity ended');
      } catch (e) {
        debugPrint('[LiveUpdates] iOS Live Activity end failed: $e');
      }
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        if (gameId != null) {
          await _liveActivitiesChannel.invokeMethod('endLocalLiveActivity', {
            'gameId': gameId,
          });
        }
      } catch (e) {
        debugPrint('[LiveUpdates] Android local notification end failed: $e');
      }
    }

    if (gameId != null) _activeGameIds.remove(gameId);
    await _registerSubscription(gameId, enabled: false);
  }

  Future<Map<Object?, Object?>?> getLiveActivityDebugState() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return null;
    try {
      return await _liveActivitiesChannel.invokeMethod<Map<Object?, Object?>>(
        'getLiveActivityDebugState',
      );
    } catch (e) {
      debugPrint('[LiveUpdates] Failed to read Live Activity debug state: $e');
      return null;
    }
  }

  Future<void> logLiveActivityDebugState(String reason) async {
    final state = await getLiveActivityDebugState();
    if (state == null) return;
    debugPrint('[LiveUpdates] Debug state ($reason): $state');
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
    String? lastMoveUci,
    String? whiteFlag,
    String? blackFlag,
    int? evalCp,
    int? evalMate,
    String? status,
    bool isGameOver = false,
    bool followLive = true,
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
      final clockAnchorTime = lastMoveTime?.toUtc();
      final activeClockColor = _activeClockColorFromFen(fen);
      final activeClockSeconds =
          activeClockColor == 'white'
              ? whiteClockSeconds
              : activeClockColor == 'black'
              ? blackClockSeconds
              : null;
      final activeClockDeadline =
          followLive &&
                  !isGameOver &&
                  clockAnchorTime != null &&
                  activeClockSeconds != null
              ? clockAnchorTime.add(Duration(seconds: activeClockSeconds))
              : null;
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
        'last_move_uci': lastMoveUci ?? lastMove ?? '',
        if (lastMoveTime != null)
          'last_move_time': lastMoveTime.toUtc().toIso8601String(),
        if (whiteClockSeconds != null) 'white_clock_seconds': whiteClockSeconds,
        if (blackClockSeconds != null) 'black_clock_seconds': blackClockSeconds,
        if (clockAnchorTime != null)
          'clock_anchor_time': clockAnchorTime.toIso8601String(),
        if (activeClockColor != null) 'active_clock_color': activeClockColor,
        if (activeClockDeadline != null)
          'active_clock_deadline': activeClockDeadline.toIso8601String(),
        if (evalCp != null) 'eval_cp': evalCp,
        if (evalMate != null) 'eval_mate': evalMate,
        if (eventName != null) 'event_name': eventName,
        if (roundName != null) 'round_name': roundName,
        if (whiteFideId != null) 'white_fide_id': whiteFideId,
        if (blackFideId != null) 'black_fide_id': blackFideId,
        if (whiteFlag != null && whiteFlag.isNotEmpty) 'white_flag': whiteFlag,
        if (blackFlag != null && blackFlag.isNotEmpty) 'black_flag': blackFlag,
        if (status != null) 'status': status,
        'is_game_over': isGameOver ? 1 : 0,
        // Only the side-to-move clock ticks, and only while the viewer is
        // following the live tail (latest move). Frozen snapshots stay static.
        'follow_live': followLive ? 1 : 0,
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

  String? _activeClockColorFromFen(String? fen) {
    final parts = fen?.trim().split(RegExp(r'\s+'));
    if (parts == null || parts.length < 2) return null;
    if (parts[1] == 'w') return 'white';
    if (parts[1] == 'b') return 'black';
    return null;
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
