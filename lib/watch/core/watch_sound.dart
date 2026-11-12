import 'dart:async';
import 'package:chessever_watch_bridge/chessever_watch_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The phone's board sounds (`assets/sfx/piece_*.wav`), in the order the
/// watch host knows them by.
enum WatchSound { move, castling, check, checkmate, draw, promotion, takeover }

/// The sound a move makes, by the phone's own rule
/// (`AudioPlayerService.sfxTypeForSan`): mate, check, castling, promotion,
/// capture, then an ordinary move.
WatchSound watchSoundForSan(String san) {
  if (san.contains('#')) return WatchSound.checkmate;
  if (san.contains('+')) return WatchSound.check;
  if (san == 'O-O' || san == 'O-O-O') return WatchSound.castling;
  if (san.contains('=')) return WatchSound.promotion;
  if (san.contains('x')) return WatchSound.takeover;
  return WatchSound.move;
}

/// Plays the board sounds through the watch host. The files are handed over
/// once, on first use; a fast Crown turn plays at most one sound per
/// [spacing] so stepping through a game ticks instead of smearing. The host
/// uses ambient audio, leaving routing and muting to watchOS. It never starts
/// clips in the background. Off the watch every call is a no-op.
class WatchSounds {
  WatchSounds._();
  static final shared = WatchSounds._();

  static const spacing = Duration(milliseconds: 90);

  /// Test seam: receives each sound instead of the host.
  @visibleForTesting
  static void Function(WatchSound sound)? debugPlayer;

  @visibleForTesting
  static Duration Function()? debugNow;

  Future<void>? _loading;
  bool _ready = false;
  final _clock = Stopwatch()..start();
  Duration? _last;

  /// Hands the sound files to the host. Safe to call repeatedly.
  Future<void> warmUp() => _loading ??= _load();

  Future<void> _load() async {
    if (debugPlayer != null) {
      _ready = true;
      return;
    }
    var any = false;
    for (final sound in WatchSound.values) {
      try {
        final data = await rootBundle.load(
          'assets/sfx/piece_${sound.name}.wav',
        );
        any =
            ChesseverWatchBridge.loadSound(
              sound.index,
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            ) ||
            any;
      } catch (_) {
        // A missing file leaves that sound silent; the rest still play.
      }
    }
    _ready = any;
  }

  void play(WatchSound sound) {
    if (!_ready) {
      unawaited(warmUp());
      return;
    }
    final now = debugNow?.call() ?? _clock.elapsed;
    if (_last != null && now - _last! < spacing) return;
    _last = now;
    final player = debugPlayer;
    if (player != null) {
      player(sound);
    } else {
      ChesseverWatchBridge.playSound(sound.index);
    }
  }

  /// Cuts a clip when the game is covered, the wrist lowers or the app leaves
  /// the foreground. Nothing is queued for the next time the game opens.
  void stop() {
    _last = null;
    if (_ready && debugPlayer == null) ChesseverWatchBridge.stopSounds();
  }

  /// Test seam: forgets the loaded state and the spacing.
  @visibleForTesting
  void debugReset() {
    _loading = null;
    _ready = false;
    _last = null;
  }
}
