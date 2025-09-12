import 'dart:ui';

import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/chess_progress_bar.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/location_service_provider.dart';
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
                    playerRank:
                        '${gamesTourModel.whitePlayer.title} ${gamesTourModel.whitePlayer.rating}',
                    countryCode: gamesTourModel.whitePlayer.countryCode,
                  ),
                ),
                Spacer(),
                (gamesTourModel.gameStatus == GameStatus.ongoing)
                    ? ChessProgressBar(fen: gamesTourModel.fen ?? '')
                    : _StatusText(
                      status: gamesTourModel.gameStatus.displayText,
                    ),
                Spacer(),
                SizedBox(
                  width: MediaQuery.of(context).size.width * (30 / 100),
                  child: _GamesRound(
                    playerName: gamesTourModel.blackPlayer.name,
                    playerRank:
                        '${gamesTourModel.blackPlayer.title} ${gamesTourModel.blackPlayer.rating}',
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
    final RenderBox cardRenderBox = context.findRenderObject() as RenderBox;
    final Offset cardPosition = cardRenderBox.localToGlobal(Offset.zero);
    final Size cardSize = cardRenderBox.size;

    final double screenHeight = MediaQuery.of(context).size.height;
    const double popupHeight = 100;
    final double spaceBelow =
        screenHeight - (cardPosition.dy + cardSize.height);

    bool showAbove = spaceBelow < popupHeight;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      pageBuilder: (
        BuildContext buildContext,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
      ) {
        final double menuTop =
            showAbove
                ? cardPosition.dy - popupHeight - 8.sp
                : cardPosition.dy + cardSize.height + 8.sp;
        return Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Stack(
              children: [
                _SelectiveBlurBackground(
                  cardPosition: cardPosition,
                  cardSize: cardSize,
                ),
                Positioned(
                  left: cardPosition.dx,
                  top: cardPosition.dy,
                  child: GestureDetector(
                    onTap: () {},
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
                                        '${gamesTourModel.whitePlayer.title} ${gamesTourModel.whitePlayer.rating}',
                                    countryCode:
                                        gamesTourModel.whitePlayer.countryCode,
                                  ),
                                ),
                                Spacer(),
                                (gamesTourModel.gameStatus ==
                                        GameStatus.ongoing)
                                    ? ChessProgressBar(
                                      fen: gamesTourModel.fen ?? "",
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
                                        '${gamesTourModel.blackPlayer.title} ${gamesTourModel.blackPlayer.rating}',
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
                // Popup menu
                Positioned(
                  left: details.globalPosition.dx - 120.w,
                  top: menuTop,
                  child: GestureDetector(
                    onTap: () {},
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
                                // Handle share
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

class _GamesRound extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final validCountryCode = ref
        .read(locationServiceProvider)
        .getValidCountryCode(countryCode);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _getString(playerName),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.textXsMedium.copyWith(color: kBlackColor),
        ),
        Row(
          children: [
            if (validCountryCode.isNotEmpty) ...<Widget>[
              CountryFlag.fromCountryCode(
                validCountryCode,
                height: 12.h,
                width: 16.w,
              ),
              SizedBox(width: 4.w),
            ],
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

String _getString(String name) {
  if (name.length > 18) {
    final firstAndLastName = name.split(',');
    if (firstAndLastName.length == 2) {
      final lastName = firstAndLastName[0].trim();
      final firstName = firstAndLastName[1].trim();

      if (firstName.isNotEmpty) {
        final firstInitial = firstName[0].toUpperCase();
        final targetFormat = '$lastName, $firstInitial.';

        if (targetFormat.length <= 18) {
          return targetFormat;
        } else {
          final maxLastNameLength = 18 - 4; // 18 - ", I.".length
          final truncatedLastName =
              '${lastName.substring(0, maxLastNameLength)}…';
          return '$truncatedLastName, $firstInitial.';
        }
      } else {
        // No first name, just return truncated last name
        return lastName.length > 18
            ? '${lastName.substring(0, 15)}…'
            : lastName;
      }
    } else {
      // Not in "LastName, FirstName" format, just truncate
      return '${name.substring(0, 15)}…';
    }
  } else {
    return name;
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
        color: turn ? kPrimaryColor : kWhiteColor,
      ),
    );
  }
}
