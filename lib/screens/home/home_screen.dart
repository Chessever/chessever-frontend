import 'dart:io';
import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/screens/authentication/auth_screen_provider.dart';
import 'package:chessever2/screens/calendar/calendar_screen.dart';
import 'package:chessever2/screens/library/library_screen.dart';
import 'package:chessever2/screens/premium/premium_screen.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/hamburger_menu/hamburger_menu.dart';
import 'package:chessever2/widgets/shorebird_update_dialog.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForShorebirdUpdate();
    });
  }

  Future<void> _checkForShorebirdUpdate() async {
    // Simulate update in Debug Mode
    if (kDebugMode) {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder:
              (context) =>
                  const ShorebirdUpdateDialog(initialStatus: UpdateStatus.outdated),
        );
      }
      return;
    }

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

  HamburgerMenuCallbacks get _menuCallbacks => HamburgerMenuCallbacks(
    onPlayersPressed: () {
      // Navigate to players screen
      Navigator.pushNamed(context, '/player_list_screen');
    },
    onAnalysisBoardPressed: () {},
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
            Expanded(child: BottomNavBarView()),
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
      body: BottomNavBarView(),
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

    // Start with the animation completed
    _animationController.forward();
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
        builder: (context, child) {
          return FadeTransition(
            opacity: _fadeAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: _buildScreen(currentItem),
            ),
          );
        },
      ),
    );
  }
}
