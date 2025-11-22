import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/repository/local_storage/favorite/favourate_standings_player_services.dart';
import 'package:chessever2/repository/local_storage/onboarding/onboarding_repository.dart';
import 'package:chessever2/screens/players/providers/player_providers.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
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
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  final favorites = ref.watch(favoritePlayersProvider);
  final countryState = ref.watch(countryDropdownProvider);

  final players = playerState.valueOrNull ?? [];
    final countryCode = countryState.value?.countryCode ?? 'US';
    final countryName = countryState.value?.name ?? 'your region';

    useEffect(() {
      void listener() {
        final text = searchController.text;
        searchQuery.value = text;
        ref.read(playerSearchQueryProvider.notifier).state = text;
        ref.read(onboardingPlayerProvider.notifier).setSearchQuery(text);
      }

      searchController.addListener(listener);
      return () => searchController.removeListener(listener);
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

    useEffect(() {
      selectedIds.value =
          favorites.map((player) => player['fideId'].toString()).toSet();
      return null;
    }, [favorites]);

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

    final recommendedResult =
        _recommendedPlayers(players, countryCode: countryCode);
    final isSearching = searchQuery.value.isNotEmpty;
    final isLoading = playerState.isLoading && players.isEmpty;
    final selectedCount = selectedIds.value.length;

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
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20.sp, 18.sp, 20.sp, 4.sp),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (badgeLabel != null) ...[
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 10.sp, vertical: 6.sp),
                      decoration: BoxDecoration(
                        color: kWhiteColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12.br),
                        border: Border.all(color: kWhiteColor.withValues(alpha: 0.1)),
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
                  ).animate().fadeIn(duration: 320.ms, curve: _springCurve).move(begin: const Offset(0, 6)),
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
                    ).animate().fadeIn(duration: 360.ms, curve: _springCurve).move(begin: const Offset(0, 8)),
                  ),
                  SizedBox(height: 12.h),
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, color: kPrimaryColor, size: 18.ic),
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
                                isSearching ? players : recommendedResult.players,
                            selectedIds: selectedIds.value,
                            onToggle: (player) => _toggleFavorite(
                              ref,
                              selectedIds,
                              player,
                            ),
                            isSearching: isSearching,
                            isLoading: isLoading,
                            hasMore: ref
                                .read(onboardingPlayerProvider.notifier)
                                .hasMore,
                            isFetchingMore: ref
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
                                backgroundColor:
                                    kWhiteColor.withValues(alpha: 0.12),
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
      ],
    );
  }
}

Future<void> markOnboardingComplete(BuildContext context, WidgetRef ref) async {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  try {
    await ref.read(onboardingRepositoryProvider).markCompleted(userId);
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
  final fromCountry = players
      .where(
        (player) =>
            (player['fed']?.toString().toUpperCase() ?? '') == normalizedCode,
      )
      .toList();

  fromCountry.sort((a, b) => (b['rating'] ?? 0).compareTo(a['rating'] ?? 0));

  final others = players
      .where(
        (player) =>
            (player['fed']?.toString().toUpperCase() ?? '') != normalizedCode,
      )
      .toList()
    ..sort((a, b) => (b['rating'] ?? 0).compareTo(a['rating'] ?? 0));

  final hasCountryMatches = fromCountry.isNotEmpty;
  final combined = hasCountryMatches
      ? [...fromCountry, ...others]
      : others;

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
    return const Center(
      child: CircularProgressIndicator(
        color: kWhiteColor,
      ),
    );
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
                padding: EdgeInsets.symmetric(horizontal: 10.sp, vertical: 6.sp),
                decoration: BoxDecoration(
                  color: kWhiteColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12.br),
                  border: Border.all(color: kWhiteColor.withValues(alpha: 0.15)),
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

Future<void> _toggleFavorite(
  WidgetRef ref,
  ValueNotifier<Set<String>> selectedIds,
  Map<String, dynamic> player,
) async {
  final fideId = player['fideId']?.toString();
  if (fideId == null || fideId.isEmpty) return;

  await ref.read(onboardingPlayerProvider.notifier).toggleFavorite(fideId);

  final updated = Set<String>.from(selectedIds.value);
  if (updated.contains(fideId)) {
    updated.remove(fideId);
  } else {
    updated.add(fideId);
  }
  selectedIds.value = updated;

  try {
    final playerModel = PlayerStandingModel(
      name: '${player['title'] ?? ''} ${player['name']}'.trim(),
      countryCode: player['fed']?.toString() ?? '',
      score: player['rating'] ?? 0,
      scoreChange: 0,
      matchScore: null,
      fideId: int.tryParse(fideId),
      title: player['title']?.toString(),
    );

    await ref.read(favoriteStandingsPlayerService).toggleFavorite(playerModel);
    ref.read(favoritesVersionProvider.notifier).state++;
  } catch (e) {
    if (kDebugMode) {
      debugPrint('Failed to sync favorite: $e');
    }
  }
}

Widget _buildFlag(
  String countryCode, {
  double? height,
  double? width,
}) {
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
      errorBuilder: (_, __, ___) => Icon(
        Icons.flag_rounded,
        size: height,
        color: kWhiteColor.withValues(alpha: 0.5),
      ),
    );
  }

  // Convert FIDE 3-letter code to ISO 2-letter code for CountryFlag widget
  final iso2Code = CountryUtils.toIso2Code(normalized);

  return CountryFlag.fromCountryCode(
    iso2Code,
    height: height,
    width: width,
  );
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
            color: isSelected
                ? kGreenColor.withValues(alpha: 0.08)
                : kBlack2Color.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(16.br),
            border: Border.all(
              color: isSelected
                  ? kGreenColor.withValues(alpha: 0.5)
                  : kWhiteColor.withValues(alpha: 0.04),
              width: isSelected ? 1.5 : 1,
            ),
            boxShadow: isSelected
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
                    color: isSelected
                        ? kGreenColor
                        : kWhiteColor.withValues(alpha: 0.05),
                    border: Border.all(
                      color: isSelected
                          ? kGreenColor
                          : kWhiteColor.withValues(alpha: 0.15),
                      width: 1.5,
                    ),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    child: isSelected
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
