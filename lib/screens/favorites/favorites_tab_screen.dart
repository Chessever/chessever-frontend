import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/screens/favorites/provider/favorites_mode_provider.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_games_tab.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_list_tab.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/screens/favorites/widgets/collection_inks.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
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

  /// [FavoritesTabScreen.initialMode] until it reaches the mode provider after
  /// the first frame. The title row reads it so a screen opened on another
  /// page never mounts the Games controls, which would start a games fetch.
  FavoritesScreenMode? _pendingInitialMode;

  @override
  void initState() {
    super.initState();
    final initialMode = widget.initialMode;
    final FavoritesScreenMode mode =
        initialMode ?? ref.read(selectedFavoritesModeProvider);
    _pendingInitialMode = initialMode;
    if (initialMode != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _pendingInitialMode = null;
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

    return Scaffold(
      key: e2eKey(E2eIds.favoritesRoot),
      backgroundColor: context.colors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.contentMaxWidth,
          ),
          child: Column(
            children: [
              SizedBox(height: MediaQuery.viewPaddingOf(context).top + 4.h),
              _buildAppBar(context, _pendingInitialMode ?? selectedMode),
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
    );
  }

  /// Back, the title, and on the Games page that page's one-tap controls
  /// (Trello #1420): the title moves left beside back to make room for them.
  /// Every other page keeps the title centred.
  Widget _buildAppBar(BuildContext context, FavoritesScreenMode selectedMode) {
    final isGames = selectedMode == FavoritesScreenMode.games;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Row(
        children: [
          IconButton(
            iconSize: 24.ic,
            padding: EdgeInsets.zero,
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.arrow_back_ios_new_outlined,
              size: 24.ic,
              color: context.colors.textPrimary,
            ),
          ),
          if (isGames) ...[
            const Expanded(child: _FavoritesTitle(dropHeartWhenTight: true)),
            const FavoritesGamesTitleControls(),
          ] else ...[
            const Expanded(child: Center(child: _FavoritesTitle())),
            SizedBox(width: 48.w), // Placeholder for symmetry
          ],
        ],
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
        dotScope: 'favorites.tab',
        backgroundColor: context.colors.popup,
        selectedBackgroundColor: context.colors.popup,
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

/// The heart and "Favorites". The title ellipsizes rather than overflow, and
/// with [dropHeartWhenTight] the heart (the least important piece) goes first
/// when the row cannot hold both at the reader's text size.
class _FavoritesTitle extends StatelessWidget {
  const _FavoritesTitle({this.dropHeartWhenTight = false});

  final bool dropHeartWhenTight;

  static const String _title = 'Favorites';

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.textLgBold.copyWith(
      color: context.colors.textPrimary,
    );
    final heartSize = 20.ic;
    final gap = 8.w;

    Widget row({required bool showHeart}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showHeart) ...[
          Icon(
            Icons.favorite,
            color: context.collectionAlertInk,
            size: heartSize,
          ),
          SizedBox(width: gap),
        ],
        Flexible(
          child: Text(
            _title,
            style: style,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    if (!dropHeartWhenTight) return row(showHeart: true);
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: _title, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final fits = heartSize + gap + painter.width <= constraints.maxWidth;
        painter.dispose();
        return row(showHeart: fits);
      },
    );
  }
}
