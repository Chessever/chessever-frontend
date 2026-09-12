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
  String? get effectiveCountry =>
      normalizeVideoCountry(savedCountry) ??
      normalizeVideoCountry(preferredCountry);
  bool _selectionLocked = false;

  void setPreferredCountry(String? country) {
    final normalized = normalizeVideoCountry(country);
    if (preferredCountry == normalized) return;
    preferredCountry = normalized;
    streams = prioritizeVideoCountry(streams, effectiveCountry);
    if (!_selectionLocked &&
        !_selections.containsKey(tourId) &&
        streams.isNotEmpty) {
      final next = streams.first;
      if (selected?.identity != next.identity) {
        selected = next;
        stopPlayback(notify: false);
        revealFlags(notify: false);
      }
    }
    notifyListeners();
  }

  String gameId = '', tourId = '', roundId = '';
  List<EventVideoStream> streams = const [];
  EventVideoStream? selected;
  bool visible = true, flagsVisible = false, playing = false, foreground = true;
  bool expanded = false;
  bool failed = false;
  int playerRevision = 0;
  bool playRequested = false;
  Timer? _refreshTimer, _flagsTimer;
  bool _disposed = false, _scrolling = false;
  int _scopeRevision = 0;
  final Set<int> _pending = {};
  final Map<String, EventVideoStream> _ranking = {};
  final Map<String, String> _selections = {};
  final Map<String, bool> _visibility = {};

  bool get hasVideo => selected != null;
  bool get showVideo => hasVideo && visible;
  bool get compactEngine => showVideo;
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
    _scrolling = false;
    final newEvent = this.tourId != tourId;
    final newScope = newEvent || this.roundId != roundId;
    if (newEvent) {
      _selectionLocked = false;
      stopPlayback(notify: false);
      streams = const [];
      selected = null;
      visible = _visibility[tourId] ?? true;
    }
    this.gameId = gameId;
    this.tourId = tourId;
    this.roundId = roundId;
    if (newScope) {
      _scopeRevision++;
      _ranking.clear();
      // Retain the same player's state while resolving a different round in
      // this event. Permanent removal or a changed selection stops it below.
      unawaited(refresh());
    }
    revealFlags(notify: false);
    notifyListeners();
  }

  Future<void> refresh() async {
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
              .map(
                (s) => s.withRanking(_ranking.putIfAbsent(s.identity, () => s)),
              )
              .toList();
      streams = prioritizeVideoCountry(ranked, effectiveCountry);
      EventVideoStream? find(bool Function(EventVideoStream) predicate) {
        for (final stream in streams) {
          if (predicate(stream)) return stream;
        }
        return null;
      }

      final previous = selected;
      selected =
          find((s) => s.id == (previous?.id ?? _selections[tourId])) ??
          (streams.isEmpty ? null : streams.first);
      if (previous?.identity != selected?.identity) {
        stopPlayback(notify: false);
        revealFlags(notify: false);
      }
      failed = false;
      notifyListeners();
    } catch (error) {
      if (_disposed || revision != _scopeRevision) return;
      failed = true;
      if (error is VideoMetadataException && error.permanent) {
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
    _selectionLocked = true;
    final next = matches.first;
    if (selected?.identity != next.identity) {
      final continuePlaying = playing;
      selected = next;
      playing = false;
      playRequested = continuePlaying;
      playerRevision++;
    }
    _selections[tourId] = id;
    rememberedLanguage = next.languageKey;
    final country = normalizeVideoCountry(next.flagCode);
    if (country != null) {
      savedCountry = country;
      streams = prioritizeVideoCountry(streams, effectiveCountry);
      final persist = saveCountry;
      if (persist != null) {
        unawaited(persist(country).catchError((Object _) {}));
      }
    }

    final save = saveLanguage;
    if (save != null) {
      unawaited(save(next.languageKey).catchError((Object _) {}));
    }
    revealFlags(notify: false);
    notifyListeners();
  }

  void reportPlayback(bool value, int revision) {
    if (_disposed || revision != playerRevision) return;
    playing = value && foreground && showVideo;
    if (playing) _selectionLocked = true;
    // No rebuild: provider state events must not recreate platform views.
  }

  void toggle() {
    _scrolling = false;
    visible = !visible;
    _visibility[tourId] = visible;
    stopPlayback(notify: false);
    if (visible) {
      revealFlags(notify: false);
    } else {
      flagsVisible = false;
      _flagsTimer?.cancel();
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

  void setForeground(bool value) {
    if (_disposed || foreground == value) return;
    foreground = value;
    // Suspending clears the native document. Returning must issue a fresh
    // revision even when the same stream and player widget stayed mounted.
    stopPlayback(notify: false);
    if (!value) {
      _scrolling = false;
      _flagsTimer?.cancel();
      flagsVisible = false;
    } else {
      revealFlags(notify: false);
      unawaited(refresh());
    }
    notifyListeners();
  }

  void setExpanded(bool value) {
    if (!value) stopPlayback(notify: false);
    expanded = value;
    revealFlags(notify: false);
    notifyListeners();
  }

  void revealFlags({bool notify = true}) {
    _flagsTimer?.cancel();
    if (!showVideo || !foreground) return;
    flagsVisible = true;
    if (!_scrolling) {
      _flagsTimer = Timer(const Duration(seconds: 3), () {
        if (_disposed) return;
        flagsVisible = false;
        notifyListeners();
      });
    }
    if (notify) notifyListeners();
  }

  void setScrolling(bool value) {
    _scrolling = value;
    revealFlags();
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    _flagsTimer?.cancel();
    repository?.close();
    super.dispose();
  }
}
