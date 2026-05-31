import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
      default:
        break;
    }
  }
}
