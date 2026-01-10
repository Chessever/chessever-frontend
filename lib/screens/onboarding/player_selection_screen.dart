import 'dart:async';

import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/providers/pending_favorite_players_provider.dart';
import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/repository/local_storage/favorite/favourate_standings_player_services.dart';
import 'package:chessever2/repository/local_storage/onboarding/onboarding_repository.dart';
import 'package:chessever2/screens/players/providers/player_providers.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:chessever2/services/analytics/analytics_service.dart';
import 'package:chessever2/utils/favorites_migration.dart';
import 'package:chessever2/utils/notification_service.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/country_utils.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/blur_background.dart';
import 'package:chessever2/widgets/rounded_search_bar.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';

final Curve _springCurve = Motion.smoothSpring().toCurve;
final Curve _snappyCurve = Motion.snappySpring().toCurve;

class PlayerSelectionScreen extends HookConsumerWidget {
  const PlayerSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ScreenWrapper(
      child: Scaffold(
        backgroundColor: kBackgroundColor,
        body: SafeArea(
          child: PlayerSelectionContent(
            title: 'Follow at least 3 players to get started',
            subtitle:
                'Build your feed with the players you love — we started with picks from {country}.',
            actionLabel: 'Next',
            onComplete: () => _completeOnboarding(context, ref),
          ),
        ),
      ),
    );
  }

  Future<void> _completeOnboarding(BuildContext context, WidgetRef ref) async {
    await markOnboardingComplete(context, ref);
  }
}

class PlayerSelectionContent extends HookConsumerWidget {
  const PlayerSelectionContent({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onComplete,
    this.badgeLabel,
    super.key,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final Future<void> Function() onComplete;
  final String? badgeLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchController = useTextEditingController();
    final listController = useScrollController();
    final searchQuery = useState('');
    final selectedIds = useState<Set<String>>({});

    final playerState = ref.watch(onboardingPlayerProvider);
    final existingFavorites = ref.watch(favoritePlayersProviderNew);
    final countryState = ref.watch(countryDropdownProvider);

    final players = playerState.valueOrNull ?? [];

    // Get existing favorite fideIds from Supabase (for existing users)
    final existingFavoriteIds = existingFavorites.maybeWhen(
      data:
          (favs) =>
              favs
                  .map((f) => f.fideId ?? '')
                  .where((id) => id.isNotEmpty)
                  .toSet(),
      orElse: () => <String>{},
    );
    final countryCode = countryState.value?.countryCode ?? 'US';
    final countryName = countryState.value?.name ?? 'your region';

    // Debounced search to avoid race conditions with rapid keystrokes
    final debounceTimer = useRef<Timer?>(null);

    useEffect(() {
      void listener() {
        final text = searchController.text;
        searchQuery.value = text;
        ref.read(playerSearchQueryProvider.notifier).state = text;

        // Cancel any existing debounce timer
        debounceTimer.value?.cancel();

        // Debounce the actual search query - wait 300ms after user stops typing
        debounceTimer.value = Timer(const Duration(milliseconds: 300), () {
          ref.read(onboardingPlayerProvider.notifier).setSearchQuery(text);
        });
      }

      searchController.addListener(listener);
      return () {
        debounceTimer.value?.cancel();
        searchController.removeListener(listener);
      };
    }, [searchController]);

    useEffect(() {
      if (countryCode.isNotEmpty) {
        ref.read(onboardingPlayerProvider.notifier).setCountry(countryCode);
      }
      return null;
    }, [countryCode]);

    useEffect(() {
      Future.microtask(() async {
        await ref.read(onboardingPlayerProvider.notifier).initFirstPage();
      });
      return null;
    }, []);

    // Initialize selectedIds from existing Supabase favorites (for existing users)
    // We use the sorted string representation as dependency since Set reference
    // equality doesn't work well with hooks - content changes won't trigger re-run
    final existingFavoriteIdsKey = existingFavoriteIds.toList()..sort();
    useEffect(() {
      if (existingFavoriteIds.isNotEmpty) {
        // Merge existing favorites with any current selections (don't replace)
        selectedIds.value = {...selectedIds.value, ...existingFavoriteIds};
      }
      return null;
    }, [existingFavoriteIdsKey.join(',')]);

    useEffect(() {
      void onScroll() {
        if (!listController.hasClients) return;
        final maxScroll = listController.position.maxScrollExtent;
        final current = listController.position.pixels;

        if (maxScroll - current <= 200) {
          ref.read(onboardingPlayerProvider.notifier).fetchNextPage();
        }
      }

      listController.addListener(onScroll);
      return () => listController.removeListener(onScroll);
    }, [listController]);

    final recommendedResult = _recommendedPlayers(
      players,
      countryCode: countryCode,
    );
    final isSearching = searchQuery.value.isNotEmpty;
    final isLoading = playerState.isLoading && players.isEmpty;
    final selectedCount = selectedIds.value.length;

    // Tablet-specific constraints
    final maxWidth = ResponsiveHelper.isTablet ? 600.0 : double.infinity;
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 20.sp,
      tablet: 24.sp,
    );

    return Stack(
      children: [
        const Positioned.fill(child: BlurBackground()),
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.03),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(20.sp, 18.sp, 20.sp, 4.sp),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (badgeLabel != null) ...[
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 10.sp,
                            vertical: 6.sp,
                          ),
                          decoration: BoxDecoration(
                            color: kWhiteColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12.br),
                            border: Border.all(
                              color: kWhiteColor.withValues(alpha: 0.1),
                            ),
                          ),
                          child: Text(
                            badgeLabel!,
                            style: AppTypography.textXsMedium.copyWith(
                              color: kWhiteColor.withValues(alpha: 0.9),
                            ),
                          ),
                        ),
                        SizedBox(height: 8.h),
                      ],
                      Text(
                        title,
                        style: AppTypography.textLgBold.copyWith(
                          color: kWhiteColor,
                        ),
                      ).animate().fadeIn(duration: 300.ms, curve: _springCurve),
                      SizedBox(height: 6.h),
                      Text(
                            subtitle.replaceFirst('{country}', countryName),
                            style: AppTypography.textSmRegular.copyWith(
                              color: kWhiteColor.withValues(alpha: 0.7),
                            ),
                          )
                          .animate()
                          .fadeIn(duration: 320.ms, curve: _springCurve)
                          .move(begin: const Offset(0, 6)),
                      SizedBox(height: 16.h),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16.br),
                          gradient: LinearGradient(
                            colors: [
                              kPrimaryColor.withValues(alpha: 0.18),
                              kBlack2Color.withValues(alpha: 0.35),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: Border.all(
                            color: kWhiteColor.withValues(alpha: 0.08),
                          ),
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: 12.sp,
                          vertical: 10.sp,
                        ),
                        child: RoundedSearchBar(
                              showProfile: false,
                              controller: searchController,
                              hintText: 'Find any player...',
                              onFilterTap: () {},
                              onProfileTap: () {},
                            )
                            .animate()
                            .fadeIn(duration: 360.ms, curve: _springCurve)
                            .move(begin: const Offset(0, 8)),
                      ),
                      SizedBox(height: 12.h),
                      Row(
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            color: kPrimaryColor,
                            size: 18.ic,
                          ),
                          SizedBox(width: 8.w),
                          Expanded(
                            child: Text(
                              'Follow at least 3 to personalize faster.',
                              style: AppTypography.textXsMedium.copyWith(
                                color: kWhiteColor.withValues(alpha: 0.78),
                              ),
                            ),
                          ),
                        ],
                      ).animate().fadeIn(duration: 340.ms, curve: _springCurve),
                    ],
                  ),
                ),
                SizedBox(height: 8.h),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child:
                        isLoading
                            ? const Center(
                              child: CircularProgressIndicator(
                                color: kWhiteColor,
                              ),
                            )
                            : Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16.sp),
                              child: _buildPlayerList(
                                context,
                                ref,
                                controller: listController,
                                title:
                                    isSearching
                                        ? 'Search results'
                                        : recommendedResult.hasCountryMatches
                                        ? 'Recommended from $countryName'
                                        : 'Top picks right now',
                                players:
                                    isSearching
                                        ? players
                                        : recommendedResult.players,
                                selectedIds: selectedIds.value,
                                onToggle:
                                    (player) => _toggleFavorite(
                                      context,
                                      ref,
                                      selectedIds,
                                      player,
                                      isOnboarding: true,
                                    ),
                                isSearching: isSearching,
                                isLoading: isLoading,
                                hasMore:
                                    ref
                                        .read(onboardingPlayerProvider.notifier)
                                        .hasMore,
                                isFetchingMore:
                                    ref
                                        .read(onboardingPlayerProvider.notifier)
                                        .isFetching,
                                flagCode:
                                    isSearching
                                        ? null
                                        : (recommendedResult.hasCountryMatches
                                            ? countryCode
                                            : null),
                              ),
                            ),
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 20.sp,
                    vertical: 14.sp,
                  ),
                  decoration: BoxDecoration(
                    color: kBlack2Color.withValues(alpha: 0.8),
                    border: Border(
                      top: BorderSide(
                        color: kWhiteColor.withValues(alpha: 0.06),
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, -6),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Selected: $selectedCount of 3',
                                  style: AppTypography.textSmMedium.copyWith(
                                    color:
                                        selectedCount >= 3
                                            ? kGreenColor
                                            : kWhiteColor,
                                  ),
                                ),
                                SizedBox(height: 6.h),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12.br),
                                  child: LinearProgressIndicator(
                                    minHeight: 6.h,
                                    value: (selectedCount / 3).clamp(0, 1),
                                    backgroundColor: kWhiteColor.withValues(
                                      alpha: 0.12,
                                    ),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      selectedCount >= 3
                                          ? kGreenColor
                                          : kPrimaryColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 14.h),
                      SizedBox(
                        width: double.infinity,
                        height: 52.h,
                        child: ElevatedButton(
                          onPressed:
                              selectedCount >= 3
                                  ? () async {
                                    HapticFeedback.mediumImpact();
                                    await onComplete();
                                  }
                                  : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                selectedCount >= 3
                                    ? kWhiteColor
                                    : kWhiteColor.withValues(alpha: 0.16),
                            foregroundColor:
                                selectedCount >= 3
                                    ? kBlackColor
                                    : kWhiteColor.withValues(alpha: 0.6),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14.br),
                            ),
                          ),
                          child: Text(
                            actionLabel,
                            style: AppTypography.textMdMedium,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> markOnboardingComplete(BuildContext context, WidgetRef ref) async {
  // Request notification permission on last page of onboarding (fire and forget)
  unawaited(NotificationService.requestPermissionWithDialog());

  // Ensure we don't lose onboarding selections: do not navigate away if we fail here
  // (user can retry without losing in-memory providers)
  try {
    // If user is not authenticated at all, create an anonymous account
    // This preserves their onboarding selections (favorites, country, etc.)
    var user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (kDebugMode) {
        debugPrint('[Onboarding] No user - creating anonymous account...');
      }
      try {
        await ref.read(authStateProvider.notifier).signInAnonymously();
        user = Supabase.instance.client.auth.currentUser;
        if (kDebugMode) {
          debugPrint('[Onboarding] Anonymous account created: ${user?.id}');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[Onboarding] Failed to create anonymous account: $e');
        }
        // Without an auth session we cannot persist selections safely
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not start guest session. Please try again.'),
            ),
          );
        }
        return;
      }
    }

    // If we still failed to obtain a user, bail out early to avoid losing selections
    if (user == null) {
      if (kDebugMode) {
        debugPrint('[Onboarding] No user session available after attempt');
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not start session. Please try again.'),
          ),
        );
      }
      return;
    }

    // Clean up any legacy favorite event pollution before syncing
    await FavoritesMigration.cleanupBadMigrationDataIfNeeded();

    // Now flush any pending favorite selections to Supabase
    // (works for both anonymous and authenticated users)
    try {
      await ref
          .read(pendingFavoriteSelectionsProvider.notifier)
          .flushToSupabase();
      if (kDebugMode) {
        debugPrint('[Onboarding] Flushed pending favorites to Supabase');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Onboarding] Failed to flush pending favorites: $e');
      }
    }

    await ref.read(onboardingRepositoryProvider).markCompleted(user?.id);
    final favoritePlayers = ref.read(favoritePlayersProviderNew);
    final favoriteCount = favoritePlayers.valueOrNull?.length;
    final isAuthenticated = user?.isAnonymous == false;

    AnalyticsService.instance.trackEventDetached(
      'Onboarding Completed',
      properties: {
        'favorite_player_count': favoriteCount,
        'is_authenticated': isAuthenticated,
        'is_anonymous': user?.isAnonymous == true,
      },
    );
  } catch (e) {
    if (kDebugMode) {
      debugPrint('Failed to mark onboarding complete: $e');
    }
  }

  if (context.mounted) {
    Navigator.pushReplacementNamed(context, '/home_screen');
  }
}

class RecommendedPlayersResult {
  RecommendedPlayersResult({
    required this.players,
    required this.hasCountryMatches,
  });

  final List<Map<String, dynamic>> players;
  final bool hasCountryMatches;
}

RecommendedPlayersResult _recommendedPlayers(
  List<Map<String, dynamic>> players, {
  required String countryCode,
}) {
  if (players.isEmpty) {
    return RecommendedPlayersResult(players: [], hasCountryMatches: false);
  }

  final normalizedCode = countryCode.toUpperCase();
  final fromCountry =
      players
          .where(
            (player) =>
                (player['fed']?.toString().toUpperCase() ?? '') ==
                normalizedCode,
          )
          .toList();

  fromCountry.sort((a, b) => (b['rating'] ?? 0).compareTo(a['rating'] ?? 0));

  final others =
      players
          .where(
            (player) =>
                (player['fed']?.toString().toUpperCase() ?? '') !=
                normalizedCode,
          )
          .toList()
        ..sort((a, b) => (b['rating'] ?? 0).compareTo(a['rating'] ?? 0));

  final hasCountryMatches = fromCountry.isNotEmpty;
  final combined = hasCountryMatches ? [...fromCountry, ...others] : others;

  return RecommendedPlayersResult(
    players: combined, // No limit - allow infinite scroll
    hasCountryMatches: hasCountryMatches,
  );
}

Widget _buildPlayerList(
  BuildContext context,
  WidgetRef ref, {
  required ScrollController controller,
  required String title,
  required List<Map<String, dynamic>> players,
  required Set<String> selectedIds,
  required ValueChanged<Map<String, dynamic>> onToggle,
  required bool isSearching,
  required bool isLoading,
  required bool hasMore,
  required bool isFetchingMore,
  String? flagCode,
}) {
  if (isLoading) {
    return const Center(child: CircularProgressIndicator(color: kWhiteColor));
  }

  if (players.isEmpty) {
    return Center(
      child: Text(
        isSearching ? 'No players found' : 'No players available yet.',
        style: AppTypography.textSmRegular.copyWith(
          color: kWhiteColor.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: EdgeInsets.only(bottom: 8.sp),
        child: Wrap(
          spacing: 8.w,
          runSpacing: 6.h,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              title,
              style: AppTypography.textMdBold.copyWith(color: kWhiteColor),
            ),
            if (!isSearching && flagCode != null)
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 10.sp,
                  vertical: 6.sp,
                ),
                decoration: BoxDecoration(
                  color: kWhiteColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12.br),
                  border: Border.all(
                    color: kWhiteColor.withValues(alpha: 0.15),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildFlag(
                      flagCode.toUpperCase(),
                      height: 14.h,
                      width: 20.w,
                    ),
                    SizedBox(width: 6.w),
                    Text(
                      'Handpicked',
                      style: AppTypography.textXsMedium.copyWith(
                        color: kWhiteColor,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      Expanded(
        child: ListView.builder(
          controller: controller,
          padding: EdgeInsets.zero,
          physics: const BouncingScrollPhysics(),
          itemCount: players.length + (hasMore ? 1 : 0),
          itemBuilder: (context, index) {
            // Loading indicator at bottom
            if (index >= players.length) {
              return AnimatedOpacity(
                opacity: isFetchingMore ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 20.sp),
                  child: Center(
                    child: SizedBox(
                      width: 24.w,
                      height: 24.h,
                      child: CircularProgressIndicator(
                        color: kWhiteColor.withValues(alpha: 0.6),
                        strokeWidth: 2.5,
                      ),
                    ),
                  ),
                ),
              );
            }

            final player = players[index];
            final fideId = player['fideId']?.toString() ?? '';
            final isSelected = selectedIds.contains(fideId);
            // Only animate first batch, skip animation for loaded items
            final shouldAnimate = index < 15;
            final delay = shouldAnimate ? (index * 18).ms : Duration.zero;

            final tile = _PlayerTile(
              player: player,
              isSelected: isSelected,
              onTap: () => onToggle(player),
            );

            return shouldAnimate
                ? tile
                    .animate(delay: delay)
                    .fadeIn(duration: 300.ms, curve: _springCurve)
                    .move(begin: const Offset(0, 8), curve: _springCurve)
                : tile;
          },
        ),
      ),
    ],
  );
}

/// Toggle favorite - MUST be instant for UI, async ops fire in background
void _toggleFavorite(
  BuildContext context,
  WidgetRef ref,
  ValueNotifier<Set<String>> selectedIds,
  Map<String, dynamic> player, {
  bool isOnboarding = false,
}) {
  final fideId = player['fideId']?.toString();
  if (fideId == null || fideId.isEmpty) return;

  final supabaseUser = Supabase.instance.client.auth.currentUser;
  final isFullyAuthenticated =
      supabaseUser != null && supabaseUser.isAnonymous != true;

  // Non-onboarding flow: check auth first, then toggle
  if (!isOnboarding) {
    requireFullAuthGuard(context).then((allowed) {
      if (!allowed) return;
      _performToggle(
        ref,
        selectedIds,
        player,
        fideId,
        supabaseUser,
        isFullyAuthenticated,
        isOnboarding: false,
      );
    });
    return;
  }

  // Onboarding flow: INSTANT toggle, no auth check needed
  _performToggle(
    ref,
    selectedIds,
    player,
    fideId,
    supabaseUser,
    isFullyAuthenticated,
    isOnboarding: true,
  );
}

/// Performs the actual toggle - all sync, async ops fire in background
void _performToggle(
  WidgetRef ref,
  ValueNotifier<Set<String>> selectedIds,
  Map<String, dynamic> player,
  String fideId,
  User? supabaseUser,
  bool isFullyAuthenticated, {
  required bool isOnboarding,
}) {
  // INSTANT UI UPDATE - this is sync, happens immediately
  final updated = Set<String>.from(selectedIds.value);
  if (updated.contains(fideId)) {
    updated.remove(fideId);
  } else {
    updated.add(fideId);
  }
  selectedIds.value = updated;
  final isSelected = updated.contains(fideId);

  // Analytics - fire and forget
  AnalyticsService.instance.trackEventDetached(
    'Onboarding Player Toggled',
    properties: {
      'fide_id': fideId,
      'player_name': (player['name'] ?? '').toString().trim(),
      'player_title': player['title']?.toString(),
      'country_code': player['fed']?.toString(),
      'rating': player['rating'],
      'is_selected': isSelected,
    },
  );

  // Fire off remote/local toggles without blocking
  unawaited(ref.read(onboardingPlayerProvider.notifier).toggleFavorite(fideId));

  // Store in pending favorites provider (sync operation)
  // Note: playerName should NOT include title - title is stored separately in metadata
  ref
      .read(pendingFavoriteSelectionsProvider.notifier)
      .setSelection(
        PendingFavoritePlayer(
          fideId: fideId,
          playerName: (player['name'] ?? '').toString().trim(),
          countryCode: player['fed']?.toString(),
          rating: player['rating'] as int?,
          title: player['title']?.toString(),
          isSelected: isSelected,
        ),
      );

  // Background sync to Supabase - fire and forget
  if (isOnboarding) {
    // ONBOARDING FLOW: Only use pendingFavoriteSelectionsProvider
    // and let flushToSupabase() handle the actual DB write at the end.
    // This prevents double-syncing (which causes duplicate UI issues).
    if (supabaseUser != null && supabaseUser.isAnonymous == true) {
      // User is anonymous - flush pending favorites in background
      unawaited(
        ref.read(pendingFavoriteSelectionsProvider.notifier).flushToSupabase(),
      );
    }
    // For fully authenticated users during onboarding, pending selections
    // will be flushed in markOnboardingComplete() - don't double-sync here
  } else {
    // NON-ONBOARDING FLOW: Sync directly to Supabase for authenticated users
    if (isFullyAuthenticated) {
      unawaited(
        Future(() async {
          try {
            // Note: name should NOT include title - title is stored separately
            final playerModel = PlayerStandingModel(
              name: (player['name'] ?? '').toString().trim(),
              countryCode: player['fed']?.toString() ?? '',
              score: player['rating'] ?? 0,
              scoreChange: 0,
              matchScore: null,
              fideId: int.tryParse(fideId),
              title: player['title']?.toString(),
            );

            await ref
                .read(favoriteStandingsPlayerService)
                .toggleFavorite(playerModel);
            ref.read(favoritesVersionProvider.notifier).state++;
          } catch (e) {
            if (kDebugMode) {
              debugPrint('Failed to sync favorite: $e');
            }
          }
        }),
      );
    } else if (supabaseUser != null) {
      // User is anonymous outside onboarding - flush pending favorites
      unawaited(
        ref.read(pendingFavoriteSelectionsProvider.notifier).flushToSupabase(),
      );
    }
  }
}

Widget _buildFlag(String countryCode, {double? height, double? width}) {
  final normalized = countryCode.toUpperCase();

  // Countries that show white/blank flags due to sanctions or restrictions
  // Use FIDE logo as fallback for these
  const restrictedCountries = {'RUS', 'BLR', 'FID'};

  if (normalized.isEmpty || restrictedCountries.contains(normalized)) {
    return Image.asset(
      PngAsset.fideLogo,
      height: height,
      width: width,
      fit: BoxFit.contain,
      errorBuilder:
          (_, __, ___) => Icon(
            Icons.flag_rounded,
            size: height,
            color: kWhiteColor.withValues(alpha: 0.5),
          ),
    );
  }

  // Convert FIDE 3-letter code to ISO 2-letter code for CountryFlag widget
  final iso2Code = CountryUtils.toIso2Code(normalized);

  return CountryFlag.fromCountryCode(iso2Code, height: height, width: width);
}

class _PlayerTile extends HookWidget {
  const _PlayerTile({
    required this.player,
    required this.isSelected,
    required this.onTap,
  });

  final Map<String, dynamic> player;
  final bool isSelected;
  final VoidCallback onTap;

  String get _playerName {
    final title = (player['title'] ?? '').toString().trim();
    final name = (player['name'] ?? '').toString().trim();
    return [title, name].where((part) => part.isNotEmpty).join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final isPressed = useState(false);
    final rating = player['rating'] ?? 0;
    final countryCode = player['fed']?.toString() ?? '';

    return GestureDetector(
      onTapDown: (_) => isPressed.value = true,
      onTapUp: (_) {
        isPressed.value = false;
        HapticFeedback.selectionClick();
        onTap();
      },
      onTapCancel: () => isPressed.value = false,
      child: AnimatedScale(
        scale: isPressed.value ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: _snappyCurve,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: _springCurve,
          margin: EdgeInsets.only(bottom: 10.sp),
          decoration: BoxDecoration(
            color:
                isSelected
                    ? kGreenColor.withValues(alpha: 0.08)
                    : kBlack2Color.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(16.br),
            border: Border.all(
              color:
                  isSelected
                      ? kGreenColor.withValues(alpha: 0.5)
                      : kWhiteColor.withValues(alpha: 0.04),
              width: isSelected ? 1.5 : 1,
            ),
            boxShadow:
                isSelected
                    ? [
                      BoxShadow(
                        color: kGreenColor.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ]
                    : null,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 14.sp, vertical: 12.sp),
            child: Row(
              children: [
                // Flag avatar
                Container(
                  width: 44.w,
                  height: 44.h,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: kWhiteColor.withValues(alpha: 0.05),
                    border: Border.all(
                      color: kWhiteColor.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Center(
                    child: _buildFlag(
                      countryCode.isEmpty ? 'US' : countryCode,
                      height: 18.h,
                      width: 26.w,
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
                // Player info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _playerName,
                        style: AppTypography.textSmMedium.copyWith(
                          color: kWhiteColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        '$rating ELO',
                        style: AppTypography.textXsRegular.copyWith(
                          color: kWhiteColor.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                // Select indicator
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: _snappyCurve,
                  width: 38.w,
                  height: 38.h,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        isSelected
                            ? kGreenColor
                            : kWhiteColor.withValues(alpha: 0.05),
                    border: Border.all(
                      color:
                          isSelected
                              ? kGreenColor
                              : kWhiteColor.withValues(alpha: 0.15),
                      width: 1.5,
                    ),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    child:
                        isSelected
                            ? Icon(
                              Icons.check,
                              key: const ValueKey('check'),
                              size: 18.ic,
                              color: kWhiteColor,
                            )
                            : Icon(
                              Icons.add,
                              key: const ValueKey('add'),
                              size: 18.ic,
                              color: kWhiteColor.withValues(alpha: 0.5),
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
