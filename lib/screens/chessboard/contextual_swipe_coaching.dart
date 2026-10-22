import 'package:flutter/widgets.dart';

import '../../repository/local_storage/local_storage_repository.dart';

const swipeCoachingDisabledKey = 'swipable_walkthrough_dont_show';
const swipeCoachingLearnedKey = 'swipable_walkthrough_learned';
// Deliberately do not migrate the old seen-once timestamp into a daily cap.
const swipeCoachingDayKey = 'contextual_swipe_coaching_local_day';

final contextualSwipeCoaching = ContextualSwipeCoaching();

/// A visit belongs to an explicit card tap, never to a board page build/preload.
class SwipeCoachingVisit {
  SwipeCoachingVisit(this.gameId, this.eligible);
  final String gameId;
  final bool eligible;
  bool active = true;
}

/// Observes the actual navigation stack so only Back to the original list
/// advances the sequence. Any intervening navigation cancels it.
class ContextualSwipeCoaching extends NavigatorObserver {
  Object? _list;
  final Set<String> _games = {};
  Route<dynamic>? _board;
  Route<dynamic>? _caller;
  SwipeCoachingVisit? _visit;
  bool _returned = false;
  bool _claiming = false;
  bool _disabled = false;
  String? _shownDay;

  SwipeCoachingVisit begin({
    required Route<dynamic> board,
    required Route<dynamic>? caller,
    required Object listIdentity,
    required String gameId,
  }) {
    if (!_returned || _list != listIdentity) _games.clear();
    _list = listIdentity;
    _returned = false;
    _games.add(gameId);
    _board = board;
    _caller = caller;
    return _visit = SwipeCoachingVisit(gameId, _games.length == 3);
  }

  void _cancel() {
    _visit?.active = false;
    _visit = null;
    _board = null;
    _caller = null;
    _list = null;
    _games.clear();
    _returned = false;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route != _board || previousRoute != _caller) _cancel();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route == _board && previousRoute == _caller) {
      if (_visit?.eligible == true) _games.clear();
      _visit?.active = false;
      _returned = true;
      _board = null;
      _visit = null;
    } else {
      _cancel();
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _cancel();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _cancel();

  String _day(DateTime now) {
    final local = now.toLocal();
    return '${local.year}-${local.month}-${local.day}';
  }

  /// Fail closed when persistence is unavailable. Recheck route readiness after
  /// asynchronous storage access, before reserving the local calendar day.
  Future<bool> claim(
    SwipeCoachingVisit? visit, {
    required bool Function() ready,
    DateTime? now,
  }) async {
    if (_claiming ||
        _disabled ||
        visit == null ||
        !visit.eligible ||
        !visit.active ||
        !identical(visit, _visit) ||
        !ready()) {
      return false;
    }
    _claiming = true;
    try {
      final prefs = await SharedPreferencesService.instance.ensureInitialized();
      if (prefs == null) return false;
      if (prefs.getBool(swipeCoachingDisabledKey) == true ||
          prefs.getBool(swipeCoachingLearnedKey) == true) {
        _disabled = true;
        return false;
      }
      final day = _day(now ?? DateTime.now());
      if (_shownDay == day ||
          prefs.getString(swipeCoachingDayKey) == day ||
          !visit.active ||
          !identical(visit, _visit) ||
          !ready()) {
        return false;
      }
      // Reserve in memory too, including concurrent routes and failed writes.
      _shownDay = day;
      if (!await prefs.setString(swipeCoachingDayKey, day)) return false;
      return !_disabled && visit.active && identical(visit, _visit) && ready();
    } catch (_) {
      return false;
    } finally {
      _claiming = false;
    }
  }

  Future<void> disable({bool learned = false}) async {
    _disabled = true;
    _cancel();
    try {
      final prefs = await SharedPreferencesService.instance.ensureInitialized();
      await prefs?.setBool(
        learned ? swipeCoachingLearnedKey : swipeCoachingDisabledKey,
        true,
      );
    } catch (_) {
      // Retain the in-memory stop even if the device store is unavailable.
    }
  }
}

/// Records only a settled, successful user drag on the games pager. Neither
/// dropdown jumps nor the tutorial's jumpTo animation supplies dragDetails.
class SwipeLearningGesture {
  String? _start;
  bool _dragged = false;

  void reset() {
    _start = null;
    _dragged = false;
  }

  bool observe(ScrollNotification notification, String page) {
    if (notification.depth != 0 ||
        notification.metrics.axis != Axis.horizontal) {
      return false;
    }
    if (notification is ScrollStartNotification) {
      _start = page;
      _dragged = notification.dragDetails != null;
    } else if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      _start ??= page;
      _dragged = true;
    } else if (notification is ScrollEndNotification) {
      final learned = _dragged && _start != null && _start != page;
      _start = null;
      _dragged = false;
      return learned;
    }
    return false;
  }
}
