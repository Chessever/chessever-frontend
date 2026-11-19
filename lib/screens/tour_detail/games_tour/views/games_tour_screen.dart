import 'dart:async';
import 'package:chessever2/screens/group_event/widget/tour_loading_widget.dart';
import 'package:chessever2/screens/tour_detail/widgets/event_games_quick_actions.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_scroll_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_body.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_grouped_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_stage_round_resolver.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/group_event_games_tour_content_body.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/search_list_resume.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/widgets/event_games_no_matches.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/page_spring.dart';
import 'package:chessever2/widgets/scroll_to_top_bus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/svg_asset.dart';

class GamesTourScreen extends ConsumerStatefulWidget {
  const GamesTourScreen({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _GamesTourScreenState();
}

class _GamesTourScreenState extends ConsumerState<GamesTourScreen>
    with ScrollToTopListenerMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  /// The reader's place in every game while a search's hits stand in for
  /// them, handed back as the search ends.
  final SearchListResume _resume = SearchListResume();

  /// The query whose hits are on screen, to tell new hits from a rebuild.
  String? _hitsQuery;

  @override
  void onScrollToTopRequested() {
    final scopeId = ref.read(gamesTourScrollScopeProvider);
    final controller = ref.read(gamesTourScrollProvider(scopeId));
    if (!controller.isAttached) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.jumpTo(index: 0);
      return;
    }
    // On the tabs' spring, as every other list's way back to its top.
    final spring = SpringCurve.of(PageSpring.motion);
    controller.scrollTo(index: 0, duration: spring.duration, curve: spring);
  }

  /// Where the list built now starts, and the hits of a new query read
  /// from their top: a list kept across queries would hold the last one's
  /// place, past the end of shorter hits.
  ListResumePoint? _startFor(GamesScreenModel data) {
    final scopeId = ref.read(gamesTourScrollScopeProvider);
    final positions = ref
        .read(gamesTourScrollProvider(scopeId).notifier)
        .itemPositionsListener;
    final start = _resume.resolve(
      searching: data.isSearchMode,
      positions: positions,
    );
    if (start != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _resume.consumed());
    }
    final query = data.isSearchMode ? data.searchQuery : null;
    final newHits = query != null && _hitsQuery != null && query != _hitsQuery;
    _hitsQuery = query;
    if (newHits) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final controller = ref.read(gamesTourScrollProvider(scopeId));
        if (controller.isAttached &&
            ListResumePoint.capture(positions) != null) {
          controller.jumpTo(index: 0);
        }
      });
    }
    return start;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final gamesListViewMode = ref.watch(gamesListViewModeProvider);
    final gamesTourMode = ref.watch(gamesTourScreenModeProvider);

    return gamesTourMode.when(
      data: (mode) {
        final gamesTourAsync = ref.watch(gamesTourScreenProvider);

        return gamesTourAsync.when(
          data: (data) {
            final startAt = _startFor(data);
            final groupedData = ref.watch(gamesTourGroupedProvider);
            final hasGroupedGames = groupedData.gamesByRound.values.any(
              (games) => games.isNotEmpty,
            );
            if (data.gamesTourModels.isEmpty && groupedData.isLoading) {
              return const TourLoadingWidget();
            }
            if (data.gamesTourModels.isEmpty && !hasGroupedGames) {
              return SingleChildScrollView(
                child: data.isSearchMode
                    ? EventGamesNoMatches(query: data.searchQuery)
                    : const NoGamesPlaceholder(),
              );
            }
            // TABLET-ONLY: Check if rounds contain knockout-stage IDs.
            // GroupEventGamesTourContentBody can't handle knockout-stage rounds
            // (it matches game.roundId == round.id which fails for knockout stages).
            // Force normal mode rendering for knockout tournaments on tablet.
            final effectiveMode = mode;
            final bool useNormalMode;
            if (ResponsiveHelper.isTablet &&
                effectiveMode == GamesTourScreenMode.groupEvent) {
              final gamesAppBar = ref.watch(gamesAppBarProvider);
              final hasKnockoutRounds =
                  gamesAppBar.valueOrNull?.gamesAppBarModels.any(
                    (r) => r.id.startsWith('$kKnockoutStagePrefix-'),
                  ) ??
                  false;
              useNormalMode = hasKnockoutRounds;
            } else {
              useNormalMode = effectiveMode == GamesTourScreenMode.normal;
            }

            return RefreshIndicator(
              onRefresh: _handleRefresh,
              color: context.colors.textPrimaryMuted,
              backgroundColor: context.colors.surfaceRecessed,
              displacement: 60.h,
              strokeWidth: 3.w,
              child: useNormalMode
                  ? GamesTourContentBody(
                      gamesScreenModel: data,
                      gamesListViewMode: gamesListViewMode,
                      startAt: startAt,
                    )
                  : GroupEventGamesTourContentBody(
                      gamesScreenModel: data,
                      gamesListViewMode: gamesListViewMode,
                      onReturnFromChessboard: (index) {},
                      startAt: startAt,
                    ),
            );
          },
          error: (e, _) {
            return Center(
              child: Text(
                userFacingError(e),
                style: AppTypography.textMdRegular.copyWith(
                  color: context.colors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
            );
          },
          loading: () => const TourLoadingWidget(),
        );
      },
      error: (e, _) {
        return Center(
          child: Text(
            userFacingError(e),
            style: AppTypography.textMdRegular.copyWith(
              color: context.colors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
        );
      },
      loading: () => const TourLoadingWidget(),
    );
  }

  Future<void> _handleRefresh() async {
    HapticFeedbackService.medium();
    try {
      FocusScope.of(context).unfocus();
      final futures = <Future>[];
      final tourDetail = ref.read(tourDetailScreenProvider).valueOrNull;
      final selectedTourId = tourDetail?.aboutTourModel.id;
      final rounds =
          ref.read(gamesAppBarProvider).valueOrNull?.gamesAppBarModels ??
          const <GamesAppBarModel>[];
      if (selectedTourId != null && selectedTourId.isNotEmpty) {
        final knownTourIds =
            tourDetail?.tours.map((tour) => tour.tour.id) ?? const <String>[];
        for (final siblingTourId in siblingKnockoutStageTourIds(
          rounds: rounds,
          selectedTourId: selectedTourId,
          knownTourIds: knownTourIds,
        )) {
          futures.add(
            ref.read(gamesTourProvider(siblingTourId).notifier).refreshGames(),
          );
        }
      }
      futures.add(
        ref.read(tourDetailScreenProvider.notifier).refreshTourDetails(),
      );
      futures.add(ref.read(gamesAppBarProvider.notifier).refresh());
      futures.add(ref.read(gamesTourScreenProvider.notifier).refreshGames());
      // The count of games in play comes along with the boards.
      futures.add(refreshEventGamesLiveIds(ref));
      await Future.wait(futures);
    } catch (_) {}
  }
}

/// Shown when an event has no boards to list. Shared with the Combined list.
class NoGamesPlaceholder extends StatelessWidget {
  const NoGamesPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.sp),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(height: 40.h),
          SvgPicture.asset(
            SvgAsset.tournamentIcon,
            height: 35.h,
            width: 35.w,
            // White stroke art: tint it for paper.
            colorFilter: context.isLightTheme
                ? ColorFilter.mode(
                    context.colors.iconSecondary,
                    BlendMode.srcIn,
                  )
                : null,
          ),
          SizedBox(height: 10.h),
          Text(
            'No games going on',
            style: AppTypography.textMdRegular.copyWith(
              color: context.colors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
