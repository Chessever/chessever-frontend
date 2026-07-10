import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/screens/favorites/provider/favorites_mode_provider.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_games_tab.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_list_tab.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/liquid_glass/chrome_scroll_collapse.dart';
import 'package:chessever2/widgets/liquid_glass/glass_back_button.dart';
import 'package:chessever2/widgets/liquid_glass/glass_floating_segments.dart';
import 'package:chessever2/widgets/liquid_glass/glass_full_screen_page.dart';
import 'package:chessever2/widgets/liquid_glass/glass_island_stack.dart';
import 'package:chessever2/widgets/liquid_glass/glass_island_top_bar.dart';
import 'package:chessever2/widgets/liquid_glass/glass_motion.dart';
import 'package:chessever2/widgets/liquid_glass/glass_title_chip.dart';
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
      _showPage(index);
      // New tab starts expanded at top.
      if (!_chromeCollapse.expanded) {
        setState(_chromeCollapse.reset);
      }
    } catch (e) {
      debugPrint('Error handling tab selection: $e');
    }
  }

  void _showPage(int index) {
    if (GlassMotion.reduceMotion(context)) {
      _pageController.jumpToPage(index);
      return;
    }
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
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
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final scaledLabelHeight = MediaQuery.textScalerOf(context).scale(14) * 1.2;
    final controlHeight = (scaledLabelHeight + 24).clamp(48.0, 72.0).toDouble();
    final contentTopInset = viewPadding.top + controlHeight * 2 + 24;
    final keepSegmentsExpanded = GlassMotion.reduceMotion(context);

    return GlassFullScreenPage(
      key: e2eKey(E2eIds.favoritesRoot),
      backgroundColor: context.colors.background,
      includeContentSafeArea: false,
      topOverlayPadding: const EdgeInsets.only(top: 4),
      topOverlay: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.contentMaxWidth,
          ),
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            label: 'Favorites controls',
            child: GlassIslandStack(
              key: const ValueKey<String>('favorites-floating-controls'),
              includeStatusBar: false,
              gap: 6,
              children: [
                GlassIslandTopBar(
                  horizontalPadding: 12.w,
                  topPadding: 0,
                  height: controlHeight,
                  leading: const GlassBackButton(),
                  title: GlassTitleChip(
                    label: 'Favorites',
                    height: controlHeight,
                    icon: Icon(
                      Icons.favorite_rounded,
                      color: const Color(0xFFEF4444),
                      size: 16.ic,
                    ),
                  ),
                ),
                Semantics(
                  container: true,
                  label: 'Favorites sections',
                  value: favoritesModeNames[selectedMode],
                  child: SizedBox(
                    key: const ValueKey<String>('favorites-segments'),
                    height: controlHeight,
                    child: Center(
                      child: GlassFloatingSegments(
                        options: favoritesModeNames.values.toList(),
                        selectedIndex: selectedIndex.clamp(
                          0,
                          favoritesModeNames.length - 1,
                        ),
                        onSelected: _handleTabSelection,
                        expanded:
                            keepSegmentsExpanded || _chromeCollapse.expanded,
                        notifyOnReselect: true,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      content: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.contentMaxWidth,
          ),
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: ScrollToTopScope(
              bus: _scrollToTopBus,
              child: PageView.builder(
                key: const ValueKey<String>('favorites-page-view'),
                controller: _pageController,
                itemCount: 3,
                onPageChanged: _handlePageChanged,
                itemBuilder: (context, index) {
                  final page = switch (index) {
                    0 => const FavoritesListTab(),
                    1 => const FavoritesGamesTab(),
                    2 => const FavoritesPlayersTab(),
                    _ => Center(
                      child: Text(
                        'Invalid page index: $index',
                        style: TextStyle(color: context.colors.textPrimary),
                      ),
                    ),
                  };
                  return Padding(
                    padding: EdgeInsets.only(
                      top: contentTopInset,
                      bottom: viewPadding.bottom,
                    ),
                    child: page,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
