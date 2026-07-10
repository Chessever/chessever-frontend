import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/screens/favorites/provider/favorites_mode_provider.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_games_tab.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_list_tab.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/liquid_glass/glass_back_button.dart';
import 'package:chessever2/widgets/liquid_glass/glass_island_top_bar.dart';
import 'package:chessever2/widgets/liquid_glass/glass_title_chip.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:chessever2/widgets/scroll_to_top_bus.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
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
    } catch (e) {
      debugPrint('Error handling page change: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedMode = ref.watch(selectedFavoritesModeProvider);

    // GlassPage composition (via ScreenWrapper) so glass chrome islands
    // sample backdrop correctly per liquid_glass_widgets package contract.
    return ScreenWrapper(
      child: Scaffold(
        key: e2eKey(E2eIds.favoritesRoot),
        backgroundColor: Colors.transparent,
        body: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: ResponsiveHelper.contentMaxWidth,
            ),
            child: Column(
              children: [
                SizedBox(height: MediaQuery.of(context).viewPadding.top + 4.h),
                _buildAppBar(context, selectedMode),
                SizedBox(height: 8.h),
                _buildSegmentedSwitcher(selectedMode),
                Expanded(
                  child: ScrollToTopScope(
                    bus: _scrollToTopBus,
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: 3,
                      onPageChanged: _handlePageChanged,
                      itemBuilder: (context, index) {
                        switch (index) {
                          case 0:
                            return const FavoritesListTab();
                          case 1:
                            return const FavoritesGamesTab();
                          case 2:
                            return const FavoritesPlayersTab();
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, FavoritesScreenMode selectedMode) {
    // Compact glass islands: back circle + title chip (no full-width title row).
    return GlassIslandTopBar(
      horizontalPadding: 12.w,
      topPadding: 0,
      leading: const GlassBackButton(),
      title: GlassTitleChip(
        label: 'Favorites',
        icon: Icon(
          Icons.favorite_rounded,
          color: const Color(0xFFEF4444),
          size: 16.ic,
        ),
      ),
    );
  }

  Widget _buildSegmentedSwitcher(FavoritesScreenMode selectedMode) {
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 20.sp,
      tablet: 32.sp,
    );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: SegmentedSwitcher(
        options: favoritesModeNames.values.toList(),
        initialSelection: favoritesModeNames.values.toList().indexOf(
          favoritesModeNames[selectedMode]!,
        ),
        currentSelection: FavoritesScreenMode.values.indexOf(selectedMode),
        onSelectionChanged: _handleTabSelection,
        notifyOnReselect: true,
      ),
    );
  }
}
