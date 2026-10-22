import 'dart:async';
import 'dart:math';

import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum BoardTeachingFeature { like, notationSwipe }

abstract class BoardFeatureTeachingStore {
  Future<Map<String, Object?>?> read();
  Future<void> write(Map<String, Object?> value);
}

class AppDatabaseBoardFeatureTeachingStore
    implements BoardFeatureTeachingStore {
  static const storageKey = 'board_feature_teaching_v1';

  @override
  Future<Map<String, Object?>?> read() async {
    final stored = await AppDatabase.instance.getJson<Object>(storageKey);
    if (stored is Map) {
      return stored.map((key, value) => MapEntry(key.toString(), value));
    }

    // Preserve opt-outs and exposure dates from the removed teaching chain.
    // An unavailable legacy store must not look like a fresh installation.
    final prefs = await SharedPreferencesService.instance.ensureInitialized();
    if (prefs == null) throw StateError('Teaching preferences unavailable');
    return progressFromLegacy(prefs);
  }

  static Map<String, Object?> progressFromLegacy(SharedPreferences prefs) {
    final features = <String, Object?>{};
    var lastShown = 0;
    for (final feature in BoardTeachingFeature.values) {
      final prefix = feature == BoardTeachingFeature.like
          ? 'like_walkthrough'
          : 'explorer_panel_walkthrough';
      final shown = prefs.getInt('${prefix}_shown_date') ?? 0;
      lastShown = max(lastShown, shown);
      features[feature.name] = <String, Object?>{
        'disabled': prefs.getBool('${prefix}_dont_show') ?? false,
        'shown': shown > 0 ? 1 : 0,
        'lastShown': shown,
      };
    }
    lastShown = max(
      lastShown,
      prefs.getInt('swipable_walkthrough_shown_date') ?? 0,
    );
    return {'features': features, 'lastShown': lastShown};
  }

  @override
  Future<void> write(Map<String, Object?> value) =>
      AppDatabase.instance.setJson(storageKey, value);
}

/// Device-local lessons, paced by visits rather than a coin toss on rebuild.
/// A target is drawn once and persisted: first on visits 3–5, then 4–7 visits
/// later. There is at most one prompt per visit, a shared seven-day cooldown,
/// fourteen days before repeating a lesson, and two exposures per feature.
class BoardFeatureTeachingTracker {
  BoardFeatureTeachingTracker(
    this._store, {
    Random? random,
    DateTime Function()? now,
  }) : _random = random ?? Random(),
       _now = now ?? DateTime.now;

  static const globalCooldown = Duration(days: 7);
  static const featureCooldown = Duration(days: 14);
  static const maxExposures = 2;

  final BoardFeatureTeachingStore _store;
  final Random _random;
  final DateTime Function() _now;
  Future<void>? _queue;
  Map<String, Object?>? _progress;

  Future<T> _serialised<T>(T fallback, Future<T> Function() action) {
    final result = Completer<T>();
    _queue = (_queue ?? Future<void>.value()).then((_) async {
      try {
        result.complete(await action());
      } catch (_) {
        // Optional education never blocks a board, gesture, or saved like.
        result.complete(fallback);
      }
    });
    return result.future;
  }

  int _number(Map record, String key) =>
      (record[key] is num ? (record[key] as num).toInt() : 0).clamp(0, 1 << 53);

  Future<Map<String, Object?>> _load() async {
    if (_progress != null) return _progress!;
    final value = await _store.read() ?? <String, Object?>{};
    final rawFeatures = value['features'];
    final features = <String, Object?>{};
    for (final feature in BoardTeachingFeature.values) {
      final raw = rawFeatures is Map ? rawFeatures[feature.name] : null;
      final record = raw is Map
          ? raw.map((key, value) => MapEntry(key.toString(), value))
          : <String, Object?>{};
      if (_number(record, 'nextVisit') == 0) {
        record['nextVisit'] = 3 + _random.nextInt(3);
      }
      features[feature.name] = record;
    }
    value['features'] = features;
    return _progress = value;
  }

  Map<String, Object?> _feature(
    Map<String, Object?> progress,
    BoardTeachingFeature feature,
  ) =>
      (progress['features'] as Map<String, Object?>)[feature.name]
          as Map<String, Object?>;

  bool _cooldownElapsed(Map record, String key, Duration cooldown) {
    final last = _number(record, key);
    return last == 0 ||
        _now().millisecondsSinceEpoch - last >= cooldown.inMilliseconds;
  }

  Future<int> beginVisit() => _serialised(0, () async {
    final progress = await _load();
    final visit = _number(progress, 'visits') + 1;
    progress['visits'] = visit;
    await _store.write(progress);
    return visit;
  });

  /// [show] rechecks the live UI synchronously. Failed/deferred presentation
  /// consumes neither an exposure nor a visit target. Serialisation prevents
  /// nested boards and concurrent learned events from racing a presentation.
  Future<bool> tryShow({
    required int visit,
    required Set<BoardTeachingFeature> eligible,
    required bool Function(BoardTeachingFeature feature) show,
  }) => _serialised(false, () async {
    if (visit < 2 || eligible.isEmpty) return false;
    final progress = await _load();
    if (_number(progress, 'lastPromptVisit') >= visit ||
        !_cooldownElapsed(progress, 'lastShown', globalCooldown)) {
      return false;
    }
    final candidates = eligible.where((feature) {
      final record = _feature(progress, feature);
      return record['learned'] != true &&
          record['disabled'] != true &&
          _number(record, 'shown') < maxExposures &&
          visit >= _number(record, 'nextVisit') &&
          _cooldownElapsed(record, 'lastShown', featureCooldown);
    }).toList();
    if (candidates.isEmpty) return false;
    // Teach both undiscovered features before reinforcing either one.
    final fewest = candidates
        .map((f) => _number(_feature(progress, f), 'shown'))
        .reduce(min);
    candidates.removeWhere(
      (f) => _number(_feature(progress, f), 'shown') > fewest,
    );
    final feature = candidates[_random.nextInt(candidates.length)];
    if (!show(feature)) return false;
    final record = _feature(progress, feature);
    record['shown'] = _number(record, 'shown') + 1;
    record['lastShown'] = _now().millisecondsSinceEpoch;
    record['nextVisit'] = visit + 4 + _random.nextInt(4);
    progress['lastShown'] = record['lastShown'];
    progress['lastPromptVisit'] = visit;
    // Keep the in-memory cap even if persistence fails after presentation.
    await _store.write(progress);
    return true;
  });

  Future<void> markLearned(BoardTeachingFeature feature) =>
      _setFlag(feature, 'learned');

  Future<void> disable(BoardTeachingFeature feature) =>
      _setFlag(feature, 'disabled');

  Future<void> _setFlag(BoardTeachingFeature feature, String flag) =>
      _serialised<void>(null, () async {
        final progress = await _load();
        final record = _feature(progress, feature);
        if (record[flag] == true) return;
        record[flag] = true;
        await _store.write(progress);
      });

  /// The first board opened from Discovery Likes is a specific once-only
  /// introduction, not the visit-paced reminder. Reuse the local progress and
  /// interruption budget, while preserving existing opt-outs/learned gestures.
  Future<bool> tryShowDiscoveryLikes(bool Function() show) =>
      _serialised(false, () async {
        final progress = await _load();
        final record = _feature(progress, BoardTeachingFeature.like);
        if (progress['discoveryLikesIntroduced'] == true ||
            record['disabled'] == true ||
            record['learned'] == true ||
            !show()) {
          return false;
        }
        progress['discoveryLikesIntroduced'] = true;
        progress['lastShown'] = _now().millisecondsSinceEpoch;
        progress['lastPromptVisit'] = _number(progress, 'visits');
        await _store.write(progress);
        return true;
      });

  /// Existing Swipe/Pinch teachings also buy a quiet week for these lessons.
  Future<void> recordOtherTeaching() => _serialised<void>(null, () async {
    final progress = await _load();
    progress['lastShown'] = _now().millisecondsSinceEpoch;
    progress['lastPromptVisit'] = _number(progress, 'visits');
    await _store.write(progress);
  });

  /// The contextual end-of-game like nudge shares the same interruption budget.
  Future<bool> tryShowLikeReminder(bool Function() show) =>
      _serialised(false, () async {
        final progress = await _load();
        final visit = _number(progress, 'visits');
        if (visit < 2 ||
            _number(progress, 'lastPromptVisit') >= visit ||
            !_cooldownElapsed(progress, 'lastShown', globalCooldown) ||
            !show()) {
          return false;
        }
        progress['lastShown'] = _now().millisecondsSinceEpoch;
        progress['lastPromptVisit'] = visit;
        await _store.write(progress);
        return true;
      });
}

final boardFeatureTeachingTrackerProvider =
    Provider<BoardFeatureTeachingTracker>(
      (_) =>
          BoardFeatureTeachingTracker(AppDatabaseBoardFeatureTeachingStore()),
    );
