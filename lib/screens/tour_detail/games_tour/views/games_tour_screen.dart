import 'dart:async';
import 'package:chessever2/screens/group_event/widget/tour_loading_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_body.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/chess_board_visibility_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
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

class _GamesTourScreenState extends ConsumerState<GamesTourScreen> {
  @override
  Widget build(BuildContext context) {
    final isChessBoardVisible = ref.watch(chessBoardVisibilityProvider);
    final gamesTourAsync = ref.watch(gamesTourScreenProvider);

    // Removed excessive debug logging to reduce console noise

    return gamesTourAsync.when(
      data: (data) {
        final aboutTourModel =
            ref.watch(tourDetailScreenProvider).valueOrNull?.aboutTourModel;

        // Add loading check for dependencies before showing empty state
        final tourDetailAsync = ref.watch(tourDetailScreenProvider);
        final gamesAsync =
            aboutTourModel != null
                ? ref.watch(gamesTourProvider(aboutTourModel.id))
                : const AsyncValue.loading();

        // Don't show empty state if we're still loading dependencies
        if (tourDetailAsync.isLoading || gamesAsync.isLoading) {
          return const TourLoadingWidget();
        }

        if (data.gamesTourModels.isEmpty) {
          if (data.isSearchMode && data.searchQuery != null) {
            return EmptySearchWidget(query: data.searchQuery!);
          } else {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SvgPicture.asset(
                    SvgAsset.tournamentIcon,
                    height: 35,
                    width: 35,
                  ),
                  SizedBox(height: 10),
                  Text(
                    'No games going on',
                    style: AppTypography.textMdRegular.copyWith(
                      color: kWhiteColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }
        }

        return RefreshIndicator(
          onRefresh: _handleRefresh,
          color: kWhiteColor70,
          backgroundColor: kDarkGreyColor,
          displacement: 60.h,
          strokeWidth: 3.w,
          child: GamesTourContentBody(
            gamesScreenModel: data,
            isChessBoardVisible: isChessBoardVisible,
          ),
        );
      },
      error: (e, _) {
        return Center(
          child: Text(
            'Error: $e',
            style: AppTypography.textMdRegular.copyWith(color: kWhiteColor),
            textAlign: TextAlign.center,
          ),
        );
      },
      loading: () => const TourLoadingWidget(),
    );
  }

  Future<void> _handleRefresh() async {
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
