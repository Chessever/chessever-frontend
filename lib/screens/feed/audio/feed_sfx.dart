import 'dart:async';

import 'package:chessever2/screens/chessboard/classification_fx/classification_fx.dart';
import 'package:chessever2/screens/chessboard/classification_fx/move_class.dart';
import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/utils/audio_player_service.dart';
import 'package:flutter/foundation.dart';

/// The classification a Feed moment carries, or null when the moment is not a
/// move verdict (checkmate, sacrifice, check, capture, ... are just moves, and
/// sound like the board's own move sounds). One mapping for sound, badge and
/// landing: this is [feedMomentClass].
MoveClass? moveClassForFeedMoment(FeedMoment? moment) =>
    feedMomentClass(moment);

/// Sound design for Feed: exactly the board's own sounds for ordinary moves,
/// the classification sound for classified moves ([ClassificationSfx] — it
/// wins over the ordinary one, never both), the board's draw chime when a
/// drawn game ends, and a soft swipe between games.
///
/// Every call is fire-and-forget; this class only decides *which* sound and
/// whether it should sound at all. The one thing it stops is Feed itself:
/// leaving Feed ([hush]) cuts whatever Feed still has sounding.
class FeedSfx {
  FeedSfx._() : boardSoundEnabled = false, _stopVoices = _stopLiveVoices;
  static final FeedSfx instance = FeedSfx._();

  /// For a silent test double: `class _Silent extends FeedSfx` can override
  /// the play methods without touching the audio engine. Starts as if the
  /// board settings had loaded with Sound on, unless told otherwise.
  /// [stopVoices] stands in for the audio engine when [hush] cuts what is
  /// still sounding; by default nothing is touched.
  @visibleForTesting
  FeedSfx.forTesting({
    this.boardSoundEnabled = true,
    void Function(Duration fade)? stopVoices,
  }) : _stopVoices = stopVoices ?? _leaveVoices;

  /// Any two Feed move sounds at least this far apart — a notch above the
  /// audio service's own 60 ms floor so the service never silently drops ours.
  static const Duration _minSpacing = Duration(milliseconds: 90);

  /// After a headline classification sound (brilliant, blunder), ordinary
  /// move sounds stay quiet this long so its tail is heard instead of being
  /// stepped on at 2x.
  static const Duration _headlineHold = Duration(milliseconds: 450);

  /// The draw chime waits this long after the last-ply sound.
  static const Duration _resultDelay = Duration(milliseconds: 420);

  /// The longest a Feed sound rings: the draw chime, 1.48 s. A voice Feed
  /// asked for longer ago than this has ended on its own.
  static const Duration _longestRing = Duration(milliseconds: 1600);

  /// How fast [hush] takes a sounding voice down: short enough to read as
  /// stopped at once, long enough not to click.
  static const Duration _hushFade = Duration(milliseconds: 80);

  final Stopwatch _clock = Stopwatch()..start();
  int? _lastPlayMs;
  int? _lastHeadlineMs;

  /// When Feed last asked for a sound of any kind (a move, a stinger, the
  /// swipe, a puzzle move); null once [hush] has cut them.
  int? _lastVoiceMs;
  final void Function(Duration fade) _stopVoices;
  Timer? _pendingResult;
  Future<void>? _warming;

  /// Mutes/unmutes Feed sounds (the speaker toggle on the Feed screen).
  bool get muted => _muted;
  set muted(bool value) {
    _muted = value;
    if (value) _cancelPendingResult();
  }

  bool _muted = false;

  /// Mirrors the board's "Sound" setting (`BoardSettingsNew.soundEnabled`).
  /// The Feed provider keeps it in sync on every settings emission. Gated
  /// exactly like the board and `FeedMoveSound`: off until the settings have
  /// loaded with Sound on, and off when they fail to load. A user who
  /// silenced the board does not get a talking feed, and nothing in the Feed
  /// sounds while the Feed's own game moves are still silent.
  bool boardSoundEnabled;

  bool get _silent => _muted || !boardSoundEnabled;

  /// Loads the classification and swipe sounds. Idempotent; call when the
  /// Feed tab first shows.
  Future<void> warmUp() => _warming ??= ClassificationSfx.warmUp()
      .catchError((Object err) {
        debugPrint('⚠️ FeedSfx warm-up failed: $err');
      })
      .whenComplete(() => _warming = null);

  /// Plays the right sound for [ply]. [fast] is true during 2x playback or
  /// scrubbing: only moments of severity 2+ sound then.
  ///
  /// The Feed player itself sounds its moves through `FeedMoveSound`; this
  /// stays for callers that only hold a [FeedPly], and classifies the move the
  /// same way ([FeedPly.effectiveClass]: the PGN's verdict first, then the
  /// eval-swing moment).
  void playForPly(FeedPly ply, {bool fast = false}) {
    if (_silent) return;
    final san = ply.san;
    if (san == null) return; // start position: nothing was played

    final moment = ply.moment;
    final severity = moment?.severity ?? 0;
    // At speed only the beats that matter (severity 2+) make a sound.
    if (fast && severity < 2) return;

    final moveClass = ply.effectiveClass;
    final headline = moveClass != null && severity >= 3;
    // A headline classification sound's tail is not stepped on by lesser
    // sounds.
    if (!headline && _withinHeadlineHold()) return;

    final now = _clock.elapsedMilliseconds;
    final last = _lastPlayMs;
    // Classified moves always sound; ordinary ones keep their spacing.
    if (moveClass == null &&
        last != null &&
        now - last < _minSpacing.inMilliseconds) {
      return;
    }
    _lastPlayMs = now;
    if (headline) _lastHeadlineMs = now;
    noteSounded();
    ClassificationSfx.playMove(san: san, moveClass: moveClass);
  }

  /// A Feed page asked the audio service for a sound on its own (the clip's
  /// and the puzzle's move sounds): [hush] cuts it too if it is still
  /// ringing when the viewer leaves.
  void noteSounded() => _lastVoiceMs = _clock.elapsedMilliseconds;

  /// When a clip reaches its last ply: the board's draw chime for a drawn
  /// game. A decisive game already ended on its own move sound (the mate, or
  /// the last move before a resignation), exactly as on the board.
  void playGameEnd(FeedItem item) {
    if (_silent) return;
    final drawn = item.result == '½-½' || item.result == '1/2-1/2';
    if (!drawn) return;

    _cancelPendingResult();
    final sinceLast = _msSince(_lastPlayMs);
    final wait = sinceLast == null
        ? 0
        : _resultDelay.inMilliseconds - sinceLast;
    if (wait <= 0) {
      noteSounded();
      ClassificationSfx.playSfx(SfxType.draw);
      return;
    }
    // Lets the last move's sound land first. A delay, not a queue: it is
    // cancelled by a swipe or mute, and still plays fire-and-forget.
    _pendingResult = Timer(Duration(milliseconds: wait), () {
      _pendingResult = null;
      if (_silent) return;
      noteSounded();
      ClassificationSfx.playSfx(SfxType.draw);
    });
  }

  /// Feed went out of sight (Back, a back swipe, a page over it, the app
  /// going away): every Feed sound stops at once. The draw chime still
  /// waiting behind a game's last move never plays, and a sound already
  /// ringing (a classification stinger runs up to 1.2 s, the draw chime
  /// 1.5 s) is taken down over [_hushFade] rather than playing out over
  /// the page the viewer went to. Feed's pages stop asking for sounds on
  /// their own.
  ///
  /// Only what Feed may still have ringing is cut: nothing when Feed asked
  /// for no sound within [_longestRing], and once per leave, so a second
  /// hush (the screen being disposed after its pop) never reaches a sound
  /// the next page started. It runs the instant Feed is left, before the
  /// page over it has built, so whatever is sounding then is Feed's.
  void hush() {
    _cancelPendingResult();
    _lastHeadlineMs = null;
    final since = _msSince(_lastVoiceMs);
    _lastVoiceMs = null;
    if (since == null || since > _longestRing.inMilliseconds) return;
    _stopVoices(_hushFade);
  }

  /// Soft whoosh when the feed moves to the next or previous game. It
  /// replaces no board sound.
  void playSwipe() {
    _cancelPendingResult();
    _lastHeadlineMs = null;
    if (_silent) return;
    noteSounded();
    ClassificationSfx.playSfx(SfxType.feedSwipe);
  }

  /// Takes down every voice the audio engine is still sounding, over [fade].
  /// The service hands Feed no handles for its fire-and-forget sounds, so
  /// this reads them off the engine's own sources; [hush] only calls it the
  /// moment Feed is left, when every voice sounding is Feed's.
  static void _stopLiveVoices(Duration fade) {
    try {
      final audio = AudioPlayerService.instance;
      final player = audio.player;
      if (!player.isInitialized) return;
      final voices = [
        for (final source in player.activeSounds) ...source.handles,
      ];
      for (final voice in voices) {
        audio.stopVoice(voice, fade: fade);
      }
    } catch (error) {
      debugPrint('[Feed] could not stop sounding voices: $error');
    }
  }

  static void _leaveVoices(Duration fade) {}

  // -------------------------------------------------------------------------

  bool _withinHeadlineHold() {
    final since = _msSince(_lastHeadlineMs);
    return since != null && since < _headlineHold.inMilliseconds;
  }

  int? _msSince(int? stamp) =>
      stamp == null ? null : _clock.elapsedMilliseconds - stamp;

  void _cancelPendingResult() {
    _pendingResult?.cancel();
    _pendingResult = null;
  }
}
