import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'live_stream_coachmark.dart';

final streamScrollCoachingProvider = ChangeNotifierProvider.autoDispose
    .family<StreamScrollCoachingController, String>((ref, gameId) {
      return StreamScrollCoachingController(
        AppDatabaseLiveStreamCoachmarkStore(
          AppDatabase.instance,
          key: 'board_stream_scroll_dont_show_v1',
        ),
      );
    });

/// A visit is one active game page, not one lifetime of a preloaded page.
class StreamScrollCoachingController extends ChangeNotifier {
  StreamScrollCoachingController(this.store);
  final LiveStreamCoachmarkStore store;
  bool showing = false;
  bool pulsing = false;
  bool _active = false, _disposed = false, _shown = false;
  bool _userGesture = false;
  int _downwardGestures = 0, _generation = 0;
  double _distance = 0;
  Timer? _pulseTimer;

  void setActive(bool active) {
    if (_active == active) return;
    _active = active;
    _generation++;
    _downwardGestures = 0;
    _shown = false;
    _userGesture = false;
    if (!active) dismiss();
  }

  void startGesture({required bool userDriven}) {
    _userGesture = _active && userDriven;
    _distance = 0;
  }

  void updateGesture(double delta) {
    if (_userGesture) _distance += delta;
  }

  Future<void> endGesture({
    bool allowed = true,
    bool Function()? stillAllowed,
  }) async {
    final counts = _userGesture && _distance >= 24;
    _userGesture = false;
    if (!counts || !_active || _shown || !allowed) return;
    if (++_downwardGestures < 2) return;
    _shown = true;
    final generation = _generation;
    try {
      if (await store.hasSeen()) return;
    } catch (_) {
      return;
    } // Optional guidance must fail closed.
    if (_disposed ||
        !_active ||
        generation != _generation ||
        !(stillAllowed?.call() ?? true)) {
      return;
    }
    showing = true;
    _pulse(const Duration(milliseconds: 2500));
  }

  void _pulse(Duration duration) {
    _pulseTimer?.cancel();
    pulsing = true;
    notifyListeners();
    _pulseTimer = Timer(duration, () {
      pulsing = false;
      notifyListeners();
    });
  }

  void acknowledge() {
    showing = false;
    _pulse(const Duration(seconds: 2));
  }

  Future<void> disable() async {
    dismiss();
    try {
      await store.markSeen();
    } catch (_) {
      /* Session remains suppressed. */
    }
  }

  void dismiss({bool notify = true}) {
    _pulseTimer?.cancel();
    showing = false;
    pulsing = false;
    if (!_disposed && notify) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _pulseTimer?.cancel();
    super.dispose();
  }
}
