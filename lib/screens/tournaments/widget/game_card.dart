import 'dart:ui';

import 'package:chessever2/screens/tournaments/model/games_tour_model.dart';
import 'package:chessever2/screens/tournaments/widget/chess_progress_bar.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/back_drop_filter_widget.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class GameCard extends StatelessWidget {
  const GameCard({
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
                (gamesTourModel.gameStatus == GameStatus.ongoing)
                    ? ChessProgressBar(asyncValue: AsyncValue.loading())
                    : _StatusText(
                      status: gamesTourModel.gameStatus.displayText,
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
                                (gamesTourModel.gameStatus ==
                                        GameStatus.ongoing)
                                    ? ChessProgressBar(
                                      asyncValue: AsyncValue.loading(),
                                    )
                                    : _StatusText(
                                      status:
                                          gamesTourModel.gameStatus.displayText,
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
                                      isPinned ? "Unpin" : "Pin to Top",
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

class _StatusText extends StatelessWidget {
  const _StatusText({required this.status, super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Text(
      status,
      textAlign: TextAlign.center,
      style: AppTypography.textXsMedium.copyWith(color: kBlackColor),
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
