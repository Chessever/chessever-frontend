import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

class AudioPlayerService with WidgetsBindingObserver {
  static final AudioPlayerService _instance = AudioPlayerService._internal();

  // Note: These MUST NOT be `final` - they need to be reassignable
  // after the native SoLoud engine is torn down and reinitialized
  // (e.g., when app returns from background)
  late AudioSource pieceMoveSfx;
  late AudioSource pieceCastlingSfx;
  late AudioSource pieceCheckSfx;
  late AudioSource pieceCheckmateSfx;
  late AudioSource pieceDrawSfx;
  late AudioSource piecePromotionSfx;
  late AudioSource pieceTakeoverSfx;

  factory AudioPlayerService() => _instance;
  AudioPlayerService._internal() {
    WidgetsBinding.instance.addObserver(this);
  }
  static AudioPlayerService get instance => _instance;

  SoLoud get player => SoLoud.instance;

  bool _initialized = false;
  bool _assetsLoaded = false;
  Future<void>? _initializing;
  bool _audioSessionConfigured = false;

  /// Configure iOS audio session to use ambient mode (doesn't interrupt other audio)
  Future<void> _configureAudioSession() async {
    if (_audioSessionConfigured) return;

    if (Platform.isIOS) {
      try {
        // Configure iOS AVAudioSession to ambient mode which:
        // - Doesn't interrupt other audio (music, podcasts, etc.)
        // - Mixes with other audio
        // - Respects the silent switch
        const channel = MethodChannel('com.chessever/audio_session');
        await channel.invokeMethod('configureAmbientSession');
        debugPrint('🎧 AudioPlayerService: iOS audio session configured for ambient mode');
      } catch (e) {
        // If the channel doesn't exist yet, we'll configure via native code
        debugPrint('🎧 AudioPlayerService: iOS audio session configuration via MethodChannel not available, using native defaults');
      }
    }

    _audioSessionConfigured = true;
  }

  Future<void> initializeAndLoadAllAssets({bool force = false}) {
    // Always reuse the in-flight initialization to avoid racing init/deinit.
    if (_initializing != null) return _initializing!;

    // If we are already initialized and the native engine is alive, skip work.
    if (_initialized && !force && player.isInitialized) {
      return Future.value();
    }

    _initializing = _initializeInternal(force: force).whenComplete(() {
      _initializing = null;
    });

    return _initializing!;
  }

  /// Play a sound while self-healing the engine if it was torn down by the OS.
  void playSound(AudioSource source) {
    unawaited(_playWithRecovery(source));
  }

  Future<void> _playWithRecovery(AudioSource source) async {
    try {
      await initializeAndLoadAllAssets();
      // Await to surface initialization issues immediately and trigger recovery.
      await player.play(source);
    } catch (e, s) {
      debugPrint('⚠️ Audio playback failed, recovering SoLoud: $e\n$s');
      _teardownPlayer();
      try {
        await initializeAndLoadAllAssets(force: true);
        await player.play(source);
      } catch (err, st) {
        debugPrint('⚠️ Audio playback failed after recovery: $err\n$st');
      }
    }
  }

  Future<void> _initializeInternal({required bool force}) async {
    if (force && player.isInitialized) {
      _teardownPlayer();
    }

    // If the native engine was killed while the Dart flag stayed true, reset.
    if (_initialized && !player.isInitialized) {
      _initialized = false;
      _assetsLoaded = false;
    }

    // Configure audio session BEFORE initializing SoLoud
    // This ensures our app doesn't steal audio focus from other apps
    await _configureAudioSession();

    if (!player.isInitialized) {
      await SoLoud.instance.init();
    }

    if (!_assetsLoaded) {
      final List<String> paths = [
        "assets/sfx/piece_move.wav",
        "assets/sfx/piece_castling.wav",
        "assets/sfx/piece_check.wav",
        "assets/sfx/piece_checkmate.wav",
        "assets/sfx/piece_draw.wav",
        "assets/sfx/piece_promotion.wav",
        "assets/sfx/piece_takeover.wav",
      ];

      final results = <AudioSource>[];

      for (final path in paths) {
        final source = await _loadWithFrameDelay(path);
        results.add(source);
      }

      // Assign in declared order
      pieceMoveSfx = results[0];
      pieceCastlingSfx = results[1];
      pieceCheckSfx = results[2];
      pieceCheckmateSfx = results[3];
      pieceDrawSfx = results[4];
      piecePromotionSfx = results[5];
      pieceTakeoverSfx = results[6];

      _assetsLoaded = true;
    }

    _initialized = true;
    debugPrint('🎧 AudioPlayerService initialized successfully');
  }

  Future<AudioSource> _loadWithFrameDelay(String path) async {
    final completer = Completer<AudioSource>();

    // Schedule the actual work in a microtask to avoid jank during frame build.
    scheduleMicrotask(() async {
      try {
        final source = await SoLoud.instance.loadAsset(path);
        completer.complete(source);
      } catch (e) {
        completer.completeError(e);
      }
    });

    // Small delay between each to yield UI (approx one frame at 60fps)
    await Future.delayed(const Duration(milliseconds: 200));

    return completer.future;
  }

  /// Dispose the native engine to avoid stale handles when the app goes
  /// background or is torn down by the OS.
  void _teardownPlayer() {
    debugPrint('🎧 AudioPlayerService: tearing down player (wasInitialized: $_initialized, assetsLoaded: $_assetsLoaded)');
    try {
      if (player.isInitialized) {
        player.deinit();
        debugPrint('🎧 AudioPlayerService: SoLoud deinit completed');
      }
    } catch (e, s) {
      debugPrint('⚠️ Audio teardown failed: $e\n$s');
    } finally {
      _initialized = false;
      _assetsLoaded = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('🎧 AudioPlayerService: lifecycle changed to $state');
    if (state == AppLifecycleState.resumed) {
      // Always refresh after coming back to foreground; some platforms tear
      // down the native engine while keeping the Dart flag alive.
      debugPrint('🎧 AudioPlayerService: resuming, will reinitialize (force: true)');
      unawaited(initializeAndLoadAllAssets(force: true));
      return;
    }

    // Treat every non-resumed state as background to avoid stale native handles.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _teardownPlayer();
      return;
    }

    // Fallback for any future lifecycle states.
    _teardownPlayer();
  }
}
