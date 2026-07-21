import 'dart:async';

import 'package:chessever2/repository/gamebase/miniatures/miniatures_models.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart'
    show playerPhotoProvider;
import 'package:chessever2/screens/library/miniatures/miniature_game_launcher.dart';
import 'package:chessever2/screens/library/providers/miniatures_provider.dart';
import 'package:chessever2/screens/library/widgets/add_to_folder_sheet.dart';
import 'package:chessever2/screens/library/widgets/gamebase_search_game_card.dart';
import 'package:chessever2/screens/library/widgets/miniatures_filter_dialog.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/scroll_cache.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:chessever2/widgets/fullscreen_image_viewer.dart';
import 'package:chessever2/widgets/player_initials_avatar.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:heroine/heroine.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

/// A player's own miniature games, in the same spirit as the tournament
/// Standings → player card → score card flow: a compact player header with
/// the headline miniature stats, then that player's games as searchable,
/// filterable game cards.
class MiniaturePlayerScorecardScreen extends ConsumerStatefulWidget {
  const MiniaturePlayerScorecardScreen({
    super.key,
    required this.player,
    this.avatarHeroTag,
  });

  final MiniaturePlayer player;

  /// Shared [Heroine] tag with the list card avatar. Defaults to
  /// [MiniaturePlayer.avatarHeroTag] when omitted.
  final String? avatarHeroTag;

  @override
  ConsumerState<MiniaturePlayerScorecardScreen> createState() =>
      _MiniaturePlayerScorecardScreenState();
}

class _MiniaturePlayerScorecardScreenState
    extends ConsumerState<MiniaturePlayerScorecardScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  Timer? _debounceTimer;
  static const Duration _debounceDuration = Duration(milliseconds: 350);
  static const String _unknownDateKey = '0000-00-00';

  final Set<String> _collapsedDates = {};

  /// 0 at the top of the list (body header owns the name); 1 once the header
  /// has scrolled under the app bar. Driven by [_onScroll].
  double _appBarTitleOpacity = 0;

  /// Scroll range over which the app-bar title eases in. Tuned to the body
  /// header (avatar + name) so the title appears as that name leaves view.
  static const double _titleFadeStart = 28;
  static const double _titleFadeEnd = 88;

  String get _playerId => widget.player.playerId;

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
    if (!_scrollController.hasClients) return;

    final offset = _scrollController.position.pixels;
    final span = _titleFadeEnd - _titleFadeStart;
    final next =
        span <= 0
            ? 0.0
            : ((offset - _titleFadeStart) / span).clamp(0.0, 1.0);
    // Skip tiny noise so we do not rebuild every pixel.
    if ((next - _appBarTitleOpacity).abs() > 0.02 ||
        (next == 0) != (_appBarTitleOpacity == 0) ||
        (next == 1) != (_appBarTitleOpacity == 1)) {
      setState(() => _appBarTitleOpacity = next);
    }

    if (offset >= _scrollController.position.maxScrollExtent - 200) {
      final state = ref.read(miniaturePlayerGamesPaginatedProvider(_playerId));
      if (!state.isLoading && state.hasMore) {
        ref
            .read(miniaturePlayerGamesPaginatedProvider(_playerId).notifier)
            .loadNextPage();
      }
    }
  }

  void _onSearchChanged(String query) {
    final trimmed = query.trim();
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () {
      if (!mounted) return;
      final current = ref.read(miniaturePlayerGamesFilterProvider(_playerId));
      ref
          .read(miniaturePlayerGamesFilterProvider(_playerId).notifier)
          .state = current.copyWith(
        search: trimmed.isEmpty ? null : trimmed,
        clearSearch: trimmed.isEmpty,
      );
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _onSearchChanged('');
  }

  Future<void> _openFilters() async {
    HapticFeedbackService.buttonPress();
    if (!mounted) return;

    final newFilter = await showMiniaturesFilterDialog(
      context: context,
      currentFilter: ref.read(miniaturePlayerGamesFilterProvider(_playerId)),
    );
    if (newFilter != null && mounted) {
      ref.read(miniaturePlayerGamesFilterProvider(_playerId).notifier).state =
          newFilter;
    }
  }

  void _toggleDateSection(String dateKey) {
    HapticFeedbackService.light();
    setState(() {
      if (!_collapsedDates.remove(dateKey)) _collapsedDates.add(dateKey);
    });
  }

  Map<String, List<GamesTourModel>> _groupGamesByDate(
    List<GamesTourModel> games,
  ) {
    final grouped = <String, List<GamesTourModel>>{};
    for (final game in games) {
      final raw = game.lastMoveTime;
      final key =
          raw == null
              ? _unknownDateKey
              : DateFormat('yyyy-MM-dd').format(raw.toUtc());
      grouped.putIfAbsent(key, () => <GamesTourModel>[]).add(game);
    }

    final sortedKeys =
        grouped.keys.toList()..sort((a, b) {
          if (a == _unknownDateKey) return 1;
          if (b == _unknownDateKey) return -1;
          return b.compareTo(a);
        });

    return {for (final key in sortedKeys) key: grouped[key]!};
  }

  String _formatDateHeader(String dateKey) {
    if (dateKey == _unknownDateKey) return 'Unknown date';
    final date = DateTime.tryParse(dateKey);
    if (date == null) return dateKey;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final deltaDays = today.difference(target).inDays;
    if (deltaDays == 0) return 'Today';
    if (deltaDays == 1) return 'Yesterday';
    return DateFormat('EEEE, MMM d, y').format(target);
  }

  Future<void> _openGame(List<GamesTourModel> games, int index) {
    return openMiniatureGame(
      context: context,
      ref: ref,
      games: games,
      index: index,
    );
  }

  void _openFullProfile() {
    HapticFeedbackService.buttonPress();
    final player = widget.player;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => PlayerProfileScreen(
              fideId: player.fideId,
              playerName: player.name,
              title: player.title,
              federation: player.fed,
              rating: player.rating ?? 0,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(miniaturePlayerGamesPaginatedProvider(_playerId));
    final games = ref.watch(miniaturePlayerGamesProvider(_playerId));
    final filter = ref.watch(miniaturePlayerGamesFilterProvider(_playerId));
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 24.w,
    );

    Widget content = RefreshIndicator(
      onRefresh: () async {
        HapticFeedbackService.medium();
        await ref
            .read(miniaturePlayerGamesPaginatedProvider(_playerId).notifier)
            .refresh();
      },
      color: context.colors.textPrimary,
      backgroundColor: context.colors.surface,
      child: CustomScrollView(
        controller: _scrollController,
        scrollCacheExtent: kListScrollCacheExtent,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                8.h,
                horizontalPadding,
                8.h,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PlayerHeader(
                    player: widget.player,
                    avatarHeroTag:
                        widget.avatarHeroTag ?? widget.player.avatarHeroTag,
                    onOpenProfile: _openFullProfile,
                  ),
                  SizedBox(height: 20.h),
                  _buildSearchBar(filter),
                ],
              ),
            ),
          ),
          _buildContentSliver(state, games, filter),
          SliverToBoxAdapter(child: SizedBox(height: 24.h)),
        ],
      ),
    );

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

    // Title is empty at rest so it does not duplicate the body header; it
    // fades in once the header name scrolls under the bar, and out on return.
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.background,
        elevation: 0,
        titleSpacing: 0,
        title: IgnorePointer(
          ignoring: _appBarTitleOpacity < 0.05,
          child: Opacity(
            opacity: _appBarTitleOpacity,
            child: Text(
              widget.player.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.textMdMedium.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(child: content),
    );
  }

  Widget _buildSearchBar(MiniatureGamesFilter filter) {
    final hasActiveFilters = filter.dialogActiveCount > 0;
    final activeFilterCount = filter.dialogActiveCount;
    final searchBarHeight = 48.h;

    Widget searchField = Container(
      decoration: BoxDecoration(
        color: context.colors.background,
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(color: context.colors.surfaceRecessed),
      ),
      child: Row(
        children: [
          SizedBox(width: 12.w),
          Icon(Icons.search, size: 20.sp, color: context.colors.textSecondary),
          SizedBox(width: 8.w),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textPrimary,
              ),
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search opponent, event or opening',
                hintStyle: AppTypography.textSmRegular.copyWith(
                  color: context.colors.textSecondary,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14.h),
              ),
            ),
          ),
          if (_searchController.text.isNotEmpty) ...[
            GestureDetector(
              onTap: _clearSearch,
              child: Icon(
                Icons.close,
                size: 20.sp,
                color: context.colors.textSecondary,
              ),
            ),
            SizedBox(width: 8.w),
          ],
          SizedBox(width: 8.w),
        ],
      ),
    );

    return SizedBox(
      height: searchBarHeight,
      child: Row(
        children: [
          Expanded(child: searchField),
          SizedBox(width: 8.w),
          GestureDetector(
            onTap: _openFilters,
            child: Container(
              width: searchBarHeight,
              height: searchBarHeight,
              decoration: BoxDecoration(
                color:
                    hasActiveFilters
                        ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                        : context.colors.background,
                borderRadius: BorderRadius.circular(12.br),
                border: Border.all(
                  color:
                      hasActiveFilters
                          ? const Color(0xFFEF4444).withValues(alpha: 0.5)
                          : context.colors.surfaceRecessed,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 20.sp,
                    color:
                        hasActiveFilters
                            ? const Color(0xFFEF4444)
                            : context.colors.textSecondary,
                  ),
                  if (hasActiveFilters)
                    Positioned(
                      right: 6.w,
                      top: 6.h,
                      child: Container(
                        width: 14.w,
                        height: 14.h,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEF4444),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '$activeFilterCount',
                            style: AppTypography.textXsBold.copyWith(
                              color: context.colors.textPrimary,
                              fontSize: 9.sp,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentSliver(
    MiniaturesPaginationState state,
    List<GamesTourModel> games,
    MiniatureGamesFilter filter,
  ) {
    if (state.isLoading && games.isEmpty) {
      return SliverToBoxAdapter(child: _buildSkeletonList());
    }

    if (state.error != null && games.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _ScorecardMessage(
          icon: Icons.cloud_off_rounded,
          title: 'Could not load games',
          subtitle: 'Check your connection and try again.',
          actionLabel: 'Retry',
          onAction:
              () =>
                  ref
                      .read(
                        miniaturePlayerGamesPaginatedProvider(
                          _playerId,
                        ).notifier,
                      )
                      .refresh(),
        ),
      );
    }

    if (games.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _ScorecardMessage(
          icon: Icons.bolt_outlined,
          title: 'No miniatures found',
          subtitle:
              filter.hasActiveFilters
                  ? 'Try widening your filters or clearing the search.'
                  : "${widget.player.name} has no miniature games yet.",
          actionLabel: filter.hasActiveFilters ? 'Clear filters' : null,
          onAction:
              filter.hasActiveFilters
                  ? () {
                    _searchController.clear();
                    ref
                        .read(
                          miniaturePlayerGamesFilterProvider(
                            _playerId,
                          ).notifier,
                        )
                        .state = MiniatureGamesFilter.defaultFilter.copyWith(
                      playerId: _playerId,
                    );
                  }
                  : null,
        ),
      );
    }

    final gameIdToIndex = <String, int>{
      for (var i = 0; i < games.length; i++) games[i].gameId: i,
    };

    final listEntries = <_ScorecardListEntry>[];
    for (final entry in _groupGamesByDate(games).entries) {
      final dateKey = entry.key;
      final dateGames = entry.value;
      final isCollapsed = _collapsedDates.contains(dateKey);

      listEntries.add(
        _ScorecardDateHeaderEntry(
          dateKey: dateKey,
          gameCount: dateGames.length,
          isExpanded: !isCollapsed,
        ),
      );
      if (isCollapsed) continue;

      for (var i = 0; i < dateGames.length; i++) {
        final game = dateGames[i];
        listEntries.add(
          _ScorecardGameEntry(
            game: game,
            gameIndex: gameIdToIndex[game.gameId] ?? 0,
            isLast: i == dateGames.length - 1,
          ),
        );
      }
    }

    if (state.isLoading) {
      listEntries.add(
        const _ScorecardFooterEntry(_ScorecardFooterType.loading),
      );
    } else if (state.hasMore) {
      listEntries.add(const _ScorecardFooterEntry(_ScorecardFooterType.spacer));
    } else {
      listEntries.add(const _ScorecardFooterEntry(_ScorecardFooterType.end));
    }

    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 24.w,
    );
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildListEntry(listEntries[index], games: games),
          childCount: listEntries.length,
          addAutomaticKeepAlives: false,
        ),
      ),
    );
  }

  Widget _buildListEntry(
    _ScorecardListEntry entry, {
    required List<GamesTourModel> games,
  }) {
    if (entry is _ScorecardDateHeaderEntry) {
      return Padding(
        padding: EdgeInsets.only(bottom: 12.h),
        child: _ScorecardDateHeader(
          dateLabel: _formatDateHeader(entry.dateKey),
          gameCount: entry.gameCount,
          isExpanded: entry.isExpanded,
          onToggle: () => _toggleDateSection(entry.dateKey),
        ),
      );
    }

    if (entry is _ScorecardGameEntry) {
      return Padding(
        padding: EdgeInsets.only(bottom: entry.isLast ? 16.h : 12.h),
        child: GamebaseSearchGameCard(
          key: ValueKey('scorecard_${entry.game.gameId}'),
          game: entry.game,
          allGames: games,
          gameIndex: entry.gameIndex,
          showRound: true,
          showGamebaseButton: false,
          requirePremiumToAdd: false,
          onAdd: () => showAddToFolderSheet(context: context, game: entry.game),
          onTap: () => _openGame(games, entry.gameIndex),
        ),
      );
    }

    if (entry is _ScorecardFooterEntry) {
      switch (entry.type) {
        case _ScorecardFooterType.loading:
          return Padding(
            padding: EdgeInsets.symmetric(vertical: 24.h),
            child: Center(
              child: SizedBox(
                width: 24.w,
                height: 24.h,
                child: CircularProgressIndicator(
                  color: context.colors.textPrimary,
                  strokeWidth: 2,
                ),
              ),
            ),
          );
        case _ScorecardFooterType.spacer:
          return SizedBox(height: 60.h);
        case _ScorecardFooterType.end:
          return Padding(
            padding: EdgeInsets.symmetric(vertical: 16.h),
            child: Center(
              child: Text(
                'No more games',
                style: AppTypography.textXsRegular.copyWith(
                  color: const Color(0xFF52525B),
                ),
              ),
            ),
          );
      }
    }

    return const SizedBox.shrink();
  }

  Widget _buildSkeletonList() {
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 24.w,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        0,
        horizontalPadding,
        24.h,
      ),
      child: Column(
        children: List.generate(
          6,
          (index) => Padding(
            padding: EdgeInsets.only(bottom: 12.h),
            child: SkeletonWidget(
              child: Container(
                height: 92.h,
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  borderRadius: BorderRadius.circular(12.br),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerHeader extends ConsumerWidget {
  const _PlayerHeader({
    required this.player,
    required this.avatarHeroTag,
    required this.onOpenProfile,
  });

  final MiniaturePlayer player;
  final String avatarHeroTag;
  final VoidCallback onOpenProfile;

  String get _initials {
    final parts =
        player.name
            .replaceAll(',', ' ')
            .split(' ')
            .where((part) => part.trim().isNotEmpty)
            .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return '${parts.first.characters.first}${parts[1].characters.first}'
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photoAsync = ref.watch(playerPhotoProvider(player.fideId));
    final avatarSize = 72.w;
    final showFlag = FederationFlag.hasVisibleFlag(player.fed ?? '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            photoAsync.when(
              data:
                  (photoUrl) => _ScorecardAvatar(
                    photoUrl: photoUrl,
                    initials: _initials,
                    title: player.title,
                    size: avatarSize,
                    heroTag: avatarHeroTag,
                  ),
              loading:
                  () => _ScorecardAvatar(
                    photoUrl: null,
                    initials: _initials,
                    title: player.title,
                    size: avatarSize,
                    heroTag: avatarHeroTag,
                    isLoading: true,
                  ),
              error:
                  (_, __) => _ScorecardAvatar(
                    photoUrl: null,
                    initials: _initials,
                    title: player.title,
                    size: avatarSize,
                    heroTag: avatarHeroTag,
                  ),
            ),
            SizedBox(width: 14.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    player.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.textMdBold.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 6.h),
                  Row(
                    children: [
                      if (showFlag) ...[
                        FederationFlag(
                          federation: player.fed,
                          width: 18.w,
                          height: 13.h,
                        ),
                        SizedBox(width: 6.w),
                      ],
                      if ((player.rating ?? 0) > 0)
                        Text(
                          '${player.rating}',
                          style: AppTypography.textSmRegular.copyWith(
                            color: context.colors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: 10.h),
                  GestureDetector(
                    onTap: onOpenProfile,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Open player profile',
                          style: AppTypography.textXsMedium.copyWith(
                            color: kPrimaryColor,
                          ),
                        ),
                        SizedBox(width: 2.w),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16.sp,
                          color: kPrimaryColor,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: 16.h),
        _MiniatureStatsRow(player: player),
      ],
    );
  }
}

/// Large scorecard avatar with heroine flight from the list card, and a
/// second flight into the fullscreen photo viewer on tap.
class _ScorecardAvatar extends StatelessWidget {
  const _ScorecardAvatar({
    required this.photoUrl,
    required this.initials,
    required this.title,
    required this.size,
    required this.heroTag,
    this.isLoading = false,
  });

  final String? photoUrl;
  final String initials;
  final String? title;
  final double size;
  final String heroTag;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    // Always use PlayerInitialsAvatar (initials while photo resolves) so the
    // list→scorecard and scorecard→fullscreen heroine flights share one shape.
    final child = PlayerInitialsAvatar(
      photoUrl: isLoading ? null : photoUrl,
      initials: initials,
      size: size,
      borderRadius: 14.br,
      title: title,
    );

    return GestureDetector(
      onTap: () {
        HapticFeedbackService.light();
        showPlayerAvatarFullscreen(
          context: context,
          photoUrl: isLoading ? null : photoUrl,
          initials: initials,
          heroTag: heroTag,
          title: title,
        );
      },
      child: Heroine(
        tag: heroTag,
        motion: const CupertinoMotion.smooth(),
        flightShuttleBuilder: const FadeShuttleBuilder(),
        child: child,
      ),
    );
  }
}

class _MiniatureStatsRow extends StatelessWidget {
  const _MiniatureStatsRow({required this.player});

  final MiniaturePlayer player;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _StatTile(value: '${player.games}', label: 'games')),
          SizedBox(width: 10.w),
          Expanded(
            child: _StatTile(
              valueWidget: _WinLossValue(
                wins: player.wins,
                losses: player.losses,
              ),
              label: '${player.winRate.round()}% won',
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: _StatTile(
              value: player.fastestWin != null ? '${player.fastestWin}' : '—',
              label: 'fastest win',
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({this.value, this.valueWidget, required this.label})
    : assert(value != null || valueWidget != null);

  final String? value;
  final Widget? valueWidget;
  final String label;

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.textSmMedium.copyWith(
      color: context.colors.textPrimary,
      fontWeight: FontWeight.w600,
    );
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12.br),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child:
                valueWidget ??
                Text(value!, maxLines: 1, style: style),
          ),
          SizedBox(height: 4.h),
          Text(
            label,
            style: AppTypography.textXsRegular.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Same W/L colors as [FigmaPlayerCard] leaderboard rows: brand primary wins,
/// danger red losses.
class _WinLossValue extends StatelessWidget {
  const _WinLossValue({required this.wins, required this.losses});

  final int wins;
  final int losses;

  @override
  Widget build(BuildContext context) {
    final base = AppTypography.textSmMedium.copyWith(
      fontWeight: FontWeight.w600,
    );
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(
            text: '${wins}W',
            style: base.copyWith(color: kPrimaryColor),
          ),
          TextSpan(
            text: '-',
            style: base.copyWith(color: context.colors.textSecondary),
          ),
          TextSpan(
            text: '${losses}L',
            style: base.copyWith(color: context.colors.danger),
          ),
        ],
      ),
      maxLines: 1,
    );
  }
}

// ---- Row descriptors ----

sealed class _ScorecardListEntry {
  const _ScorecardListEntry();
}

class _ScorecardDateHeaderEntry extends _ScorecardListEntry {
  const _ScorecardDateHeaderEntry({
    required this.dateKey,
    required this.gameCount,
    required this.isExpanded,
  });

  final String dateKey;
  final int gameCount;
  final bool isExpanded;
}

class _ScorecardGameEntry extends _ScorecardListEntry {
  const _ScorecardGameEntry({
    required this.game,
    required this.gameIndex,
    required this.isLast,
  });

  final GamesTourModel game;
  final int gameIndex;
  final bool isLast;
}

enum _ScorecardFooterType { loading, spacer, end }

class _ScorecardFooterEntry extends _ScorecardListEntry {
  const _ScorecardFooterEntry(this.type);

  final _ScorecardFooterType type;
}

// ---- Widgets ----

class _ScorecardDateHeader extends StatelessWidget {
  const _ScorecardDateHeader({
    required this.dateLabel,
    required this.gameCount,
    required this.isExpanded,
    this.onToggle,
  });

  final String dateLabel;
  final int gameCount;
  final bool isExpanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(12.br),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: context.colors.surfaceRecessed,
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(
            color: context.colors.textPrimary.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 4.w,
              height: 20.h,
              decoration: BoxDecoration(
                color: kPrimaryColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                '$dateLabel • $gameCount ${gameCount == 1 ? 'game' : 'games'}',
                style: AppTypography.textSmMedium.copyWith(
                  color: context.colors.textPrimary,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              isExpanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 20.sp,
              color: context.colors.textPrimary.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScorecardMessage extends StatelessWidget {
  const _ScorecardMessage({
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 48.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40.sp, color: context.colors.textSecondary),
            SizedBox(height: 16.h),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.textSmMedium.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
            if (subtitle != null) ...[
              SizedBox(height: 8.h),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: AppTypography.textXsRegular.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: 20.h),
              GestureDetector(
                onTap: onAction,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 20.w,
                    vertical: 10.h,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.surfaceRecessed,
                    borderRadius: BorderRadius.circular(10.br),
                  ),
                  child: Text(
                    actionLabel!,
                    style: AppTypography.textXsMedium.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
