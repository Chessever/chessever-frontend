import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/favorites/favorite_players_provider.dart';
import 'package:chessever2/screens/player_profile/provider/player_profile_provider.dart';
import 'package:chessever2/screens/player_profile/tabs/player_about_tab.dart';
import 'package:chessever2/screens/player_profile/tabs/player_events_tab.dart';
import 'package:chessever2/screens/player_profile/tabs/player_games_tab.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/country_utils.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

/// Enum for player profile screen tabs
enum PlayerProfileTab { about, games, events }

/// Tab names for display
const playerProfileTabNames = {
  PlayerProfileTab.about: 'About',
  PlayerProfileTab.games: 'Games',
  PlayerProfileTab.events: 'Events',
};

/// Provider for selected tab
final selectedPlayerProfileTabProvider =
    StateProvider.autoDispose<PlayerProfileTab>(
      (ref) => PlayerProfileTab.about,
    );

/// Player profile screen showing detailed player information
/// with three tabs: About, Games, and Events.
class PlayerProfileScreen extends ConsumerStatefulWidget {
  const PlayerProfileScreen({
    super.key,
    this.fideId,
    required this.playerName,
    this.title,
    this.federation,
    this.rating,
  });

  /// FIDE ID - can be null for players without official FIDE registration
  final int? fideId;
  final String playerName;
  final String? title;
  final String? federation;
  final int? rating;

  /// Create from SearchPlayer model
  factory PlayerProfileScreen.fromSearchPlayer(SearchPlayer player) {
    return PlayerProfileScreen(
      fideId: player.fideId,
      playerName: player.name,
      title: player.title,
      federation: player.fed,
      rating: player.rating,
    );
  }

  @override
  ConsumerState<PlayerProfileScreen> createState() =>
      _PlayerProfileScreenState();
}

class _PlayerProfileScreenState extends ConsumerState<PlayerProfileScreen>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _favoriteAnimationController;
  late Animation<double> _favoriteScaleAnimation;

  @override
  void initState() {
    super.initState();
    final initialTab = ref.read(selectedPlayerProfileTabProvider);
    _pageController = PageController(
      initialPage: PlayerProfileTab.values.indexOf(initialTab),
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
    ref.read(selectedPlayerProfileTabProvider.notifier).state =
        PlayerProfileTab.values[index];
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _handlePageChanged(int index) {
    final currentTab = ref.read(selectedPlayerProfileTabProvider);
    if (PlayerProfileTab.values.indexOf(currentTab) != index) {
      ref.read(selectedPlayerProfileTabProvider.notifier).state =
          PlayerProfileTab.values[index];
    }
  }

  void _openGames({
    GameFilter? filter,
    PlayerResultFilter? playerResultFilter,
    String? searchQuery,
  }) {
    HapticFeedbackService.buttonPress();
    final playerKey = PlayerProfileKey(
      fideId: widget.fideId,
      playerName: widget.playerName,
    );
    final notifier = ref.read(playerProfileGamesKeyProvider(playerKey).notifier);

    notifier.applyFilter(filter ?? GameFilter.defaultFilter());
    notifier.setPlayerResultFilter(playerResultFilter ?? PlayerResultFilter.all);
    notifier.setSearchQuery(searchQuery ?? '');

    // Don't auto-switch to Games tab - keep user on current page
    // Badge will indicate filter is applied on Games tab
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
      name: widget.playerName,
      countryCode: widget.federation ?? '',
      score: widget.rating ?? 0,
      scoreChange: 0,
      matchScore: null,
      fideId: widget.fideId,
      title: widget.title,
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
    final selectedTab = ref.watch(selectedPlayerProfileTabProvider);
    final countryCode =
        widget.federation != null
            ? CountryUtils.toIso2Code(widget.federation!) ?? ''
            : '';

    // Watch favorites to show correct state
    final favoritesAsync = ref.watch(favoritePlayersNotifierProvider);
    final isFavorite = favoritesAsync.maybeWhen(
      data: (state) => state.players.any((p) => p.fideId == widget.fideId),
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
              _buildAppBar(context, countryCode, isFavorite),

              SizedBox(height: 8.h),

              // Tab switcher
              _buildTabSwitcher(selectedTab),

              // Tab content with filter indicator bar
              Expanded(
                child: _buildTabContentWithFilterBar(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(
    BuildContext context,
    String countryCode,
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
                  if (widget.federation?.toUpperCase() == 'FID')
                    Image.asset(
                      PngAsset.fideLogo,
                      height: 16.h,
                      width: 22.w,
                      fit: BoxFit.cover,
                    )
                  else if (countryCode.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2.br),
                      child: CountryFlag.fromCountryCode(
                        countryCode,
                        height: 16.h,
                        width: 22.w,
                      ),
                    ),

                  if (countryCode.isNotEmpty ||
                      widget.federation?.toUpperCase() == 'FID')
                    SizedBox(width: 8.w),

                  // Title and name
                  Flexible(
                    child: Text(
                      _formatDisplayName(),
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

  Widget _buildTabSwitcher(PlayerProfileTab selectedTab) {
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 20.sp,
      tablet: 32.sp,
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: SegmentedSwitcher(
        backgroundColor: kPopUpColor,
        selectedBackgroundColor: kPopUpColor,
        options: playerProfileTabNames.values.toList(),
        initialSelection: PlayerProfileTab.values.indexOf(selectedTab),
        currentSelection: PlayerProfileTab.values.indexOf(selectedTab),
        onSelectionChanged: _handleTabSelection,
      ),
    );
  }

  Widget _buildTabContentWithFilterBar() {
    final playerKey = PlayerProfileKey(
      fideId: widget.fideId,
      playerName: widget.playerName,
    );
    final gamesState = ref.watch(playerProfileGamesKeyProvider(playerKey));
    final hasActiveFilter = gamesState.hasActiveFilters;

    return Stack(
      children: [
        // PageView content
        PageView.builder(
          controller: _pageController,
          itemCount: PlayerProfileTab.values.length,
          onPageChanged: _handlePageChanged,
          itemBuilder: (context, index) {
            switch (PlayerProfileTab.values[index]) {
              case PlayerProfileTab.about:
                return PlayerAboutTab(
                  fideId: widget.fideId,
                  playerName: widget.playerName,
                  title: widget.title,
                  federation: widget.federation,
                  fallbackRating: widget.rating,
                  onOpenGames: _openGames,
                );
              case PlayerProfileTab.games:
                return PlayerGamesTab(
                  fideId: widget.fideId,
                  playerName: widget.playerName,
                );
              case PlayerProfileTab.events:
                return PlayerEventsTab(
                  fideId: widget.fideId,
                  playerName: widget.playerName,
                );
            }
          },
        ),
        // Filter active indicator bar at top - visible on all tabs
        SingleMotionBuilder(
          motion: const CupertinoMotion.snappy(),
          value: hasActiveFilter ? 1.0 : 0.0,
          builder: (context, barProgress, _) {
            if (barProgress < 0.01) return const SizedBox.shrink();

            return Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 2.h * barProgress,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      kPrimaryColor.withValues(alpha: 0.0),
                      kPrimaryColor.withValues(alpha: 0.8 * barProgress),
                      kPrimaryColor.withValues(alpha: 0.8 * barProgress),
                      kPrimaryColor.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 0.2, 0.8, 1.0],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  String _formatDisplayName() {
    String displayName = widget.playerName;

    // Handle "Lastname, Firstname" format
    if (displayName.contains(',')) {
      final parts = displayName.split(',');
      if (parts.length >= 2) {
        displayName = '${parts[1].trim()} ${parts[0].trim()}';
      }
    }

    // Prepend title if present
    if (widget.title != null && widget.title!.isNotEmpty) {
      return '${widget.title} $displayName';
    }

    return displayName;
  }
}

/// Model for recent opponent data (keeping for backward compatibility)
class RecentOpponent {
  const RecentOpponent({
    required this.name,
    required this.title,
    required this.countryCode,
    required this.rating,
    required this.result,
    required this.playedAsWhite,
    this.fideId,
  });

  final String name;
  final String? title;
  final String countryCode;
  final int rating;
  final double result; // 1.0 = win, 0.5 = draw, 0.0 = loss
  final bool playedAsWhite;
  final String? fideId;
}
