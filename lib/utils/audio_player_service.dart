import 'dart:async';
import 'dart:io';
import 'package:chessever2/utils/foreground_task_scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

/// Sound effect types used by the SoLoud audio path.
///
/// The first seven are the board's own sounds, loaded at startup. The rest are
/// loaded on demand, never on the board's startup path:
/// - [feedSwipe], the Feed page whoosh (it replaces no board sound), loaded by
///   [AudioPlayerService.loadOnDemandAssets];
/// - the `race*` Puzzle Race sounds ([isRace]), loaded by
///   [AudioPlayerService.loadRaceAssets] only, when a race warms up. They
///   play as layers ([AudioPlayerService.playOverlay],
///   [AudioPlayerService.startLoop]) that no board gate touches;
/// - the `nag*` classification sounds, one per classified move type, loaded
///   by [AudioPlayerService.loadOnDemandAssets]. A classified move plays its
///   `nag*` sound INSTEAD of the ordinary one, and [SfxPriorityGate] makes it
///   win when both are asked for at once.
///
/// Order matters: [isOnDemand] and [isClassification] are index ranges, so a
/// new on-demand sound that is not a classification goes before
/// [nagBrilliant], and the classification sounds stay last.
enum SfxType {
  move,
  castling,
  check,
  checkmate,
  draw,
  promotion,
  takeover,
  feedSwipe,
  raceCountdownBeat,
  raceGo,
  raceCorrect,
  raceCorrectStreak,
  raceWrong,
  raceLevelUp,
  raceTensionLoop,
  raceLastLife,
  raceFinish,
  raceNewBest,
  nagBrilliant,
  nagGreat,
  nagBest,
  nagInteresting,
  nagInaccuracy,
  nagMistake,
  nagBlunder,
  nagMissedWin,
  nagBook;

  /// Loaded on demand ([AudioPlayerService.loadOnDemandAssets], or
  /// [AudioPlayerService.loadRaceAssets] for [isRace]), not at startup.
  bool get isOnDemand => index >= SfxType.feedSwipe.index;

  /// A Puzzle Race sound (`assets/sfx/race_*.mp3`), loaded only for a race.
  bool get isRace =>
      index >= SfxType.raceCountdownBeat.index &&
      index <= SfxType.raceNewBest.index;

  /// A move-classification sound (wins over ordinary move sounds).
  bool get isClassification => index >= SfxType.nagBrilliant.index;
}

/// A layered voice as this service hands it out
/// ([AudioPlayerService.startLoop]) and takes it back
/// ([AudioPlayerService.fadeVoice], [AudioPlayerService.stopVoice],
/// [AudioPlayerService.isVoiceAlive]). Callers hold it under this name and
/// never import the audio package themselves, so its lifecycle stays here.
typedef SfxVoiceHandle = SoundHandle;

/// How a layered voice plays ([AudioPlayerService.playOverlay],
/// [AudioPlayerService.startLoop]).
typedef _Voice = ({double volume, double speed, bool looping});

/// One set of on-demand sounds that loads together.
class _OnDemandGroup {
  _OnDemandGroup(this.paths);

  final Map<SfxType, String> paths;

  /// Something asked for this set: recovery paths reload it after a teardown.
  bool wanted = false;
  bool loaded = false;
  Future<void>? loading;
}

/// Decides which of a move's two sounds is heard: its classification sound
/// always wins over its ordinary one, and the two never both sound. Sounds of
/// OTHER moves are left alone, so stepping through a game (long-press repeats
/// every 150 ms) keeps every unclassified ply's own sound.
///
/// A move is recognised by its ordinary sound (the `fallback` a
/// classification carries, `sfxTypeForSan(san)`) plus [echoWindow]: the board
/// raises each move from two independent paths on the same state change, so
/// both requests for one move land inside that window with the same sound.
/// The service already treats the same ordinary sound twice inside this
/// window as that echo, so no ply that used to sound is silenced here.
///
/// - The move's ordinary sound that STARTED less than [echoWindow] before its
///   classification sound is cut ([requestClass] hands its handle back).
/// - The move's ordinary sound REQUESTED within [echoWindow] after its
///   classification sound is skipped ([requestOrdinary] returns null).
/// - The move's ordinary sound requested before its classification sound but
///   not started yet (it was waiting on engine init) is dropped when it gets
///   there ([mayStartOrdinary] is false).
/// - One classification voice at a time: a newer classification cuts the
///   previous voice ([requestClass]), and one still waiting on its decode is
///   dropped once a newer one was asked for ([mayStartClass] is false), so
///   fast stepping through a reviewed game never stacks clips.
///
/// Pure bookkeeping — no audio, no queue, no awaits — so every play stays
/// fire-and-forget. Generic over the voice handle so tests drive it with a
/// fake player and a fake clock.
class SfxPriorityGate<H> {
  SfxPriorityGate({int Function()? nowMicros})
    : _now = nowMicros ?? _defaultNowMicros;

  /// How far apart one move's two requests can land.
  static const Duration echoWindow = Duration(milliseconds: 120);

  /// Classification requests remembered for [mayStartOrdinary]. An ordinary
  /// sound can wait on engine init for a while, so these are bounded by count
  /// rather than age.
  static const int _classHistory = 8;

  static final Stopwatch _clock = Stopwatch()..start();
  static int _defaultNowMicros() => _clock.elapsedMicroseconds;

  final int Function() _now;
  final List<({int atMicros, SfxType move})> _recentClass = [];
  final List<({int atMicros, SfxType sound, H handle})> _recentOrdinary = [];
  int _classTicket = 0;
  H? _classVoice;

  int get _windowMicros => echoWindow.inMicroseconds;

  /// Asks to play the ordinary [sound]. Returns the ticket to pass to
  /// [mayStartOrdinary], or null when it is the echo of a move whose
  /// classification sound was just asked for.
  int? requestOrdinary(SfxType sound) {
    final now = _now();
    for (final request in _recentClass) {
      final since = now - request.atMicros;
      if (request.move == sound && since >= 0 && since < _windowMicros) {
        return null;
      }
    }
    return now;
  }

  /// Checked right before an admitted ordinary [sound] actually starts: false
  /// when the same move's classification sound was asked for since [ticket].
  bool mayStartOrdinary(int ticket, SfxType sound) {
    for (final request in _recentClass) {
      final lag = request.atMicros - ticket;
      if (request.move == sound && lag >= 0 && lag < _windowMicros) {
        return false;
      }
    }
    return true;
  }

  /// Records an ordinary voice that just started, so its move's
  /// classification sound arriving within [echoWindow] can cut it.
  void ordinaryStarted(H handle, SfxType sound) {
    final now = _now();
    _recentOrdinary
      ..removeWhere((voice) => now - voice.atMicros >= _windowMicros)
      ..add((atMicros: now, sound: sound, handle: handle));
  }

  /// A classification sound for the move whose ordinary sound is [move] is
  /// about to play ([move] is null when there is none, such as puzzle
  /// feedback). Returns its ticket for [mayStartClass] / [classStarted], and
  /// the voices the caller must stop: the previous classification voice and
  /// this move's ordinary voice when it started within [echoWindow].
  ({int ticket, List<H> cut}) requestClass([SfxType? move]) {
    final now = _now();
    final cut = <H>[];
    final previous = _classVoice;
    if (previous != null) cut.add(previous);
    _classVoice = null;
    if (move != null) {
      _recentClass.add((atMicros: now, move: move));
      if (_recentClass.length > _classHistory) _recentClass.removeAt(0);
      final kept = <({int atMicros, SfxType sound, H handle})>[];
      for (final voice in _recentOrdinary) {
        if (now - voice.atMicros >= _windowMicros) continue;
        if (voice.sound == move) {
          cut.add(voice.handle);
        } else {
          kept.add(voice);
        }
      }
      _recentOrdinary
        ..clear()
        ..addAll(kept);
    }
    return (ticket: ++_classTicket, cut: cut);
  }

  /// Checked right before a classification sound starts: false once a newer
  /// classification sound was asked for (that move is the one being heard).
  bool mayStartClass(int ticket) => ticket == _classTicket;

  /// Records the classification voice that just started, so the next
  /// classification sound cuts it.
  void classStarted(int ticket, H handle) {
    if (ticket == _classTicket) _classVoice = handle;
  }
}

class AudioPlayerService with WidgetsBindingObserver {
  static final AudioPlayerService _instance = AudioPlayerService._internal();
  static const String _foregroundPrepareTaskKey = 'audio_foreground_prepare';
  static const Duration _minimumAnyPlaySpacing = Duration(milliseconds: 60);
  // The same sound twice inside this window is the board's two-path echo of
  // one move — for classification sounds too ([SfxPriorityGate.echoWindow]).
  static const Duration _minimumSameSoundSpacing = SfxPriorityGate.echoWindow;
  static const Duration _backgroundTeardownGrace = Duration(milliseconds: 300);

  // Note: These MUST NOT be `final` - recovery reloads them after
  // the native SoLoud engine is torn down and reinitialized.
  late AudioSource pieceMoveSfx;
  late AudioSource pieceCastlingSfx;
  late AudioSource pieceCheckSfx;
  late AudioSource pieceCheckmateSfx;
  late AudioSource pieceDrawSfx;
  late AudioSource piecePromotionSfx;
  late AudioSource pieceTakeoverSfx;

  /// On-demand sounds, keyed by type. Filled only after [loadOnDemandAssets]
  /// (or the first play of one of them); a type whose asset failed to load is
  /// simply absent — a classification sound then plays its ordinary fallback.
  static const Map<SfxType, String> onDemandAssetPaths = {
    SfxType.feedSwipe: 'assets/sfx/feed_swipe.mp3',
    SfxType.nagBrilliant: 'assets/sfx/nag_brilliant.mp3',
    SfxType.nagGreat: 'assets/sfx/nag_great.mp3',
    SfxType.nagBest: 'assets/sfx/nag_best.mp3',
    SfxType.nagInteresting: 'assets/sfx/nag_interesting.mp3',
    SfxType.nagInaccuracy: 'assets/sfx/nag_inaccuracy.mp3',
    SfxType.nagMistake: 'assets/sfx/nag_mistake.mp3',
    SfxType.nagBlunder: 'assets/sfx/nag_blunder.mp3',
    SfxType.nagMissedWin: 'assets/sfx/nag_missed_win.mp3',
    SfxType.nagBook: 'assets/sfx/nag_book.mp3',
  };

  /// Puzzle Race sounds ([SfxType.isRace]): on demand too, but their own set,
  /// loaded only by [loadRaceAssets] (or a race sound's first play), never
  /// with the classification set, so nobody who never races decodes them.
  static const Map<SfxType, String> raceAssetPaths = {
    SfxType.raceCountdownBeat: 'assets/sfx/race_countdown_beat.mp3',
    SfxType.raceGo: 'assets/sfx/race_go.mp3',
    SfxType.raceCorrect: 'assets/sfx/race_correct.mp3',
    SfxType.raceCorrectStreak: 'assets/sfx/race_correct_streak.mp3',
    SfxType.raceWrong: 'assets/sfx/race_wrong.mp3',
    SfxType.raceLevelUp: 'assets/sfx/race_level_up.mp3',
    SfxType.raceTensionLoop: 'assets/sfx/race_tension_loop.mp3',
    SfxType.raceLastLife: 'assets/sfx/race_last_life.mp3',
    SfxType.raceFinish: 'assets/sfx/race_finish.mp3',
    SfxType.raceNewBest: 'assets/sfx/race_new_best.mp3',
  };

  final Map<SfxType, AudioSource> _onDemandSources = <SfxType, AudioSource>{};

  /// Assets that failed to load since the last invalidation: not retried on
  /// every play (their plays fall back straight away).
  final Set<SfxType> _onDemandFailed = <SfxType>{};

  /// The classification sounds plus the Feed swipe.
  final _OnDemandGroup _moveGroup = _OnDemandGroup(onDemandAssetPaths);

  /// The Puzzle Race sounds.
  final _OnDemandGroup _raceGroup = _OnDemandGroup(raceAssetPaths);

  List<_OnDemandGroup> get _groups => [_moveGroup, _raceGroup];

  _OnDemandGroup _groupFor(SfxType type) =>
      type.isRace ? _raceGroup : _moveGroup;

  /// Bumped whenever loaded sources are invalidated (teardown, Android source
  /// disposal), so an on-demand load that straddles one never stores dead
  /// handles.
  int _sourceEpoch = 0;

  /// Classification sounds win over ordinary move sounds.
  final SfxPriorityGate<SoundHandle> _priority = SfxPriorityGate<SoundHandle>();

  factory AudioPlayerService() => _instance;
  AudioPlayerService._internal() {
    WidgetsBinding.instance.addObserver(this);
  }
  static AudioPlayerService get instance => _instance;

  SoLoud get player => SoLoud.instance;

  bool _initialized = false;
  bool _assetsLoaded = false;
  bool _isBackgrounded = false;
  bool _needsForegroundReload = false;
  Timer? _backgroundTeardownTimer;
  Future<void>? _initializing;
  Future<void>? _androidRecovering;
  Future<void>? _backgroundTeardown;
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
    if (_isBackgrounded) {
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

  /// Per-voice gain. Board and classification sounds play as mastered (the
  /// classification files are levelled against the board sounds when they
  /// are generated); only the Feed swipe sits quietly under the clip.
  static double gainFor(SfxType type) => switch (type) {
    SfxType.feedSwipe => 0.35,
    _ => 1.0,
  };

  /// Whether [type] would play its own asset right now (not a fallback).
  bool hasOwnSource(SfxType type) =>
      type.isOnDemand ? _onDemandSources.containsKey(type) : _assetsLoaded;

  /// Loads the on-demand sounds (classification + Feed swipe) next to the
  /// board sounds. Idempotent and cheap to repeat; recovery paths reload them
  /// once this has been called. Call it when a surface that shows classified
  /// moves opens, so the first classified move does not wait on a decode.
  Future<void> loadOnDemandAssets() => _loadGroup(_moveGroup);

  /// Loads the Puzzle Race sounds ([raceAssetPaths]). Idempotent and cheap to
  /// repeat; recovery paths reload them once this has been called. Call it
  /// when a race is being set up, so the countdown never waits on a decode.
  Future<void> loadRaceAssets() => _loadGroup(_raceGroup);

  Future<void> _loadGroup(_OnDemandGroup group) async {
    group.wanted = true;
    if (_isBackgrounded) return;
    try {
      await initializeAndLoadAllAssets();
      if (group.loaded || _isBackgrounded || !player.isInitialized) {
        return;
      }
      await _ensureGroup(group);
    } catch (err, st) {
      debugPrint('⚠️ On-demand SFX load failed: $err\n$st');
    }
  }

  Future<void> _ensureGroup(_OnDemandGroup group) {
    final inFlight = group.loading;
    if (inFlight != null) return inFlight;
    late final Future<void> loading;
    loading = _loadGroupSources(group).whenComplete(() {
      if (identical(group.loading, loading)) group.loading = null;
    });
    return group.loading = loading;
  }

  Future<void> _loadGroupSources(_OnDemandGroup group) async {
    final epoch = _sourceEpoch;
    // Only what is not loaded yet: re-loading a live source would leak it.
    final entries = group.paths.entries
        .where((entry) => !_onDemandSources.containsKey(entry.key))
        .toList(growable: false);
    // Parallel, like the board sounds. A missing or undecodable file costs
    // only its own sound: it is skipped and plays its fallback instead.
    final loaded = await Future.wait(
      entries.map((entry) async {
        try {
          return await SoLoud.instance.loadAsset(
            entry.value,
            mode: LoadMode.memory,
          );
        } catch (err) {
          debugPrint('⚠️ SFX ${entry.value} unavailable: $err');
          return null;
        }
      }),
    );
    if (!player.isInitialized) return;
    if (epoch != _sourceEpoch) {
      // Sources were invalidated mid-load; these handles are orphans.
      for (final source in loaded.whereType<AudioSource>()) {
        unawaited(
          SoLoud.instance.disposeSource(source).catchError((Object _) {}),
        );
      }
      return;
    }
    for (var i = 0; i < entries.length; i++) {
      final source = loaded[i];
      if (source != null) {
        _onDemandSources[entries[i].key] = source;
      } else {
        _onDemandFailed.add(entries[i].key);
      }
    }
    group.loaded = true;
  }

  void _invalidateSources() {
    _sourceEpoch++;
    _onDemandSources.clear();
    _onDemandFailed.clear();
    for (final group in _groups) {
      group.loaded = false;
      // A load already in flight will discard its now-stale handles; the
      // next init must start a fresh one rather than wait on it.
      group.loading = null;
    }
  }

  /// Resolve the fresh AudioSource for a given [SfxType].
  /// Must only be called AFTER [initializeAndLoadAllAssets] has completed,
  /// and for an on-demand type only once [hasOwnSource] says it is loaded.
  AudioSource _resolve(SfxType type) {
    if (type.isOnDemand) return _onDemandSources[type]!;
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
      default:
        return pieceMoveSfx;
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
  ///
  /// A classification type ([SfxType.isClassification]) goes through
  /// [playClassification] with no ordinary fallback. Every other type is an
  /// ordinary sound: it is skipped only when it is the echo of a move whose
  /// classification sound was just asked for ([SfxPriorityGate]); the next
  /// move's sound always gets through. Always fire-and-forget.
  void playSound(SfxType type) {
    if (type.isClassification) {
      playClassification(type);
      return;
    }
    if (_isBackgrounded) return;
    final ticket = _priority.requestOrdinary(type);
    if (ticket == null) return; // this move's classification sound won
    if (_shouldSkipForSpacing(type)) return;
    unawaited(_playWithRecovery(type, ticket: ticket));
  }

  /// Plays a classification sound, which WINS over its move's ordinary sound
  /// ([fallback]): that sound started or requested within
  /// [SfxPriorityGate.echoWindow] of this one is cut or skipped — the two
  /// never both sound. Other moves' sounds are left alone. Only one
  /// classification voice sounds at a time: this one cuts the previous one.
  ///
  /// [fallback] is also the ordinary sound to play instead when the
  /// classification asset cannot be loaded, so a classified move is never
  /// silent. The asset set loads on first use when [loadOnDemandAssets] was
  /// not called yet. Fire-and-forget; no queue.
  void playClassification(SfxType type, {SfxType? fallback}) {
    assert(type.isClassification, '$type is not a classification sound');
    if (_isBackgrounded) return;
    // The board raises every move from two independent paths; the same
    // classification sound twice inside the same-sound window is that echo.
    if (_isSameSoundEcho(type)) return;
    final request = _priority.requestClass(
      fallback == null || fallback.isOnDemand ? null : fallback,
    );
    for (final handle in request.cut) {
      _cut(handle);
    }
    _lastPlayedType = type;
    _lastPlayAtMicros = _playSpacingClock.elapsedMicroseconds;
    _moveGroup.wanted = true;
    unawaited(
      _playWithRecovery(type, fallback: fallback, classTicket: request.ticket),
    );
  }

  /// Plays [type] as a layer over the board (the Puzzle Race sounds). None of
  /// the board's gates apply (spacing, echo, classification priority), and it
  /// does not count as the board's last sound, so a move sound landing right
  /// next to it is never dropped. [volume] scales its level (0..1); [speed]
  /// is its rate and pitch (1 = as recorded, 2^(1/12) = a semitone up). An
  /// on-demand asset loads on first use when its set was not loaded yet.
  /// Fire-and-forget; no queue.
  void playOverlay(SfxType type, {double volume = 1, double speed = 1}) {
    if (_isBackgrounded) return;
    if (type.isOnDemand) _groupFor(type).wanted = true;
    unawaited(
      _playWithRecovery(
        type,
        voice: (volume: volume, speed: speed, looping: false),
      ),
    );
  }

  /// Starts [type] looping, as a layer like [playOverlay]. Completes with its
  /// voice, or null when it could not start (backgrounded, engine down, asset
  /// missing). The caller owns the voice: shape it with [fadeVoice], end it
  /// with [stopVoice]. A voice dies with the engine (the app backgrounding
  /// tears it down), so check [isVoiceAlive] before relying on one.
  Future<SoundHandle?> startLoop(
    SfxType type, {
    double volume = 0,
    double speed = 1,
  }) async {
    if (_isBackgrounded) return null;
    if (type.isOnDemand) _groupFor(type).wanted = true;
    return _playWithRecovery(
      type,
      voice: (volume: volume, speed: speed, looping: true),
    );
  }

  /// Whether [voice] is still playing (or paused) on the live engine.
  bool isVoiceAlive(SoundHandle voice) {
    try {
      return player.isInitialized && player.getIsValidVoiceHandle(voice);
    } catch (_) {
      return false;
    }
  }

  /// Glides [voice] to [volume] (0..1) and/or [speed] over [over]. A dead
  /// voice is ignored.
  void fadeVoice(
    SoundHandle voice, {
    double? volume,
    double? speed,
    required Duration over,
  }) {
    if (!isVoiceAlive(voice)) return;
    try {
      if (volume != null) {
        player.fadeVolume(voice, _voiceVolume(volume), over);
      }
      if (speed != null) {
        player.fadeRelativePlaySpeed(voice, _voiceSpeed(speed), over);
      }
    } catch (err) {
      debugPrint('⚠️ Could not fade SFX voice $voice: $err');
    }
  }

  /// Fades [voice] out over [fade] and stops it (at once for a zero fade).
  /// A dead voice is ignored.
  void stopVoice(
    SoundHandle voice, {
    Duration fade = const Duration(milliseconds: 120),
  }) {
    if (!isVoiceAlive(voice)) return;
    try {
      if (fade <= Duration.zero) {
        unawaited(
          player.stop(voice).catchError((Object err) {
            debugPrint('⚠️ Could not stop SFX voice $voice: $err');
          }),
        );
        return;
      }
      player.fadeVolume(voice, 0, fade);
      player.scheduleStop(voice, fade + const Duration(milliseconds: 4));
    } catch (err) {
      debugPrint('⚠️ Could not stop SFX voice $voice: $err');
    }
  }

  static double _voiceVolume(double volume) =>
      volume.isFinite ? volume.clamp(0.0, 1.0) : 0.0;

  static double _voiceSpeed(double speed) =>
      speed.isFinite ? speed.clamp(0.5, 2.0) : 1.0;

  bool _isSameSoundEcho(SfxType type) {
    final last = _lastPlayAtMicros;
    if (last == null || _lastPlayedType != type) return false;
    final elapsed = _playSpacingClock.elapsedMicroseconds - last;
    return elapsed < _minimumSameSoundSpacing.inMicroseconds;
  }

  /// Stops a voice a classification sound replaces: its move's ordinary sound,
  /// or the previous classification voice. A 12 ms fade before the stop keeps
  /// the cut click-free.
  void _cut(SoundHandle handle) {
    try {
      if (!player.isInitialized || !player.getIsValidVoiceHandle(handle)) {
        return;
      }
      player.fadeVolume(handle, 0, const Duration(milliseconds: 12));
      player.scheduleStop(handle, const Duration(milliseconds: 14));
    } catch (err) {
      debugPrint('⚠️ Could not cut SFX voice $handle: $err');
    }
  }

  Future<void> prepareForForegroundPlayback() async {
    try {
      await _backgroundTeardown;
      if (_isBackgrounded) return;

      if (Platform.isAndroid) {
        if (!player.isInitialized || !_assetsLoaded) {
          await _recoverAndroidSfxAssets();
        } else {
          _needsForegroundReload = false;
        }
        return;
      }

      await initializeAndLoadAllAssets();
      if (player.isInitialized) {
        _needsForegroundReload = false;
      }
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

  /// Plays [type] once the engine and its asset are ready. Completes with the
  /// voice that started, or null when nothing did.
  Future<SoundHandle?> _playWithRecovery(
    SfxType type, {
    int? ticket,
    SfxType? fallback,
    int? classTicket,
    _Voice? voice,
  }) async {
    if (_isBackgrounded) return null;

    try {
      await _waitForAndroidRecoveryIfNeeded();
      if (_isBackgrounded) return null;
      await initializeAndLoadAllAssets();
      if (_isBackgrounded) return null;
      await _waitForAndroidRecoveryIfNeeded();
      if (_isBackgrounded) return null;
      if (type.isOnDemand &&
          !_onDemandSources.containsKey(type) &&
          !_onDemandFailed.contains(type)) {
        // First use, or reloading after a teardown. The ordinary sounds keep
        // playing meanwhile; only this voice waits on the decode.
        await _ensureGroup(_groupFor(type));
        if (_isBackgrounded) return null;
      }
      // The engine can die during the await gap above (for example iOS route
      // changes). Re-check and funnel into recovery instead of letting play()
      // throw SoLoudNotInitializedException.
      if (!player.isInitialized) {
        throw StateError('SoLoud not initialized after init; forcing recovery');
      }
      return _playResolved(
        type,
        ticket: ticket,
        fallback: fallback,
        classTicket: classTicket,
        voice: voice,
      );
    } catch (e, s) {
      if (Platform.isAndroid) {
        // Keep Android on the package's normal init/play lifecycle. A failed
        // play can still leave Dart with stale source handles, so reload the
        // short SFX assets without app-side deinit/reinit.
        debugPrint('⚠️ Android SoLoud playback failed, reloading SFX: $e\n$s');
        final recovered = await _recoverAndroidPlayback(
          type,
          ticket: ticket,
          fallback: fallback,
          classTicket: classTicket,
          voice: voice,
        );
        return recovered;
      }
      debugPrint('⚠️ Audio playback failed, recovering SoLoud: $e\n$s');
      _teardownPlayer();
      try {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (_isBackgrounded) return null;
        await initializeAndLoadAllAssets(force: true);
        if (_isBackgrounded) return null;
        // Only play if recovery actually brought the engine back, so a failed
        // recovery can't throw a second SoLoudNotInitializedException.
        if (player.isInitialized) {
          if (type.isOnDemand) await _ensureGroup(_groupFor(type));
          if (_isBackgrounded || !player.isInitialized) return null;
          // _resolve reads the freshly-loaded field — no stale handles.
          return _playResolved(
            type,
            ticket: ticket,
            fallback: fallback,
            classTicket: classTicket,
            voice: voice,
          );
        }
      } catch (err, st) {
        debugPrint('⚠️ Audio playback failed after recovery: $err\n$st');
      }
      return null;
    }
  }

  Future<void> _waitForAndroidRecoveryIfNeeded() async {
    if (!Platform.isAndroid) return;
    final androidRecovery = _androidRecovering;
    if (androidRecovery != null) {
      await androidRecovery;
    }
  }

  Future<SoundHandle?> _recoverAndroidPlayback(
    SfxType type, {
    int? ticket,
    SfxType? fallback,
    int? classTicket,
    _Voice? voice,
  }) async {
    if (_isBackgrounded) return null;

    try {
      await _recoverAndroidSfxAssets();
      if (type.isOnDemand && !_isBackgrounded && player.isInitialized) {
        await _ensureGroup(_groupFor(type));
      }

      if (!_isBackgrounded && player.isInitialized && _assetsLoaded) {
        return _playResolved(
          type,
          ticket: ticket,
          fallback: fallback,
          classTicket: classTicket,
          voice: voice,
        );
      }
    } catch (err, st) {
      debugPrint('⚠️ Android SoLoud recovery failed: $err\n$st');
    }
    return null;
  }

  Future<void> _recoverAndroidSfxAssets() {
    if (_isBackgrounded) return Future.value();

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
    if (_isBackgrounded) return;
    await initializeAndLoadAllAssets();
  }

  Future<void> _disposeLoadedSourcesForRecovery() async {
    _invalidateSources();
    if (!player.isInitialized) return;

    try {
      await player.disposeAllSources();
    } catch (err, st) {
      debugPrint('⚠️ Android SoLoud source disposal failed: $err\n$st');
    }
  }

  SoundHandle? _playResolved(
    SfxType requested, {
    int? ticket,
    SfxType? fallback,
    int? classTicket,
    _Voice? voice,
  }) {
    if (_isBackgrounded) return null;
    // An ordinary sound that waited on init while its move's classification
    // sound was asked for: the classification sound wins, this never starts.
    if (ticket != null && !_priority.mayStartOrdinary(ticket, requested)) {
      return null;
    }
    // A classification sound that waited on its decode while a newer move
    // was classified: that move is the one heard, this one never starts.
    if (classTicket != null && !_priority.mayStartClass(classTicket)) {
      return null;
    }

    var type = requested;
    if (type.isOnDemand && !hasOwnSource(type)) {
      // The asset is missing: a classified move still gets its ordinary
      // sound rather than silence; anything else stays silent.
      if (fallback == null || fallback.isOnDemand) return null;
      type = fallback;
    }

    // Board sounds keep the untouched call; only quieter voices carry a gain.
    final gain = gainFor(type);
    // A layered voice at another speed starts paused, so its first sample
    // already plays at that speed.
    final pitched = voice != null && voice.speed != 1;
    final SoundHandle handle;
    if (voice != null) {
      handle = player.play(
        _resolve(type),
        volume: _voiceVolume(gain * voice.volume),
        looping: voice.looping,
        paused: pitched,
      );
    } else if (gain >= 1) {
      handle = player.play(_resolve(type));
    } else {
      handle = player.play(_resolve(type), volume: gain);
    }
    if (handle.isError || handle.id <= 0) {
      throw StateError('SoLoud returned an invalid handle for $type');
    }
    if (!player.getIsValidVoiceHandle(handle)) {
      throw StateError('SoLoud returned an inactive handle for $type');
    }
    if (pitched) {
      try {
        player.setRelativePlaySpeed(handle, _voiceSpeed(voice.speed));
      } catch (err) {
        debugPrint('⚠️ Could not set SFX speed for $type: $err');
      } finally {
        player.setPause(handle, false);
      }
    }
    if (ticket != null) {
      _priority.ordinaryStarted(handle, requested);
    } else if (classTicket != null && type.isClassification) {
      _priority.classStarted(classTicket, handle);
    }
    return handle;
  }

  Future<void> _initializeInternal({required bool force}) async {
    if (_isBackgrounded) return;

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
      _invalidateSources();
    }

    // Configure audio session BEFORE and AFTER initializing SoLoud
    // This ensures our app doesn't steal audio focus from other apps
    // and correctly applies ambient mode even if SoLoud resets it during init.
    await _configureAudioSession();
    if (_isBackgrounded) return;

    if (!player.isInitialized) {
      await SoLoud.instance.init();
      if (_isBackgrounded) {
        _teardownPlayer();
        return;
      }
      // Re-apply after init just in case SoLoud native layer reset the category
      _audioSessionConfigured = false;
      await _configureAudioSession();
      if (_isBackgrounded) {
        _teardownPlayer();
        return;
      }
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
      if (_isBackgrounded) {
        _teardownPlayer();
        return;
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
    _needsForegroundReload = false;
    debugPrint('🎧 AudioPlayerService initialized successfully');

    // On-demand sounds reload after a teardown only once something asked for
    // them, and never hold up the board sounds: a play that needs one awaits
    // this same load itself.
    for (final group in _groups) {
      if (!group.wanted || group.loaded) continue;
      unawaited(
        _ensureGroup(group).catchError((Object err) {
          debugPrint('⚠️ On-demand SFX reload failed: $err');
        }),
      );
    }
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
      _audioSessionConfigured = false;
      _invalidateSources();
    }
  }

  Future<void> _hibernateForBackground() {
    return _backgroundTeardown ??= _hibernateForBackgroundInternal()
        .whenComplete(() {
          _backgroundTeardown = null;
        });
  }

  Future<void> _hibernateForBackgroundInternal() async {
    final inFlightInitialization = _initializing;
    if (inFlightInitialization != null) {
      try {
        await inFlightInitialization;
      } catch (_) {
        // Teardown below still needs to clear native callbacks/resources.
      }
    }

    if (!_isBackgrounded) return;

    debugPrint('🎧 AudioPlayerService: hibernating SoLoud for background');
    _teardownPlayer();
  }

  void _scheduleBackgroundHibernate() {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    _needsForegroundReload =
        _needsForegroundReload ||
        _initialized ||
        _assetsLoaded ||
        player.isInitialized ||
        _initializing != null;

    _backgroundTeardownTimer?.cancel();
    _backgroundTeardownTimer = Timer(_backgroundTeardownGrace, () {
      _backgroundTeardownTimer = null;
      if (!_isBackgrounded) return;
      unawaited(_hibernateForBackground());
    });
  }

  void _scheduleForegroundPrepare() {
    _backgroundTeardownTimer?.cancel();
    _backgroundTeardownTimer = null;

    if (_backgroundTeardown == null &&
        _needsForegroundReload &&
        _initialized &&
        _assetsLoaded &&
        player.isInitialized) {
      _needsForegroundReload = false;
      return;
    }

    if (!_needsForegroundReload && !_initialized && !player.isInitialized) {
      return;
    }

    ForegroundTaskScheduler.schedule(
      key: _foregroundPrepareTaskKey,
      delay: kForegroundRefreshDelay,
      task: prepareForForegroundPlayback,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('🎧 AudioPlayerService: lifecycle changed to $state');
    if (state == AppLifecycleState.resumed) {
      _isBackgrounded = false;
      _scheduleForegroundPrepare();
      return;
    }

    // Only tear down when truly backgrounded (paused) or detached.
    // `inactive` is a transient state (notification shade, dialogs, split-screen)
    // and tearing down there causes sound to disappear on Android.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _isBackgrounded = true;
      ForegroundTaskScheduler.cancel(_foregroundPrepareTaskKey);
      _scheduleBackgroundHibernate();
      return;
    }

    // inactive / hidden: do nothing — keep the engine alive.
  }
}
