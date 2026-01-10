import 'package:chessever2/screens/favorites/favorite_players_provider.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/library/providers/library_player_profile_provider.dart';
import 'package:chessever2/screens/library/tabs/library_player_about_tab.dart';
import 'package:chessever2/screens/library/tabs/library_player_events_tab.dart';
import 'package:chessever2/screens/library/tabs/library_player_games_tab.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/chess_title_utils.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Enum for library player profile screen tabs
enum LibraryPlayerProfileTab { about, games, events }

/// Tab names for display
const libraryPlayerProfileTabNames = {
  LibraryPlayerProfileTab.about: 'About',
  LibraryPlayerProfileTab.games: 'Games',
  LibraryPlayerProfileTab.events: 'Events',
};

/// Provider for selected tab
final selectedLibraryPlayerProfileTabProvider =
    StateProvider.autoDispose<LibraryPlayerProfileTab>(
      (ref) => LibraryPlayerProfileTab.about,
    );

/// Library player profile screen showing detailed player information
/// with three tabs: About, Games (combined gamebase+supabase), and Events.
class LibraryPlayerProfileScreen extends ConsumerStatefulWidget {
  const LibraryPlayerProfileScreen({super.key, required this.player});

  final GamebasePlayer player;

  @override
  ConsumerState<LibraryPlayerProfileScreen> createState() =>
      _LibraryPlayerProfileScreenState();
}

class _LibraryPlayerProfileScreenState
    extends ConsumerState<LibraryPlayerProfileScreen>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _favoriteAnimationController;
  late Animation<double> _favoriteScaleAnimation;

  /// Get the player profile key for provider lookups
  LibraryPlayerProfileKey get _playerKey => LibraryPlayerProfileKey(
    fideId: int.tryParse(widget.player.fideId),
    playerName: widget.player.name,
    gamebasePlayerId: widget.player.id,
  );

  int? get _fideIdInt => int.tryParse(widget.player.fideId);

  @override
  void initState() {
    super.initState();
    final initialTab = ref.read(selectedLibraryPlayerProfileTabProvider);
    _pageController = PageController(
      initialPage: LibraryPlayerProfileTab.values.indexOf(initialTab),
    );

    _favoriteAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _favoriteScaleAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(
        parent: _favoriteAnimationController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _favoriteAnimationController.dispose();
    super.dispose();
  }

  void _handleTabSelection(int index) {
    HapticFeedbackService.buttonPress();
    ref.read(selectedLibraryPlayerProfileTabProvider.notifier).state =
        LibraryPlayerProfileTab.values[index];
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _handlePageChanged(int index) {
    final currentTab = ref.read(selectedLibraryPlayerProfileTabProvider);
    if (LibraryPlayerProfileTab.values.indexOf(currentTab) != index) {
      ref.read(selectedLibraryPlayerProfileTabProvider.notifier).state =
          LibraryPlayerProfileTab.values[index];
    }
  }

  Future<void> _toggleFavorite() async {
    final allowed = await requireFullAuthGuard(context);
    if (!allowed) return;

    HapticFeedbackService.buttonPress();

    final favoritesNotifier = ref.read(
      favoritePlayersNotifierProvider.notifier,
    );

    // Create a PlayerStandingModel for the favorites system
    final player = PlayerStandingModel(
      name: widget.player.name,
      countryCode: widget.player.fed,
      score: widget.player.highestRating ?? 0,
      scoreChange: 0,
      matchScore: null,
      fideId: _fideIdInt,
      title: ChessTitleUtils.normalize(widget.player.title),
    );

    try {
      final isNowFavorite = await favoritesNotifier.toggleFavorite(player);
      if (isNowFavorite) {
        _favoriteAnimationController.forward().then(
          (_) => _favoriteAnimationController.reverse(),
        );
      }
    } catch (e) {
      debugPrint('Error toggling favorite: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update favorite. Please try again.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedTab = ref.watch(selectedLibraryPlayerProfileTabProvider);
    final displayTitle = ChessTitleUtils.normalize(widget.player.title);

    // Watch favorites to show correct state
    final favoritesAsync = ref.watch(favoritePlayersNotifierProvider);
    final isFavorite = favoritesAsync.maybeWhen(
      data: (state) => state.players.any((p) => p.fideId == _fideIdInt),
      orElse: () => false,
    );

    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth:
                ResponsiveHelper.isTablet
                    ? ResponsiveHelper.contentMaxWidth
                    : double.infinity,
          ),
          child: Column(
            children: [
              SizedBox(height: MediaQuery.of(context).viewPadding.top + 4.h),

              // App bar
              _buildAppBar(context, displayTitle, isFavorite),

              SizedBox(height: 8.h),

              // Tab switcher
              _buildTabSwitcher(selectedTab),

              // Tab content
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: LibraryPlayerProfileTab.values.length,
                  onPageChanged: _handlePageChanged,
                  itemBuilder: (context, index) {
                    switch (LibraryPlayerProfileTab.values[index]) {
                      case LibraryPlayerProfileTab.about:
                        return LibraryPlayerAboutTab(
                          playerKey: _playerKey,
                          player: widget.player,
                        );
                      case LibraryPlayerProfileTab.games:
                        return LibraryPlayerGamesTab(
                          playerKey: _playerKey,
                          player: widget.player,
                        );
                      case LibraryPlayerProfileTab.events:
                        return LibraryPlayerEventsTab(
                          playerKey: _playerKey,
                          player: widget.player,
                        );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(
    BuildContext context,
    String displayTitle,
    bool isFavorite,
  ) {
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 24.w,
    );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Row(
        children: [
          // Back button
          IconButton(
            iconSize: 24.ic,
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.arrow_back_ios_new_outlined,
              size: 24.ic,
              color: kWhiteColor,
            ),
          ),

          // Player name and flag
          Expanded(
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Country flag
                  if (widget.player.fed.toUpperCase() == 'FID')
                    Image.asset(
                      PngAsset.fideLogo,
                      height: 16.h,
                      width: 22.w,
                      fit: BoxFit.cover,
                    )
                  else if (widget.player.fed.isNotEmpty)
                    FederationFlag(
                      federation: widget.player.fed,
                      width: 22.w,
                      height: 16.h,
                      borderRadius: BorderRadius.circular(2.br),
                    ),

                  if (widget.player.fed.isNotEmpty) SizedBox(width: 8.w),

                  // Title and name
                  if (displayTitle.isNotEmpty) ...[
                    Text(
                      displayTitle,
                      style: AppTypography.textSmBold.copyWith(
                        color: const Color(0xFFA1A1AA),
                      ),
                    ),
                    SizedBox(width: 6.w),
                  ],
                  Flexible(
                    child: Text(
                      widget.player.name,
                      style: AppTypography.textLgBold.copyWith(
                        color: kWhiteColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Favorite button
          GestureDetector(
            onTap: _toggleFavorite,
            child: Container(
              width: 48.w,
              height: 48.h,
              padding: EdgeInsets.all(8.sp),
              child: ScaleTransition(
                scale: _favoriteScaleAnimation,
                child: SvgWidget(
                  isFavorite
                      ? SvgAsset.favouriteRedIcon
                      : SvgAsset.favouriteIcon2,
                  semanticsLabel: 'Favorite',
                  height: 22.h,
                  width: 22.w,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabSwitcher(LibraryPlayerProfileTab selectedTab) {
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 20.sp,
      tablet: 32.sp,
    );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: SegmentedSwitcher(
        backgroundColor: kPopUpColor,
        selectedBackgroundColor: kPopUpColor,
        options: libraryPlayerProfileTabNames.values.toList(),
        initialSelection: LibraryPlayerProfileTab.values.indexOf(selectedTab),
        currentSelection: LibraryPlayerProfileTab.values.indexOf(selectedTab),
        onSelectionChanged: _handleTabSelection,
      ),
    );
  }
}
