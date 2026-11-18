import 'dart:async';

import 'package:chessever2/screens/library/miniatures/miniature_player_scorecard_screen.dart';
import 'package:chessever2/screens/library/miniatures/miniatures_mode_provider.dart';
import 'package:chessever2/screens/library/miniatures/widgets/miniature_players_filter_dialog.dart';
import 'package:chessever2/screens/library/providers/miniatures_provider.dart';
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/screens/player_profile/utils/player_menu_actions.dart';
import 'package:chessever2/screens/player_profile/widgets/lifted_row_menu.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/scroll_cache.dart';
import 'package:chessever2/widgets/figma_player_card.dart';
import 'package:chessever2/screens/tour_detail/widgets/event_search_bar.dart'
    show EventSearchBarFrame;
import 'package:chessever2/widgets/ink_fab.dart' show InkFabSize;
import 'package:chessever2/widgets/scroll_to_top_bus.dart';
import 'package:chessever2/widgets/simple_search_bar.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:skeletonizer/skeletonizer.dart';

/// High-ELO player leaderboard for Miniatures → Players, ranked the same way as
/// For You → Favorites → Players (Supabase `chess_players`, rating desc).
/// Same [FigmaPlayerCard] shell (rank + avatar + name/rating, miniature W-L in
/// the score slot). The search and the title filters open from the screen's
/// floating search button ([MiniaturePlayersSearchField]). Tapping opens the
/// player profile.
class MiniaturesPlayersTab extends ConsumerStatefulWidget {
  const MiniaturesPlayersTab({super.key});

  @override
  ConsumerState<MiniaturesPlayersTab> createState() =>
      _MiniaturesPlayersTabState();
}

class _MiniaturesPlayersTabState extends ConsumerState<MiniaturesPlayersTab>
    with AutomaticKeepAliveClientMixin, ScrollToTopListenerMixin {
  final ScrollController _scrollController = ScrollController();

  /// Latched true the first time this tab becomes the selected one.
  bool _activated = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void onScrollToTopRequested() {
    animateScrollControllerToTop(_scrollController);
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final state = ref.read(miniaturePlayersPaginatedProvider);
      if (!state.isLoading && state.hasMore) {
        ref.read(miniaturePlayersPaginatedProvider.notifier).loadNextPage();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // No cards are built until the tab is first opened — the ranking itself is
    // warmed by MiniaturesScreen, but each card costs a photo and a W-L lookup,
    // so they wait for the tab to actually be on screen. Once opened the
    // watches stay put: dropping them on a tab switch would auto-dispose the
    // paginated provider and reset the list.
    _activated |=
        ref.watch(selectedMiniaturesModeProvider) ==
        MiniaturesScreenMode.players;
    if (!_activated) return const SizedBox.shrink();

    final state = ref.watch(miniaturePlayersPaginatedProvider);
    final query = ref.watch(miniaturePlayersQueryProvider);
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 24.w,
    );

    Widget content = RefreshIndicator(
      onRefresh: () async {
        HapticFeedbackService.medium();
        await ref.read(miniaturePlayersPaginatedProvider.notifier).refresh();
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
          SliverToBoxAdapter(child: SizedBox(height: 4.h)),
          _buildContentSliver(state, query, horizontalPadding),
          // Clear of the floating search button at the list's end.
          SliverToBoxAdapter(
            child: SizedBox(height: 24.h + InkFabSize.regular.side),
          ),
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

    return content;
  }

  Widget _buildContentSliver(
    MiniaturePlayersState state,
    MiniaturePlayersQuery query,
    double horizontalPadding,
  ) {
    if (state.isLoading && state.items.isEmpty) {
      return SliverPadding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          8.h,
          horizontalPadding,
          24.h,
        ),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => const _MiniaturePlayerCardSkeleton(),
            childCount: 10,
          ),
        ),
      );
    }

    if (state.items.isEmpty) {
      final hasQuery =
          query.titles.isNotEmpty ||
          (query.search ?? '').isNotEmpty ||
          query.hasActiveFilters;
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 48.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  state.error != null
                      ? Icons.cloud_off_rounded
                      : Icons.person_search_rounded,
                  size: 40.sp,
                  color: context.colors.textSecondary,
                ),
                SizedBox(height: 16.h),
                Text(
                  state.error != null
                      ? 'Could not load players'
                      : hasQuery
                      ? 'No players match this filter'
                      : 'No players yet',
                  textAlign: TextAlign.center,
                  style: AppTypography.textSmMedium.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
                if (state.error != null) ...[
                  SizedBox(height: 16.h),
                  TextButton(
                    onPressed: () {
                      HapticFeedbackService.buttonPress();
                      ref
                          .read(miniaturePlayersPaginatedProvider.notifier)
                          .refresh();
                    },
                    child: Text(
                      'Try again',
                      style: AppTypography.textSmMedium.copyWith(
                        color: context.colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    final showFooter = state.isLoading || !state.hasMore;
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        8.h,
        horizontalPadding,
        0,
      ),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          if (index >= state.items.length) {
            return Padding(
              padding: EdgeInsets.symmetric(vertical: 20.h),
              child: Center(
                child: state.isLoading
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 24.w,
                            height: 24.h,
                            child: CircularProgressIndicator(
                              color: context.colors.textPrimary,
                              strokeWidth: 2,
                            ),
                          ),
                          SizedBox(height: 8.h),
                          Text(
                            'Loading more…',
                            style: AppTypography.textXsRegular.copyWith(
                              color: context.isLightTheme
                                  ? context.colors.textSecondary
                                  : const Color(0xFF71717A),
                            ),
                          ),
                        ],
                      )
                    : Text(
                        'No more players',
                        style: AppTypography.textXsRegular.copyWith(
                          color: const Color(0xFF52525B),
                        ),
                      ),
              ),
            );
          }

          final player = state.items[index];
          final keyId = player.fideId?.toString() ?? player.name;
          return _MiniaturePlayerRow(
            key: ValueKey('mini_player_$keyId'),
            player: player,
            rank: index + 1,
          );
        }, childCount: state.items.length + (showFooter ? 1 : 0)),
      ),
    );
  }
}

/// One leaderboard row. W-L comes from gamebase, one name search per player, so
/// it is resolved by the row that is actually on screen rather than up front for
/// the whole page — the list paints as soon as the ELO ranking is in, and the
/// score slot holds its width under a shimmer until its own lookup lands.
/// Already-resolved players (a scroll back, a second visit) read straight off
/// the session cache and paint their record on the first frame.
/// The Players list's search, typed in the Miniatures screen's search
/// header, with the title filters behind its glyph. It writes the list's own
/// query ([miniaturePlayersQueryProvider]), so the ranking narrows under it.
class MiniaturePlayersSearchField extends ConsumerStatefulWidget {
  const MiniaturePlayersSearchField({super.key, required this.focusNode});

  final FocusNode focusNode;

  @override
  ConsumerState<MiniaturePlayersSearchField> createState() =>
      _MiniaturePlayersSearchFieldState();
}

class _MiniaturePlayersSearchFieldState
    extends ConsumerState<MiniaturePlayersSearchField> {
  // Opens on what the ranking is narrowed to, so reopening shows it.
  late final TextEditingController _controller = TextEditingController(
    text: ref.read(miniaturePlayersQueryProvider).search ?? '',
  );
  Timer? _debounce;
  static const Duration _debounceDuration = Duration(milliseconds: 350);

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _apply(String query) {
    final trimmed = query.trim();
    final current = ref.read(miniaturePlayersQueryProvider);
    final next = current.copyWith(
      search: trimmed.isEmpty ? null : trimmed,
      clearSearch: trimmed.isEmpty,
    );
    // An equal query (e.g. a trailing space) must not rebuild the list.
    if (next == current) return;
    ref.read(miniaturePlayersQueryProvider.notifier).state = next;
  }

  void _changed(String query) {
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, () {
      if (mounted) _apply(query);
    });
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    widget.focusNode.unfocus();
    _apply('');
  }

  Future<void> _openFilters() async {
    HapticFeedbackService.buttonPress();
    widget.focusNode.unfocus();
    final result = await showMiniaturePlayersFilterDialog(
      context: context,
      currentQuery: ref.read(miniaturePlayersQueryProvider),
    );
    if (result != null && mounted) {
      ref.read(miniaturePlayersQueryProvider.notifier).state = result;
    }
  }

  @override
  Widget build(BuildContext context) {
    final applied = ref.watch(
      miniaturePlayersQueryProvider.select((q) => q.activeFilterCount),
    );
    return EventSearchBarFrame(
      compact: true,
      child: SimpleSearchBar(
        controller: _controller,
        focusNode: widget.focusNode,
        // Built only as the search opens: the cursor goes straight in.
        autofocus: true,
        hintText: 'Search players',
        textFieldKey: const ValueKey('miniatures_players_search'),
        filterButtonKey: const ValueKey('miniatures_players_filters'),
        compactFilter: true,
        filterBadgeCount: applied,
        onChanged: _changed,
        onOpenFilter: _openFilters,
        onCloseTap: _clear,
      ),
    );
  }
}

class _MiniaturePlayerRow extends ConsumerWidget {
  const _MiniaturePlayerRow({
    super.key,
    required this.player,
    required this.rank,
  });

  final PlayerStandingModel player;
  final int rank;

  ({int fideId, String name})? get _recordKey {
    final fideId = player.fideId;
    return fideId == null ? null : (fideId: fideId, name: player.name);
  }

  /// Miniature scorecard when this player exists in gamebase, full profile
  /// otherwise. A tap before the lookup lands waits briefly for it rather than
  /// silently sending the player to the other screen.
  Future<void> _open(BuildContext context, WidgetRef ref) async {
    HapticFeedbackService.cardTap();

    final key = _recordKey;
    var miniature = key == null
        ? null
        : cachedMiniaturePlayerRecord(key.fideId);
    if (miniature == null &&
        key != null &&
        !hasResolvedMiniaturePlayerRecord(key.fideId)) {
      try {
        miniature = await ref
            .read(miniaturePlayerRecordProvider(key).future)
            .timeout(const Duration(seconds: 2), onTimeout: () => null);
      } catch (_) {
        miniature = null;
      }
    }
    if (!context.mounted) return;

    final resolved = miniature;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => resolved != null
            ? MiniaturePlayerScorecardScreen(
                player: resolved,
                avatarHeroTag: resolved.avatarHeroTag,
              )
            : PlayerProfileScreen(
                fideId: player.fideId,
                playerName: player.name,
                title: player.title,
                federation: player.countryCode,
                rating: player.score,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = _recordKey;
    // A settled lookup (hit or miss) is read synchronously, so a row scrolled
    // back into view never re-shimmers while its autoDispose provider replays
    // against the same cache. Only unresolved rows subscribe and fetch.
    final settled = key != null && hasResolvedMiniaturePlayerRecord(key.fideId);
    final lookup = key == null || settled
        ? null
        : ref.watch(miniaturePlayerRecordProvider(key));
    final miniature = settled
        ? cachedMiniaturePlayerRecord(key.fideId)
        : lookup?.valueOrNull;

    final matchScore = player.matchScore ?? miniature?.winLossLabel;
    final cardPlayer = matchScore == null || matchScore == player.matchScore
        ? player
        : player.copyWith(matchScore: matchScore);

    final hasScorecard = miniature != null;
    // Long-press lifts the row into the shared focus menu. The lifted copy
    // drops the avatar hero tag: two Heroines with one tag on screen would
    // fight over the flight.
    return LiftedRowMenu(
      onPreviewTap: () => _open(context, ref),
      preview: FigmaPlayerCard(
        player: cardPlayer,
        rank: rank,
        showFavoriteButton: false,
        reserveMatchScoreSlot: true,
        onTap: () {},
      ),
      actions: (rowContext) => playerStandingMenuActions(
        rowContext,
        ref,
        player,
        onOpen: () => _open(context, ref),
        openLabel: hasScorecard ? 'Open scorecard' : 'Open profile',
        openIcon: hasScorecard
            ? Icons.open_in_new_rounded
            : Icons.person_outline_rounded,
        extra: [
          if (hasScorecard)
            LibraryMenuAction(
              icon: Icons.person_outline_rounded,
              label: 'Open profile',
              onSelected: () => openPlayerProfileFor(context, player),
            ),
        ],
      ),
      child: FigmaPlayerCard(
        player: cardPlayer,
        rank: rank,
        showFavoriteButton: false,
        avatarHeroTag: miniature?.avatarHeroTag,
        // Pending only while this row's own lookup is genuinely still out; a
        // settled miss leaves the slot empty instead of shimmering forever.
        matchScorePending: matchScore == null && (lookup?.isLoading ?? false),
        // Records here run from `5W-2L` to `172W-41L` and land row by row, so
        // the slot is held at one width: every name ends on the same x, and
        // nothing moves when a record arrives.
        reserveMatchScoreSlot: true,
        onTap: () => _open(context, ref),
      ),
    );
  }
}

/// Card-shaped shimmer that matches [FigmaPlayerCard] layout (rank + avatar +
/// name/rating + W-L). Plain [Container]s under [SkeletonWidget] do not
/// shimmer because containers are ignored — bones give a real animation.
class _MiniaturePlayerCardSkeleton extends StatelessWidget {
  const _MiniaturePlayerCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final avatarSize = 56.w;
    return SkeletonWidget(
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: context.colors.divider, width: 1),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 24.w,
              child: Text(
                '00',
                style: AppTypography.textSmMedium.copyWith(
                  color: context.colors.textTertiary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(width: 12.w),
            Bone.square(
              size: avatarSize,
              borderRadius: BorderRadius.circular(8.br),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Player Name Placeholder',
                    style: AppTypography.textSmBold.copyWith(
                      color: context.colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    '2500',
                    style: AppTypography.textSmRegular.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.only(left: 8.w),
              // Same string the card reserves its score slot with, so the list
              // does not jump sideways when it replaces this shimmer.
              child: Text(
                '000W-000L',
                style: AppTypography.textMdMedium.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
