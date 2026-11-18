import 'dart:async';
import 'dart:io';
import 'package:chessever2/chat/chat_api.dart';
import 'package:chessever2/chat/chat_screen.dart';
import 'package:chessever2/e2e/e2e_config.dart';
import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
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
import 'package:chessever2/screens/search/search_tab_screen.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/paywall/billing_issue_sheet.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:chessever2/widgets/shorebird_update_dialog.dart';
import 'package:chessever2/services/att_prompt_service.dart';
import 'package:chessever2/services/review_prompt_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import 'widget/bottom_nav_bar.dart';
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

/// The app's home: five sections under one bar (Home, Feed, Botvinnik,
/// Search, Profile). There is no sidebar; what it held lives on Profile.
///
/// The bar and the section's own top bar step out of the way as the reader
/// scrolls down a list and come back as they scroll up ([ScrollChromeRegion]).
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

  /// Each section's own chrome state: Search can sit with its field
  /// scrolled away while Home's strip is in view.
  final Map<BottomNavBarItem, ScrollChromeController> _chromes = {};

  ScrollChromeController _chromeFor(BottomNavBarItem item) =>
      _chromes.putIfAbsent(item, () => ScrollChromeController(vsync: this));

  @override
  void initState() {
    super.initState();
    forgetForYouPageForLaunch();
    if (!E2eConfig.suppressInterruptivePrompts) {
      unawaited(ReviewPromptService.instance.incrementSessionCount());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
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

  @override
  void dispose() {
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

    // A new section opens with its bars in view; Botvinnik switched off in
    // Settings while its tab was open hands the reader back to Home.
    ref.listen<BottomNavBarItem>(selectedBottomNavBarItemProvider, (_, next) {
      _chromeFor(next).show();
      FocusManager.instance.primaryFocus?.unfocus();
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
    final chrome = _chromeFor(ref.watch(selectedBottomNavBarItemProvider));

    final body = BillingIssueGate(
      child: KeyedSubtree(
        key: e2eKey(E2eIds.homeRoot),
        child: KeyedSubtree(
          key: _sectionKey,
          child: BottomNavBarView(chromeFor: _chromeFor),
        ),
      ),
    );

    final fab = SlidingFabs(controller: chrome, child: const _HomeFab());

    // Tablet layout: NavigationRail on the side
    if (ResponsiveHelper.isTablet) {
      return Scaffold(
        resizeToAvoidBottomInset:
            ref.watch(selectedBottomNavBarItemProvider) ==
            BottomNavBarItem.botvinnik,
        floatingActionButton: fab,
        body: Row(
          children: [
            const TabletNavRail(),
            // Vertical divider
            Container(width: 1, color: context.colors.divider),
            // Main content
            Expanded(child: body),
          ],
        ),
      );
    }

    // Phone layout: Bottom navigation bar. Botvinnik's composer rides the
    // keyboard: the shell lifts the page over it (the keyboard covers the
    // bar anyway), and the chat page does not lift itself again.
    final typingToBotvinnik =
        ref.watch(selectedBottomNavBarItemProvider) ==
        BottomNavBarItem.botvinnik;
    return Scaffold(
      resizeToAvoidBottomInset: typingToBotvinnik,
      floatingActionButton: fab,
      bottomNavigationBar: CollapsingChrome(
        controller: chrome,
        edge: VerticalDirection.down,
        child: const BottomNavBar(),
      ),
      body: body,
    );
  }
}

extension on BottomNavBarItem {
  /// Whether scrolling this section moves the bars.
  bool get scrollsChrome => switch (this) {
    BottomNavBarItem.forYou ||
    BottomNavBarItem.search ||
    BottomNavBarItem.profile => true,
    BottomNavBarItem.feed || BottomNavBarItem.botvinnik => false,
  };
}

/// The selected section, switched in place. No scale or fade on a switch:
/// the section is simply there, and nothing is ever drawn from nothing.
///
/// Botvinnik and Search stay alive once visited, out of sight: a
/// conversation mid-answer or a half-typed search must survive a look at
/// another tab. The others are built fresh, as before, so a section the
/// reader is not on costs nothing (Feed's playback above all).
class BottomNavBarView extends HookConsumerWidget {
  const BottomNavBarView({super.key, this.chromeFor});

  /// Each section's scroll chrome. Null (a test driving the view alone)
  /// leaves the bars where they are.
  final ScrollChromeController Function(BottomNavBarItem item)? chromeFor;

  static const _kept = {BottomNavBarItem.botvinnik, BottomNavBarItem.search};

  Widget _buildScreen(BottomNavBarItem item) {
    final chrome = chromeFor?.call(item);
    final screen = _screen(item);
    if (chrome == null) return screen;
    return ScrollChromeRegion(
      controller: chrome,
      // Feed pages through whole posts and Botvinnik is a conversation:
      // neither is a list to read down.
      enabled: item.scrollsChrome,
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
      case BottomNavBarItem.search:
        return const SearchTabScreen();
      case BottomNavBarItem.profile:
        return const ProfileHubScreen();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedBottomNavBarItemProvider);
    final visible = ref.watch(visibleBottomNavItemsProvider);
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
                    child: _buildScreen(item),
                  ),
                ),
              ),
          if (!_kept.contains(current))
            KeyedSubtree(
              key: ValueKey('home-section-${current.name}'),
              child: _buildScreen(current),
            ),
        ],
      ),
    );
  }
}

/// The floating buttons of the section in view: My Space keeps its add
/// menu, Today its Live first (while something is live) and, while a filter
/// narrows it, the way back to that filter. Botvinnik has a tab now; it no
/// longer floats over Home.
class _HomeFab extends ConsumerWidget {
  const _HomeFab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home =
        ref.watch(selectedBottomNavBarItemProvider) == BottomNavBarItem.forYou;
    if (!home) return const SizedBox.shrink();
    final tab = ref.watch(selectedForYouTabProvider);
    return switch (tab) {
      ForYouTab.mySpace => const SpaceAddFab(),
      ForYouTab.today => const ForYouTodayFabs(),
      ForYouTab.discovery => const SizedBox.shrink(),
    };
  }
}
