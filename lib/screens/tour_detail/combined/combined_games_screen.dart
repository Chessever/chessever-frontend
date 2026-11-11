import 'dart:async';

import 'package:chessever2/providers/event_pin_refresh_provider.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart'
    show BoardNavigationListPolicy;
import 'package:chessever2/screens/group_event/widget/tour_loading_widget.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_category.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_games_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_pin_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/views/games_tour_screen.dart'
    show NoGamesPlaceholder;
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_list_view.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/round_header_widget.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/scroll_to_top_bus.dart';
import 'package:chessever2/widgets/search/gameSearch/game_search_overlay.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// The Games tab while the event is shown in Combined: every category's
/// rounds in one list, each block named after its category.
///
/// It paints with the same list, cards, view modes and live streams as the
/// single-category tab; only the grouping differs.
class CombinedGamesScreen extends ConsumerStatefulWidget {
  const CombinedGamesScreen({super.key});

  @override
  ConsumerState<CombinedGamesScreen> createState() =>
      _CombinedGamesScreenState();
}

class _CombinedGamesScreenState extends ConsumerState<CombinedGamesScreen>
    with ScrollToTopListenerMixin, AutomaticKeepAliveClientMixin {
  final ItemScrollController _scrollController = ItemScrollController();
  final ItemPositionsListener _positionsListener =
      ItemPositionsListener.create();

  /// A round created after the schedule was read has no name or start time
  /// yet. Re-read the schedule for it, but not on every rebuild.
  static const Duration _scheduleRefreshInterval = Duration(seconds: 20);
  DateTime? _scheduleRefreshedAt;

  @override
  bool get wantKeepAlive => true;

  @override
  void onScrollToTopRequested() {
    if (!_scrollController.isAttached) return;
    _scrollController.scrollTo(
      index: 0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _refreshScheduleIfStale() {
    final now = DateTime.now();
    final last = _scheduleRefreshedAt;
    if (last != null && now.difference(last) < _scheduleRefreshInterval) {
      return;
    }
    _scheduleRefreshedAt = now;
    final tourIds = ref.read(combinedCategoriesProvider).tourIds;
    ref.invalidate(combinedRoundsProvider(combinedRoundsKey(tourIds)));
  }

  Future<void> _handleRefresh() async {
    HapticFeedbackService.medium();
    FocusScope.of(context).unfocus();
    final tourIds = ref.read(combinedCategoriesProvider).tourIds;
    _scheduleRefreshedAt = DateTime.now();
    ref.invalidate(combinedRoundsProvider(combinedRoundsKey(tourIds)));
    try {
      await Future.wait<void>([
        ref.read(tourDetailScreenProvider.notifier).refreshTourDetails(),
        for (final tourId in tourIds)
          ref.read(gamesTourProvider(tourId).notifier).refreshGames(),
      ]);
    } catch (_) {
      // Boards already on screen stay; the next poll repairs the rest.
    }
  }

  /// A board is pinned into its own category, so the pin is the same one the
  /// single-category view shows.
  Future<void> _togglePin(GamesTourModel game) async {
    await ref
        .read(gamesPinprovider(game.tourId).notifier)
        .togglePin(gameId: game.gameId, sourceTourId: game.tourId);
    if (!mounted) return;
    final eventId = ref.read(selectedBroadcastModelProvider)?.id;
    if (eventId != null && eventId.isNotEmpty) {
      ref.read(eventPinRefreshProvider(eventId).notifier).state++;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final presentation = ref.watch(combinedGamesPresentationProvider);
    final viewMode = ref.watch(gamesListViewModeProvider);

    ref.listen<bool>(
      combinedRoundSectionsProvider.select(
        (value) => value.hasUnscheduledRounds,
      ),
      (_, hasUnscheduledRounds) {
        if (hasUnscheduledRounds) _refreshScheduleIfStale();
      },
    );

    if (presentation.isLoading) return const TourLoadingWidget();

    if (presentation.layout.itemCount == 0) {
      return RefreshIndicator(
        onRefresh: _handleRefresh,
        color: context.colors.textPrimaryMuted,
        backgroundColor: context.colors.surfaceRecessed,
        displacement: 60.h,
        strokeWidth: 3.w,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: _emptyState(context, presentation),
        ),
      );
    }

    final isSearchMode = presentation.isSearchMode;
    return RefreshIndicator(
      onRefresh: _handleRefresh,
      color: context.colors.textPrimaryMuted,
      backgroundColor: context.colors.surfaceRecessed,
      displacement: 60.h,
      strokeWidth: 3.w,
      child: GamesListView(
        key: ValueKey('combined_games_${viewMode.name}_search_$isSearchMode'),
        gamesByRound: presentation.gamesByRound,
        gamesData: GamesScreenModel(
          gamesTourModels: presentation.layout.orderedGames,
          pinnedGamedIs: presentation.pinnedGameIds,
          isSearchMode: isSearchMode,
          searchQuery: isSearchMode ? presentation.searchQuery : null,
        ),
        gamesListViewMode: viewMode,
        itemScrollController: _scrollController,
        itemPositionsListener: _positionsListener,
        isSearchMode: isSearchMode,
        layout: presentation.layout,
        onPinToggle: _togglePin,
        // The board screen pages through the combined list, in this order,
        // instead of reloading one category's games.
        navigationListPolicy: BoardNavigationListPolicy.preserve,
        roundHeaderBuilder: (context, entry, isExpanded, onToggle) {
          final category = presentation.categoryLabelFor(entry.round.id);
          final when = entry.round.formattedRoundDateTime;
          return TournamentRoundHeader(
            title: category ?? entry.round.name,
            subtitle: category == null
                ? (when.isEmpty ? null : when)
                : (when.isEmpty
                      ? entry.round.name
                      : '${entry.round.name} · $when'),
            isExpanded: isExpanded,
            onToggle: onToggle,
            multiline: true,
            titleMaxLines: 1,
          );
        },
      ),
    );
  }

  Widget _emptyState(
    BuildContext context,
    CombinedGamesPresentation presentation,
  ) {
    if (presentation.isSearchMode) {
      return EmptySearchWidget(query: presentation.searchQuery);
    }
    final error = presentation.error;
    if (error != null) {
      return Padding(
        padding: EdgeInsets.fromLTRB(24.sp, 40.h, 24.sp, 0),
        child: Text(
          userFacingError(error),
          style: AppTypography.textMdRegular.copyWith(
            color: context.colors.textPrimary,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }
    return const NoGamesPlaceholder();
  }
}
