import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/chess_progress_bar.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/location_service_provider.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/string_utils_provider.dart';
import 'package:chessever2/widgets/atomic_countdown_text.dart';
import 'package:country_flags/country_flags.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/screens/chessboard/widgets/context_pop_up_menu.dart';

class GameCard extends ConsumerWidget {
  const GameCard({
    required this.matchComparison,
    required this.onPinToggle,
    required this.pinnedIds,
    required this.onTap,
    super.key,
  });

  final MatchWithComparison matchComparison;
  final void Function(GamesTourModel game) onPinToggle;
  final List<String> pinnedIds;
  final Function() onTap;

  bool get isPinned => pinnedIds.contains(matchComparison.game.gameId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: onTap,
      onLongPressStart: (details) {
        HapticFeedback.lightImpact();
        _showBlurredPopup(context, details: details);
      },
      child: SizedBox(
        width: double.infinity,
        child: Stack(
          children: [
            _GameCardContent(matchComparison: matchComparison),
            if (isPinned) PinIconOverlay(right: 8.sp, top: 2.sp),
          ],
        ),
      ),
    );
  }

  void _showBlurredPopup(
    BuildContext context, {
    required LongPressStartDetails details,
  }) {
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
            onTap: () => Navigator.of(buildContext).pop(),
            child: Stack(
              children: [
                SelectiveBlurBackground(
                  clearPosition: cardPosition,
                  clearSize: cardSize,
                ),
                Positioned(
                  left: cardPosition.dx,
                  top: cardPosition.dy,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(buildContext),
                    child: SizedBox(
                      width: cardSize.width,
                      height: cardSize.height,
                      child: Stack(
                        children: [
                          _GameCardContent(matchComparison: matchComparison),
                          if (isPinned) PinIconOverlay(right: 8.sp, top: 4.sp),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: details.globalPosition.dx - 60.w,
                  top: menuTop,
                  child: ContextPopupMenu(
                    isPinned: isPinned,
                    onPinToggle: () {
                      onPinToggle(matchComparison.game);
                      Future.microtask(() {
                        Navigator.pop(buildContext);
                      });
                    },
                    onShare: () {
                      Navigator.pop(buildContext);
                    },
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

class _GameCardContent extends ConsumerWidget {
  const _GameCardContent({required this.matchComparison});

  final MatchWithComparison matchComparison;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _TopSection(matchComparison: matchComparison),
        _BottomSection(matchComparison: matchComparison),
      ],
    );
  }
}

class _TopSection extends ConsumerWidget {
  const _TopSection({required this.matchComparison});

  final MatchWithComparison matchComparison;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player1 =
        matchComparison.comparison == MatchComparison.sameOrder
            ? matchComparison.game.whitePlayer
            : matchComparison.game.blackPlayer;

    final player2 =
        matchComparison.comparison == MatchComparison.sameOrder
            ? matchComparison.game.blackPlayer
            : matchComparison.game.whitePlayer;
    return Container(
      height: 60.h,
      padding: EdgeInsets.only(left: 12.sp, right: 12.sp),
      decoration: BoxDecoration(
        color: kWhiteColor70,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(12.br),
          topRight: Radius.circular(12.br),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _GamesRound(
              playerName: player1.name,
              playerRank: '${player1.title} ${player1.rating}',
              countryCode: player1.countryCode,
            ),
          ),
          Expanded(child: _CenterContent(matchWithComparison: matchComparison)),
          Expanded(
            child: _GamesRound(
              playerName: player2.name,
              playerRank: '${player2.title} ${player2.rating}',
              countryCode: player2.countryCode,
            ),
          ),
        ],
      ),
    );
  }
}

class _CenterContent extends StatelessWidget {
  const _CenterContent({required this.matchWithComparison});

  final MatchWithComparison matchWithComparison;

  @override
  Widget build(BuildContext context) {
    // Use effectiveGameStatus to handle DB update lag
    final effectiveStatus = matchWithComparison.game.effectiveGameStatus;

    return Center(
      child:
          effectiveStatus == GameStatus.ongoing
              ? matchWithComparison.comparison == MatchComparison.sameOrder
                  ? ChessProgressBar(gamesTourModel: matchWithComparison.game)
                  : ChessProgressBar.reversedMode(
                    gamesTourModel: matchWithComparison.game,
                  )
              : StatusText(status: _displayTextSupporter(matchWithComparison)),
    );
  }
}

class _BottomSection extends ConsumerWidget {
  const _BottomSection({required this.matchComparison});

  final MatchWithComparison matchComparison;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
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
        children:
            matchComparison.comparison == MatchComparison.sameOrder
                ? [
                  _TimerWidget(
                    turn: matchComparison.game.activePlayer == Side.white,
                    time: matchComparison.game.whiteTimeDisplay,
                    gamesTourModel: matchComparison.game,
                    isWhitePlayer: true,
                  ),
                  Spacer(),
                  _TimerWidget(
                    turn: matchComparison.game.activePlayer == Side.black,
                    time: matchComparison.game.blackTimeDisplay,
                    gamesTourModel: matchComparison.game,
                    isWhitePlayer: false,
                  ),
                ]
                : [
                  _TimerWidget(
                    turn: matchComparison.game.activePlayer == Side.black,
                    time: matchComparison.game.blackTimeDisplay,
                    gamesTourModel: matchComparison.game,
                    isWhitePlayer: false,
                  ),

                  Spacer(),

                  _TimerWidget(
                    turn: matchComparison.game.activePlayer == Side.white,
                    time: matchComparison.game.whiteTimeDisplay,
                    gamesTourModel: matchComparison.game,
                    isWhitePlayer: true,
                  ),
                ],
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
          ref.read(stringUtilsProvider).getTrimmedString(playerName),
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
            Flexible(
              child: Text(
                playerRank,
                style: AppTypography.textXsMedium.copyWith(color: kBlack2Color),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class StatusText extends StatelessWidget {
  const StatusText({required this.status, this.color = kBlackColor, super.key});

  final String status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      status,
      textAlign: TextAlign.center,
      style: AppTypography.textXsMedium.copyWith(color: color),
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
    // Use effectiveGameStatus to detect if game is actually finished
    final effectiveStatus = gamesTourModel.effectiveGameStatus;
    final isGameFinished = effectiveStatus.isFinished;

    final isClockRunning =
        !isGameFinished &&
        gamesTourModel.gameStatus.isOngoing &&
        gamesTourModel.lastMoveTime != null &&
        gamesTourModel.activePlayer != null &&
        ((isWhitePlayer && gamesTourModel.activePlayer == Side.white) ||
            (!isWhitePlayer && gamesTourModel.activePlayer == Side.black));

    final clockCentiseconds =
        isWhitePlayer
            ? gamesTourModel.whiteClockCentiseconds
            : gamesTourModel.blackClockCentiseconds;

    final clockSeconds =
        isWhitePlayer
            ? gamesTourModel.whiteClockSeconds
            : gamesTourModel.blackClockSeconds;

    return AtomicCountdownText(
      clockSeconds:
          clockSeconds, // Primary source: time in seconds from last_clock fields
      clockCentiseconds:
          clockCentiseconds, // Fallback source: raw database clock
      lastMoveTime: gamesTourModel.lastMoveTime,
      isActive: isClockRunning, // Clock frozen if game is effectively finished
      style: AppTypography.textXsMedium.copyWith(
        color:
            isGameFinished
                ? kWhiteColor
                : (turn ? kPrimaryColor : kWhiteColor),
      ),
    );
  }
}

String _displayTextSupporter(MatchWithComparison game) {
  // Use effectiveGameStatus to show correct result even if DB hasn't updated
  final effectiveStatus = game.game.effectiveGameStatus;

  if (game.comparison == MatchComparison.sameOrder) {
    switch (effectiveStatus) {
      case GameStatus.whiteWins:
        return '1-0';
      case GameStatus.blackWins:
        return '0-1';
      case GameStatus.draw:
        return '½-½';
      case GameStatus.ongoing:
        return '*';
      case GameStatus.unknown:
        return '';
    }
  } else {
    switch (effectiveStatus) {
      case GameStatus.whiteWins:
        return '0-1';
      case GameStatus.blackWins:
        return '1-0';
      case GameStatus.draw:
        return '½-½';
      case GameStatus.ongoing:
        return '*';
      case GameStatus.unknown:
        return '';
    }
  }
}
