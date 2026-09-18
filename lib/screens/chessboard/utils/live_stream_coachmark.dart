import 'package:chessever2/repository/sqlite/app_database.dart';

abstract class LiveStreamCoachmarkStore {
  Future<bool> hasSeen();

  Future<void> markSeen();
}

class AppDatabaseLiveStreamCoachmarkStore implements LiveStreamCoachmarkStore {
  AppDatabaseLiveStreamCoachmarkStore(this._database);

  static const String storageKey = 'live_stream_toggle_coachmark_v1';
  final AppDatabase _database;

  @override
  Future<bool> hasSeen() async => await _database.getBool(storageKey) ?? false;

  @override
  Future<void> markSeen() => _database.setBool(storageKey, true);
}

/// Ensures the live-stream camera coachmark is claimed by at most one board
/// page and is never shown again after its first successful display.
class LiveStreamCoachmarkTracker {
  LiveStreamCoachmarkTracker(this._store);

  final LiveStreamCoachmarkStore _store;
  bool _reservedInProcess = false;
  bool _shownInProcess = false;

  Future<bool> claim() async {
    if (_reservedInProcess || _shownInProcess) return false;
    _reservedInProcess = true;
    try {
      if (await _store.hasSeen()) {
        _reservedInProcess = false;
        _shownInProcess = true;
        return false;
      }
      return true;
    } catch (_) {
      _reservedInProcess = false;
      // An optional hint must never disrupt the board if storage is unavailable.
      return false;
    }
  }

  Future<void> markShown() async {
    if (!_reservedInProcess || _shownInProcess) return;
    _reservedInProcess = false;
    _shownInProcess = true;
    try {
      await _store.markSeen();
    } catch (_) {
      // Still suppress repeats for this process after a successful display.
    }
  }

  void release() {
    if (!_shownInProcess) _reservedInProcess = false;
  }
}

final liveStreamCoachmarkTracker = LiveStreamCoachmarkTracker(
  AppDatabaseLiveStreamCoachmarkStore(AppDatabase.instance),
);
