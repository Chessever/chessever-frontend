import 'dart:async';
import 'dart:io';
import 'package:chessever2/chat/chat_api.dart';
import 'package:chessever2/chat/chat_screen.dart';
import 'package:chessever2/e2e/e2e_config.dart';
import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/screens/collections/collections_screen.dart';
import 'package:chessever2/screens/feed/feed_screen.dart';
import 'package:chessever2/screens/inbox/inbox_provider.dart';
import 'package:chessever2/screens/my_profile/profile_hub_screen.dart';
import 'package:chessever2/screens/my_space/widgets/space_add_fab.dart';
import 'package:chessever2/screens/my_prep/prep_profiles_cloud.dart';
import 'package:chessever2/screens/my_prep/prep_space_shortcut.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart'
    show prepKeepFreshProvider;
import 'package:chessever2/screens/for_you/for_you_screen.dart';
import 'package:chessever2/screens/for_you/providers/for_you_tab_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/screens/search/search_tab_screen.dart'
    show keepSearchLandingWarm;
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:chessever2/widgets/paywall/billing_issue_sheet.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:chessever2/widgets/shorebird_update_dialog.dart';
import 'package:chessever2/services/att_prompt_service.dart';
import 'package:chessever2/services/review_prompt_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import 'package:chessever2/services/deep_link_service.dart';
import 'widget/bottom_nav_bar.dart';
import 'widget/home_nav_dock.dart';
import 'widget/tablet_nav_rail.dart';

/// A launch opens on For You › Today. The For You page memory must not carry
/// a stored My Space or Discovery into a cold start, so Home drops it before
/// For You first reads it. Within a session nothing changes: the page
/// controller is already alive and keeps the user's page.
///
/// The prefs cache is normally warm by the time Home mounts (auth storage
/// opens it at startup), so the key is gone synchronously. When it is not,
/// the removal is queued on the same initialisation the controller waits on,
/// ahead of it.
@visibleForTesting
void forgetForYouPageForLaunch() {
  final service = SharedPreferencesService.instance;
  final prefs = service.prefsOrNull;
  if (prefs != null) {
    unawaited(prefs.remove(forYouLastTabPrefsKey));
    return;
  }
  unawaited(
    service.ensureInitialized().then(
      (prefs) => prefs?.remove(forYouLastTabPrefsKey),
    ),
  );
}

/// Test seam: a page to stand in for each dock section. Null in the app,
/// where the sections are the real screens, which read the network. Tests
/// that drive the shell itself (its dock and rail, the held-link drain, the
/// dock reveal a link asks for) stand their own pages in here.
@visibleForTesting
final homeSectionPageOverrideProvider =
    Provider<Widget Function(BottomNavBarItem item)?>((ref) => null);

/// The app's home: five sections over one dock (Home, Feed, Botvinnik,
/// Collections, Profile). There is no sidebar; what it held lives on
/// Profile. Search is a page of its own, opened from Today's floating
/// button.
///
/// Every section wears the same top bar ([HomeTopBarFrame]): one inset, one
/// height, one gutter, one centre line, and the page under it starting at
/// the same line ([HomeTopBarMetrics.headerExtent]). On a phone the sections
/// run under a frosted dock ([HomeNavDock]): as the reader scrolls down a
/// list the top bar steps away and the dock leaves whole, sliding past the
/// screen's edge and fading out, on one value; scrolling back up brings both
/// back, at the pace the reader's own scroll sets (the chrome's spring takes
/// its speed). The floating buttons ride down to where a page with no dock
/// stands them, and back. Feed's follow the posts a page at a time
/// ([ScrollChromeRegion]). Botvinnik is a conversation with its composer
/// under it: its bars stay.
///
/// Android's back on a section first brings hidden bars back, then goes to
/// Home, and only on Home with its bars in view closes the app.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
  /// Carries the open section across the phone and tablet shells. iPhone Duo
  /// switches between them as it closes and opens; without a global key the
  /// section's whole subtree (its tab, scroll position, search text) was
  /// rebuilt from scratch on every fold.
  final GlobalKey _sectionKey = GlobalKey(debugLabel: 'home-section');
  static const int _favoritePromptThreshold = 5;

  /// Each section's own chrome state: Collections can sit with its tabs
  /// scrolled away while Home's strip is in view.
  final Map<BottomNavBarItem, ScrollChromeController> _chromes = {};

  ScrollChromeController _chromeFor(BottomNavBarItem item) =>
      _chromes.putIfAbsent(item, () => ScrollChromeController(vsync: this));

  @override
  void initState() {
    super.initState();
    forgetForYouPageForLaunch();
    // The Collections mark is not in the app's SVG warm-up: read it now, so
    // the dock never shows an empty slot while it loads.
    final loader = const SvgAssetLoader(collectionsNavIcon);
    svg.cache.putIfAbsent(loader.cacheKey(null), () => loader.loadBytes(null));
    if (!E2eConfig.suppressInterruptivePrompts) {
      unawaited(ReviewPromptService.instance.incrementSessionCount());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // A link or push that arrived while the reader was signing in or
      // onboarding was held for Home: open it now that Home is up.
      if (mounted) DeepLinkService.instance.drainPendingDestination();
      // A start section that is not on the bar (Botvinnik saved as the start
      // screen, then switched off) opens Home instead of nothing selected.
      if (mounted &&
          !ref
              .read(visibleBottomNavItemsProvider)
              .contains(ref.read(selectedBottomNavBarItemProvider))) {
        ref.read(selectedBottomNavBarItemProvider.notifier).state =
            BottomNavBarItem.forYou;
      }
      _checkForShorebirdUpdate();
      // Safety net: fire system ATT dialog without explainer sheet for users
      // already past onboarding. Onboarding triggers it with the sheet.
      if (mounted) {
        AttPromptService.instance.ensurePrompted(context, showExplainer: false);
      }
      if (!E2eConfig.suppressInterruptivePrompts) {
        Future.delayed(const Duration(seconds: 8), () {
          if (!mounted) return;
          // A notification or link that opened a page over Home in these
          // eight seconds owns the screen: never ask for a rating over it.
          if (ModalRoute.of(context)?.isCurrent == false) return;
          unawaited(
            ReviewPromptService.instance.maybePrompt(
              context: context,
              trigger: ReviewPromptTrigger.session,
              skipSurveyForHighRating: true,
            ),
          );
        });
      }
    });
  }

  /// The route the shell stands on, for pages over it that go back to one
  /// of its sections ([openHomeSection]).
  ModalRoute<Object?>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (!identical(route, _route)) {
      unregisterHomeShellRoute(_route);
      _route = route;
    }
    registerHomeShellRoute(route);
  }

  @override
  void dispose() {
    unregisterHomeShellRoute(_route);
    for (final chrome in _chromes.values) {
      chrome.dispose();
    }
    super.dispose();
  }

  Future<void> _checkForShorebirdUpdate() async {
    // Skip update check in Debug Mode
    if (kDebugMode) return;

    // Shorebird is only supported on Android and iOS
    if (!(Platform.isAndroid || Platform.isIOS)) return;

    try {
      final updater = ShorebirdUpdater();
      final status = await updater.checkForUpdate();

      if (status == UpdateStatus.outdated ||
          status == UpdateStatus.restartRequired) {
        if (mounted) {
          unawaited(
            showAlertModal<void>(
              context: context,
              barrierDismissible: false,
              child: ShorebirdUpdateDialog(initialStatus: status),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Shorebird update check failed: $e');
    }
  }

  void _listenForFavoriteSignals() {
    if (E2eConfig.suppressInterruptivePrompts) {
      return;
    }

    ref.listen<AsyncValue<List<FavoriteEvent>>>(favoriteEventsProvider, (
      previous,
      next,
    ) {
      final prevCount = previous?.valueOrNull?.length ?? 0;
      final nextCount = next.valueOrNull?.length ?? 0;
      if (prevCount < _favoritePromptThreshold &&
          nextCount >= _favoritePromptThreshold) {
        if (!mounted) return;
        unawaited(
          ReviewPromptService.instance.maybePrompt(
            context: context,
            trigger: ReviewPromptTrigger.favoriteEvent,
            skipSurveyForHighRating: true,
          ),
        );
      }
    });

    ref.listen<AsyncValue<List<FavoritePlayer>>>(favoritePlayersProviderNew, (
      previous,
      next,
    ) {
      final prevCount = previous?.valueOrNull?.length ?? 0;
      final nextCount = next.valueOrNull?.length ?? 0;
      if (prevCount < _favoritePromptThreshold &&
          nextCount >= _favoritePromptThreshold) {
        if (!mounted) return;
        unawaited(
          ReviewPromptService.instance.maybePrompt(
            context: context,
            trigger: ReviewPromptTrigger.favoritePlayer,
            skipSurveyForHighRating: true,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Listen for favorite signals (must be in build method)
    _listenForFavoriteSignals();
    // My Prep players' new games arrive while the app is open.
    ref.watch(prepKeepFreshProvider);
    // Prep cards in My Space open on every device of the reader.
    ref.watch(prepSpaceSyncProvider);
    // Prep profiles in step with the reader's other devices and desktop.
    ref.watch(prepCloudSyncProvider);
    // Start account-scoped Inbox sync early: the Profile tab wears its dot.
    ref.watch(inboxHasUnreadProvider);
    // Once Search has been opened (Today's button), its landing stays read
    // between visits, as the dock's Search tab kept it.
    keepSearchLandingWarm(ref);

    // A new section opens with its bars in view, from its first frame: the
    // bottom bar follows the section's own chrome, and one left away there
    // must not blink out under the finger that just tapped it and spring
    // back. Botvinnik switched off in Settings while its tab was open hands
    // the reader back to Home.
    ref.listen<BottomNavBarItem>(selectedBottomNavBarItemProvider, (_, next) {
      _chromeFor(next).show(animate: false);
      FocusManager.instance.primaryFocus?.unfocus();
    });
    // A link or push that lands on the section already open changes no
    // section, so it asks for the bars by itself: the reader must never
    // arrive on Home with its dock scrolled away. It asks too when it opens
    // a page over Home, so Back from that page finds the bars, and the
    // list's coast stops where it is (as a tap on it would): left running,
    // it paused under the page and ran on once Back closed it, moving the
    // list and sending the bars away again.
    ref.listen<int>(homeChromeRevealRequestProvider, (_, _) {
      _chromeFor(ref.read(selectedBottomNavBarItemProvider)).showAndHold();
    });
    ref.listen<List<BottomNavBarItem>>(visibleBottomNavItemsProvider, (
      _,
      items,
    ) {
      final selected = ref.read(selectedBottomNavBarItemProvider);
      if (!items.contains(selected)) {
        ref.read(selectedBottomNavBarItemProvider.notifier).state =
            BottomNavBarItem.forYou;
      }
    });
    final section = ref.watch(selectedBottomNavBarItemProvider);
    final chrome = _chromeFor(section);

    final body = BillingIssueGate(
      child: KeyedSubtree(
        key: e2eKey(E2eIds.homeRoot),
        child: KeyedSubtree(
          key: _sectionKey,
          child: BottomNavBarView(chromeFor: _chromeFor),
        ),
      ),
    );

    // Tablet layout: NavigationRail on the side
    if (ResponsiveHelper.isTablet) {
      return _backOnSection(
        section: section,
        chrome: chrome,
        child: Scaffold(
          resizeToAvoidBottomInset: section == BottomNavBarItem.botvinnik,
          floatingActionButton: SlidingFabs(
            controller: chrome,
            child: const _HomeFab(),
          ),
          body: Row(
            children: [
              const TabletNavRail(),
              // Vertical divider
              Container(width: 1, color: context.colors.divider),
              // Main content
              Expanded(child: body),
            ],
          ),
        ),
      );
    }

    // Phone layout: the dock. Every section but Botvinnik runs under it
    // ([Scaffold.extendBody]): its lists pad their end by the dock's slot
    // ([MediaQuery.paddingOf]) and scroll on under the frosted capsule. The
    // slot keeps one height whether the capsule is there or not, so the
    // capsule leaving and coming back never lays the page out again (a
    // list's last row clears it when it is shown, and nothing jumps).
    //
    // Botvinnik's composer rides the keyboard: the shell lifts the page
    // over it (the keyboard covers the dock anyway), and the chat page does
    // not lift itself again. Its page stops above the dock, so the
    // conversation's own drawer never runs under the capsule.
    final items = ref.watch(visibleBottomNavItemsProvider);
    final metrics = HomeNavMetrics.of(context, count: items.length);
    final underDock = section != BottomNavBarItem.botvinnik;
    return _backOnSection(
      section: section,
      chrome: chrome,
      child: Scaffold(
        resizeToAvoidBottomInset: section == BottomNavBarItem.botvinnik,
        extendBody: underDock,
        // The buttons leave with the dock and come back with it: they slide
        // off and fade on the same spring and the same speed (PM,
        // 2026-11-21), resting above the dock's slot while it is shown.
        floatingActionButton: SlidingFabs(
          controller: chrome,
          child: const _HomeFab(),
        ),
        bottomNavigationBar: HomeNavDock(
          chrome: chrome,
          // Feed lays its own deck under the dock.
          scrim: underDock && section != BottomNavBarItem.feed,
        ),
        body: HomeNavScope(metrics: metrics, child: body),
      ),
    );
  }

  /// Android's back (and the predictive back gesture) on a section: see
  /// [HomeBackScope].
  Widget _backOnSection({
    required BottomNavBarItem section,
    required ScrollChromeController chrome,
    required Widget child,
  }) {
    return HomeBackScope(
      chrome: chrome,
      atHome: section == BottomNavBarItem.forYou,
      onGoHome: () => selectBottomNavBarItem(
        ref,
        BottomNavBarItem.forYou,
        navigationType: 'back',
      ),
      child: child,
    );
  }
}

/// Android's back (and the predictive back gesture) on the Home shell:
/// hidden bars come back first, then Home opens, and only Home with its bars
/// in view lets the app close. iOS has no back on the first route.
///
/// The shell is the last to answer a back. What the page itself holds back
/// with comes first and alone:
///
/// * Another [PopScope] of the route refusing (My Space in Edit, an in-place
///   search): the back is that page's. Every refusing entry of a route hears
///   the refused back, the shell's included; the shell then leaves the bars
///   and the section where they are, so one back never both leaves Edit and
///   throws the reader to the top of the page.
/// * The route's own local history (a [Scaffold] drawer such as Botvinnik's
///   conversations, a persistent bottom sheet): the shell lets the back
///   through while there is one, and the route closes it. A route with a
///   refusing entry never reaches its local history, so a shell that
///   refused would leave the drawer open.
///
/// It registers a [PopEntry] of its own rather than a [PopScope], so that
/// whether it lets a back through is read when the back comes: the drawer
/// opens and closes without rebuilding anything here.
class HomeBackScope extends StatefulWidget {
  const HomeBackScope({
    super.key,
    required this.chrome,
    required this.atHome,
    required this.onGoHome,
    required this.child,
  });

  /// The open section's chrome: hidden bars come back before anything else.
  final ScrollChromeController chrome;

  /// Whether the open section is Home, where a back with the bars in view
  /// closes the app.
  final bool atHome;

  /// Opens Home.
  final VoidCallback onGoHome;

  final Widget child;

  @override
  State<HomeBackScope> createState() => _HomeBackScopeState();
}

class _HomeBackScopeState extends State<HomeBackScope> {
  late final _HomeBackEntry _entry = _HomeBackEntry(this);
  ModalRoute<dynamic>? _route;

  /// Set while the shell asks the route whether anything else refuses.
  bool _probing = false;

  /// Whether the shell itself lets a back through: Home with its bars in
  /// view, where the back closes the app.
  bool get _shellLetsGo => widget.atHome && widget.chrome.value >= 1;

  bool get _canPop =>
      _probing || _shellLetsGo || (_route?.willHandlePopInternally ?? false);

  @override
  void initState() {
    super.initState();
    widget.chrome.addListener(_entry.refresh);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _route) {
      _route?.unregisterPopEntry(_entry);
      _route = route;
      _route?.registerPopEntry(_entry);
    }
  }

  @override
  void didUpdateWidget(HomeBackScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chrome != widget.chrome) {
      oldWidget.chrome.removeListener(_entry.refresh);
      widget.chrome.addListener(_entry.refresh);
    }
    _entry.refresh();
  }

  @override
  void dispose() {
    widget.chrome.removeListener(_entry.refresh);
    _route?.unregisterPopEntry(_entry);
    _entry.dispose();
    super.dispose();
  }

  /// Whether an entry of the route other than the shell refuses the back,
  /// asked with the shell letting it through.
  bool _anotherRefuses() {
    final route = _route;
    if (route == null) return false;
    _probing = true;
    try {
      return route.popDisposition == RoutePopDisposition.doNotPop;
    } finally {
      _probing = false;
    }
  }

  void _onBack(bool didPop) {
    if (didPop || !mounted || _anotherRefuses()) return;
    final chrome = widget.chrome;
    if (chrome.value < 1) {
      chrome.show();
      return;
    }
    if (!widget.atHome) widget.onGoHome();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The shell's [PopEntry]: whether it lets a back through is read live
/// ([_HomeBackScopeState._canPop]), and its listeners (the route, which
/// tells Android whether the app takes the back) hear when the shell's own
/// answer changes.
class _HomeBackEntry extends PopEntry<Object?> {
  _HomeBackEntry(this._scope) : _canPop = _HomeBackCanPop(_scope);

  final _HomeBackScopeState _scope;
  final _HomeBackCanPop _canPop;

  /// The shell's own answer at the last notification.
  late bool _last = _scope._shellLetsGo;

  @override
  ValueListenable<bool> get canPopNotifier => _canPop;

  /// Tells the listeners when the shell's own answer changed.
  void refresh() {
    final now = _scope._shellLetsGo;
    if (now == _last) return;
    _last = now;
    _canPop.changed();
  }

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) =>
      _scope._onBack(didPop);

  void dispose() => _canPop.dispose();
}

class _HomeBackCanPop extends ChangeNotifier implements ValueListenable<bool> {
  _HomeBackCanPop(this._scope);

  final _HomeBackScopeState _scope;

  @override
  bool get value => _scope._canPop;

  void changed() => notifyListeners();
}

extension on BottomNavBarItem {
  /// Whether scrolling this section moves the bars. Botvinnik is a
  /// conversation over its own composer: its bars stay where they are.
  bool get scrollsChrome => this != BottomNavBarItem.botvinnik;

  /// Feed pages through whole posts rather than scrolling a list
  /// ([ScrollChromeRegion.paged]): the dock leaves as the reader pages on
  /// and comes back as they page back, and each post moves to stay centred
  /// in the room it leaves, never changing size (see `FeedScreen`).
  bool get pagesChrome => this == BottomNavBarItem.feed;
}

/// The selected section, switched in place. No scale or fade on a switch:
/// the section is simply there, and nothing is ever drawn from nothing.
///
/// Botvinnik and Collections stay alive once visited, out of sight: a
/// conversation mid-answer, or the catalog page, tab and place the reader
/// left, must survive a look at another tab. The others are built fresh, as
/// before, so a section the reader is not on costs nothing (Feed's playback
/// above all).
class BottomNavBarView extends HookConsumerWidget {
  const BottomNavBarView({super.key, this.chromeFor});

  /// Each section's scroll chrome. Null (a test driving the view alone)
  /// leaves the bars where they are.
  final ScrollChromeController Function(BottomNavBarItem item)? chromeFor;

  static const _kept = {
    BottomNavBarItem.botvinnik,
    BottomNavBarItem.collections,
  };

  Widget _buildScreen(
    BottomNavBarItem item,
    Widget Function(BottomNavBarItem item)? standIn,
  ) {
    final chrome = chromeFor?.call(item);
    final screen = standIn?.call(item) ?? _screen(item);
    if (chrome == null) return screen;
    return ScrollChromeRegion(
      controller: chrome,
      enabled: item.scrollsChrome,
      paged: item.pagesChrome,
      child: screen,
    );
  }

  Widget _screen(BottomNavBarItem item) {
    switch (item) {
      case BottomNavBarItem.forYou:
        return const ForYouScreen();
      case BottomNavBarItem.feed:
        return const FeedScreen(embedded: true);
      case BottomNavBarItem.botvinnik:
        return const ChatScreen(
          embedded: true,
          screenContext: ChatScreenContext(screen: 'home'),
        );
      case BottomNavBarItem.collections:
        // The root: the bar every root wears, no way back ([CollectionsScreen
        // .open] is the pushed copy, with its back).
        return const CollectionsScreen(embedded: true);
      case BottomNavBarItem.profile:
        return const ProfileHubScreen();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedBottomNavBarItemProvider);
    final visible = ref.watch(visibleBottomNavItemsProvider);
    final standIn = ref.watch(homeSectionPageOverrideProvider);
    final current = visible.contains(selected)
        ? selected
        : BottomNavBarItem.forYou;
    final kept = useRef(<BottomNavBarItem>{});
    kept.value.removeWhere((item) => !visible.contains(item));
    if (_kept.contains(current)) kept.value.add(current);

    return GestureDetector(
      onTap: FocusScope.of(context).unfocus,
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (final item in bottomNavBarOrder)
            if (kept.value.contains(item))
              Offstage(
                key: ValueKey('home-section-${item.name}'),
                offstage: item != current,
                child: TickerMode(
                  enabled: item == current,
                  child: ExcludeFocus(
                    excluding: item != current,
                    child: _buildScreen(item, standIn),
                  ),
                ),
              ),
          if (!_kept.contains(current))
            KeyedSubtree(
              key: ValueKey('home-section-${current.name}'),
              child: _buildScreen(current, standIn),
            ),
        ],
      ),
    );
  }
}

/// The floating buttons of the section in view. Search stands in the
/// corner on all three Home tabs ([homeSearchFab]), the way into the
/// app-wide search the 38.17 field over all three was: My Space keeps its
/// add menu over it (Edit's save while editing); Today has Live first
/// over it while an event is in play or while it is on, so a flag left on
/// can always be turned off ([ForYouTodayFabs]). Botvinnik has a tab now;
/// it no longer floats over Home. Collections floats its own catalog
/// search, on its own page ([CollectionsScreen]).
///
/// Every set stands in an [InkFabStack], as the event screen's do: one
/// right edge, one step, the main button in the corner.
class _HomeFab extends ConsumerWidget {
  const _HomeFab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home =
        ref.watch(selectedBottomNavBarItemProvider) == BottomNavBarItem.forYou;
    if (!home) return const SizedBox.shrink();
    final tab = ref.watch(selectedForYouTabProvider);
    return switch (tab) {
      // Search stays through Edit too, so the add button (Edit's save
      // there) never moves under the finger.
      ForYouTab.mySpace => InkFabStack(
        children: [
          const SpaceAddFab(),
          homeSearchFab(context, key: kMySpaceSearchButtonKey),
        ],
      ),
      ForYouTab.today => const ForYouTodayFabs(),
      ForYouTab.discovery => InkFabStack(
        children: [homeSearchFab(context, key: kDiscoverySearchButtonKey)],
      ),
    };
  }
}
