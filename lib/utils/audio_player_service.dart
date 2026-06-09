import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:chessever2/services/pip_service.dart';

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
  bool _hasInitializedOnce = false;
  bool _androidAudioUnavailable = false;

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
    if (Platform.isAndroid && _androidAudioUnavailable) {
      return Future.value();
    }

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
  ///
  /// Fire-and-forget: each call plays independently. SoLoud mixes voices
  /// natively, so SFX must NOT be serialized through a shared queue — doing so
  /// couples every sound to the slowest/previous native op and lets a single
  /// stalled init/recovery silence all subsequent moves.
  void playSound(SfxType type) {
    // While in PiP the move SFX is played natively (iOS/Android) from the poll,
    // so suppress the Flutter path to avoid double sounds. On iOS the Dart
    // isolate is suspended in PiP anyway, making this a no-op there.
    if (PipService.instance.isInPip) return;
    if (Platform.isAndroid && _androidAudioUnavailable) return;
    unawaited(_playWithRecovery(type));
  }

  /// Convenience: determine sound from SAN notation and play it.
  void playSfxForSan(String san) => playSound(sfxTypeForSan(san));

  Future<void> _playWithRecovery(SfxType type) async {
    try {
      await initializeAndLoadAllAssets();
      // The engine can die during the await gap above (Android backgrounding,
      // iOS route change). Calling play() then throws SoLoudNotInitializedException
      // — the 1169-user "MA" crash, surfaced to Sentry via SoLoud's logger.
      // Re-check and funnel into recovery instead of letting play() throw.
      if (!player.isInitialized) {
        throw StateError('SoLoud not initialized after init; forcing recovery');
      }
      // soloud 4.x: play() is sync — no await.
      player.play(_resolve(type));
    } catch (e, s) {
      debugPrint('⚠️ Audio playback failed, recovering SoLoud: $e\n$s');
      if (Platform.isAndroid) {
        _markAndroidAudioUnavailable(
          'playback failed; skipping forced SoLoud restart',
        );
        return;
      }
      _teardownPlayer();
      try {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await initializeAndLoadAllAssets(force: true);
        // Only play if recovery actually brought the engine back, so a failed
        // recovery can't throw a second SoLoudNotInitializedException.
        if (player.isInitialized) {
          // _resolve reads the freshly-loaded field — no stale handles.
          player.play(_resolve(type));
        }
      } catch (err, st) {
        debugPrint('⚠️ Audio playback failed after recovery: $err\n$st');
      }
    }
  }

  Future<void> _initializeInternal({required bool force}) async {
    if (Platform.isAndroid && _androidAudioUnavailable) {
      return;
    }

    // On Android, flutter_soloud's init() tears down native SoLoud when the
    // native engine is still initialized but Dart-side callbacks are not. That
    // path reaches disposeAllSound()/ma_device_stop__opensl and has shown up as
    // a delayed production crash. Keep Android SoLoud single-init per process.
    if (Platform.isAndroid && force) {
      debugPrint(
        '🎧 AudioPlayerService: ignoring forced Android SoLoud restart',
      );
      force = false;
    }

    if (Platform.isAndroid && _hasInitializedOnce && !player.isInitialized) {
      _markAndroidAudioUnavailable(
        'SoLoud lost Dart initialized state after previous Android init',
      );
      return;
    }

    if (force) {
      // A forced init means the previous Dart AudioSource handles may no longer
      // match the native audio device/session even when SoLoud still reports
      // initialized after backgrounding. Always clear the flags so assets are
      // reloaded with fresh native handles — no stale-handle reuse.
      if (player.isInitialized) {
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
      if (Platform.isAndroid) {
        await SoLoud.instance.init(
          sampleRate: 48000,
          bufferSize: 4096,
          channels: Channels.stereo,
        );
      } else {
        await SoLoud.instance.init();
      }
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
    _hasInitializedOnce = true;
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

  void _markAndroidAudioUnavailable(String reason) {
    if (_androidAudioUnavailable) return;
    _androidAudioUnavailable = true;
    _initialized = false;
    _assetsLoaded = false;
    debugPrint(
      '⚠️ AudioPlayerService: Android audio disabled until next app start: $reason',
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('🎧 AudioPlayerService: lifecycle changed to $state');
    if (state == AppLifecycleState.resumed) {
      if (Platform.isAndroid && _androidAudioUnavailable) {
        return;
      }

      // Otherwise only reinitialize if the native engine is actually gone.
      // Avoids unnecessary teardown→reinit cycles (esp. iOS) that create
      // windows of broken audio.
      if (!player.isInitialized) {
        if (Platform.isAndroid && _hasInitializedOnce) {
          _markAndroidAudioUnavailable(
            'SoLoud not initialized on Android resume after previous init',
          );
          return;
        }

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
