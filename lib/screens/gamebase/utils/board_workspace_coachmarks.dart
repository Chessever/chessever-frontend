import 'package:chessever2/repository/local_storage/local_storage_repository.dart';

abstract class BoardWorkspaceCoachmarkStore {
  Future<bool> hasSeen();

  Future<void> markSeen();
}

class PreferencesBoardWorkspaceCoachmarkStore
    implements BoardWorkspaceCoachmarkStore {
  PreferencesBoardWorkspaceCoachmarkStore(this._preferences, this.storageKey);

  final AppSharedPreferences _preferences;
  final String storageKey;

  @override
  Future<bool> hasSeen() async =>
      await _preferences.getBool(storageKey) ?? false;

  @override
  Future<void> markSeen() => _preferences.setBool(storageKey, true);
}

class BoardWorkspaceCoachmarkTracker {
  BoardWorkspaceCoachmarkTracker(this._store);

  final BoardWorkspaceCoachmarkStore _store;
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
      // Coaching is optional and must never block the Board workspace.
    }
  }

  void release() {
    if (!_shownInProcess) _reservedInProcess = false;
  }
}

final boardWorkspaceViewsCoachmarkTracker = BoardWorkspaceCoachmarkTracker(
  PreferencesBoardWorkspaceCoachmarkStore(
    AppSharedPreferences(),
    'board_workspace_views_coachmark_v1',
  ),
);

final boardWorkspaceEditorCoachmarkTracker = BoardWorkspaceCoachmarkTracker(
  PreferencesBoardWorkspaceCoachmarkStore(
    AppSharedPreferences(),
    'board_workspace_editor_coachmark_v1',
  ),
);

Future<bool> _displayCoachmark({
  required BoardWorkspaceCoachmarkTracker tracker,
  required bool Function() isEligible,
  required bool Function() show,
}) async {
  final reserved = await tracker.claim();
  if (!reserved) return false;
  if (!isEligible()) {
    tracker.release();
    return false;
  }
  final displayed = show();
  if (!displayed) {
    tracker.release();
    return false;
  }
  await tracker.markShown();
  return true;
}

Future<void> showBoardWorkspaceCoachmarks({
  required BoardWorkspaceCoachmarkTracker viewsTracker,
  required BoardWorkspaceCoachmarkTracker editorTracker,
  required bool Function() isEligible,
  required bool Function() showViews,
  required bool Function() showEditor,
  Duration pauseBetween = const Duration(seconds: 5),
}) async {
  final showedViews = await _displayCoachmark(
    tracker: viewsTracker,
    isEligible: isEligible,
    show: showViews,
  );
  if (showedViews && pauseBetween > Duration.zero) {
    // Keep onboarding lightweight: the first Board visit teaches the two
    // views; the next visit teaches Editor. Tests can pass Duration.zero to
    // verify the complete ordered sequence without timers.
    return;
  }
  await _displayCoachmark(
    tracker: editorTracker,
    isEligible: isEligible,
    show: showEditor,
  );
}
