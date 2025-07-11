import 'package:chessever2/screens/chessboard/view_model/chess_board_fen_model.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_widget.dart';
import 'package:chessever2/screens/tournaments/model/games_tour_model.dart';
import 'package:chessever2/screens/tournaments/providers/chess_board_visibility_provider.dart';
import 'package:chessever2/screens/tournaments/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tournaments/providers/games_tour_screen_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/back_drop_filter_widget.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'dart:ui';

class GamesTourScreen extends ConsumerWidget {
  const GamesTourScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isChessBoardVisible = ref.watch(chessBoardVisibilityProvider);
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
                        if (data.gamesTourModels.isEmpty) {
                          return EmptyWidget(
                            title:
                                "No games available yet. Check back soon or set a\nreminder for updates.",
                          );
                        }

                        return Column(
                          children: [
                            if (isChessBoardVisible)
                              Expanded(
                                child: ListView.builder(
                                  padding: EdgeInsets.only(
                                    left: 20.sp,
                                    right: 20.sp,
                                    top: 12.sp,
                                    bottom:
                                        MediaQuery.of(
                                          context,
                                        ).viewPadding.bottom,
                                  ),
                                  itemCount: data.gamesTourModels.length,
                                  itemBuilder: (cxt, index) {
                                    return ChessBoardFromFEN(
                                      chessBoardFenModel:
                                          ChessBoardFenModel.fromGamesTourModel(
                                            data.gamesTourModels[index],
                                          ),
                                    );
                                  },
                                ),
                              )
                            else
                              Expanded(
                                child: ListView.builder(
                                  padding: EdgeInsets.only(
                                    left: 20.sp,
                                    right: 20.sp,
                                    top: 12.sp,
                                    bottom:
                                        MediaQuery.of(
                                          context,
                                        ).viewPadding.bottom,
                                  ),
                                  itemCount: data.gamesTourModels.length,
                                  itemBuilder: (cxt, index) {
                                    final game = data.gamesTourModels[index];
                                    return Padding(
                                      padding: EdgeInsets.only(bottom: 12.sp),
                                      child: _GameCard(
                                        onTap: () {
                                          if (data
                                                  .gamesTourModels[index]
                                                  .gameStatus
                                                  .displayText !=
                                              '*') {
                                            Navigator.pushNamed(
                                              context,
                                              '/chess_screen',
                                              arguments: {
                                                'games': data,
                                                'currentIndex': index,
                                              },
                                            );
                                          } else {
                                            showDialog(
                                              context: context,
                                              builder:
                                                  (_) => AlertDialog(
                                                    title: const Text(
                                                      "No PGN Data",
                                                    ),
                                                    content: const Text(
                                                      "This game has no PGN data available.",
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed:
                                                            () => Navigator.pop(
                                                              context,
                                                            ),
                                                        child: const Text("OK"),
                                                      ),
                                                    ],
                                                  ),
                                            );
                                          }
                                        },
                                        gamesTourModel: game,
                                        pinnedIds: data.pinnedGamedIs,
                                        onPinToggle: (gamesTourModel) async {
                                          await ref
                                              .read(
                                                gamesTourScreenProvider
                                                    .notifier,
                                              )
                                              .togglePinGame(
                                                gamesTourModel.gameId,
                                              );
                                        },
                                      ),
                                    );
                                  },
                                ),
                              ),
                          ],
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
              onTap: () {},
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
    required this.onTap,
    super.key,
  });

  final GamesTourModel gamesTourModel;
  final void Function(GamesTourModel game) onPinToggle;
  final List<String> pinnedIds;
  final Function() onTap;

  bool get isPinned => pinnedIds.contains(gamesTourModel.gameId);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            height: 60.h,
            padding: EdgeInsets.only(left: 12.sp),
            decoration: BoxDecoration(
              color: kWhiteColor70,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12.br),
                topRight: Radius.circular(12.br),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: MediaQuery.of(context).size.width * (30 / 100),
                  child: _GamesRound(
                    playerName: gamesTourModel.whitePlayer.name,
                    playerRank: gamesTourModel.whitePlayer.displayTitle,
                    countryCode: gamesTourModel.whitePlayer.countryCode,
                  ),
                ),
                Spacer(),
                _ProgressWidget(
                  progress: gamesTourModel.gameStatus.index / 100,
                ),
                Spacer(),
                SizedBox(
                  width: MediaQuery.of(context).size.width * (30 / 100),
                  child: _GamesRound(
                    playerName: gamesTourModel.blackPlayer.name,
                    playerRank: gamesTourModel.blackPlayer.displayTitle,
                    countryCode: gamesTourModel.blackPlayer.countryCode,
                  ),
                ),
                Spacer(),
                Stack(
                  alignment: Alignment.topRight,
                  children: [
                    if (isPinned) ...[
                      Positioned(
                        left: 4.sp,
                        child: SvgPicture.asset(
                          SvgAsset.pin,
                          color: kpinColor,
                          height: 14.h,
                          width: 14.w,
                        ),
                      ),
                    ],
                    Align(
                      alignment: Alignment.center,
                      child: GestureDetector(
                        onTapDown: (TapDownDetails details) {
                          _showBlurredPopup(context, details);
                        },
                        child: Icon(
                          Icons.more_vert_rounded,
                          color: kBlackColor,
                        ),
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
                _TimerWidget(
                  turn: false,
                  time: gamesTourModel.whiteTimeDisplay,
                ),
                Spacer(),
                _TimerWidget(
                  turn: false,
                  time: gamesTourModel.blackTimeDisplay,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showBlurredPopup(BuildContext context, TapDownDetails details) {
    // Get card position and size
    final RenderBox cardRenderBox = context.findRenderObject() as RenderBox;
    final Offset cardPosition = cardRenderBox.localToGlobal(Offset.zero);
    final Size cardSize = cardRenderBox.size;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      pageBuilder: (
        BuildContext buildContext,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
      ) {
        // Position menu at bottom of card + 8 padding
        final double menuTop = cardPosition.dy + 60.h + 24.h + 8.sp;

        return Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Stack(
              children: [
                // Blur background with cutout for current card
                _SelectiveBlurBackground(
                  cardPosition: cardPosition,
                  cardSize: cardSize,
                ),
                // Selected card in its original position (unblurred)
                Positioned(
                  left: cardPosition.dx,
                  top: cardPosition.dy,
                  child: GestureDetector(
                    onTap: () {}, // Prevent tap from closing dialog
                    child: SizedBox(
                      width: cardSize.width,
                      height: cardSize.height,
                      child: Column(
                        children: [
                          Container(
                            height: 60.h,
                            padding: EdgeInsets.only(left: 12.sp),
                            decoration: BoxDecoration(
                              color: kWhiteColor70,
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(12.br),
                                topRight: Radius.circular(12.br),
                              ),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width:
                                      MediaQuery.of(context).size.width *
                                      (30 / 100),
                                  child: _GamesRound(
                                    playerName: gamesTourModel.whitePlayer.name,
                                    playerRank:
                                        gamesTourModel.whitePlayer.displayTitle,
                                    countryCode:
                                        gamesTourModel.whitePlayer.countryCode,
                                  ),
                                ),
                                Spacer(),
                                _ProgressWidget(
                                  progress:
                                      gamesTourModel.gameStatus.index / 100,
                                ),
                                Spacer(),
                                SizedBox(
                                  width:
                                      MediaQuery.of(context).size.width *
                                      (30 / 100),
                                  child: _GamesRound(
                                    playerName: gamesTourModel.blackPlayer.name,
                                    playerRank:
                                        gamesTourModel.blackPlayer.displayTitle,
                                    countryCode:
                                        gamesTourModel.blackPlayer.countryCode,
                                  ),
                                ),
                                Spacer(),
                                Stack(
                                  alignment: Alignment.topRight,
                                  children: [
                                    if (isPinned) ...[
                                      Positioned(
                                        left: 4.sp,
                                        child: SvgPicture.asset(
                                          SvgAsset.pin,
                                          color: kpinColor,
                                          height: 14.h,
                                          width: 14.w,
                                        ),
                                      ),
                                    ],
                                    Align(
                                      alignment: Alignment.center,
                                      child: Icon(
                                        Icons.more_vert_rounded,
                                        color: kBlackColor,
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
                                _TimerWidget(
                                  turn: false,
                                  time: gamesTourModel.whiteTimeDisplay,
                                ),
                                Spacer(),
                                _TimerWidget(
                                  turn: false,
                                  time: gamesTourModel.blackTimeDisplay,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Popup menu positioned correctly
                Positioned(
                  left: details.globalPosition.dx - 120.w,
                  top: menuTop,
                  child: GestureDetector(
                    onTap: () {}, // Prevent tap from closing dialog
                    child: Material(
                      color: Colors.transparent,
                      child: Container(
                        width: 120.w,
                        decoration: BoxDecoration(
                          color: kDarkGreyColor,
                          borderRadius: BorderRadius.circular(12.br),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 10,
                              offset: Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _PopupMenuItem(
                              onTap: () {
                                Navigator.pop(context);
                                onPinToggle(gamesTourModel);
                              },
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      isPinned
                                          ? "Unpin from Top"
                                          : "Pin to Top",
                                      style: AppTypography.textXsMedium
                                          .copyWith(color: kWhiteColor),
                                    ),
                                  ),
                                  SizedBox(width: 8.w),
                                  SvgPicture.asset(
                                    SvgAsset.pin,
                                    height: 13.h,
                                    width: 13.w,
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              height: 1.h,
                              width: double.infinity,
                              margin: EdgeInsets.symmetric(horizontal: 12.sp),
                              color: kDividerColor,
                            ),
                            _PopupMenuItem(
                              onTap: () {
                                Navigator.pop(context);
                                // Handle share action
                              },
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      "Share",
                                      style: AppTypography.textXsMedium
                                          .copyWith(color: kWhiteColor),
                                    ),
                                  ),
                                  SizedBox(width: 8.w),
                                  SvgPicture.asset(
                                    SvgAsset.share,
                                    height: 13.h,
                                    width: 13.w,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
      transitionDuration: const Duration(milliseconds: 300),
    );
  }
}

class _SelectiveBlurBackground extends StatelessWidget {
  const _SelectiveBlurBackground({
    required this.cardPosition,
    required this.cardSize,
    super.key,
  });

  final Offset cardPosition;
  final Size cardSize;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Full screen blur
        BackDropFilterWidget(),
        // Cutout for the selected card (clear area)
        Positioned(
          left: cardPosition.dx,
          top: cardPosition.dy,
          child: Container(
            width: cardSize.width,
            height: cardSize.height,
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12.br),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12.br),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PopupMenuItem extends StatelessWidget {
  const _PopupMenuItem({required this.onTap, required this.child, super.key});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.br),
      child: Container(
        width: 120.w,
        height: 40.h,
        padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 8.sp),
        child: child,
      ),
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
          maxLines: 1,
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
