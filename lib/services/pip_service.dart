import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:chessever2/utils/audio_player_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef PipModeChanged = void Function(bool isInPip);

class PipService {
  PipService._() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  static final PipService instance = PipService._();
  static const MethodChannel _channel = MethodChannel('com.chessever/pip');

  final Set<PipModeChanged> _listeners = <PipModeChanged>{};
  bool _isInPip = false;
  String? _lastSoundedMove;
  String? _lastFen;

  bool get isInPip => _isInPip;

  static const Map<String, String> _releaseEnvValues = {
    'SUPABASE_URL': String.fromEnvironment('SUPABASE_URL', defaultValue: ''),
    'SUPABASE_ANON_KEY': String.fromEnvironment(
      'SUPABASE_ANON_KEY',
      defaultValue: '',
    ),
  };

  void addListener(PipModeChanged listener) {
    _listeners.add(listener);
  }

  void removeListener(PipModeChanged listener) {
    _listeners.remove(listener);
  }

  Future<void> setActiveGame(Map<String, dynamic> payload) async {
    if (kIsWeb) return;
    if (!_isInPip) _primeSfxBaseline(payload);
    try {
      await _channel.invokeMethod<void>(
        'setActiveGame',
        _withNativeLiveConfig(payload),
      );
    } catch (e) {
      debugPrint('[PiP] setActiveGame failed: $e');
    }
  }

  Future<void> updatePosition(Map<String, dynamic> payload) async {
    if (kIsWeb) return;
    if (_isInPip) {
      _playSfxForPipPayload(payload);
    } else {
      _primeSfxBaseline(payload);
    }
    try {
      await _channel.invokeMethod<void>(
        'updatePosition',
        _withNativeLiveConfig(payload),
      );
    } catch (e) {
      debugPrint('[PiP] updatePosition failed: $e');
    }
  }

  Map<String, dynamic> _withNativeLiveConfig(Map<String, dynamic> payload) {
    final supabaseUrl = _env('SUPABASE_URL');
    final supabaseAnonKey = _env('SUPABASE_ANON_KEY');
    final accessToken =
        Supabase.instance.client.auth.currentSession?.accessToken;

    return <String, dynamic>{
      ...payload,
      if (supabaseUrl != null) 'supabaseUrl': supabaseUrl,
      if (supabaseAnonKey != null) 'supabaseAnonKey': supabaseAnonKey,
      if (accessToken != null && accessToken.isNotEmpty)
        'supabaseAccessToken': accessToken,
    };
  }

  String? _env(String key) {
    final releaseValue = _releaseEnvValues[key]?.trim();
    if (releaseValue != null && releaseValue.isNotEmpty) return releaseValue;
    final debugValue = dotenv.env[key]?.trim();
    if (debugValue != null && debugValue.isNotEmpty) return debugValue;
    return null;
  }

  Future<bool> enterIfEligible() async {
    if (kIsWeb) return false;
    try {
      final result = await _channel.invokeMethod<bool>('enterIfEligible');
      return result ?? false;
    } catch (e) {
      debugPrint('[PiP] enterIfEligible failed: $e');
      return false;
    }
  }

  Future<void> clearActiveGame() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('clearActiveGame');
    } catch (e) {
      debugPrint('[PiP] clearActiveGame failed: $e');
    }
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onPipModeChanged':
        final args = call.arguments;
        final isInPip =
            args is Map ? args['isInPip'] == true : call.arguments == true;
        _isInPip = isInPip;
        for (final listener in List<PipModeChanged>.of(_listeners)) {
          listener(isInPip);
        }
        break;
      case 'playSfx':
        _playSfxFromNative(call.arguments);
        break;
      default:
        break;
    }
  }

  void _playSfxFromNative(Object? arguments) {
    if (arguments is! Map) return;
    final san = arguments['san'];
    if (san is String && san.isNotEmpty) {
      AudioPlayerService.instance.playSfxForSan(san);
      return;
    }

    final type = switch (arguments['type']) {
      'castling' => SfxType.castling,
      'check' => SfxType.check,
      'checkmate' => SfxType.checkmate,
      'draw' => SfxType.draw,
      'promotion' => SfxType.promotion,
      'takeover' => SfxType.takeover,
      _ => SfxType.move,
    };
    AudioPlayerService.instance.playSound(type);
  }

  void _primeSfxBaseline(Map<String, dynamic> payload) {
    final move = _payloadMove(payload);
    if (move != null) _lastSoundedMove = move;
    final fen = payload['fen'];
    if (fen is String && fen.isNotEmpty) _lastFen = fen;
  }

  void _playSfxForPipPayload(Map<String, dynamic> payload) {
    final move = _payloadMove(payload);
    final fen = payload['fen'];
    if (payload['soundEnabled'] != true) {
      _primeSfxBaseline(payload);
      return;
    }
    if (move == null || move == _lastSoundedMove) {
      if (fen is String && fen.isNotEmpty) _lastFen = fen;
      return;
    }

    final san = payload['lastMoveSan'];
    final previousFen = _lastFen;
    _lastSoundedMove = move;
    if (fen is String && fen.isNotEmpty) _lastFen = fen;

    if (san is String && san.isNotEmpty) {
      AudioPlayerService.instance.playSfxForSan(san);
      return;
    }

    final captured = _fenPieceCount(fen) < _fenPieceCount(previousFen);
    AudioPlayerService.instance.playSound(
      captured ? SfxType.takeover : SfxType.move,
    );
  }

  String? _payloadMove(Map<String, dynamic> payload) {
    final move = payload['lastMoveUci'] ?? payload['lastMove'];
    return move is String && move.isNotEmpty ? move : null;
  }

  int _fenPieceCount(Object? fen) {
    if (fen is! String || fen.isEmpty) return 0;
    return fen.split(' ').first.split('').where(_isFenPiece).length;
  }

  bool _isFenPiece(String char) {
    return 'pnbrqkPNBRQK'.contains(char);
  }
}
