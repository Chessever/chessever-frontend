import 'package:chessever2/screens/calendar_screen.dart';
import 'package:chessever2/screens/library/library_screen.dart';
import 'package:chessever2/providers/notifications_settings_provider.dart';
import 'package:chessever2/providers/timezone_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/board_settings_dialog.dart';
import 'package:chessever2/widgets/hamburger_menu.dart';
import 'package:chessever2/widgets/language_settings_dialog.dart';
import 'package:chessever2/widgets/notifications_settings_dialog.dart';
import 'package:chessever2/widgets/settings_menu.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:chessever2/widgets/timezone_settings_dialog.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../localization/locale_provider.dart';
import 'tournaments/tournament_screen.dart';
import 'tournaments/widget/bottom_nav_bar.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static final GlobalKey<ScaffoldState> scaffoldKey =
      GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: scaffoldKey,
      drawer: HamburgerMenu(
        onSettingsPressed: () {
          Navigator.pop(context); // Close the drawer first
          showAlertModal(
            context: context,
            backgroundColor: kPopUpColor,
            child: Consumer(
              builder: (context, ref, _) {
                final notificationsSettings = ref.watch(
                  notificationsSettingsProvider,
                );
                final localeName = ref.watch(localeNameProvider);
                final timezone = ref.watch(timezoneProvider);

                return SettingsMenu(
                  notificationsEnabled: notificationsSettings.enabled,
                  languageSubtitle: localeName,
                  timezoneSubtitle: timezone.display,
                  boardSettingsIcon: SvgWidget(SvgAsset.boardSettings),
                  languageIcon: SvgWidget(SvgAsset.languageIcon),
                  timezoneIcon: SvgWidget(SvgAsset.timezoneIcon),
                  onBoardSettingsPressed: () {
                    Navigator.pop(context); // Close settings menu
                    // Add a small delay before showing the next dialog
                    Future.delayed(Duration(milliseconds: 100), () {
                      showAlertModal(
                        context: context,
                        backgroundColor: kPopUpColor,
                        barrierColor:
                            Colors
                                .transparent, // Use transparent barrier for nested dialogs
                        child: BoardSettingsDialog(),
                      );
                    });
                  },
                  onLanguagePressed: () {
                    Navigator.pop(context); // Close settings menu
                    // Add a small delay before showing the next dialog
                    Future.delayed(Duration(milliseconds: 100), () {
                      showAlertModal(
                        context: context,
                        backgroundColor: kPopUpColor,
                        barrierColor:
                            Colors
                                .transparent, // Use transparent barrier for nested dialogs
                        child: LanguageSettingsDialog(),
                      );
                    });
                  },
                  onTimezonePressed: () {
                    Navigator.pop(context); // Close settings menu
                    // Add a small delay before showing the next dialog
                    Future.delayed(Duration(milliseconds: 100), () {
                      showAlertModal(
                        context: context,
                        backgroundColor: kPopUpColor,
                        barrierColor:
                            Colors
                                .transparent, // Use transparent barrier for nested dialogs
                        child: TimezoneSettingsDialog(),
                      );
                    });
                  },
                  onNotificationsPressed: () {
                    Navigator.pop(context); // Close settings menu
                    // Add a small delay before showing the next dialog
                    Future.delayed(Duration(milliseconds: 100), () {
                      showAlertModal(
                        context: context,
                        backgroundColor: kPopUpColor,
                        barrierColor:
                            Colors
                                .transparent, // Use transparent barrier for nested dialogs
                        child: NotificationsSettingsDialog(),
                      );
                    });
                  },
                );
              },
            ),
          );
        },
        onPlayersPressed: () {},
        onFavoritesPressed: () {},
        onCountrymanPressed: () {},
        onAnalysisBoardPressed: () {},
        onSupportPressed: () {},
        onPremiumPressed: () {},
        onLogoutPressed: () {},
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

    return AnimatedBuilder(
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
    );
  }
}
