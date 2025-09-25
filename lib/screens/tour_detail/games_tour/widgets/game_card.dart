import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/chess_progress_bar.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/location_service_provider.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/atomic_countdown_text.dart';
import 'package:country_flags/country_flags.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/screens/chessboard/widgets/context_pop_up_menu.dart';

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
            _GameCardContent(gamesTourModel: gamesTourModel),
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
            onTap: () => Navigator.of(context).pop(),
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
                    onTap: () {},
                    child: SizedBox(
                      width: cardSize.width,
                      height: cardSize.height,
                      child: Stack(
                        children: [
                          _GameCardContent(gamesTourModel: gamesTourModel),
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
                      Navigator.pop(context);
                      onPinToggle(gamesTourModel);
                    },
                    onShare: () {
                      Navigator.pop(context);
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
  const _GameCardContent({required this.gamesTourModel});

  final GamesTourModel gamesTourModel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _TopSection(gamesTourModel: gamesTourModel),
        _BottomSection(gamesTourModel: gamesTourModel),
      ],
    );
  }
}

class _TopSection extends ConsumerWidget {
  const _TopSection({required this.gamesTourModel});

  final GamesTourModel gamesTourModel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              playerName: gamesTourModel.whitePlayer.name,
              playerRank:
                  '${gamesTourModel.whitePlayer.title} ${gamesTourModel.whitePlayer.rating}',
              countryCode: gamesTourModel.whitePlayer.countryCode,
            ),
          ),
          Expanded(child: _CenterContent(gamesTourModel: gamesTourModel)),
          Expanded(
            child: _GamesRound(
              playerName: gamesTourModel.blackPlayer.name,
              playerRank:
                  '${gamesTourModel.blackPlayer.title} ${gamesTourModel.blackPlayer.rating}',
              countryCode: gamesTourModel.blackPlayer.countryCode,
            ),
          ),
        ],
      ),
    );
  }
}

class _CenterContent extends StatelessWidget {
  const _CenterContent({required this.gamesTourModel});

  final GamesTourModel gamesTourModel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child:
          gamesTourModel.gameStatus == GameStatus.ongoing
              ? ChessProgressBar(gamesTourModel: gamesTourModel)
              : _StatusText(status: gamesTourModel.gameStatus.displayText),
    );
  }
}

class _BottomSection extends ConsumerWidget {
  const _BottomSection({required this.gamesTourModel});

  final GamesTourModel gamesTourModel;

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
    final isClockRunning =
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
      isActive: isClockRunning,
      style: AppTypography.textXsMedium.copyWith(
        color:
            gamesTourModel.gameStatus.isFinished
                ? kWhiteColor
                : (turn ? kPrimaryColor : kWhiteColor),
      ),
    );
  }
}
