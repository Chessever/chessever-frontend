import 'package:chessever2/repository/sqlite/app_database.dart';

abstract class ScorecardNameCoachmarkStore {
  Future<bool> hasSeen();

  Future<void> markSeen();
}

class AppDatabaseScorecardNameCoachmarkStore
    implements ScorecardNameCoachmarkStore {
  AppDatabaseScorecardNameCoachmarkStore(this._database);

  static const String storageKey = 'player_name_share_coachmark_v1';
  final AppDatabase _database;

  @override
  Future<bool> hasSeen() async => await _database.getBool(storageKey) ?? false;

  @override
  Future<void> markSeen() => _database.setBool(storageKey, true);
}

class ScorecardNameCoachmarkTracker {
  ScorecardNameCoachmarkTracker(this._store);

  final ScorecardNameCoachmarkStore _store;
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
      // Coaching is optional; storage failures must never disrupt a scorecard.
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
      // The coachmark was displayed. Avoid repeating it during this process even
      // if persistence is temporarily unavailable.
    }
  }

  void release() {
    if (!_shownInProcess) _reservedInProcess = false;
  }
}

final playerNameShareCoachmarkTracker = ScorecardNameCoachmarkTracker(
  AppDatabaseScorecardNameCoachmarkStore(AppDatabase.instance),
);

Future<bool> displayScorecardNameCoachmark({
  required ScorecardNameCoachmarkTracker tracker,
  required bool Function() isEligible,
  required bool Function() showTooltip,
}) async {
  final reserved = await tracker.claim();
  if (!reserved) return false;
  if (!isEligible()) {
    tracker.release();
    return false;
  }
  final displayed = showTooltip();
  if (!displayed) {
    tracker.release();
    return false;
  }
  await tracker.markShown();
  return true;
}
