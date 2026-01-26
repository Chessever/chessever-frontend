import 'dart:async';

import 'package:chessever2/repository/supabase/chess_player/chess_player_repository.dart';
import 'package:chessever2/widgets/player_initials_avatar.dart';
import 'package:chessever2/screens/favorites/favorite_players_provider.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/score_card_screen.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/services/fide_photo_service.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/scroll_to_top_button.dart';
import 'package:chessever2/widgets/search/gameSearch/enhanced_game_search_widget.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:skeletonizer/skeletonizer.dart' as skel;

// Provider for player photo URLs - autoDispose for memory efficiency
final playerPhotoProvider = FutureProvider.autoDispose.family<String?, int?>(
  (ref, fideId) async {
    if (fideId == null) return null;
    return FidePhotoService.getPhotoUrlOrNull(fideId.toString());
  },
);

// Provider for world players search
final worldPlayersSearchProvider = StateNotifierProvider.autoDispose<
    WorldPlayersSearchNotifier, WorldPlayersSearchState>(
  (ref) => WorldPlayersSearchNotifier(ref),
);

class WorldPlayersSearchState {
  final List<PlayerStandingModel> players;
  final bool isLoading;
  final bool hasMore;
  final int offset;
  final String searchQuery;
  final String? error;

  const WorldPlayersSearchState({
    this.players = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.offset = 0,
    this.searchQuery = '',
    this.error,
  });

  bool get isSearching => searchQuery.isNotEmpty;

  WorldPlayersSearchState copyWith({
    List<PlayerStandingModel>? players,
    bool? isLoading,
    bool? hasMore,
    int? offset,
    String? searchQuery,
    String? error,
  }) {
    return WorldPlayersSearchState(
      players: players ?? this.players,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      offset: offset ?? this.offset,
      searchQuery: searchQuery ?? this.searchQuery,
      error: error,
    );
  }
}

class WorldPlayersSearchNotifier extends StateNotifier<WorldPlayersSearchState> {
  final Ref _ref;
  static const int _pageSize = 30;

  WorldPlayersSearchNotifier(this._ref)
      : super(const WorldPlayersSearchState(isLoading: true)) {
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    await _fetchPlayers(isInitial: true);
  }

  Future<void> _fetchPlayers({required bool isInitial}) async {
    if (!mounted) return;

    state = state.copyWith(isLoading: true);

    try {
      final repo = _ref.read(chessPlayerRepositoryProvider);
      final offset = isInitial ? 0 : state.offset;

      final players = state.isSearching
          ? await repo.searchAllPlayers(
              query: state.searchQuery,
              limit: _pageSize,
              offset: offset,
            )
          : await repo.getTopPlayers(
              limit: _pageSize,
              offset: offset,
            );

      final playerModels = players
          .map((p) => PlayerStandingModel(
                name: p.name,
                countryCode: _fideFedToCountryCode(p.country),
                score: p.rating ?? 0,
                scoreChange: 0,
                matchScore: null,
                title: p.title,
                fideId: p.fideid,
              ))
          .toList();

      final allPlayers =
          isInitial ? playerModels : [...state.players, ...playerModels];

      if (!mounted) return;

      state = state.copyWith(
        players: allPlayers,
        isLoading: false,
        hasMore: players.length >= _pageSize,
        offset: offset + players.length,
      );
    } catch (e) {
      debugPrint('[WorldPlayersSearch] Error: $e');
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore) return;
    await _fetchPlayers(isInitial: false);
  }

  Future<void> search(String query) async {
    final trimmed = query.trim();

    if (trimmed.isEmpty) {
      await clearSearch();
      return;
    }

    state = state.copyWith(
      searchQuery: trimmed,
      players: [],
      offset: 0,
      hasMore: true,
    );

    await _fetchPlayers(isInitial: true);
  }

  Future<void> clearSearch() async {
    if (!state.isSearching) return;

    state = state.copyWith(
      searchQuery: '',
      players: [],
      offset: 0,
      hasMore: true,
    );

    await _fetchPlayers(isInitial: true);
  }

  Future<void> refresh() async {
    state = const WorldPlayersSearchState(isLoading: true);
    await _loadInitial();
  }

  /// Convert FIDE federation code to ISO country code
  String _fideFedToCountryCode(String? fed) {
    if (fed == null || fed.isEmpty) return '';
    // Most FIDE federation codes are already ISO 3166-1 alpha-3
    // We need to map some special cases
    final mapping = <String, String>{
      'USA': 'US',
      'RUS': 'RU',
      'GER': 'DE',
      'ENG': 'GB',
      'NED': 'NL',
      'SUI': 'CH',
      'ESP': 'ES',
      'FRA': 'FR',
      'ITA': 'IT',
      'CHN': 'CN',
      'IND': 'IN',
      'NOR': 'NO',
      'POL': 'PL',
      'UKR': 'UA',
      'AZE': 'AZ',
      'ARM': 'AM',
      'GEO': 'GE',
      'ISR': 'IL',
      'TUR': 'TR',
      'CZE': 'CZ',
      'HUN': 'HU',
      'SRB': 'RS',
      'CRO': 'HR',
      'SLO': 'SI',
      'AUT': 'AT',
      'BEL': 'BE',
      'DEN': 'DK',
      'SWE': 'SE',
      'FIN': 'FI',
      'GRE': 'GR',
      'POR': 'PT',
      'ARG': 'AR',
      'BRA': 'BR',
      'PER': 'PE',
      'CUB': 'CU',
      'MEX': 'MX',
      'CAN': 'CA',
      'AUS': 'AU',
      'PHI': 'PH',
      'VIE': 'VN',
      'IRI': 'IR',
      'KAZ': 'KZ',
      'UZB': 'UZ',
      'SGP': 'SG',
      'MAS': 'MY',
      'INA': 'ID',
      'EGY': 'EG',
      'RSA': 'ZA',
      'LAT': 'LV',
      'LTU': 'LT',
      'EST': 'EE',
      'BLR': 'BY',
      'MDA': 'MD',
      'ROU': 'RO',
      'BUL': 'BG',
      'SVK': 'SK',
      'SCO': 'GB-SCT',
      'WAL': 'GB-WLS',
      'IRL': 'IE',
      'ISL': 'IS',
      'LUX': 'LU',
      'MNC': 'MC',
      'AND': 'AD',
      'SYR': 'SY',
      'JOR': 'JO',
      'LBN': 'LB',
      'IRQ': 'IQ',
      'UAE': 'AE',
      'KSA': 'SA',
      'QAT': 'QA',
      'KUW': 'KW',
      'BRN': 'BH',
      'PAK': 'PK',
      'BAN': 'BD',
      'SRI': 'LK',
      'NEP': 'NP',
      'AFG': 'AF',
      'MGL': 'MN',
      'JPN': 'JP',
      'KOR': 'KR',
      'TPE': 'TW',
      'HKG': 'HK',
      'MAC': 'MO',
      'THA': 'TH',
      'MYA': 'MM',
      'LAO': 'LA',
      'CAM': 'KH',
      'BRU': 'BN',
      'NZL': 'NZ',
      'FIJ': 'FJ',
      'PNG': 'PG',
      'SOL': 'SB',
      'NGR': 'NG',
      'GHA': 'GH',
      'KEN': 'KE',
      'UGA': 'UG',
      'TAN': 'TZ',
      'ZAM': 'ZM',
      'ZIM': 'ZW',
      'BOT': 'BW',
      'NAM': 'NA',
      'MAD': 'MG',
      'MRI': 'MU',
      'SEY': 'SC',
      'TUN': 'TN',
      'ALG': 'DZ',
      'MAR': 'MA',
      'LBA': 'LY',
      'SUD': 'SD',
      'ETH': 'ET',
      'SEN': 'SN',
      'CIV': 'CI',
      'CMR': 'CM',
      'COD': 'CD',
      'ANG': 'AO',
      'MOZ': 'MZ',
      'MLI': 'ML',
      'BUR': 'BF',
      'GAM': 'GM',
      'MLT': 'MT',
      'CYP': 'CY',
      'BIH': 'BA',
      'MKD': 'MK',
      'MNE': 'ME',
      'ALB': 'AL',
      'KOS': 'XK',
      'COL': 'CO',
      'VEN': 'VE',
      'ECU': 'EC',
      'CHI': 'CL',
      'PAR': 'PY',
      'URU': 'UY',
      'BOL': 'BO',
      'GUA': 'GT',
      'CRC': 'CR',
      'PAN': 'PA',
      'HON': 'HN',
      'ESA': 'SV',
      'NCA': 'NI',
      'DOM': 'DO',
      'PUR': 'PR',
      'JAM': 'JM',
      'TRI': 'TT',
      'BAR': 'BB',
      'HAI': 'HT',
      'SUR': 'SR',
      'GUY': 'GY',
      'BER': 'BM',
      'ARU': 'AW',
      'ANT': 'AN',
      'CAY': 'KY',
      'BVI': 'VG',
      'VIR': 'VI',
      'BAH': 'BS',
      'GUM': 'GU',
      'SAM': 'WS',
      'TGA': 'TO',
      'VAN': 'VU',
      'COK': 'CK',
      'NCL': 'NC',
      'PLE': 'PS',
      'YEM': 'YE',
      'OMA': 'OM',
    };
    return mapping[fed.toUpperCase()] ?? fed;
  }
}

class FavoritesPlayersTab extends ConsumerStatefulWidget {
  const FavoritesPlayersTab({super.key});

  @override
  ConsumerState<FavoritesPlayersTab> createState() =>
      _FavoritesPlayersTabState();
}

class _FavoritesPlayersTabState extends ConsumerState<FavoritesPlayersTab>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounceTimer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(worldPlayersSearchProvider.notifier).loadMore();
    }
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      ref.read(worldPlayersSearchProvider.notifier).search(value);
    });
  }

  void _clearSearch() {
    HapticFeedback.lightImpact();
    _debounceTimer?.cancel();
    _searchController.clear();
    _searchFocusNode.unfocus();
    ref.read(worldPlayersSearchProvider.notifier).clearSearch();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final state = ref.watch(worldPlayersSearchProvider);
    // Watch favoritePlayersNotifierProvider for optimistic updates
    final favoritesAsync = ref.watch(favoritePlayersNotifierProvider);
    final favoriteIds = favoritesAsync.valueOrNull?.players
            .map((p) => p.fideId)
            .where((id) => id != null)
            .cast<int>()
            .toSet() ??
        <int>{};

    // Apply tablet max-width constraint
    Widget content = RefreshIndicator(
      onRefresh: () async {
        HapticFeedbackService.medium();
        await ref.read(worldPlayersSearchProvider.notifier).refresh();
      },
      color: kWhiteColor,
      backgroundColor: kBlack2Color,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          // Search bar
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
              child: SearchBarWidget(
                hintText: 'Search all players',
                margin: 0.sp,
                autoFocus: false,
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: _onSearchChanged,
                onClose: _clearSearch,
              ),
            ),
          ),

          // Content
          _buildContentSliver(state, favoriteIds),

          // Bottom padding
          SliverToBoxAdapter(child: SizedBox(height: 24.h)),
        ],
      ),
    );

    // Apply tablet max-width constraint
    if (ResponsiveHelper.isTablet) {
      content = Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.contentMaxWidth,
          ),
          child: content,
        ),
      );
    }

    return Stack(
      children: [
        content,
        // Scroll to top button
        Positioned(
          bottom: 0,
          right: 0,
          child: ScrollToTopButton(scrollController: _scrollController),
        ),
      ],
    );
  }

  Widget _buildContentSliver(
    WorldPlayersSearchState state,
    Set<int> favoriteIds,
  ) {
    if (state.isLoading && state.players.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildLoadingState(),
      );
    }

    if (state.error != null && state.players.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildErrorState(state.error!),
      );
    }

    if (state.players.isEmpty) {
      if (state.isSearching) {
        return SliverFillRemaining(
          hasScrollBody: false,
          child: _buildNoSearchResultsState(),
        );
      }
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildEmptyState(),
      );
    }

    return _buildPlayersSliver(state, favoriteIds);
  }

  Widget _buildPlayersSliver(
    WorldPlayersSearchState state,
    Set<int> favoriteIds,
  ) {
    final players = state.players;
    final showLoadingIndicator =
        (state.hasMore || state.isLoading) && players.isNotEmpty;

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index >= players.length) {
              return Padding(
                padding: EdgeInsets.symmetric(vertical: 24.h),
                child: Center(
                  child: state.isLoading
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 24.w,
                              height: 24.h,
                              child: const CircularProgressIndicator(
                                color: kWhiteColor,
                                strokeWidth: 2,
                              ),
                            ),
                            SizedBox(height: 8.h),
                            Text(
                              'Loading more players...',
                              style: AppTypography.textXsRegular.copyWith(
                                color: const Color(0xFF71717A),
                              ),
                            ),
                          ],
                        )
                      : state.hasMore
                          ? const SizedBox.shrink()
                          : Text(
                              'No more players',
                              style: AppTypography.textXsRegular.copyWith(
                                color: const Color(0xFF52525B),
                              ),
                            ),
                ),
              );
            }

            final player = players[index];
            final isFavorite = favoriteIds.contains(player.fideId);

            return _PlayerCard(
              player: player,
              isFavorite: isFavorite,
              rank: index + 1,
              onTap: () => _navigateToPlayerDetail(player),
              onToggleFavorite: () => _toggleFavorite(player, isFavorite),
            );
          },
          childCount: players.length + (showLoadingIndicator ? 1 : 0),
        ),
      ),
    );
  }

  void _navigateToPlayerDetail(PlayerStandingModel player) {
    ref.read(selectedBroadcastModelProvider.notifier).state = null;
    ref.read(selectedPlayerProvider.notifier).state = player;
    // Clear games context to use fallback (fetches all player games globally)
    ref.read(scoreCardGamesContextProvider.notifier).state = null;
    // No event context from favorites players tab
    ref.read(scoreCardHasEventContextProvider.notifier).state = false;
    Navigator.pushNamed(context, '/scorecard_screen');
  }

  void _toggleFavorite(
    PlayerStandingModel player,
    bool currentlyFavorite,
  ) {
    // Check auth first, then toggle without blocking
    requireFullAuthGuard(context).then((allowed) {
      if (!allowed) return;

      HapticFeedback.mediumImpact();

      // Fire and forget - provider handles optimistic updates internally
      if (currentlyFavorite) {
        unawaited(
          ref
              .read(favoritePlayersNotifierProvider.notifier)
              .removeFavorite(player),
        );
      } else {
        unawaited(
          ref
              .read(favoritePlayersNotifierProvider.notifier)
              .addFavorite(player),
        );
      }
    });
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 48.w,
            height: 48.h,
            child: const CircularProgressIndicator(
              color: kWhiteColor,
              strokeWidth: 2.5,
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            'Loading players...',
            style: AppTypography.textSmRegular.copyWith(
              color: const Color(0xFFA1A1AA),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64.w,
            height: 64.h,
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16.br),
            ),
            child: Icon(
              Icons.error_outline_rounded,
              color: const Color(0xFFEF4444),
              size: 32.ic,
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            'Failed to load players',
            style: AppTypography.textMdMedium.copyWith(color: kWhiteColor),
          ),
          SizedBox(height: 8.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 32.w),
            child: Text(
              error,
              style: AppTypography.textSmRegular.copyWith(
                color: const Color(0xFFA1A1AA),
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(height: 24.h),
          TextButton(
            onPressed: () =>
                ref.read(worldPlayersSearchProvider.notifier).refresh(),
            style: TextButton.styleFrom(
              backgroundColor: kWhiteColor.withValues(alpha: 0.1),
              padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.br),
              ),
            ),
            child: Text(
              'Retry',
              style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80.w,
            height: 80.h,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  kWhiteColor.withValues(alpha: 0.15),
                  kWhiteColor.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(20.br),
            ),
            child: Icon(
              Icons.person_search_outlined,
              color: kWhiteColor.withValues(alpha: 0.7),
              size: 40.ic,
            ),
          ),
          SizedBox(height: 20.h),
          Text(
            'No players found',
            style: AppTypography.textMdMedium.copyWith(color: kWhiteColor),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).scale(begin: const Offset(0.95, 0.95));
  }

  Widget _buildNoSearchResultsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off_outlined,
            size: 56.sp,
            color: kWhiteColor.withValues(alpha: 0.4),
          ),
          SizedBox(height: 12.h),
          Text(
            'No results',
            style: AppTypography.textMdMedium.copyWith(
              color: kWhiteColor.withValues(alpha: 0.85),
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            'Try a different search term',
            style: AppTypography.textSmRegular.copyWith(
              color: kWhiteColor.withValues(alpha: 0.55),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }
}

class _PlayerCard extends ConsumerWidget {
  final PlayerStandingModel player;
  final bool isFavorite;
  final int rank;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  const _PlayerCard({
    required this.player,
    required this.isFavorite,
    required this.rank,
    required this.onTap,
    required this.onToggleFavorite,
  });

  String _getInitials(String name) {
    final parts = name.split(',');
    if (parts.length > 1) {
      final first = parts[0].trim();
      final second = parts[1].trim();
      return '${first.isNotEmpty ? first[0] : ''}${second.isNotEmpty ? second[0] : ''}'.toUpperCase();
    }
    final words = name.trim().split(' ');
    if (words.length >= 2) {
      return '${words[0].isNotEmpty ? words[0][0] : ''}${words[1].isNotEmpty ? words[1][0] : ''}'.toUpperCase();
    }
    return name.isNotEmpty ? name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase() : '';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photoAsync = ref.watch(playerPhotoProvider(player.fideId));
    final avatarSize = 44.w;
    final initials = _getInitials(player.name);

    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
          decoration: BoxDecoration(
            color: kBlack2Color,
            borderRadius: BorderRadius.circular(12.br),
          ),
          child: Row(
            children: [
              // Rank number
              SizedBox(
                width: 28.w,
                child: Text(
                  rank.toString(),
                  style: AppTypography.textSmMedium.copyWith(
                    color: const Color(0xFF71717A),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              SizedBox(width: 4.w),
              // Player photo
              photoAsync.when(
                data: (photoUrl) => PlayerInitialsAvatarCompact(
                  photoUrl: photoUrl,
                  initials: initials,
                  size: avatarSize,
                  borderRadius: 8.br,
                ),
                loading: () => skel.Skeletonizer(
                  enabled: true,
                  effect: const skel.ShimmerEffect(
                    baseColor: Color(0xFF2A2A2A),
                    highlightColor: Color(0xFF3A3A3A),
                  ),
                  child: Container(
                    width: avatarSize,
                    height: avatarSize,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(8.br),
                    ),
                  ),
                ),
                error: (_, __) => PlayerInitialsAvatarCompact(
                  initials: initials,
                  size: avatarSize,
                  borderRadius: 8.br,
                ),
              ),
              SizedBox(width: 12.w),
              // Player info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Flag
                        if (player.countryCode.isNotEmpty)
                          Padding(
                            padding: EdgeInsets.only(right: 6.w),
                            child: CountryFlag.fromCountryCode(
                              player.countryCode,
                              height: 12.h,
                              width: 18.w,
                              shape: RoundedRectangle(2.br),
                            ),
                          ),
                        if (player.title != null && player.title!.isNotEmpty)
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 4.w,
                              vertical: 1.h,
                            ),
                            margin: EdgeInsets.only(right: 6.w),
                            decoration: BoxDecoration(
                              color: _getTitleColor(player.title!),
                              borderRadius: BorderRadius.circular(3.br),
                            ),
                            child: Text(
                              player.title!,
                              style: AppTypography.textXsBold.copyWith(
                                color: kWhiteColor,
                                fontSize: 10.sp,
                              ),
                            ),
                          ),
                        Expanded(
                          child: Text(
                            player.name,
                            style: AppTypography.textSmMedium.copyWith(
                              color: kWhiteColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'Elo: ${player.score}',
                      style: AppTypography.textXsRegular.copyWith(
                        color: const Color(0xFFA1A1AA),
                      ),
                    ),
                  ],
                ),
              ),
              // Favorite button
              GestureDetector(
                onTap: onToggleFavorite,
                child: Container(
                  padding: EdgeInsets.all(8.sp),
                  child: Icon(
                    isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: isFavorite
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF71717A),
                    size: 22.ic,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getTitleColor(String title) {
    switch (title.toUpperCase()) {
      case 'GM':
        return const Color(0xFFEAB308); // Gold
      case 'IM':
        return const Color(0xFF3B82F6); // Blue
      case 'FM':
        return const Color(0xFF22C55E); // Green
      case 'CM':
      case 'NM':
        return const Color(0xFF8B5CF6); // Purple
      case 'WGM':
        return const Color(0xFFEC4899); // Pink
      case 'WIM':
        return const Color(0xFF06B6D4); // Cyan
      case 'WFM':
        return const Color(0xFF84CC16); // Lime
      case 'WCM':
        return const Color(0xFFF97316); // Orange
      default:
        return const Color(0xFF71717A); // Gray
    }
  }
}

