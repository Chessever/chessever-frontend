import 'package:chessever2/screens/authentication/home_screen/home_screen_provider.dart';
import 'package:chessever2/screens/calendar_screen.dart';
import 'package:chessever2/screens/chessboard/ChessBoardScreen.dart';
import 'package:chessever2/screens/library/library_screen.dart';
import 'package:chessever2/screens/premium/premium_screen.dart'; // Import premium screen
import 'package:chessever2/widgets/hamburger_menu/hamburger_menu.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../tournaments/tournament_screen.dart';
import '../../tournaments/widget/bottom_nav_bar.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static final GlobalKey<ScaffoldState> scaffoldKey =
      GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: scaffoldKey,
      drawer: HamburgerMenu(
        callbacks: HamburgerMenuCallbacks(
          onPlayersPressed: () {
            // Navigate to players screen
            Navigator.pushNamed(context, '/playerList');
          },
          onFavoritesPressed: () {
            // Navigate to favorites screen
            Navigator.pushNamed(context, '/favorites');
          },
          onCountrymanPressed: () {
            // Navigate to countryman screen
            Navigator.pushNamed(context, '/countryman');
          },
          onAnalysisBoardPressed: () {
            // Navigate to analysis board
            // Navigator.pushNamed(context, '/analysisBoard');
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ChessScreen()),
            );
          },
          onSupportPressed: () {
            // Handle support action
            // e.g., open support form or chat
          },
          onPremiumPressed: () {
            // Navigate to premium screen
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const PremiumScreen()),
            );
          },
          onLogoutPressed: () {
            // Handle logout
            // e.g., clear session and navigate to login
          },
        ),
      ),
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
        return const TournamentScreen();
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
      child: RefreshIndicator(
        onRefresh: ref.read(homeScreenProvider).onPullRefresh,
        color: Theme.of(context).primaryColor,
        backgroundColor: Theme.of(context).cardColor,
        displacement: 40.0,
        // Distance from top where indicator appears
        strokeWidth: 3.0,
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
      ),
    );
  }
}
