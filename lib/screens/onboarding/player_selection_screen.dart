import 'dart:async';

import 'package:chessever2/e2e/e2e_config.dart';
import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/widgets/player_initials_avatar.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/providers/pending_favorite_players_provider.dart';
import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/repository/local_storage/favorite/favourate_standings_player_services.dart';
import 'package:chessever2/repository/local_storage/onboarding/onboarding_repository.dart';
import 'package:chessever2/screens/players/providers/player_providers.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:chessever2/services/analytics/analytics_service.dart';
import 'package:chessever2/services/fide_photo_service.dart';
import 'package:chessever2/utils/favorite_constants.dart';
import 'package:chessever2/utils/favorite_limit_guard.dart';
import 'package:chessever2/utils/favorites_migration.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/country_utils.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:chessever2/services/push_notifications_service.dart';
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
        key: e2eKey(E2eIds.playerSelectionRoot),
        backgroundColor: kBackgroundColor,
        body: SafeArea(
          child: PlayerSelectionContent(
            title: 'Follow 3 players to get started',
            subtitle: 'Follow 3+ players to personalize your feed.',
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

    return Container(
      color: kBlackColor,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header section
              Padding(
                padding: EdgeInsets.fromLTRB(20.sp, 12.sp, 20.sp, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Text(
                      title,
                      style: AppTypography.textLgBold.copyWith(
                        color: kWhiteColor,
                      ),
                    ).animate().fadeIn(duration: 300.ms, curve: _springCurve),
                    SizedBox(height: 4.h),
                    // Selection counter
                    Text(
                      'Selected: $selectedCount of $kFreeFavoriteLimit',
                      style: AppTypography.textSmRegular.copyWith(
                        color: kWhiteColor.withOpacity(0.6),
                      ),
                    ).animate().fadeIn(duration: 320.ms, curve: _springCurve),
                    SizedBox(height: 16.h),
                    // Search bar - simplified
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12.br),
                        color: kBlack2Color,
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: 14.sp,
                        vertical: 12.sp,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.search,
                            color: kWhiteColor.withOpacity(0.5),
                            size: 20.ic,
                          ),
                          SizedBox(width: 10.w),
                          Expanded(
                            child: TextField(
                              key: e2eKey(E2eIds.playerSelectionSearchField),
                              controller: searchController,
                              style: AppTypography.textSmRegular.copyWith(
                                color: kWhiteColor,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Find any player...',
                                hintStyle: AppTypography.textSmRegular.copyWith(
                                  color: kWhiteColor.withOpacity(0.4),
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                          if (searchQuery.value.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                searchController.clear();
                                HapticFeedback.lightImpact();
                              },
                              child: Padding(
                                padding: EdgeInsets.only(left: 8.w),
                                child: Icon(
                                  Icons.close_rounded,
                                  color: kWhiteColor.withOpacity(0.5),
                                  size: 20.ic,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ).animate().fadeIn(duration: 360.ms, curve: _springCurve),
                    SizedBox(height: 12.h),
                    // Subtitle tip
                    Text(
                      subtitle,
                      style: AppTypography.textXsRegular.copyWith(
                        color: kWhiteColor.withOpacity(0.6),
                      ),
                    ).animate().fadeIn(duration: 340.ms, curve: _springCurve),
                  ],
                ),
              ),
              SizedBox(height: 12.h),
              // Player list
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
                            padding: EdgeInsets.symmetric(horizontal: 20.sp),
                            child: _buildPlayerList(
                              context,
                              ref,
                              controller: listController,
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
                            ),
                          ),
                ),
              ),
              // Bottom action area
              SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20.sp, 12.sp, 20.sp, 12.sp),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52.h,
                    child: ElevatedButton(
                      key: e2eKey(E2eIds.playerSelectionContinueButton),
                      onPressed:
                          selectedCount >= kFreeFavoriteLimit
                              ? () async {
                                HapticFeedback.mediumImpact();
                                await onComplete();
                              }
                              : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            selectedCount >= kFreeFavoriteLimit
                                ? kWhiteColor
                                : kWhiteColor.withOpacity(0.16),
                        foregroundColor:
                            selectedCount >= kFreeFavoriteLimit
                                ? kBlackColor
                                : kWhiteColor.withOpacity(0.6),
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> markOnboardingComplete(BuildContext context, WidgetRef ref) async {
  // Request notification permission on last page of onboarding (fire and forget)
  if (!E2eConfig.suppressInterruptivePrompts) {
    unawaited(PushNotificationsService.instance.requestPermissionWithDialog());
  }

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
  required List<Map<String, dynamic>> players,
  required Set<String> selectedIds,
  required ValueChanged<Map<String, dynamic>> onToggle,
  required bool isSearching,
  required bool isLoading,
  required bool hasMore,
  required bool isFetchingMore,
}) {
  if (isLoading) {
    return const Center(child: CircularProgressIndicator(color: kWhiteColor));
  }

  if (players.isEmpty) {
    return Center(
      child: Text(
        isSearching ? 'No players found' : 'No players available yet.',
        style: AppTypography.textSmRegular.copyWith(
          color: kWhiteColor.withOpacity(0.6),
        ),
      ),
    );
  }

  return ListView.builder(
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
                  color: kWhiteColor.withOpacity(0.6),
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
        key: ValueKey(fideId),
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

  final isAdding = !selectedIds.value.contains(fideId);

  // Non-onboarding flow: check auth first, then toggle
  if (!isOnboarding) {
    requireFullAuthGuard(context).then((allowed) async {
      if (!allowed) return;

      // Check favorite limit before adding
      if (isAdding) {
        final canAdd = await canAddMoreFavorites(
          context,
          ref,
          isOnboarding: false,
        );
        if (!canAdd) return;
      }

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

  // Onboarding flow: check limit before adding
  if (isAdding) {
    canAddMoreFavorites(
      context,
      ref,
      isOnboarding: true,
      currentSelectedCount: selectedIds.value.length,
    ).then((canAdd) {
      if (!canAdd) return;
      _performToggle(
        ref,
        selectedIds,
        player,
        fideId,
        supabaseUser,
        isFullyAuthenticated,
        isOnboarding: true,
      );
    });
    return;
  }

  // Removing — always allowed
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

class _PlayerTile extends HookWidget {
  const _PlayerTile({
    super.key,
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

  String get _initials {
    final name = (player['name'] ?? '').toString().trim();
    final parts = name.split(', ');
    if (parts.length >= 2) {
      return '${parts[1][0]}${parts[0][0]}'.toUpperCase();
    }
    final words = name.split(' ');
    if (words.length >= 2) {
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : name.length).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final isPressed = useState(false);
    final rating = player['rating'] ?? 0;
    final countryCode = player['fed']?.toString() ?? '';
    final fideId = player['fideId']?.toString() ?? '';
    final flagEmoji = CountryUtils.toFlagEmoji(countryCode);

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
          margin: EdgeInsets.only(bottom: 6.sp),
          padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 10.sp),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(14.br),
          ),
          child: Row(
            children: [
              // Player photo avatar
              _PlayerAvatar(fideId: fideId, initials: _initials, size: 44),
              SizedBox(width: 12.w),
              // Player info with flag emoji
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (flagEmoji.isNotEmpty)
                          Padding(
                            padding: EdgeInsets.only(right: 6.w),
                            child: Text(
                              flagEmoji,
                              style: TextStyle(fontSize: 14.f),
                            ),
                          ),
                        Expanded(
                          child: Text(
                            _playerName,
                            style: AppTypography.textSmMedium.copyWith(
                              color: kWhiteColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      '$rating',
                      style: AppTypography.textXsRegular.copyWith(
                        color: kWhiteColor.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
              // Select indicator - minimal design matching mockup
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: _snappyCurve,
                width: 24.w,
                height: 24.h,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? kGreenColor : Colors.transparent,
                  border: Border.all(
                    color:
                        isSelected
                            ? kGreenColor
                            : kWhiteColor.withOpacity(0.18),
                    width: isSelected ? 0 : 1,
                  ),
                ),
                child: Icon(
                  isSelected ? Icons.check : Icons.add,
                  size: isSelected ? 14.ic : 12.ic,
                  color:
                      isSelected ? kWhiteColor : kWhiteColor.withOpacity(0.3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Widget to display player photo with fallback to initials
class _PlayerAvatar extends HookWidget {
  const _PlayerAvatar({
    required this.fideId,
    required this.initials,
    required this.size,
  });

  final String fideId;
  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    final photoUrl = useState<String?>(null);

    useEffect(() {
      photoUrl.value = null;
      if (fideId.isNotEmpty) {
        FidePhotoService.getPhotoUrlOrNull(fideId).then((url) {
          if (url != null) {
            photoUrl.value = url;
          }
        });
      }
      return null;
    }, [fideId]);

    return PlayerInitialsAvatarCompact(
      photoUrl: photoUrl.value,
      initials: initials,
      size: size.w,
      borderRadius: size.w / 2, // Circular
    );
  }
}
