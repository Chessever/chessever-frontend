import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

/// Sound effect types used by the SoLoud audio path.
enum SfxType { move, castling, check, checkmate, draw, promotion, takeover }

class AudioPlayerService with WidgetsBindingObserver {
  static final AudioPlayerService _instance = AudioPlayerService._internal();
  static const Duration _minimumAnyPlaySpacing = Duration(milliseconds: 60);
  static const Duration _minimumSameSoundSpacing = Duration(milliseconds: 120);

  // Note: These MUST NOT be `final` - recovery reloads them after
  // the native SoLoud engine is torn down and reinitialized.
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
  Future<void>? _androidRecovering;
  final Stopwatch _playSpacingClock = Stopwatch()..start();
  int? _lastPlayAtMicros;
  SfxType? _lastPlayedType;
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

  /// Play a sound effect by type through flutter_soloud.
  void playSound(SfxType type) {
    if (_shouldSkipForSpacing(type)) return;
    unawaited(_playWithRecovery(type));
  }

  Future<void> prepareForForegroundPlayback() async {
    try {
      if (Platform.isAndroid) {
        await _recoverAndroidSfxAssets();
        return;
      }

      await initializeAndLoadAllAssets();
    } catch (err, st) {
      debugPrint('⚠️ Audio foreground preparation failed: $err\n$st');
    }
  }

  /// Convenience: determine sound from SAN notation and play it.
  void playSfxForSan(String san) => playSound(sfxTypeForSan(san));

  bool _shouldSkipForSpacing(SfxType type) {
    final nowMicros = _playSpacingClock.elapsedMicroseconds;
    final lastPlayAtMicros = _lastPlayAtMicros;
    if (lastPlayAtMicros != null) {
      final elapsed = Duration(microseconds: nowMicros - lastPlayAtMicros);
      if (elapsed < _minimumAnyPlaySpacing ||
          (_lastPlayedType == type && elapsed < _minimumSameSoundSpacing)) {
        return true;
      }
    }

    _lastPlayedType = type;
    _lastPlayAtMicros = nowMicros;
    return false;
  }

  Future<void> _playWithRecovery(SfxType type) async {
    try {
      await _waitForAndroidRecoveryIfNeeded();
      await initializeAndLoadAllAssets();
      await _waitForAndroidRecoveryIfNeeded();
      // The engine can die during the await gap above (for example iOS route
      // changes). Re-check and funnel into recovery instead of letting play()
      // throw SoLoudNotInitializedException.
      if (!player.isInitialized) {
        throw StateError('SoLoud not initialized after init; forcing recovery');
      }
      _playResolved(type);
    } catch (e, s) {
      if (Platform.isAndroid) {
        // Keep Android on the package's normal init/play lifecycle. A failed
        // play can still leave Dart with stale source handles, so reload the
        // short SFX assets without app-side deinit/reinit.
        debugPrint('⚠️ Android SoLoud playback failed, reloading SFX: $e\n$s');
        await _recoverAndroidPlayback(type);
        return;
      }
      debugPrint('⚠️ Audio playback failed, recovering SoLoud: $e\n$s');
      _teardownPlayer();
      try {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await initializeAndLoadAllAssets(force: true);
        // Only play if recovery actually brought the engine back, so a failed
        // recovery can't throw a second SoLoudNotInitializedException.
        if (player.isInitialized) {
          // _resolve reads the freshly-loaded field — no stale handles.
          _playResolved(type);
        }
      } catch (err, st) {
        debugPrint('⚠️ Audio playback failed after recovery: $err\n$st');
      }
    }
  }

  Future<void> _waitForAndroidRecoveryIfNeeded() async {
    if (!Platform.isAndroid) return;
    final androidRecovery = _androidRecovering;
    if (androidRecovery != null) {
      await androidRecovery;
    }
  }

  Future<void> _recoverAndroidPlayback(SfxType type) async {
    try {
      await _recoverAndroidSfxAssets();

      if (player.isInitialized && _assetsLoaded) {
        _playResolved(type);
      }
    } catch (err, st) {
      debugPrint('⚠️ Android SoLoud recovery failed: $err\n$st');
    }
  }

  Future<void> _recoverAndroidSfxAssets() {
    return _androidRecovering ??= _reloadAndroidSfxAssets().whenComplete(() {
      _androidRecovering = null;
    });
  }

  Future<void> _reloadAndroidSfxAssets() async {
    final inFlightInitialization = _initializing;
    if (inFlightInitialization != null) {
      try {
        await inFlightInitialization;
      } catch (_) {
        // The recovery below still needs to clear and reload any partial state.
      }
    }

    _initialized = false;
    _assetsLoaded = false;
    await _disposeLoadedSourcesForRecovery();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await initializeAndLoadAllAssets();
  }

  Future<void> _disposeLoadedSourcesForRecovery() async {
    if (!player.isInitialized) return;

    try {
      await player.disposeAllSources();
    } catch (err, st) {
      debugPrint('⚠️ Android SoLoud source disposal failed: $err\n$st');
    }
  }

  void _playResolved(SfxType type) {
    final handle = player.play(_resolve(type));
    if (handle.isError || handle.id <= 0) {
      throw StateError('SoLoud returned an invalid handle for $type');
    }
    if (!player.getIsValidVoiceHandle(handle)) {
      throw StateError('SoLoud returned an inactive handle for $type');
    }
  }

  Future<void> _initializeInternal({required bool force}) async {
    if (force) {
      // A forced init means the previous Dart AudioSource handles may no longer
      // match the native audio device/session even when SoLoud still reports
      // initialized after backgrounding. Always clear the flags so assets are
      // reloaded with fresh native handles — no stale-handle reuse.
      if (Platform.isAndroid) {
        _initialized = false;
        _assetsLoaded = false;
        await _disposeLoadedSourcesForRecovery();
      } else if (player.isInitialized) {
        _teardownPlayer();
      } else {
        _initialized = false;
        _assetsLoaded = false;
      }
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

      // Load all SFX into memory in PARALLEL. The previous version loaded them
      // serially with a 200ms delay between each (~1.4s of dead time), which
      // delayed sound and — on a forced reinit after backgrounding — piled work
      // onto the foregrounding burst that was already contended. loadAsset with
      // LoadMode.memory is cheap for these short WAVs and is safe to run
      // concurrently; the awaits still yield the UI between native calls.
      final results = await Future.wait(
        paths.map(
          (path) => SoLoud.instance.loadAsset(path, mode: LoadMode.memory),
        ),
      );

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

  /// Tear down the native engine only during explicit recovery.
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
      // Otherwise only reinitialize if the native engine is actually gone.
      // Avoids unnecessary teardown→reinit cycles (esp. iOS) that create
      // windows of broken audio.
      if (!player.isInitialized) {
        debugPrint(
          '🎧 AudioPlayerService: engine dead after resume, reinitializing',
        );
        unawaited(initializeAndLoadAllAssets());
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
      // Do not deinit during normal lifecycle transitions. SoLoud's native
      // audio callback can still be mixing a short SFX while Dart receives
      // paused/detached, and tearing down then can corrupt the active voice.
      return;
    }

    // inactive / hidden: do nothing — keep the engine alive.
  }
}
