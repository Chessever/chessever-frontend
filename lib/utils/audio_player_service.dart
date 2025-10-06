import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

class AudioPlayerService {
  static final AudioPlayerService _instance = AudioPlayerService._internal();

  late final AudioSource pieceMoveSfx;
  late final AudioSource pieceCastlingSfx;
  late final AudioSource pieceCheckSfx;
  late final AudioSource pieceCheckmateSfx;
  late final AudioSource pieceDrawSfx;
  late final AudioSource piecePromotionSfx;
  late final AudioSource pieceTakeoverSfx;

  factory AudioPlayerService() => _instance;
  AudioPlayerService._internal();
  static AudioPlayerService get instance => _instance;

  SoLoud get player => SoLoud.instance;

  bool _initialized = false;

  Future<void> initializeAndLoadAllAssets() async {
    if (_initialized) return;
    _initialized = true;

    try {
      await SoLoud.instance.init();

      final List<String> _paths = [
        "assets/sfx/piece_move.wav",
        "assets/sfx/piece_castling.wav",
        "assets/sfx/piece_check.wav",
        "assets/sfx/piece_checkmate.wav",
        "assets/sfx/piece_draw.wav",
        "assets/sfx/piece_promotion.wav",
        "assets/sfx/piece_takeover.wav",
      ];

      final results = <AudioSource>[];

      for (final path in _paths) {
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

      debugPrint('🎧 AudioPlayerService initialized successfully');
    } catch (e, s) {
      debugPrint('⚠️ AudioPlayerService failed: $e\n$s');
    }
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
}
