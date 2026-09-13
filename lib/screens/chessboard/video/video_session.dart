import 'dart:async';
import 'package:flutter/foundation.dart';
import 'video_repository.dart';
import 'video_stream.dart';
import 'video_country_preference.dart';

typedef SaveVideoLanguage = Future<void> Function(String language);

/// Route-owned. No player or timer is created for adjacent game pages.
class EventVideoSession extends ChangeNotifier {
  EventVideoSession({
    required this.repository,
    this.rememberedLanguage,
    this.saveLanguage,
    this.preferredCountry,
    this.savedCountry,
    this.saveCountry,
    this.visible = true,
    this.saveVisibility,
  }) {
    if (repository != null) {
      _refreshTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => refresh(),
      );
    }
  }
  final EventVideoRepository? repository;
  final SaveVideoLanguage? saveLanguage;
  String? rememberedLanguage;
  String? preferredCountry;
  String? savedCountry;
  final SaveVideoLanguage? saveCountry;
  final Future<void> Function(bool visible)? saveVisibility;
  String? get effectiveCountry =>
      normalizeVideoCountry(savedCountry) ??
      normalizeVideoCountry(preferredCountry);
  bool _selectionLocked = false;
  String? _orderingCountry;
  String? _orderingCountrymen;

  void setPreferredCountry(String? country) {
    final normalized = normalizeVideoCountry(country);
    if (preferredCountry == normalized) return;
    preferredCountry = normalized;
    if (!_selectionLocked && !_selections.containsKey(tourId)) {
      _orderingCountry = effectiveCountry;
      _orderingCountrymen = normalizeVideoCountry(preferredCountry);
      streams = prioritizeVideoCountry(
        streams,
        _orderingCountry,
        countrymen: _orderingCountrymen,
      );
    }
    if (!_selectionLocked &&
        !_selections.containsKey(tourId) &&
        streams.isNotEmpty) {
      final next = streams.first;
      if (selected?.identity != next.identity) {
        selected = next;
        stopPlayback(notify: false);
      }
    }
    notifyListeners();
  }

  String gameId = '', tourId = '', roundId = '';
  List<EventVideoStream> streams = const [];
  EventVideoStream? selected;
  bool visible;
  bool playing = false, foreground = true;

  /// Linear choice flow: the stream area shows the stream picker until the
  /// user picks one, then the player fades in. Reset at every switch-on moment
  /// (show toggle, new event/round) and kept across same-round game changes so
  /// the video never drops while swiping games.
  bool streamChosen = false;

  /// Last mute state reported by the embedded provider player. Carried into
  /// every later embed document, so switching streams never resets mute. Only
  /// the next document consumes it, so reporting it never rebuilds the mounted
  /// platform view.
  bool muted = false;
  bool expanded = false;
  bool failed = false;
  int playerRevision = 0;
  bool playRequested = false;

  /// Monotonic nudge counted when a same-event game change keeps the running
  /// stream. The player re-asserts playback after the page swap reattaches the
  /// native view; it never reloads the document.
  int playNudge = 0;
  Timer? _refreshTimer;
  bool _disposed = false;
  int _scopeRevision = 0;
  final Set<int> _pending = {};
  final Map<String, EventVideoStream> _ranking = {};
  final Map<String, String> _selections = {};

  bool get hasVideo => selected != null;
  bool get showVideo => hasVideo && visible;
  bool isActive(String id) => gameId == id;

  void openGame({
    required String gameId,
    required String tourId,
    required String roundId,
  }) {
    if (this.gameId == gameId &&
        this.tourId == tourId &&
        this.roundId == roundId) {
      return;
    }
    final newEvent = this.tourId != tourId;
    final newScope = newEvent || this.roundId != roundId;
    if (newEvent) {
      _selectionLocked = false;
      _orderingCountry = effectiveCountry;
      _orderingCountrymen = normalizeVideoCountry(preferredCountry);
      stopPlayback(notify: false);
      streams = const [];
      selected = null;
      // A new event is a fresh switch-on: choose again before the video fades
      // in. A new round of the same event keeps the running stream instead.
      streamChosen = false;
    }
    this.gameId = gameId;
    this.tourId = tourId;
    this.roundId = roundId;
    if (newScope) {
      _scopeRevision++;
      _ranking.clear();
      // Resolve the new scope's streams for the picker without ever dropping a
      // stream that is already running in this event.
      unawaited(refresh(preserveSelection: true));
    }
    // Browsing the event's games — swipe or the top dropdown, same round or
    // another one — must not interrupt the stream. The page swap can reattach
    // the native view; ask the player to re-assert playback once it settles.
    if (!newEvent && selected != null && (playing || playRequested)) {
      playNudge++;
    }
    notifyListeners();
  }

  Future<void> refresh({bool preserveSelection = false}) async {
    final revision = _scopeRevision;
    if (_disposed ||
        !foreground ||
        repository == null ||
        tourId.isEmpty ||
        !_pending.add(revision)) {
      return;
    }
    try {
      final result = await repository!.fetch(tourId: tourId, roundId: roundId);
      if (_disposed || revision != _scopeRevision) return;
      final ranked =
          result.streams
              .where((s) => s.supportsPlatform(VideoClientPlatform.mobile))
              .map(
                (s) => s.withRanking(_ranking.putIfAbsent(s.identity, () => s)),
              )
              .toList();
      streams = prioritizeVideoCountry(
        ranked,
        _orderingCountry,
        countrymen: _orderingCountrymen,
      );
      EventVideoStream? find(bool Function(EventVideoStream) predicate) {
        for (final stream in streams) {
          if (predicate(stream)) return stream;
        }
        return null;
      }

      final previous = selected;
      final match = find((s) => s.id == (previous?.id ?? _selections[tourId]));
      if (preserveSelection && previous != null) {
        // Browsing the event's games or rounds (swipe or the top dropdown)
        // never drops a running stream, even when the resolved scope does not
        // list it. Only a new event resets playback; the provider itself shows
        // offline/error states if the stream dies.
        selected = match ?? previous;
      } else {
        selected = match ?? (streams.isEmpty ? null : streams.first);
        if (previous?.identity != selected?.identity) {
          stopPlayback(notify: false);
          // The stream the reader was watching no longer exists in this scope:
          // offer the choice again instead of silently playing another one.
          if (previous != null &&
              !streams.any((s) => s.identity == previous.identity)) {
            streamChosen = false;
          }
        }
      }
      failed = false;
      notifyListeners();
    } catch (error) {
      if (_disposed || revision != _scopeRevision) return;
      failed = true;
      if (!preserveSelection &&
          error is VideoMetadataException &&
          error.permanent) {
        streams = const [];
        selected = null;
        stopPlayback(notify: false);
      }
      notifyListeners();
    } finally {
      _pending.remove(revision);
    }
  }

  void select(String id) {
    final matches = streams.where((s) => s.id == id);
    if (matches.isEmpty) return;
    streamChosen = true;
    _selectionLocked = true;
    final next = matches.first;
    // Tapping a tile is the play gesture: choosing starts the stream, so the
    // reader never has to press the provider's own play button. The revision
    // always advances so re-picking an already-loaded stream reloads with
    // autoplay instead of leaving its paused document in place.
    selected = next;
    playing = false;
    playRequested = true;
    playerRevision++;
    _selections[tourId] = id;
    rememberedLanguage = next.languageKey;
    final country = normalizeVideoCountry(next.flagCode);
    if (country != null) {
      savedCountry = country;
      final persist = saveCountry;
      if (persist != null) {
        unawaited(persist(country).catchError((Object _) {}));
      }
    }

    final save = saveLanguage;
    if (save != null) {
      unawaited(save(next.languageKey).catchError((Object _) {}));
    }
    notifyListeners();
  }

  void reportPlayback(bool value, int revision) {
    if (_disposed || revision != playerRevision) return;
    playing = value && foreground && showVideo;
    if (playing) _selectionLocked = true;
    // No rebuild: provider state events must not recreate platform views.
  }

  void reportMuted(bool value, int revision) {
    if (_disposed || revision != playerRevision) return;
    muted = value;
    // No rebuild: the next embed document consumes this on load.
  }

  void toggle() {
    visible = !visible;
    final save = saveVisibility;
    if (save != null) {
      unawaited(save(visible).catchError((Object _) {}));
    }
    stopPlayback(notify: false);
    if (visible) {
      // Showing the video is a switch-on: choose first, then fade in.
      streamChosen = false;
    }
    notifyListeners();
  }

  void stopPlayback({bool notify = true}) {
    playing = false;
    playRequested = false;
    playerRevision++;
    expanded = false;
    if (notify && !_disposed) notifyListeners();
  }

  /// True when the stream was actually playing at the moment the app was
  /// backgrounded. Returning then reloads it at the live edge and keeps going
  /// instead of dropping the viewer back to paused.
  bool _wasStreamingOnBackground = false;

  void setForeground(bool value, {bool resumeAfterBackground = false}) {
    if (_disposed || foreground == value) return;
    foreground = value;
    if (!value) {
      // Capture the live state before the document is cleared.
      _wasStreamingOnBackground = playing;
    }
    // Suspending clears the native document. Returning must issue a fresh
    // revision even when the same stream and player widget stayed mounted.
    stopPlayback(notify: false);
    if (value) {
      if (resumeAfterBackground &&
          _wasStreamingOnBackground &&
          showVideo &&
          streamChosen) {
        // App background return continues a stream that was live; the reload
        // starts it at the provider's live edge.
        playRequested = true;
      }
      _wasStreamingOnBackground = false;
      unawaited(refresh());
    }
    notifyListeners();
  }

  void setExpanded(bool value) {
    if (!value) stopPlayback(notify: false);
    expanded = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    repository?.close();
    super.dispose();
  }
}
