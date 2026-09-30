import 'dart:async';

import 'package:chessever2/screens/chessboard/classification_fx/move_class.dart';
import 'package:chessever2/screens/chessboard/game_review/classification_style.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/screens/chessboard/widgets/nag_display.dart';
import 'package:chessever2/utils/audio_player_service.dart';
import 'package:flutter/widgets.dart';

export 'classification_landing.dart'
    show ClassificationLanding, kClassificationLandingDelay;

/// Sound + look of each [MoveClass], shared by every surface that raises
/// classified moves (the board screen, Feed boards, puzzles).
extension MoveClassFx on MoveClass {
  /// The class's badge colour: the gradient top stop of its badge SVG, read
  /// through the same map the board badges and notation use. `!?` has no
  /// badge; it takes the notation glyph's magenta.
  Color get fxColor => switch (this) {
    MoveClass.brilliant => classificationColor(
      GameMoveClassification.brilliant,
    ),
    MoveClass.great => classificationColor(GameMoveClassification.goodMove),
    MoveClass.best => classificationColor(GameMoveClassification.bestMove),
    MoveClass.interesting => getNagDisplay(5)!.color,
    MoveClass.inaccuracy => classificationColor(
      GameMoveClassification.inaccuracy,
    ),
    MoveClass.mistake => classificationColor(GameMoveClassification.mistake),
    MoveClass.blunder => classificationColor(GameMoveClassification.blunder),
    MoveClass.missedWin => classificationColor(
      GameMoveClassification.missedWin,
    ),
    MoveClass.book => classificationColor(GameMoveClassification.bookMove),
  };

  /// The ElevenLabs sound for this class (`assets/sfx/nag_*.mp3`).
  SfxType get sfxType => switch (this) {
    MoveClass.brilliant => SfxType.nagBrilliant,
    MoveClass.great => SfxType.nagGreat,
    MoveClass.best => SfxType.nagBest,
    MoveClass.interesting => SfxType.nagInteresting,
    MoveClass.inaccuracy => SfxType.nagInaccuracy,
    MoveClass.mistake => SfxType.nagMistake,
    MoveClass.blunder => SfxType.nagBlunder,
    MoveClass.missedWin => SfxType.nagMissedWin,
    MoveClass.book => SfxType.nagBook,
  };
}

/// Where [ClassificationSfx] sends its sounds. Production plays through
/// [AudioPlayerService]; tests swap in a recording fake via
/// [ClassificationSfx.output].
abstract interface class ClassificationSfxOutput {
  /// An ordinary board sound (move / capture / check / ...).
  void playOrdinary(SfxType type);

  /// A classification sound. It wins over ordinary sounds; [fallback] plays
  /// instead when the classification asset cannot be loaded.
  void playClassification(SfxType type, {SfxType? fallback});

  /// Loads the classification sounds ahead of their first use.
  Future<void> warmUp();
}

class _AudioServiceOutput implements ClassificationSfxOutput {
  const _AudioServiceOutput();

  @override
  void playOrdinary(SfxType type) =>
      AudioPlayerService.instance.playSound(type);

  @override
  void playClassification(SfxType type, {SfxType? fallback}) =>
      AudioPlayerService.instance.playClassification(type, fallback: fallback);

  @override
  Future<void> warmUp() => AudioPlayerService.instance.loadOnDemandAssets();
}

/// Sound for classified moves, shared by the board screen, Feed boards and
/// puzzles.
///
/// A classified move plays its class's ElevenLabs sound INSTEAD of the
/// ordinary move sound — never both. When the two are raised together (the
/// board raises every move from two independent paths), the audio service's
/// [SfxPriorityGate] makes the class sound win: the same move's ordinary
/// sound (same sound, within ~120 ms either side) is cut or skipped. Other
/// moves' sounds are never held, so stepping through a game keeps every
/// unclassified move's usual sound exactly, and a newer class sound cuts the
/// previous one so fast stepping never stacks clips.
///
/// Callers gate on the board's Sound setting exactly as the board does
/// (`boardSettingsProviderNew` → `soundEnabled == true`; loading or off means
/// silent). Every call is fire-and-forget: nothing is awaited or queued.
class ClassificationSfx {
  ClassificationSfx._();

  static ClassificationSfxOutput _output = const _AudioServiceOutput();

  /// The sound sink. Tests set a fake; `null` restores the audio service.
  @visibleForTesting
  static ClassificationSfxOutput get output => _output;

  @visibleForTesting
  static set output(ClassificationSfxOutput? value) =>
      _output = value ?? const _AudioServiceOutput();

  /// The class sound for [moveClass].
  static SfxType sfxTypeFor(MoveClass moveClass) => moveClass.sfxType;

  /// Plays the move's sound: [moveClass]'s ElevenLabs sound when the move is
  /// classified (it WINS over the ordinary move sound — the ordinary one for
  /// this move is skipped, and one already started within the last ~120ms is
  /// cut), else the board's ordinary sound for [san] (move / capture / check /
  /// checkmate / castling / promotion), exactly as before. Fire-and-forget.
  static void playMove({required String san, MoveClass? moveClass}) {
    final ordinary = AudioPlayerService.sfxTypeForSan(san);
    _safely(() {
      if (moveClass == null) {
        _output.playOrdinary(ordinary);
      } else {
        _output.playClassification(moveClass.sfxType, fallback: ordinary);
      }
    });
  }

  /// Just the class sound (e.g. puzzle feedback).
  static void playClass(MoveClass moveClass) {
    _safely(() => _output.playClassification(moveClass.sfxType));
  }

  /// Any other sound through the same sink — the board's draw chime at a
  /// game's end, the Feed swipe — so tests capture it too. These belong to no
  /// classified move, so a classification sound never holds them.
  static void playSfx(SfxType type) {
    if (type.isClassification) {
      _safely(() => _output.playClassification(type));
    } else {
      _safely(() => _output.playOrdinary(type));
    }
  }

  /// Loads the class sounds so the first classified move plays without a
  /// decode wait. Idempotent; call when a surface that shows classified moves
  /// opens. Never throws.
  static Future<void> warmUp() async {
    try {
      await _output.warmUp();
    } catch (error) {
      debugPrint('[ClassificationSfx] warm-up failed: $error');
    }
  }

  /// A sound failure must never reach the board or the Feed player.
  static void _safely(void Function() call) {
    try {
      call();
    } catch (error, stack) {
      debugPrint('[ClassificationSfx] play failed: $error\n$stack');
    }
  }
}
