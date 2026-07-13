import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/screens/favorites/provider/favorites_mode_provider.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_games_tab.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_list_tab.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/liquid_glass/chrome_scroll_collapse.dart';
import 'package:chessever2/widgets/liquid_glass/glass_back_button.dart';
import 'package:chessever2/widgets/liquid_glass/liquid_tab_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:chessever2/widgets/liquid_glass/liquid_glass_halo.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:chessever2/widgets/scroll_to_top_bus.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class FavoritesTabScreen extends ConsumerStatefulWidget {
  const FavoritesTabScreen({super.key, this.initialMode});

  final FavoritesScreenMode? initialMode;

  @override
  ConsumerState<FavoritesTabScreen> createState() => _FavoritesTabScreenState();
}

class _FavoritesTabScreenState extends ConsumerState<FavoritesTabScreen> {
  late PageController _pageController;
  final ScrollToTopBus _scrollToTopBus = ScrollToTopBus();
  final ChromeScrollCollapse _chromeCollapse = ChromeScrollCollapse();

  @override
  void initState() {
    super.initState();
    final initialMode = widget.initialMode;
    final FavoritesScreenMode mode =
        initialMode ?? ref.read(selectedFavoritesModeProvider);
    if (initialMode != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read(selectedFavoritesModeProvider.notifier)
            .update((_) => initialMode);
      });
    }
    _pageController = PageController(
      initialPage: FavoritesScreenMode.values.indexOf(mode),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _scrollToTopBus.dispose();
    super.dispose();
  }

  void _handleTabSelection(int index) {
    try {
      final currentIndex = FavoritesScreenMode.values.indexOf(
        ref.read(selectedFavoritesModeProvider),
      );
      if (index == currentIndex) {
        _scrollToTopBus.request();
        if (!_chromeCollapse.expanded) {
          setState(_chromeCollapse.reset);
        }
        return;
      }
      ref
          .read(selectedFavoritesModeProvider.notifier)
          .update((_) => FavoritesScreenMode.values[index]);
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      // New tab starts expanded at top.
      if (!_chromeCollapse.expanded) {
        setState(_chromeCollapse.reset);
      }
    } catch (e) {
      debugPrint('Error handling tab selection: $e');
    }
  }

  void _handlePageChanged(int index) {
    try {
      final currentModeIndex = FavoritesScreenMode.values.indexOf(
        ref.read(selectedFavoritesModeProvider),
      );
      if (currentModeIndex != index) {
        ref
            .read(selectedFavoritesModeProvider.notifier)
            .update((_) => FavoritesScreenMode.values[index]);
      }
      if (!_chromeCollapse.expanded) {
        setState(_chromeCollapse.reset);
      }
    } catch (e) {
      debugPrint('Error handling page change: $e');
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification is! ScrollUpdateNotification) return false;
    if (_chromeCollapse.onScrollUpdate(notification) && mounted) {
      setState(() {});
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final selectedMode = ref.watch(selectedFavoritesModeProvider);
    final selectedIndex = FavoritesScreenMode.values.indexOf(selectedMode);

    // Page content owns the whole screen edge-to-edge; discrete glass islands
    // float on top and the list scrolls *underneath*. Each tab gets this inset
    // as leading padding (via a first sliver spacer) so its first row clears the
    // islands (status bar + control row + gap + segment island) without a
    // reserved opaque strip that would read as a traditional appbar.
    final statusTop = MediaQuery.viewPaddingOf(context).top;
    // Single-line header now (back + title + segments): status bar + 8 top pad
    // + 44 row + a little breathing room.
    final topInset = statusTop + 64;

    return ScreenWrapper(
      child: Scaffold(
        key: e2eKey(E2eIds.favoritesRoot),
        backgroundColor: Colors.transparent,
        body: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: ResponsiveHelper.contentMaxWidth,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Full-bleed page content.
                Positioned.fill(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _onScroll,
                    child: ScrollToTopScope(
                      bus: _scrollToTopBus,
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: 3,
                        onPageChanged: _handlePageChanged,
                        itemBuilder: (context, index) {
                          switch (index) {
                            case 0:
                              return FavoritesListTab(topPadding: topInset);
                            case 1:
                              return FavoritesGamesTab(topPadding: topInset);
                            case 2:
                              return FavoritesPlayersTab(topPadding: topInset);
                            default:
                              return Center(
                                child: Text(
                                  'Invalid page index: $index',
                                  style: TextStyle(
                                    color: context.colors.textPrimary,
                                  ),
                                ),
                              );
                          }
                        },
                      ),
                    ),
                  ),
                ),
                // Floating glass chrome — scales down on scroll-down and back up
                // on scroll-up, mirroring the home bottom nav bar's behaviour.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: AnimatedScale(
                    scale: _chromeCollapse.expanded ? 1.0 : 0.94,
                    alignment: Alignment.topCenter,
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    child: AnimatedOpacity(
                      opacity: _chromeCollapse.expanded ? 1.0 : 0.96,
                      duration: const Duration(milliseconds: 240),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          12.w,
                          statusTop + 8,
                          12.w,
                          0,
                        ),
                        // One line: back button + the mode tabs hugging the
                        // right. The tabs are the SAME bare LiquidTabBar (with
                        // icons) used on the Home / Tournaments / Calendar
                        // headers — identical glass, motion and brand-bubble.
                        child: SizedBox(
                          height: 44,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              LiquidGlassHalo(
                                borderRadius: 20,
                                child: const GlassBackButton(),
                              ),
                              const Spacer(),
                              LiquidTabBar(
                                options: favoritesModeNames.values.toList(),
                                icons: const [
                                  CupertinoIcons.heart,
                                  CupertinoIcons.square_grid_2x2,
                                  CupertinoIcons.person_2,
                                ],
                                selectedIndex: selectedIndex.clamp(
                                  0,
                                  favoritesModeNames.length - 1,
                                ),
                                onSelected: _handleTabSelection,
                                separated: !_chromeCollapse.expanded,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
