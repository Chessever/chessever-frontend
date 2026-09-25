import 'dart:async';
import 'dart:io';
import 'package:chessever2/e2e/e2e_config.dart';
import 'package:chessever2/chat/botvinnik_chat_button.dart';
import 'package:chessever2/chat/chat_api.dart';
import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/screens/authentication/auth_screen_provider.dart';
import 'package:chessever2/screens/library/library_screen.dart';
import 'package:chessever2/screens/favorites/favorites_tab_screen.dart';
import 'package:chessever2/screens/favorites/provider/favorites_mode_provider.dart';
import 'package:chessever2/screens/for_you/for_you_screen.dart';
import 'package:chessever2/screens/for_you/providers/for_you_tab_provider.dart';
import 'package:chessever2/screens/gamebase/gamebase_explorer_screen.dart';
import 'package:chessever2/screens/my_space/widgets/space_add_fab.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/hamburger_menu/hamburger_menu.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/paywall/billing_issue_sheet.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:chessever2/widgets/shorebird_update_dialog.dart';
import 'package:chessever2/services/att_prompt_service.dart';
import 'package:chessever2/services/review_prompt_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../group_event/group_event_screen.dart';
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

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  static const int _favoritePromptThreshold = 5;

  @override
  void initState() {
    super.initState();
    forgetForYouPageForLaunch();
    if (!E2eConfig.suppressInterruptivePrompts) {
      unawaited(ReviewPromptService.instance.incrementSessionCount());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
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

  HamburgerMenuCallbacks get _menuCallbacks => HamburgerMenuCallbacks(
    onPlayersPressed: () {
      // Navigate to players screen
      Navigator.pushNamed(context, '/player_list_screen');
    },
    onBoardPressed: () async {
      final allowed = await requireFullAuthGuard(context);
      if (!allowed) return;
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => GamebaseExplorerScreen.scoped()),
      );
    },
    onFavoritesPressed: () {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder:
              (_) => const FavoritesTabScreen(
                initialMode: FavoritesScreenMode.players,
              ),
        ),
      );
    },
    onSupportPressed: () {
      // Handle support action
    },
    onPremiumPressed: () async {
      await showPremiumPaywallSheet(context: context);
    },
    onLogoutPressed: () async {
      final user = Supabase.instance.client.auth.currentUser;
      final isAnonymous = user?.isAnonymous == true;

      // Anonymous users: navigate to auth screen WITHOUT signing out
      if (isAnonymous) {
        Navigator.of(context).pop(); // Close drawer
        ref.read(authScreenProvider.notifier).reset();
        Navigator.of(context).pushNamed('/auth_screen');
        return;
      }

      // Fully authenticated users: show logout confirmation
      final confirmed = await showSmoothConfirmDialog(
        context: context,
        title: 'Logout',
        message: 'Are you sure you want to log out?',
        confirmText: 'Logout',
      );
      if (confirmed == true) {
        await ref.read(authStateProvider.notifier).signOut();
      }
    },
  );

  Widget get _chatButton => const _HomeFab();

  @override
  Widget build(BuildContext context) {
    // Listen for favorite signals (must be in build method)
    _listenForFavoriteSignals();

    // Tablet layout: NavigationRail on the side
    if (ResponsiveHelper.isTablet) {
      return Scaffold(
        key: _scaffoldKey,
        resizeToAvoidBottomInset: false,
        drawerScrimColor: context.colors.scrim,
        drawer: HamburgerMenu(callbacks: _menuCallbacks),
        floatingActionButton: _chatButton,
        body: BillingIssueGate(
          child: Row(
            children: [
              // Navigation rail for tablets
              TabletNavRail(scaffoldKey: _scaffoldKey),
              // Vertical divider
              Container(width: 1, color: context.colors.divider),
              // Main content
              Expanded(
                child: KeyedSubtree(
                  key: e2eKey(E2eIds.homeRoot),
                  child: BottomNavBarView(),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Phone layout: Bottom navigation bar
    return Scaffold(
      key: _scaffoldKey,
      resizeToAvoidBottomInset: false,
      drawerScrimColor: context.colors.scrim,
      drawer: HamburgerMenu(callbacks: _menuCallbacks),
      floatingActionButton: _chatButton,
      bottomNavigationBar: BottomNavBar(),
      body: BillingIssueGate(
        child: KeyedSubtree(
          key: e2eKey(E2eIds.homeRoot),
          child: BottomNavBarView(),
        ),
      ),
    );
  }
}

/// The selected section, switched in place. No scale or fade on a switch:
/// the section is simply there, and nothing is ever drawn from nothing.
class BottomNavBarView extends ConsumerWidget {
  const BottomNavBarView({super.key});

  Widget _buildScreen(BottomNavBarItem item) {
    switch (item) {
      case BottomNavBarItem.tournaments:
        return const GroupEventScreen();
      case BottomNavBarItem.forYou:
        return const ForYouScreen();
      case BottomNavBarItem.library:
        return const LibraryScreen();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentItem = ref.watch(selectedBottomNavBarItemProvider);
    return GestureDetector(
      onTap: FocusScope.of(context).unfocus,
      child: _buildScreen(currentItem),
    );
  }
}

/// Home's floating slot: Botvinnik's launcher everywhere, and My Space's
/// add button while My Space is the page in view. Both stay mounted and
/// trade places on one spring (the outgoing one shrinks and fades as the
/// incoming one grows in), so the slot never empties and never shifts.
class _HomeFab extends ConsumerWidget {
  const _HomeFab();

  static const _swap = CupertinoMotion.snappy(snapToEnd: true);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onForYou = ref.watch(
      selectedBottomNavBarItemProvider.select(
        (item) => item == BottomNavBarItem.forYou,
      ),
    );
    // Watched only while For You is up, so the search query (which resets
    // whenever For You leaves the tree) is not kept alive from here.
    final onSpace =
        onForYou &&
        ref.watch(selectedForYouTabProvider) == ForYouTab.mySpace &&
        ref.watch(forYouSearchQueryProvider.select((q) => q.isEmpty));
    final reduce = MediaQuery.disableAnimationsOf(context);

    // The hidden one also sits out hero flights: the launcher's hero would
    // otherwise fly, fully drawn, out of a slot that shows the "+".
    Widget slot(bool active, Widget child) => IgnorePointer(
      ignoring: !active,
      child: ExcludeSemantics(
        excluding: !active,
        child: HeroMode(
          enabled: active,
          child: SingleMotionBuilder(
            motion: _swap,
            value: active ? 1.0 : 0.0,
            active: !reduce,
            child: child,
            builder: (context, value, child) {
              final t = value.clamp(0.0, 1.0);
              final scale = 0.7 + 0.3 * t;
              return Opacity(
                opacity: t,
                child: Transform.scale(
                  scale: (scale - 1).abs() < 0.002 ? 1.0 : scale,
                  child: child,
                ),
              );
            },
          ),
        ),
      ),
    );

    return Stack(
      alignment: Alignment.center,
      children: [
        slot(
          !onSpace,
          const BotvinnikChatButton(
            heroTag: 'botvinnik',
            screenContext: ChatScreenContext(screen: 'home'),
            iconOnly: true,
          ),
        ),
        slot(onSpace, const SpaceAddFab()),
      ],
    );
  }
}
