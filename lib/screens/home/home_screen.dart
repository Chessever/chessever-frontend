import 'dart:async';
import 'dart:io';
import 'package:chessever2/e2e/e2e_config.dart';
import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/screens/authentication/auth_screen_provider.dart';
import 'package:chessever2/screens/calendar/calendar_screen.dart';
import 'package:chessever2/screens/library/library_screen.dart';
import 'package:chessever2/screens/board_editor/board_editor_screen.dart';
import 'package:chessever2/screens/favorites/favorites_tab_screen.dart';
import 'package:chessever2/screens/favorites/provider/favorites_mode_provider.dart';
import 'package:chessever2/screens/gamebase/gamebase_explorer_screen.dart';
import 'package:chessever2/screens/premium/premium_screen.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/hamburger_menu/hamburger_menu.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/liquid_glass/glass_feedback.dart';
import 'package:chessever2/widgets/paywall/billing_issue_sheet.dart';
import 'package:chessever2/widgets/shorebird_update_dialog.dart';
import 'package:chessever2/services/att_prompt_service.dart';
import 'package:chessever2/services/review_prompt_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../group_event/group_event_screen.dart';
import 'widget/bottom_nav_bar.dart';
import 'widget/tablet_nav_rail.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

/// Key on the outer home [Scaffold] that owns the drawer. Exposed so nested
/// chrome (e.g. the Events avatar island) can open the left sidebar — the
/// GlassScaffold wraps its own inner Scaffold, so `Scaffold.of` from the body
/// would find that one (which has no drawer) instead of this one.
final GlobalKey<ScaffoldState> homeScaffoldKey = GlobalKey<ScaffoldState>();

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static const int _favoritePromptThreshold = 5;

  @override
  void initState() {
    super.initState();
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
    onAnalysisBoardPressed: () {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const BoardEditorScreen()));
    },
    onOpeningExplorerPressed: () async {
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
                initialMode: FavoritesScreenMode.favorites,
              ),
        ),
      );
    },
    onSupportPressed: () {
      // Handle support action
    },
    onPremiumPressed: () {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        constraints: ResponsiveHelper.bottomSheetConstraints,
        builder: (_) => const PremiumScreen(),
      );
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
      final confirmed = await showGlassConfirmDialog(
        context: context,
        title: 'Logout',
        message: 'Are you sure you want to log out?',
        confirmText: 'Logout',
        destructive: true,
      );
      if (confirmed == true) {
        await ref.read(authStateProvider.notifier).signOut();
      }
    },
  );

  @override
  Widget build(BuildContext context) {
    // Listen for favorite signals (must be in build method)
    _listenForFavoriteSignals();

    // Tablet layout: NavigationRail on the side (unchanged — phone island is primary)
    if (ResponsiveHelper.isTablet) {
      return Scaffold(
        key: homeScaffoldKey,
        resizeToAvoidBottomInset: false,
        drawer: HamburgerMenu(callbacks: _menuCallbacks),
        body: BillingIssueGate(
          child: Row(
            children: [
              // Navigation rail for tablets
              TabletNavRail(scaffoldKey: homeScaffoldKey),
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

    // Phone layout: content owns every pixel; the floating glass tab bar is the
    // canonical GlassScaffold.bottomBar (the package handles z-order, edge fade,
    // safe-area and content-aware brightness sampling for us).
    // Outer Scaffold only owns the drawer (GlassScaffold has no drawer slot).
    return Scaffold(
      key: homeScaffoldKey,
      resizeToAvoidBottomInset: false,
      backgroundColor: context.colors.background,
      drawer: HamburgerMenu(callbacks: _menuCallbacks),
      body: GlassScaffold(
        backgroundColor: context.colors.background,
        statusBarStyle: GlassStatusBarStyle.auto,
        // Package: bars sample content scrolling underneath and flip icon colors.
        contentAwareBrightness: true,
        extendBody: true,
        // iOS-26 scroll-edge effect: content dissolves into the background in a
        // band above the floating bottom nav, so the glass bar stays readable no
        // matter what scrolls behind it. Top is handled per-screen (the floating
        // top islands are body content, so a scaffold top-fade would dissolve
        // them — each screen paints its own scrim BEHIND its island instead).
        edgeFade: false,
        topEdgeFade: false,
        bottomEdgeFade: true,
        bottomBarHeight: 96,
        bottomEdgeFadeExtent: 28,
        edgeStyle: GlassScrollEdgeStyle.soft,
        resizeToAvoidBottomInset: false,
        bottomBar: const BottomNavBar(),
        body: BillingIssueGate(
          child: KeyedSubtree(
            key: e2eKey(E2eIds.homeRoot),
            child: const BottomNavBarView(),
          ),
        ),
      ),
    );
  }
}

class BottomNavBarView extends ConsumerStatefulWidget {
  const BottomNavBarView({super.key});

  @override
  ConsumerState<BottomNavBarView> createState() => _BottomNavBarViewState();
}

class _BottomNavBarViewState extends ConsumerState<BottomNavBarView> {
  Widget _buildScreen(BottomNavBarItem item) {
    switch (item) {
      case BottomNavBarItem.tournaments:
        return const GroupEventScreen();
      case BottomNavBarItem.calendar:
        return const CalendarScreen();
      case BottomNavBarItem.library:
        return const LibraryScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentItem = ref.watch(selectedBottomNavBarItemProvider);

    return GestureDetector(
      onTap: FocusScope.of(context).unfocus,
      child: _buildScreen(currentItem),
    );
  }
}
