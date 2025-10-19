import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/score_card_screen.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/location_service_provider.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/atomic_countdown_text.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_svg/svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/utils/svg_asset.dart';

enum PlayerView { listView, gridView, boardView }

class PlayerFirstRowDetailWidget extends HookConsumerWidget {
  final bool isCurrentPlayer;
  final PlayerView playerView;
  final GamesTourModel gamesTourModel;
  final bool isWhitePlayer;
  final ChessBoardStateNew? chessBoardState;
  final bool isPinned;

  const PlayerFirstRowDetailWidget({
    super.key,
    required this.playerView,
    required this.isWhitePlayer,
    required this.gamesTourModel,
    this.isCurrentPlayer = false,
    this.chessBoardState,
    this.isPinned = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerCard = useMemoized(() {
      return isWhitePlayer
          ? gamesTourModel.whitePlayer
          : gamesTourModel.blackPlayer;
    }, [gamesTourModel, isWhitePlayer]);
    final validCountryCode = ref
        .read(locationServiceProvider)
        .getValidCountryCode(playerCard.countryCode);

    // Calculate move time from state if available, otherwise use game model's time
    final moveTime = useMemoized(() {
      String? calculatedMoveTime;

      // In analysis mode, use the analysis state's current move index to show clock time
      // Otherwise use the main state's current move index
      final effectiveMoveIndex =
          chessBoardState?.isAnalysisMode == true
              ? chessBoardState!.analysisState.currentMoveIndex
              : chessBoardState?.currentMoveIndex ?? -1;

      // For past moves or when in analysis mode: Show the clock time at the current position
      if (chessBoardState != null && !chessBoardState!.isAtEnd) {
        if (chessBoardState!.moveTimes.isNotEmpty) {
          // Find this player's most recent move up to current position
          for (int i = effectiveMoveIndex; i >= 0; i--) {
            final wasMoveByThisPlayer =
                (i % 2 == 0 && isWhitePlayer) || (i % 2 == 1 && !isWhitePlayer);

            if (wasMoveByThisPlayer && i < chessBoardState!.moveTimes.length) {
              calculatedMoveTime = chessBoardState!.moveTimes[i];
              break;
            }
          }
        }
      }
      // For latest move in normal mode: use live data (handled by clockSeconds)
      else if (chessBoardState != null &&
          chessBoardState!.moveTimes.isNotEmpty &&
          effectiveMoveIndex >= 0) {
        // Look for this player's most recent move
        for (int i = effectiveMoveIndex; i >= 0; i--) {
          final wasMoveByThisPlayer =
              (i % 2 == 0 && isWhitePlayer) || (i % 2 == 1 && !isWhitePlayer);

          if (wasMoveByThisPlayer && i < chessBoardState!.moveTimes.length) {
            calculatedMoveTime = chessBoardState!.moveTimes[i];
            break;
          }
        }
      }

      // Fallback to game model's time display (which comes from database or PGN)
      calculatedMoveTime ??=
          isWhitePlayer
              ? gamesTourModel.whiteTimeDisplay
              : gamesTourModel.blackTimeDisplay;

      return calculatedMoveTime;
    }, [chessBoardState, isWhitePlayer, gamesTourModel]);

    final rankStyle =
        playerView == PlayerView.listView
            ? TextStyle(
              fontSize: 8.5.f,
              fontWeight: FontWeight.w600,
              color: kLightYellowColor,
              height: 1.2,
            )
            : playerView == PlayerView.gridView
            ? AppTypography.textXsMedium.copyWith(
              color: kLightYellowColor,
              fontWeight: FontWeight.w400,
              fontSize: 4.f,
              height: 1.2,
            )
            : AppTypography.textXsMedium.copyWith(
              color: kLightYellowColor,
              fontWeight: FontWeight.w600,
              fontSize: 14.f,
              height: 1.2,
            );

    final nameStyle =
        playerView == PlayerView.listView
            ? TextStyle(
              fontSize: 8.5.f,
              fontWeight: FontWeight.w500,
              color: kWhiteColor,
              height: 1.2,
            )
            : playerView == PlayerView.gridView
            ? AppTypography.textXsMedium.copyWith(
              color: kWhiteColor,
              fontWeight: FontWeight.w400,
              fontSize: 4.f,
              height: 1.2,
            )
            : AppTypography.textXsMedium.copyWith(
              color: kWhiteColor,
              fontWeight: FontWeight.w600,
              fontSize: 14.f,
              height: 1.2,
            );

    final ratingStyle =
        playerView == PlayerView.listView
            ? TextStyle(
              fontSize: 8.5.f,
              fontWeight: FontWeight.w500, // Match name font weight
              color: kWhiteColor70,
              height: 1.2,
            )
            : playerView == PlayerView.gridView
            ? AppTypography.textXsMedium.copyWith(
              color: kWhiteColor70,
              fontWeight: FontWeight.w400,
              fontSize: 4.f,
              height: 1.2,
            )
            : AppTypography.textXsMedium.copyWith(
              color: kWhiteColor70,
              fontWeight: FontWeight.w600, // Match name font weight
              fontSize: 14.f,
              height: 1.2,
            );

    final flagHeight =
        playerView == PlayerView.listView
            ? 10.h
            : playerView == PlayerView.gridView
            ? 8.h
            : 12.h;
    final flagWidth =
        playerView == PlayerView.listView
            ? 12.w
            : playerView == PlayerView.gridView
            ? 10.w
            : 16.w;

    // Determine if we're showing scores (finished game)
    final isGameFinished = gamesTourModel.gameStatus.isFinished;

    final timeStyle =
        playerView == PlayerView.listView
            ? TextStyle(
              color: isCurrentPlayer ? kWhiteColor70 : kWhiteColor,
              fontSize: 8.5.f,
              fontWeight: FontWeight.w500,
            )
            : playerView == PlayerView.gridView
            ? AppTypography.textXsMedium.copyWith(
              color: isCurrentPlayer ? kWhiteColor70 : kWhiteColor,
              fontSize: 4.f,
              fontWeight: FontWeight.w500,
            )
            : AppTypography.textXsMedium.copyWith(
              color: isCurrentPlayer ? kWhiteColor70 : kWhiteColor,
              fontSize: 14.f,
              fontWeight: FontWeight.w500,
            );

    final scoreStyle =
        playerView == PlayerView.listView
            ? TextStyle(
              color: kWhiteColor,
              fontSize: 8.5.f,
              fontWeight: FontWeight.w600,
              height: 1.2,
            )
            : playerView == PlayerView.gridView
            ? AppTypography.textXsMedium.copyWith(
              color: kWhiteColor,
              fontSize: 4.f,
              fontWeight: FontWeight.w600,
              height: 1.2,
            )
            : AppTypography.textXsMedium.copyWith(
              color: kWhiteColor,
              fontSize: 14.f,
              fontWeight: FontWeight.w600,
              height: 1.2,
            );

    final spacing = playerView == PlayerView.gridView ? 4.w : 8.w;
    final endPadding = playerView == PlayerView.gridView ? 8.w : 16.w; // Align with board edge

    // Board has 16.sp horizontal margin, engine gauge is 20.w wide
    // So flags should start at 16.sp + 20.w to align with board's left edge
    final boardMargin = 16.sp;
    final engineGaugeWidth = 20.w;

    return GestureDetector(
      onTap: () {
        final standingsAsync = ref.read(playerTourScreenProvider);

        standingsAsync.whenData((standings) {
          final playerStanding = standings.firstWhere(
            (player) => player.name == playerCard.name,
            orElse:
                () => PlayerStandingModel(
                  countryCode: playerCard.countryCode,
                  title: playerCard.title.isNotEmpty ? playerCard.title : null,
                  name: playerCard.name,
                  score: 0,
                  // Fallback if not found in standings
                  scoreChange: 0,
                  matchScore: null,
                ),
          );

          ref.read(selectedPlayerProvider.notifier).state = playerStanding;

          Navigator.pushNamed(context, '/scorecard_screen');
        });
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: boardMargin),
          // Show score on the very left for finished games (aligned with engine gauge)
          if (isGameFinished) ...[
            SizedBox(
              width: engineGaugeWidth,
              child: Text(
                gamesTourModel.gameStatus == GameStatus.whiteWins
                    ? (isWhitePlayer ? '1' : '0')
                    : gamesTourModel.gameStatus == GameStatus.blackWins
                    ? (isWhitePlayer ? '0' : '1')
                    : '½',
                style: scoreStyle,
                textAlign: TextAlign.center,
              ),
            ),
          ] else
            SizedBox(width: engineGaugeWidth),
          if (playerCard.countryCode.toUpperCase() == 'FID') ...[
            Image.asset(
              PngAsset.fideLogo,
              height: flagHeight,
              width: flagWidth,
              fit: BoxFit.cover,
              cacheWidth: 48,
              cacheHeight: 36,
            ),
            SizedBox(width: spacing),
          ] else if (validCountryCode.isNotEmpty) ...[
            CountryFlag.fromCountryCode(
              validCountryCode,
              height: flagHeight,
              width: flagWidth,
            ),
            SizedBox(width: spacing),
          ] else
            SizedBox(width: spacing),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Parse name parts - format is "Surname, Given Names"
                final fullName = playerCard.name;
                final nameParts = fullName.split(',').map((e) => e.trim()).toList();
                final surname = nameParts.isNotEmpty ? nameParts[0] : ''; // Part before comma
                final firstName = nameParts.length > 1 ? nameParts[1] : ''; // Part after comma

                // Build static parts that must always be visible
                final title = playerCard.title.isNotEmpty ? '${playerCard.title} ' : '';
                final firstNameWithComma = firstName.isNotEmpty ? ', $firstName' : '';
                final rating = ' ${playerCard.rating}';

                // Create text painter to measure text width
                final textPainter = TextPainter(
                  textDirection: TextDirection.ltr,
                  maxLines: 1,
                );

                // Measure static parts (title + firstName + rating)
                textPainter.text = TextSpan(
                  children: [
                    TextSpan(text: title, style: rankStyle),
                    TextSpan(text: firstNameWithComma, style: nameStyle),
                    TextSpan(text: rating, style: ratingStyle),
                  ],
                );
                textPainter.layout();
                final staticWidth = textPainter.width;

                // Calculate available space for surname
                final availableForSurname = constraints.maxWidth - staticWidth;

                // Try to fit full surname
                String displaySurname = surname;
                if (surname.isNotEmpty) {
                  textPainter.text = TextSpan(text: surname, style: nameStyle);
                  textPainter.layout();

                  if (textPainter.width > availableForSurname) {
                    // Surname doesn't fit, use initials
                    final surnameParts = surname.split(' ');
                    displaySurname = surnameParts
                        .where((part) => part.isNotEmpty)
                        .map((part) => '${part[0]}.')
                        .join(' ');
                  }
                }

                return RichText(
                  overflow: TextOverflow.visible,
                  maxLines: 1,
                  textAlign: TextAlign.left,
                  text: TextSpan(
                    children: [
                      if (title.isNotEmpty)
                        TextSpan(text: title, style: rankStyle),
                      if (displaySurname.isNotEmpty)
                        TextSpan(text: displaySurname, style: nameStyle),
                      if (firstNameWithComma.isNotEmpty)
                        TextSpan(text: firstNameWithComma, style: nameStyle),
                      TextSpan(text: rating, style: ratingStyle),
                    ],
                  ),
                );
              },
            ),
          ),
          if (isPinned) ...[
            SvgPicture.asset(
              SvgAsset.pin,
              color: kpinColor,
              height: 12.h,
              width: 12.w,
            ),
            SizedBox(width: 4.w),
          ],
          // Always show clock/time on the right
          Container(
            padding: EdgeInsets.symmetric(horizontal: 4.sp),
            decoration: BoxDecoration(
              color: isCurrentPlayer ? kDarkBlue : Colors.transparent,
            ),
            child: _PlayerClock(
              isWhitePlayer: isWhitePlayer,
              gamesTourModel: gamesTourModel,
              chessBoardState: chessBoardState,
              isCurrentPlayer: isCurrentPlayer,
              timeStyle: timeStyle,
              moveTime: moveTime,
            ),
          ),
          SizedBox(width: endPadding),
        ],
      ),
    );
  }
}

class _PlayerClock extends StatelessWidget {
  const _PlayerClock({
    required this.isWhitePlayer,
    required this.gamesTourModel,
    required this.chessBoardState,
    required this.isCurrentPlayer,
    required this.timeStyle,
    required this.moveTime,
  });

  final bool isWhitePlayer;
  final GamesTourModel gamesTourModel;
  final ChessBoardStateNew? chessBoardState;
  final bool isCurrentPlayer;
  final TextStyle timeStyle;
  final String? moveTime;

  @override
  Widget build(BuildContext context) {
    final bool isAtLatestPosition = () {
      final state = chessBoardState;
      if (state == null) return true;

      if (state.isAnalysisMode) {
        // In analysis mode rely on analysis state's pointer to know if we're at the live position.
        return state.analysisState.isAtEnd &&
            !(state.analysisState.isInAnalysisVariation);
      }

      return state.isAtEnd;
    }();

    // Determine if this player's clock should be counting down
    // Only countdown for live games when at the latest move and it's this player's turn
    // NEVER countdown when exploring analysis variations - always show static clock time
    final isClockRunning =
        gamesTourModel.gameStatus.isOngoing &&
        gamesTourModel.lastMoveTime != null &&
        isCurrentPlayer && // Use the isCurrentPlayer prop from parent which uses state.position.turn
        isAtLatestPosition && // Only countdown when at latest move
        !(chessBoardState?.analysisState.isInAnalysisVariation ??
            false); // Never countdown when exploring analysis variations

    // Use atomic countdown text widget for optimized rebuilds
    // Get the clock values for this player
    // BUSINESS LOGIC:
    // - last_clock_white/black are snapshots when that player's clock STOPPED (when they made their move)
    // - last_move_time is when the previous move was completed (previous player's clock stopped)
    // - If it's this player's turn NOW, count down from their saved clock since last_move_time
    // - If it's NOT this player's turn, show their static saved clock value

    final clockCentiseconds =
        isWhitePlayer
            ? gamesTourModel.whiteClockCentiseconds
            : gamesTourModel.blackClockCentiseconds;

    return AtomicCountdownText(
      // CRITICAL FIX: Add key to force widget rebuild when lastMoveTime changes
      // This ensures the dateTimeProvider selector captures the NEW lastMoveTime
      key: ValueKey(gamesTourModel.lastMoveTime?.millisecondsSinceEpoch ?? 0),
      moveTime:
          moveTime, // Primary for past moves: PGN-parsed move times (more accurate for historical display)
      clockSeconds:
          // For live games at latest move: use database fields for accurate countdown math
          // For past moves: null (rely on PGN moveTime)
          (chessBoardState?.isAtEnd ?? true) && isClockRunning
              ? (isWhitePlayer
                  ? gamesTourModel.whiteClockSeconds
                  : gamesTourModel.blackClockSeconds)
              : null,
      clockCentiseconds:
          clockCentiseconds, // Fallback source: raw database clock
      lastMoveTime:
          gamesTourModel.lastMoveTime, // Critical for live countdown timing
      isActive: isClockRunning,
      style: timeStyle,
    );
  }
}
