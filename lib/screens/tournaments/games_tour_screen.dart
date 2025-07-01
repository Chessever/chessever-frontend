import 'package:chessever2/screens/tournaments/model/games_tour_model.dart';
import 'package:chessever2/screens/tournaments/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tournaments/providers/games_tour_screen_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class GamesTourScreen extends ConsumerWidget {
  const GamesTourScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: FocusScope.of(context).unfocus,
      child: RefreshIndicator(
        onRefresh: () async {
          FocusScope.of(context).unfocus();
          await ref.read(gamesTourScreenProvider.notifier).refreshGames();
        },
        color: kWhiteColor70,
        backgroundColor: kDarkGreyColor,
        displacement: 60.h,
        // Distance from top where indicator appears
        strokeWidth: 3.w,
        child: ref
            .watch(gamesAppBarProvider)
            .when(
              data: (_) {
                return ref
                    .watch(gamesTourScreenProvider)
                    .when(
                      data: (data) {
                        if (data.isEmpty) {
                          return EmptyWidget(
                            title:
                                "No games available yet. Check back soon or set a\nreminder for updates.",
                          );
                        }
                        return ListView.builder(
                          padding: EdgeInsets.only(
                            left: 20.sp,
                            right: 20.sp,
                            top: 12.sp,
                            bottom: MediaQuery.of(context).viewPadding.bottom,
                          ),
                          shrinkWrap: true,
                          itemCount: data.length,
                          itemBuilder: (cxt, index) {
                            return Padding(
                              padding: EdgeInsets.only(bottom: 12.sp),
                              child: _GameCard(gamesTourModel: data[index]),
                            );
                          },
                        );
                      },
                      error: (error, _) {
                        return GenericErrorWidget();
                      },
                      loading: () {
                        return _TourLoadingWidget();
                      },
                    );
              },
              error: (error, _) {
                return GenericErrorWidget();
              },
              loading: () {
                return _TourLoadingWidget();
              },
            ),
      ),
    );
  }
}

class _TourLoadingWidget extends StatelessWidget {
  const _TourLoadingWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final mockPlayer = PlayerCard(
      name: 'name',
      federation: 'federation',
      title: 'title',
      rating: 0,
      countryCode: 'USA',
    );
    final gamesTourModel = GamesTourModel(
      gameId: 'gameId',
      whitePlayer: mockPlayer,
      blackPlayer: mockPlayer,
      whiteTimeDisplay: 'whiteTimeDisplay',
      blackTimeDisplay: 'blackTimeDisplay',
      gameStatus: GameStatus.whiteWins,
    );

    final gamesTourModelList = List.generate(8, (_) => gamesTourModel);

    return ListView.builder(
      scrollDirection: Axis.vertical,
      padding: EdgeInsets.only(
        left: 20.sp,
        right: 20.sp,
        top: 12.sp,
        bottom: MediaQuery.of(context).viewPadding.bottom,
      ),
      shrinkWrap: true,
      itemCount: gamesTourModelList.length,
      itemBuilder: (cxt, index) {
        return SkeletonWidget(
          ignoreContainers: true,
          child: Padding(
            padding: EdgeInsets.only(bottom: 12.sp),
            child: _GameCard(gamesTourModel: gamesTourModelList[index]),
          ),
        );
      },
    );
  }
}

class EmptyWidget extends StatelessWidget {
  const EmptyWidget({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgWidget(SvgAsset.infoIcon, height: 24.h, width: 24.w),
        SizedBox(height: 12.h),
        Text(
          title,
          style: AppTypography.textXsRegular.copyWith(color: kWhiteColor70),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.gamesTourModel, super.key});

  final GamesTourModel gamesTourModel;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 60.h,
          padding: EdgeInsets.symmetric(horizontal: 12.sp),
          decoration: BoxDecoration(
            color: kWhiteColor70,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(12.br),
              topRight: Radius.circular(12.br),
            ),
          ),
          child: Row(
            children: [
              _GamesRound(
                playerName: gamesTourModel.whitePlayer.name,
                playerRank: gamesTourModel.whitePlayer.displayTitle,
                countryCode: gamesTourModel.whitePlayer.countryCode,
              ),
              Spacer(),
              _ProgressWidget(progress: gamesTourModel.gameStatus.index / 100),
              Spacer(),
              _GamesRound(
                playerName: gamesTourModel.blackPlayer.name,
                playerRank: gamesTourModel.blackPlayer.displayTitle,
                countryCode: gamesTourModel.blackPlayer.countryCode,
              ),
            ],
          ),
        ),
        Container(
          height: 24.h,
          padding: EdgeInsets.symmetric(horizontal: 10.sp),
          decoration: BoxDecoration(
            color: kBlack2Color,
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(12.br),
              bottomRight: Radius.circular(12.br),
            ),
          ),
          child: Row(
            children: [
              _TimerWidget(turn: true, time: gamesTourModel.whiteTimeDisplay),
              Spacer(),
              _TimerWidget(turn: false, time: gamesTourModel.blackTimeDisplay),
            ],
          ),
        ),
      ],
    );
  }
}

class _GamesRound extends StatelessWidget {
  const _GamesRound({
    required this.playerName,
    required this.playerRank,
    required this.countryCode,
    super.key,
  });

  final String playerName;
  final String playerRank;
  final String countryCode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          playerName,
          style: AppTypography.textXsMedium.copyWith(color: kBlackColor),
        ),
        Row(
          children: [
            CountryFlag.fromCountryCode(countryCode, height: 12.h, width: 16.w),
            SizedBox(width: 4.w),
            Text(
              playerRank,
              style: AppTypography.textXsMedium.copyWith(color: kBlack2Color),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProgressWidget extends StatelessWidget {
  const _ProgressWidget({required this.progress, super.key});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48.w,
      height: 12.h,
      child: Stack(
        children: [
          // Background container
          Container(
            width: 48.w,
            height: 12.h,
            decoration: BoxDecoration(
              color: kBlack2Color,
              borderRadius: BorderRadius.all(Radius.circular(4.br)),
            ),
          ),
          // Progress container
          Container(
            width: 48 * progress, // 0.5 is the progress value
            height: 12.0.h,
            decoration: BoxDecoration(
              color: kWhiteColor,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(4.br),
                bottomLeft: Radius.circular(4.br),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimerWidget extends StatelessWidget {
  const _TimerWidget({required this.turn, required this.time, super.key});

  final bool turn;
  final String time;

  @override
  Widget build(BuildContext context) {
    return Text(
      time,
      style: AppTypography.textXsMedium.copyWith(
        color: turn ? kLightBlue : kWhiteColor,
      ),
    );
  }
}
