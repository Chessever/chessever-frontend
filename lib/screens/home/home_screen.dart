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
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/hamburger_menu/hamburger_menu.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/shorebird_update_dialog.dart';
import 'package:chessever2/services/push_notifications_service.dart';
import 'package:chessever2/services/review_prompt_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
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

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  static const int _favoritePromptThreshold = 5;

  @override
  void initState() {
    super.initState();
    if (!E2eConfig.suppressInterruptivePrompts) {
      unawaited(ReviewPromptService.instance.incrementSessionCount());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForShorebirdUpdate();
      if (!E2eConfig.suppressInterruptivePrompts) {
        // Plan B: request notification permission if not already granted.
        // Delayed to avoid clashing with onboarding or other early dialogs.
        Future.delayed(const Duration(seconds: 5), () {
          if (!mounted) return;
          unawaited(
            PushNotificationsService.instance.requestPermissionIfNotGranted(),
          );
        });
        Future.delayed(const Duration(seconds: 8), () {
          if (!mounted) return;
          unawaited(
            ReviewPromptService.instance.maybePrompt(
              context: context,
              trigger: ReviewPromptTrigger.session,
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
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => ShorebirdUpdateDialog(initialStatus: status),
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
      await showDialog<void>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: const Text('Logout'),
              content: const Text('Are you sure you want to log out?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.of(dialogContext).pop();
                    await ref.read(authStateProvider.notifier).signOut();
                  },
                  child: const Text('Logout'),
                ),
              ],
            ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    // Listen for favorite signals (must be in build method)
    _listenForFavoriteSignals();

    // Tablet layout: NavigationRail on the side
    if (ResponsiveHelper.isTablet) {
      return Scaffold(
        key: _scaffoldKey,
        resizeToAvoidBottomInset: false,
        drawer: HamburgerMenu(callbacks: _menuCallbacks),
        body: Row(
          children: [
            // Navigation rail for tablets
            TabletNavRail(scaffoldKey: _scaffoldKey),
            // Vertical divider
            Container(width: 1, color: kDarkGreyColor),
            // Main content
            Expanded(
              child: KeyedSubtree(
                key: e2eKey(E2eIds.homeRoot),
                child: BottomNavBarView(),
              ),
            ),
          ],
        ),
      );
    }

    // Phone layout: Bottom navigation bar
    return Scaffold(
      key: _scaffoldKey,
      resizeToAvoidBottomInset: false,
      drawer: HamburgerMenu(callbacks: _menuCallbacks),
      bottomNavigationBar: BottomNavBar(),
      body: KeyedSubtree(
        key: e2eKey(E2eIds.homeRoot),
        child: BottomNavBarView(),
      ),
    );
  }
}

class BottomNavBarView extends ConsumerStatefulWidget {
  const BottomNavBarView({super.key});

  @override
  ConsumerState<BottomNavBarView> createState() => _BottomNavBarViewState();
}

class _BottomNavBarViewState extends ConsumerState<BottomNavBarView>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.elasticOut),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeInOut),
      ),
    );

    // The Events tab is the first screen users see; don't spend the first
    // frames scaling/repainting the whole For You feed while it is loading.
    _animationController.value = 1;
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

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

    // Listen for tab changes and trigger animation
    ref.listen<BottomNavBarItem>(selectedBottomNavBarItemProvider, (
      previous,
      next,
    ) {
      if (previous != null && previous != next) {
        _animationController.reset();
        _animationController.forward();
      }
    });

    return GestureDetector(
      onTap: FocusScope.of(context).unfocus,
      child: AnimatedBuilder(
        animation: _animationController,
        child: _buildScreen(currentItem),
        builder: (context, child) {
          return FadeTransition(
            opacity: _fadeAnimation,
            child: ScaleTransition(scale: _scaleAnimation, child: child),
          );
        },
      ),
    );
  }
}
