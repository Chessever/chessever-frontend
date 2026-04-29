import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

/// Sound effect types — used instead of raw AudioSource to avoid stale native
/// handles after the SoLoud engine is torn down and reinitialized.
enum SfxType { move, castling, check, checkmate, draw, promotion, takeover }

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
        debugPrint(
          '🎧 AudioPlayerService: iOS audio session configured for ambient mode',
        );
      } catch (e) {
        // If the channel doesn't exist yet, we'll configure via native code
        debugPrint(
          '🎧 AudioPlayerService: iOS audio session configuration via MethodChannel not available, using native defaults',
        );
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

  /// Resolve the fresh AudioSource for a given [SfxType].
  /// Must only be called AFTER [initializeAndLoadAllAssets] has completed.
  AudioSource _resolve(SfxType type) {
    switch (type) {
      case SfxType.move:
        return pieceMoveSfx;
      case SfxType.castling:
        return pieceCastlingSfx;
      case SfxType.check:
        return pieceCheckSfx;
      case SfxType.checkmate:
        return pieceCheckmateSfx;
      case SfxType.draw:
        return pieceDrawSfx;
      case SfxType.promotion:
        return piecePromotionSfx;
      case SfxType.takeover:
        return pieceTakeoverSfx;
    }
  }

  /// Determine the [SfxType] from a SAN move string.
  static SfxType sfxTypeForSan(String san) {
    if (san.contains('#')) return SfxType.checkmate;
    if (san.contains('+')) return SfxType.check;
    if (san == 'O-O' || san == 'O-O-O') return SfxType.castling;
    if (san.contains('=')) return SfxType.promotion;
    if (san.contains('x')) return SfxType.takeover;
    return SfxType.move;
  }

  /// Play a sound effect by type. Resolves the native handle AFTER ensuring
  /// the engine is initialized, preventing stale-handle issues.
  void playSound(SfxType type) {
    unawaited(_playWithRecovery(type));
  }

  /// Convenience: determine sound from SAN notation and play it.
  void playSfxForSan(String san) => playSound(sfxTypeForSan(san));

  Future<void> _playWithRecovery(SfxType type) async {
    try {
      await initializeAndLoadAllAssets();
      // soloud 4.x: play() is sync — no await.
      player.play(_resolve(type));
    } catch (e, s) {
      debugPrint('⚠️ Audio playback failed, recovering SoLoud: $e\n$s');
      _teardownPlayer();
      try {
        await initializeAndLoadAllAssets(force: true);
        // _resolve reads the freshly-loaded field — no stale handles.
        player.play(_resolve(type));
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

    // Configure audio session BEFORE and AFTER initializing SoLoud
    // This ensures our app doesn't steal audio focus from other apps
    // and correctly applies ambient mode even if SoLoud resets it during init.
    await _configureAudioSession();

    if (!player.isInitialized) {
      await SoLoud.instance.init();
      // Re-apply after init just in case SoLoud native layer reset the category
      _audioSessionConfigured = false;
      await _configureAudioSession();
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
  // SoLoud.instance is per-isolate state, so deinit MUST run on the main
  // isolate. A previous version off-loaded this to Isolate.run, which both
  // failed to sendport-encode the closure (it captured `this`, which holds a
  // non-sendable Future) and would have deinit'd an empty fresh SoLoud
  // instance in the child isolate anyway.
  void _teardownPlayer() {
    debugPrint(
      '🎧 AudioPlayerService: tearing down player (wasInitialized: $_initialized, assetsLoaded: $_assetsLoaded)',
    );
    try {
      if (player.isInitialized) {
        player.deinit();
        debugPrint('🎧 AudioPlayerService: SoLoud deinit complete');
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
      // Only reinitialize if the native engine is gone. Avoids unnecessary
      // teardown→reinit cycles that create windows of broken audio.
      if (!player.isInitialized) {
        debugPrint(
          '🎧 AudioPlayerService: engine dead after resume, reinitializing',
        );
        unawaited(initializeAndLoadAllAssets(force: true));
      } else {
        debugPrint(
          '🎧 AudioPlayerService: engine still alive after resume, no action',
        );
      }
      return;
    }

    // Only tear down when truly backgrounded (paused) or detached.
    // `inactive` is a transient state (notification shade, dialogs, split-screen)
    // and tearing down there causes sound to disappear on Android.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // IMPORTANT: Skip native teardown in debug mode to prevent hot-restarts
      // from triggering native FFI teardowns that crash the VM (Service disappeared).
      if (!kDebugMode) {
        _teardownPlayer();
      }
      return;
    }

    // inactive / hidden: do nothing — keep the engine alive.
  }
}
