import 'dart:async';

import 'package:chessever2/providers/guest_session_provider.dart';
import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/repository/authentication/model/auth_state.dart';
import 'package:chessever2/services/analytics/analytics_service.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Route argument key read by the auth screen so it can explain *why* the user
/// landed there when the guest window has run out.
const String kForcedGuestUpgradeArg = 'forced_guest_upgrade';

/// Routes that must never be interrupted by an upgrade prompt: the splash
/// screen owns startup routing, and onboarding/auth already present the choice.
const Set<String> _guestGateBlockedRoutes = {
  '/',
  '/auth_screen',
  '/onboarding',
  '/player_selection_screen',
};

/// Tracks the top-most *page* route and whether a modal is on screen.
///
/// [ModalRoute.of] cannot be used from the root navigator's own context (the
/// modal scope is a descendant of `Navigator`, not an ancestor), so the gate
/// reads the current route from this observer instead.
class GuestGateRouteObserver extends NavigatorObserver {
  GuestGateRouteObserver._();

  static final GuestGateRouteObserver instance = GuestGateRouteObserver._();

  /// Name of the visible page route, e.g. `/home_screen`.
  final ValueNotifier<String?> topRouteName = ValueNotifier<String?>(null);

  /// Number of dialogs / bottom sheets currently stacked above the page.
  final ValueNotifier<int> modalDepth = ValueNotifier<int>(0);

  bool get isModalOpen => modalDepth.value > 0;

  bool _isPage(Route<dynamic>? route) => route is PageRoute;

  bool _isModal(Route<dynamic>? route) =>
      route is ModalRoute && route is! PageRoute;

  void _bumpModalDepth(int delta) {
    final next = modalDepth.value + delta;
    modalDepth.value = next < 0 ? 0 : next;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isPage(route)) {
      topRouteName.value = route.settings.name;
    } else if (_isModal(route)) {
      _bumpModalDepth(1);
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (_isPage(newRoute)) {
      topRouteName.value = newRoute!.settings.name;
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isPage(route)) {
      if (_isPage(previousRoute)) {
        topRouteName.value = previousRoute!.settings.name;
      }
    } else if (_isModal(route)) {
      _bumpModalDepth(-1);
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isPage(route)) {
      if (_isPage(previousRoute)) {
        topRouteName.value = previousRoute!.settings.name;
      }
    } else if (_isModal(route)) {
      _bumpModalDepth(-1);
    }
  }
}

/// Sits above [MaterialApp] and owns the whole guest-upgrade policy:
///
/// * day 0-6   — silence; a guest is just a free account.
/// * day 7+    — soft prompt with a "Not now" escape hatch, re-asked weekly.
/// * day 28+   — routed to the auth screen; guest window is over.
///
/// Placed high in the tree on purpose: the decision is global, needs the root
/// navigator, and must survive every screen the guest happens to be on.
class GuestSessionGateListener extends ConsumerStatefulWidget {
  const GuestSessionGateListener({
    required this.child,
    required this.navigatorKey,
    super.key,
  });

  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  ConsumerState<GuestSessionGateListener> createState() =>
      _GuestSessionGateListenerState();
}

class _GuestSessionGateListenerState
    extends ConsumerState<GuestSessionGateListener>
    with WidgetsBindingObserver {
  bool _handlingGate = false;

  /// The ticket asks for the prompt when the user *enters* the app, not every
  /// time they open a screen. So each app entry (launch or resume) arms one
  /// check, which fires at the first moment it is safe to interrupt — never
  /// mid-navigation afterwards.
  bool _entryCheckArmed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    GuestGateRouteObserver.instance.topRouteName.addListener(_scheduleEvaluate);
    GuestGateRouteObserver.instance.modalDepth.addListener(_scheduleEvaluate);
  }

  @override
  void dispose() {
    GuestGateRouteObserver.instance.topRouteName.removeListener(
      _scheduleEvaluate,
    );
    GuestGateRouteObserver.instance.modalDepth.removeListener(
      _scheduleEvaluate,
    );
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // A guest can cross the 7- or 28-day line while the app is backgrounded.
    _entryCheckArmed = true;
    unawaited(ref.read(guestSessionProvider.notifier).refresh());
    _scheduleEvaluate();
  }

  void _scheduleEvaluate() {
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_evaluate()));
  }

  bool get _isGuest {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      return user != null && user.isAnonymous == true;
    } catch (_) {
      // Supabase not initialized (tests, or a failed startup) — never let the
      // gate take down the app shell it wraps.
      return false;
    }
  }

  Future<void> _evaluate() async {
    if (!mounted || _handlingGate || !_entryCheckArmed) return;

    final navigator = widget.navigatorKey.currentState;
    if (navigator == null) return;

    // Not a safe moment yet — hold the armed check and try again on the next
    // route change (splash handing over, a sheet closing, and so on).
    final observer = GuestGateRouteObserver.instance;
    if (observer.isModalOpen) return;

    final routeName = observer.topRouteName.value;
    if (routeName == null || _guestGateBlockedRoutes.contains(routeName)) {
      return;
    }

    if (!_isGuest) {
      _entryCheckArmed = false;
      return;
    }

    final sessionState = ref.read(guestSessionProvider).valueOrNull;
    if (sessionState == null) return; // still reading prefs

    // Legacy anonymous installs (created before guest mode shipped) have no
    // stamp — start their clock now instead of locking them out immediately.
    if (!sessionState.hasGuestClock) {
      _entryCheckArmed = false;
      await ref.read(guestSessionProvider.notifier).startGuestSession();
      return;
    }

    final gate = sessionState.gateAt(DateTime.now());
    // This entry has had its look; anything further waits for the next launch.
    _entryCheckArmed = false;
    if (gate == GuestGate.none) return;

    _handlingGate = true;
    try {
      switch (gate) {
        case GuestGate.softPrompt:
          await _showSoftPrompt(navigator, sessionState);
        case GuestGate.forcedSignUp:
          await _forceSignUp(navigator, sessionState);
        case GuestGate.none:
          break;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[GuestSession] Gate handling failed: $e');
      }
    } finally {
      _handlingGate = false;
    }
  }

  Future<void> _showSoftPrompt(
    NavigatorState navigator,
    GuestSessionState sessionState,
  ) async {
    final overlayContext = navigator.overlay?.context;
    if (overlayContext == null) return;

    // Mark before showing: if the app is killed while the sheet is up we would
    // rather skip a nag than greet them with it on every cold start.
    await ref.read(guestSessionProvider.notifier).markPromptShown();

    final days = sessionState.ageAt(DateTime.now())?.inDays ?? 0;
    AnalyticsService.instance.trackEventDetached(
      'Guest Upgrade Prompt Shown',
      properties: {'guest_days': days, 'forced': false},
    );

    if (!overlayContext.mounted) return;
    final upgraded = await showAuthUpgradeSheet(
      context: overlayContext,
      title: 'Keep your chess,\nwherever you play',
      message:
          '${days == 1 ? '1 day' : '$days days'} as a guest. '
          'A free account keeps it all safe, on every device.',
      dismissLabel: 'Not now',
    );

    if (upgraded) {
      await ref.read(guestSessionProvider.notifier).clearGuestSession();
    }
  }

  Future<void> _forceSignUp(
    NavigatorState navigator,
    GuestSessionState sessionState,
  ) async {
    final days = sessionState.ageAt(DateTime.now())?.inDays ?? 0;
    AnalyticsService.instance.trackEventDetached(
      'Guest Upgrade Forced',
      properties: {'guest_days': days},
    );

    navigator.pushNamedAndRemoveUntil(
      '/auth_screen',
      (route) => false,
      arguments: const {kForcedGuestUpgradeArg: true},
    );
  }

  @override
  Widget build(BuildContext context) {
    // Any of these can change the answer, so all three re-run the evaluation.
    ref.listen<AsyncValue<GuestSessionState>>(
      guestSessionProvider,
      (_, __) => _scheduleEvaluate(),
    );
    ref.listen<AsyncValue<AppAuthState>>(authStateProvider, (_, next) {
      next.whenData((authState) {
        // Upgrading out of guest mode stops the clock for good.
        if (authState.status == AppAuthStatus.authenticated &&
            authState.user?.isAnonymous == false) {
          unawaited(
            ref.read(guestSessionProvider.notifier).clearGuestSession(),
          );
          return;
        }
        _scheduleEvaluate();
      });
    });

    return widget.child;
  }
}
