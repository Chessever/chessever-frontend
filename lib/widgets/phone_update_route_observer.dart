import 'package:flutter/material.dart';

/// A conservative allowlist: unnamed pages (boards, games, editors, Watch,
/// puzzles) and all modals defer reminders. Track the actual stack so removing
/// a covered route cannot accidentally declare an active game safe.
class PhoneUpdateRouteObserver extends NavigatorObserver {
  PhoneUpdateRouteObserver() {
    homeSectionSafe.addListener(_publish);
  }

  static const homeRoute = '/home_screen';

  static const safeRoutes = {
    homeRoute,
    '/group_event_screen',
    '/calendar_screen',
    '/library_screen',
    '/favorites_screen',
    '/player_list_screen',
  };

  /// Whether the section [homeRoute] shows is a page to browse. Home's route
  /// holds every bottom-bar section, and Botvinnik, Feed and Search were
  /// unnamed pages (so deferred) before they became tabs: a chat, a clip
  /// playing or a query being typed must still not be interrupted. The bar's
  /// selection keeps this current; true when nothing has set it.
  static final homeSectionSafe = ValueNotifier<bool>(true);

  final safeToPrompt = ValueNotifier<bool>(false);
  final List<Route<dynamic>> _routes = [];

  bool get isSafe {
    if (_routes.isEmpty || navigator?.userGestureInProgress == true) {
      return false;
    }
    final top = _routes.last;
    final name = top.settings.name;
    return top is PageRoute &&
        safeRoutes.contains(name) &&
        (name != homeRoute || homeSectionSafe.value) &&
        !top.willHandlePopInternally &&
        top.animation?.status == AnimationStatus.completed;
  }

  /// Stops following [homeSectionSafe]. The app's observer lives as long as
  /// the app; this is for observers made and dropped, as in tests.
  void dispose() => homeSectionSafe.removeListener(_publish);

  void _publish([AnimationStatus? _]) => safeToPrompt.value = isSafe;

  void _track(Route<dynamic> route) {
    if (route is! ModalRoute) return;
    if (route.animation == null) {
      // didReplace can run before the incoming page has been installed.
      // Null is not a safe/completed transition; attach once it is installed.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_routes.contains(route)) return;
        route.animation?.addStatusListener(_publish);
        _publish();
      });
    } else {
      route.animation!.addStatusListener(_publish);
    }
  }

  void _untrack(Route<dynamic> route) {
    if (route is ModalRoute) route.animation?.removeStatusListener(_publish);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _track(route);
    _publish();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _untrack(route);
    _publish();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _untrack(route);
    _publish();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (oldRoute != null) _untrack(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    } else if (newRoute != null) {
      _routes.add(newRoute);
    }
    if (newRoute != null) _track(newRoute);
    _publish();
  }

  @override
  void didStartUserGesture(
    Route<dynamic> route,
    Route<dynamic>? previousRoute,
  ) {
    safeToPrompt.value = false;
  }

  @override
  void didStopUserGesture() => _publish();
}
