import 'dart:ui';

import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/chess_progress_bar.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/location_service_provider.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/atomic_countdown_text.dart';
import 'package:chessever2/widgets/back_drop_filter_widget.dart';
import 'package:country_flags/country_flags.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class GameCard extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
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
                  turn: gamesTourModel.activePlayer == Side.white,
                  time: gamesTourModel.whiteTimeDisplay,
                  gamesTourModel: gamesTourModel,
                  isWhitePlayer: true,
                ),
                Spacer(),
                _TimerWidget(
                  turn: gamesTourModel.activePlayer == Side.black,
                  time: gamesTourModel.blackTimeDisplay,
                  gamesTourModel: gamesTourModel,
                  isWhitePlayer: false,
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
                                  turn: gamesTourModel.activePlayer == Side.white,
                                  time: gamesTourModel.whiteTimeDisplay,
                                  gamesTourModel: gamesTourModel,
                                  isWhitePlayer: true,
                                ),
                                Spacer(),
                                _TimerWidget(
                                  turn: gamesTourModel.activePlayer == Side.black,
                                  time: gamesTourModel.blackTimeDisplay,
                                  gamesTourModel: gamesTourModel,
                                  isWhitePlayer: false,
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
            if (countryCode.toUpperCase() == 'FID') ...<Widget>[
              Image.asset(
                PngAsset.fideLogo,
                height: 12.h,
                width: 16.w,
                fit: BoxFit.cover,
                cacheWidth: 48,
                cacheHeight: 36,
              ),
              SizedBox(width: 4.w),
            ] else if (validCountryCode.isNotEmpty) ...<Widget>[
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
  const _TimerWidget({
    required this.turn,
    required this.time,
    required this.gamesTourModel,
    required this.isWhitePlayer,
    super.key,
  });

  final bool turn;
  final String time;
  final GamesTourModel gamesTourModel;
  final bool isWhitePlayer;

  @override
  Widget build(BuildContext context) {
    // Determine if this player's clock should be counting down
    final isClockRunning =
        gamesTourModel.gameStatus.isOngoing &&
        gamesTourModel.lastMoveTime != null &&
        gamesTourModel.activePlayer != null &&
        ((isWhitePlayer && gamesTourModel.activePlayer == Side.white) ||
            (!isWhitePlayer && gamesTourModel.activePlayer == Side.black));

    // Use atomic countdown text widget for optimized rebuilds
    // Calculate moveTime using SAME logic as PlayerFirstRowDetailWidget
    String? calculatedMoveTime;

    // Extract move times from PGN and calculate current move index like ChessBoardProvider
    if (gamesTourModel.pgn != null && gamesTourModel.pgn!.isNotEmpty) {
      try {

        final moveTimes = _parseMoveTimesFromPgn(gamesTourModel.pgn!);
        final currentMoveIndex = _calculateCurrentMoveIndex(gamesTourModel.pgn!);


        if (moveTimes.isNotEmpty && currentMoveIndex >= 0) {
          // Find the most recent move for this player using currentMoveIndex (same logic as PlayerFirstRowDetailWidget)
          for (int i = currentMoveIndex; i >= 0; i--) {
            final wasMoveByThisPlayer =
                (i % 2 == 0 && isWhitePlayer) || (i % 2 == 1 && !isWhitePlayer);

            if (wasMoveByThisPlayer && i < moveTimes.length) {
              calculatedMoveTime = moveTimes[i];
              break;
            }
          }
        }

      } catch (e) {
        // If PGN parsing fails, will use fallback below
      }
    } else {
    }

    // Fallback to game model's time (same as PlayerFirstRowDetailWidget)
    final fallbackTime = isWhitePlayer
        ? gamesTourModel.whiteTimeDisplay
        : gamesTourModel.blackTimeDisplay;

    calculatedMoveTime ??= fallbackTime;

    final clockCentiseconds = isWhitePlayer
        ? gamesTourModel.whiteClockCentiseconds
        : gamesTourModel.blackClockCentiseconds;


    return AtomicCountdownText(
      moveTime: calculatedMoveTime, // Same calculation as PlayerFirstRowDetailWidget
      clockCentiseconds: clockCentiseconds, // Fallback source: raw database clock
      lastMoveTime: gamesTourModel.lastMoveTime,
      isActive: isClockRunning,
      style: AppTypography.textXsMedium.copyWith(
        color: gamesTourModel.gameStatus.isFinished
            ? kWhiteColor
            : (turn ? kPrimaryColor : kWhiteColor),
      ),
    );
  }

  // PGN parsing methods copied from ChessBoardProvider to match PlayerFirstRowDetailWidget logic
  static List<String> _parseMoveTimesFromPgn(String pgn) {
    final List<String> times = [];

    try {
      final game = PgnGame.parsePgn(pgn);

      // Iterate through the mainline moves
      for (final nodeData in game.moves.mainline()) {
        String? timeString;

        // Check if this move has comments
        if (nodeData.comments != null) {
          // Extract time if it exists in any comment
          for (String comment in nodeData.comments!) {
            final timeMatch = RegExp(
              r'\[%clk (\d+:\d+:\d+)\]',
            ).firstMatch(comment);
            if (timeMatch != null) {
              timeString = timeMatch.group(1);
              break; // Found time, no need to check other comments for this move
            }
          }
        }

        // Add formatted time or default if no time found
        if (timeString != null) {
          times.add(_formatDisplayTime(timeString));
        } else {
          times.add('-:--:--'); // Default for moves without time
        }
      }
    } catch (e) {
      // Fallback to regex method if dartchess parsing fails
      return _parseMoveTimesFromPgnFallback(pgn);
    }

    return times;
  }

  // Fallback method using the original regex approach
  static List<String> _parseMoveTimesFromPgnFallback(String pgn) {
    final List<String> times = [];
    final regex = RegExp(r'\{ \[%clk (\d+:\d+:\d+)\] \}');
    final matches = regex.allMatches(pgn);

    for (final match in matches) {
      final timeString = match.group(1) ?? '0:00:00';
      times.add(_formatDisplayTime(timeString));
    }

    return times;
  }

  static String _formatDisplayTime(String timeString) {
    // Convert "1:40:57" to display format
    final parts = timeString.split(':');
    if (parts.length == 3) {
      final hours = int.parse(parts[0]);
      final minutes = parts[1];
      final seconds = parts[2];

      // If less than an hour, show MM:SS format
      if (hours == 0) {
        return '$minutes:$seconds';
      }
      // Otherwise show H:MM:SS format
      return '$hours:$minutes:$seconds';
    }
    return timeString;
  }

  // Calculate current move index from PGN (same logic as ChessBoardProvider)
  static int _calculateCurrentMoveIndex(String pgn) {
    try {
      final gameData = PgnGame.parsePgn(pgn);
      final moves = gameData.moves.mainline().toList();
      // Return index of last move (0-based, so length - 1)
      return moves.length - 1;
    } catch (e) {
      return -1; // Return -1 if parsing fails
    }
  }
}
