import 'package:chessever2/screens/tournaments/model/games_tour_model.dart';
import 'package:chessever2/screens/tournaments/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tournaments/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tournaments/providers/pintop_storage.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/back_drop_filter_widget.dart';
import 'package:chessever2/widgets/divider_widget.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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

                        return FutureBuilder<List<String>>(
                          future: PinnedGamesStorage().getPinnedGameIds(),
                          builder: (context, snapshot) {
                            final pinnedIds = snapshot.data ?? [];

                            final sortedGames = [
                              ...data.where(
                                (game) => pinnedIds.contains(game.gameId),
                              ),
                              ...data.where(
                                (game) => !pinnedIds.contains(game.gameId),
                              ),
                            ];

                            return ListView.builder(
                              padding: EdgeInsets.only(
                                left: 20.sp,
                                right: 20.sp,
                                top: 12.sp,
                                bottom:
                                    MediaQuery.of(context).viewPadding.bottom,
                              ),
                              itemCount: sortedGames.length,
                              itemBuilder: (cxt, index) {
                                final game = sortedGames[index];
                                return Padding(
                                  padding: EdgeInsets.only(bottom: 12.sp),
                                  child: _GameCard(
                                    gamesTourModel: game,
                                    pinnedIds: pinnedIds,
                                    onPinToggle: (gamesTourModel) async {
                                      print(
                                        'Pin toggle tapped for game: ${gamesTourModel.gameId}',
                                      );
                                      await ref
                                          .read(
                                            gamesTourScreenProvider.notifier,
                                          )
                                          .togglePinGame(gamesTourModel.gameId);
                                    },
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                      error: (_, __) => GenericErrorWidget(),
                      loading: () => _TourLoadingWidget(),
                    );
              },
              error: (_, __) => GenericErrorWidget(),
              loading: () => _TourLoadingWidget(),
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
            child: _GameCard(
              gamesTourModel: gamesTourModelList[index],
              onPinToggle: (game) {},
              pinnedIds: [],
            ),
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
  const _GameCard({
    required this.gamesTourModel,
    required this.onPinToggle,
    required this.pinnedIds,
    super.key,
  });

  final GamesTourModel gamesTourModel;
  final void Function(GamesTourModel game) onPinToggle;
  final List<String> pinnedIds;

  bool get isPinned => pinnedIds.contains(gamesTourModel.gameId);

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
              SizedBox(width: 10.w),
              Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  if (isPinned) ...[
                    SizedBox(width: 8.w),
                    SvgPicture.asset(
                      SvgAsset.pin,
                      color: kpinColor,
                      height: 14.h,
                      width: 14.w,
                    ),
                  ],
                  SizedBox(height: 10.h),
                  GestureDetector(
                    onTapDown: (TapDownDetails details) {
                      showMenu(
                        context: context,
                        position: RelativeRect.fromLTRB(
                          details.globalPosition.dx,
                          details.globalPosition.dy,
                          0,
                          0,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.br),
                        ),
                        items: <PopupMenuEntry<String>>[
                          PopupMenuItem<String>(
                            value: 'pin',
                            child: GestureDetector(
                              onTap: () {
                                Navigator.pop(context);
                                onPinToggle(gamesTourModel);
                              },
                              child: SizedBox(
                                width: 200,
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      isPinned
                                          ? "Unpin from Top"
                                          : "Pin to Top",
                                      style: AppTypography.textXsMedium
                                          .copyWith(color: kWhiteColor),
                                    ),
                                    SvgPicture.asset(
                                      SvgAsset.pin,
                                      height: 13.h,
                                      width: 13.w,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          PopupMenuDivider(
                            height: 1.h,
                            thickness: 0.5.w,
                            color: kDividerColor,
                          ),

                          PopupMenuItem(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "Share",
                                  style: AppTypography.textXsMedium.copyWith(
                                    color: kWhiteColor,
                                  ),
                                ),
                                SvgPicture.asset(
                                  SvgAsset.share,
                                  height: 13.h,
                                  width: 13.w,
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                    child: SvgPicture.asset(
                      SvgAsset.threeDots,
                      color: kBlack2Color,
                      height: 18.h,
                      width: 12.w,
                    ),
                  ),
                ],
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
