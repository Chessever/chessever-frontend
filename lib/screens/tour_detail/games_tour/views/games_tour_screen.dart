import 'dart:async';
import 'package:chessever2/screens/group_event/widget/tour_loading_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_scroll_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_body.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/group_event_games_tour_content_body.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/widgets/scroll_to_top_bus.dart';
import 'package:chessever2/widgets/search/gameSearch/game_search_overlay.dart';
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
    with ScrollToTopListenerMixin {
  @override
  void onScrollToTopRequested() {
    final scopeId = ref.read(gamesTourScrollScopeProvider);
    final controller = ref.read(gamesTourScrollProvider(scopeId));
    if (controller.isAttached) {
      controller.scrollTo(
        index: 0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final gamesListViewMode = ref.watch(gamesListViewModeProvider);
    final gamesTourMode = ref.watch(gamesTourScreenModeProvider);

    return gamesTourMode.when(
      data: (mode) {
        final gamesTourAsync = ref.watch(gamesTourScreenProvider);

        return gamesTourAsync.when(
          data: (data) {
            if (data.gamesTourModels.isEmpty) {
              return SingleChildScrollView(
                child:
                    data.isSearchMode && data.searchQuery != null
                        ? EmptySearchWidget(query: data.searchQuery!)
                        : Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12.sp),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(height: 40.h),
                              SvgPicture.asset(
                                SvgAsset.tournamentIcon,
                                height: 35.h,
                                width: 35.w,
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
                        ),
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
              child:
                  useNormalMode
                      ? GamesTourContentBody(
                        gamesScreenModel: data,
                        gamesListViewMode: gamesListViewMode,
                      )
                      : GroupEventGamesTourContentBody(
                        gamesScreenModel: data,
                        gamesListViewMode: gamesListViewMode,
                        onReturnFromChessboard: (index) {},
                      ),
            );
          },
          error: (e, _) {
            return Center(
              child: Text(
                'Error: $e',
                style: AppTypography.textMdRegular.copyWith(color: context.colors.textPrimary),
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
            'Error: $e',
            style: AppTypography.textMdRegular.copyWith(color: context.colors.textPrimary),
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
      futures.add(
        ref.read(tourDetailScreenProvider.notifier).refreshTourDetails(),
      );
      futures.add(ref.read(gamesAppBarProvider.notifier).refresh());
      futures.add(ref.read(gamesTourScreenProvider.notifier).refreshGames());
      await Future.wait(futures);
    } catch (_) {}
  }
}
