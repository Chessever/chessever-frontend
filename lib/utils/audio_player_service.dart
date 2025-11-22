import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

class AudioPlayerService with WidgetsBindingObserver {
  static final AudioPlayerService _instance = AudioPlayerService._internal();

  late final AudioSource pieceMoveSfx;
  late final AudioSource pieceCastlingSfx;
  late final AudioSource pieceCheckSfx;
  late final AudioSource pieceCheckmateSfx;
  late final AudioSource pieceDrawSfx;
  late final AudioSource piecePromotionSfx;
  late final AudioSource pieceTakeoverSfx;

  factory AudioPlayerService() => _instance;
  AudioPlayerService._internal() {
    WidgetsBinding.instance.addObserver(this);
  }
  static AudioPlayerService get instance => _instance;

  SoLoud get player => SoLoud.instance;

  bool _initialized = false;
  bool _assetsLoaded = false;
  Future<void>? _initializing;

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
      player.play(source);
    } catch (e, s) {
      debugPrint('⚠️ Audio playback failed, recovering SoLoud: $e\n$s');
      _teardownPlayer();
      try {
        await initializeAndLoadAllAssets(force: true);
        player.play(source);
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
    try {
      if (player.isInitialized) {
        player.deinit();
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
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _teardownPlayer();
    } else if (state == AppLifecycleState.resumed) {
      // Refresh assets and the engine after returning to foreground.
      unawaited(initializeAndLoadAllAssets(force: !_initialized));
    }
  }
}
