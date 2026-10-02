import 'package:flutter/material.dart';

/// Keeps suspended premium routes alive (and their drafts intact), but requires
/// a new grant before the user can return to them from the free screen.
class RewardedNavigationObserver extends NavigatorObserver {
  static final instance = RewardedNavigationObserver();
  final changes = ValueNotifier<int>(0);
  final List<Route<dynamic>> _pages = [];
  final Set<Route<dynamic>> _suspended = {};
  bool get returningToSuspended =>
      _pages.isNotEmpty && _suspended.contains(_pages.last);

  void suspendCurrent() {
    if (_pages.isNotEmpty) _suspended.add(_pages.last);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) {
      _pages.add(route);
      changes.value++;
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _pages.remove(route);
    _suspended.remove(route);
    changes.value++;
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _pages.remove(route);
    _suspended.remove(route);
    changes.value++;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _pages.indexOf(oldRoute);
    if (index >= 0) {
      _pages.removeAt(index);
      if (newRoute is PageRoute) _pages.insert(index, newRoute);
    }
    _suspended.remove(oldRoute);
    changes.value++;
  }
}
