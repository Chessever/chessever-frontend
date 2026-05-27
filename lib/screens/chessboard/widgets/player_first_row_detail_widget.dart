import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/group_event/providers/countryman_games_tour_screen_provider.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/score_card_screen.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
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
  final bool showClock;

  const PlayerFirstRowDetailWidget({
    super.key,
    required this.playerView,
    required this.isWhitePlayer,
    required this.gamesTourModel,
    this.isCurrentPlayer = false,
    this.chessBoardState,
    this.isPinned = false,
    this.showClock = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final noSpoilersEnabled = ref.watch(
      eventNoSpoilersProvider(gamesTourModel.tourId).select(
        (state) => state.enabled,
      ),
    );
    final spoilersRevealedForGame = ref.watch(
      eventNoSpoilersRevealedGamesProvider.select(
        (gameIds) => gameIds.contains(gamesTourModel.gameId),
      ),
    );
    final revealSpoilers =
        !noSpoilersEnabled ||
        !gamesTourModel.gameStatus.isFinished ||
        spoilersRevealedForGame;

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

    // Harmonized text styles for consistent visual hierarchy
    final rankStyle =
        playerView == PlayerView.listView
            ? TextStyle(
              fontSize: 8.5.f,
              fontWeight: FontWeight.w600,
              color: kLightYellowColor,
              height: 1.15,
              letterSpacing: 0,
            )
            : playerView == PlayerView.gridView
            ? TextStyle(
              fontSize: 8.f,
              fontWeight: FontWeight.w600,
              color: kLightYellowColor,
              height: 1.15,
              letterSpacing: -0.15,
            )
            : AppTypography.textXsMedium.copyWith(
              color: kLightYellowColor,
              fontWeight: FontWeight.w700,
              fontSize: 14.f,
              height: 1.2,
            );

    final nameStyle =
        playerView == PlayerView.listView
            ? TextStyle(
              fontSize: 8.5.f,
              fontWeight: FontWeight.w500,
              color: kWhiteColor,
              height: 1.15,
              letterSpacing: 0,
            )
            : playerView == PlayerView.gridView
            ? TextStyle(
              fontSize: 8.f,
              fontWeight: FontWeight.w600,
              color: kWhiteColor,
              height: 1.15,
              letterSpacing: -0.15,
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
              fontWeight: FontWeight.w500,
              color: kWhiteColor70,
              height: 1.15,
              letterSpacing: 0,
            )
            : playerView == PlayerView.gridView
            ? TextStyle(
              fontSize: 7.5.f,
              fontWeight: FontWeight.w500,
              color: kWhiteColor70,
              height: 1.15,
              letterSpacing: -0.15,
            )
            : AppTypography.textXsMedium.copyWith(
              color: kWhiteColor70,
              fontWeight: FontWeight.w600,
              fontSize: 14.f,
              height: 1.2,
            );

    // Proportional flag sizing for visual consistency
    final flagHeight =
        playerView == PlayerView.listView
            ? 10.h
            : playerView == PlayerView.gridView
            ? 12.h
            : 12.h;
    final flagWidth =
        playerView == PlayerView.listView
            ? 12.w
            : playerView == PlayerView.gridView
            ? 16.w
            : 16.w;

    final timeStyle =
        playerView == PlayerView.listView
            ? TextStyle(
              fontSize: 8.5.f,
              fontWeight: FontWeight.w500,
              color: isCurrentPlayer ? kWhiteColor70 : kWhiteColor,
              height: 1.15,
              letterSpacing: 0,
              fontFeatures: const [FontFeature.tabularFigures()],
            )
            : playerView == PlayerView.gridView
            ? TextStyle(
              fontSize: 8.f,
              fontWeight: FontWeight.w600,
              color: isCurrentPlayer ? kWhiteColor70 : kWhiteColor,
              height: 1.15,
              letterSpacing: -0.2,
              fontFeatures: const [FontFeature.tabularFigures()],
            )
            : AppTypography.textXsMedium.copyWith(
              color: isCurrentPlayer ? kWhiteColor70 : kWhiteColor,
              fontSize: 14.f,
              fontWeight: FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            );

    // CRITICAL: Pixel-perfect alignment with board edges
    // Structure: [Container Padding] [EvalBar] [Flag at board LEFT edge] [Name] [Clock at board RIGHT edge] [Container Padding]
    //
    // ListView: Container ALREADY has 24.sp padding, so NO additional margin needed!
    // GridView: No container padding, so we handle margins here
    // BoardView: Container has 16.sp margin, so we add 16.sp here to match

    // Element spacing - between flag and name
    final elementSpacing = playerView == PlayerView.gridView ? 4.w : 8.w;

    // Left/Right margins:
    // ListView: 0 (container already has 24.sp padding via ChessBoardFromFENNew)
    // GridView: 0 (no container padding)
    // BoardView: 16.sp (matches container margin in chess_board_screen_new)
    final boardMargin =
        playerView == PlayerView.listView ? 0.sp :  // NO margin - container has padding!
        playerView == PlayerView.gridView ? 0.sp :
        16.sp; // BoardView needs margin

    final endPadding = boardMargin; // Right margin matches left margin

    final engineGaugeWidth = useMemoized(() {
      // Check if engine gauge is enabled in settings
      final settings = ref.watch(engineSettingsProviderNew).valueOrNull;
      final showEvalBarInSettings =
          (settings?.showEngineAnalysis ?? true) &&
          (settings?.showEngineGauge ?? true);

      // We only show the gauge area if:
      // 1. The finished-game result is allowed to be shown
      // 2. The game is ongoing AND started AND gauge is enabled in settings
      final isFinished = gamesTourModel.gameStatus.isFinished && revealSpoilers;
      final effectivelyShowingEvalBar =
          showEvalBarInSettings &&
          gamesTourModel.hasStarted &&
          gamesTourModel.gameStatus.isOngoing;

      if (isFinished || effectivelyShowingEvalBar) {
        return playerView == PlayerView.gridView ? 10.w : 20.w;
      }
      return 0.0;
    }, [ref.watch(engineSettingsProviderNew), gamesTourModel, playerView, revealSpoilers]);

    // Clock padding - add small horizontal padding to prevent flickering and provide stability
    final clockPadding = playerView == PlayerView.gridView ? 4.w : 6.w;

    return GestureDetector(
      onTap: () {
        final standingsAsync = ref.read(playerTourScreenProvider);

        // Create fallback player model from game data - always has fideId if available
        final fallbackPlayer = PlayerStandingModel(
          countryCode: playerCard.countryCode,
          title: playerCard.title.isNotEmpty ? playerCard.title : null,
          name: playerCard.name,
          score: playerCard.rating,
          scoreChange: 0,
          matchScore: null,
          fideId: playerCard.fideId,
        );

        // Try to find player in tournament standings, otherwise use fallback
        var playerStanding = standingsAsync.whenOrNull(
          data: (standings) => standings.firstWhere(
            (player) => player.name == playerCard.name,
            orElse: () => fallbackPlayer,
          ),
        ) ?? fallbackPlayer;

        // IMPORTANT: If standings player has null fideId but game data has it,
        // use the fideId from game data (playerCard) - this is more reliable
        // since games.players always has fideId from broadcast while tours.players
        // may sometimes be missing it
        if (playerStanding.fideId == null && playerCard.fideId != null) {
          playerStanding = playerStanding.copyWith(fideId: playerCard.fideId);
        }

        ref.read(selectedPlayerProvider.notifier).state = playerStanding;

        // Get the current games context based on the chessboard view source
        // This ensures ScoreCardScreen displays games from the correct source
        final view = ref.read(chessboardViewFromProviderNew);
        List<GamesTourModel>? gamesContext;
        bool hasEventContext = false;

        switch (view) {
          case ChessboardView.favScorecard:
          case ChessboardView.playerProfile:
            // For favorites/player profile, show ALL player games (no event context)
            // Clear tournament context to avoid ScoreCardScreen using stale tournament data
            ref.read(selectedBroadcastModelProvider.notifier).state = null;
            gamesContext = null; // Let ScoreCardScreen fetch via playerGamesProvider
            hasEventContext = false;
            break;
          case ChessboardView.tour:
            // For tournament view, selectedBroadcastModelProvider will be set
            // ScoreCardScreen will use gamesTourScreenProvider directly
            gamesContext = null;
            hasEventContext = true; // Tournament context
            break;
          case ChessboardView.countryman:
            // For countrymen view, filter games by the current game's tournament
            // This ensures ScoreCardScreen shows only games from that specific event
            ref.read(selectedBroadcastModelProvider.notifier).state = null;
            final allCountrymanGames = ref.read(countrymanGamesTourScreenProvider).valueOrNull?.gamesTourModels ?? [];
            final currentTourIdCountryman = gamesTourModel.tourId;
            if (currentTourIdCountryman.isNotEmpty) {
              gamesContext = allCountrymanGames
                  .where((g) => g.tourId == currentTourIdCountryman)
                  .toList();
              hasEventContext = true; // Filtered to specific event
            } else {
              gamesContext = allCountrymanGames;
              hasEventContext = false; // No specific event
            }
            break;
          case ChessboardView.forYou:
            // For "For You" view, use current game's tourId so ScoreCardScreen
            // can fetch all event games. Don't rely on convertedForYouGamesProvider
            // since it may not contain the current game (ChessBoardScreenNew receives
            // resolved full event games from gameCardWrapperProvider).
            ref.read(selectedBroadcastModelProvider.notifier).state = null;
            if (gamesTourModel.tourId.isNotEmpty) {
              // Pass current game - ScoreCardScreen will fetch all event games via tourId
              gamesContext = [gamesTourModel];
              hasEventContext = true;
            } else {
              // No tourId - can't determine event context
              gamesContext = null;
              hasEventContext = false;
            }
            break;
        }

        // Fallback: ensure event context is set when we have a valid tourId
        // This handles cases where:
        // - view might not match expected case
        // - gamesContext filter returned empty (e.g., For You only has few games from event)
        if ((gamesContext == null || gamesContext.isEmpty) && gamesTourModel.tourId.isNotEmpty) {
          gamesContext = [gamesTourModel];
          hasEventContext = true;
        }

        // Set the games context and event context flag for ScoreCardScreen
        ref.read(scoreCardGamesContextProvider.notifier).state = gamesContext;
        ref.read(scoreCardHasEventContextProvider.notifier).state = hasEventContext;

        Navigator.pushNamed(context, '/scorecard_screen');
      },
      child: SizedBox(
        height: playerView == PlayerView.gridView ? 20.h : null,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
          SizedBox(width: boardMargin),
          // Game result score - centered in eval bar width
          SizedBox(
            width: engineGaugeWidth,
            child: gamesTourModel.gameStatus.isFinished && revealSpoilers
                ? Center(
                    child: Text(
                      gamesTourModel.gameStatus == GameStatus.whiteWins
                          ? (isWhitePlayer ? '1' : '0')
                          : gamesTourModel.gameStatus == GameStatus.blackWins
                          ? (isWhitePlayer ? '0' : '1')
                          : '½',
                      style: TextStyle(
                        fontSize: playerView == PlayerView.gridView ? 9.f : 10.f,
                        fontWeight: FontWeight.w700,
                        color: kWhiteColor,
                        height: 1.0,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : null,
          ),
          if (playerCard.countryCode.toUpperCase() == 'FID') ...[
            Image.asset(
              PngAsset.fideLogo,
              height: flagHeight,
              width: flagWidth,
              fit: BoxFit.cover,
              cacheWidth: 48,
              cacheHeight: 36,
            ),
            SizedBox(width: elementSpacing),
          ] else if (validCountryCode.isNotEmpty) ...[
            CountryFlag.fromCountryCode(
              validCountryCode,
              height: flagHeight,
              width: flagWidth,
            ),
            SizedBox(width: elementSpacing),
          ] else
            SizedBox(width: elementSpacing),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Parse name parts - format is "Surname, Given Names"
                final fullName = playerCard.name;
                final nameParts =
                    fullName.split(',').map((e) => e.trim()).toList();
                final surname =
                    nameParts.isNotEmpty
                        ? nameParts[0]
                        : ''; // Part before comma
                final firstName =
                    nameParts.length > 1
                        ? nameParts[1]
                        : ''; // Part after comma

                // Build static parts
                final rating = ' ${playerCard.rating}';

                // DEBUG: Log title value
                if (playerView == PlayerView.boardView) {
                  debugPrint('[PlayerTitle] ${playerCard.name}: title="${playerCard.title}", isEmpty=${playerCard.title.isEmpty}');
                }

                // Create text painter to measure text width
                final textPainter = TextPainter(
                  textDirection: TextDirection.ltr,
                  maxLines: 1,
                );

                // Smart truncation: ALWAYS prioritize showing full surname
                // Only abbreviate/truncate other parts, never reduce surname to initials
                String displaySurname = surname;
                String displayFirstName = firstName.isNotEmpty ? ', $firstName' : '';

                if (surname.isNotEmpty) {
                  // Strategy 1: Try full surname + full first name
                  textPainter.text = TextSpan(
                    children: [
                      TextSpan(text: '${playerCard.title} ', style: rankStyle),
                      TextSpan(text: surname, style: nameStyle),
                      if (firstName.isNotEmpty)
                        TextSpan(text: ', $firstName', style: nameStyle),
                      TextSpan(text: rating, style: ratingStyle),
                    ],
                  );
                  textPainter.layout();

                  // If doesn't fit, start trimming (but keep full surname!)
                  if (textPainter.width > constraints.maxWidth && firstName.isNotEmpty) {
                    // Strategy 2: Keep full surname + abbreviate first name
                    final firstNameParts = firstName.split(' ');
                    final abbreviatedFirst = firstNameParts
                        .where((part) => part.isNotEmpty)
                        .map((part) => '${part[0]}.')
                        .join(' ');
                    displayFirstName = ', $abbreviatedFirst';

                    textPainter.text = TextSpan(
                      children: [
                        TextSpan(text: '${playerCard.title} ', style: rankStyle),
                        TextSpan(text: surname, style: nameStyle),
                        TextSpan(text: displayFirstName, style: nameStyle),
                        TextSpan(text: rating, style: ratingStyle),
                      ],
                    );
                    textPainter.layout();

                    // Strategy 3: If still doesn't fit, drop first name entirely
                    if (textPainter.width > constraints.maxWidth) {
                      displayFirstName = '';

                      textPainter.text = TextSpan(
                        children: [
                          TextSpan(text: '${playerCard.title} ', style: rankStyle),
                          TextSpan(text: surname, style: nameStyle),
                          TextSpan(text: rating, style: ratingStyle),
                        ],
                      );
                      textPainter.layout();

                      // Strategy 4: If STILL doesn't fit, let ellipsis truncate surname
                      // This is the last resort - RichText will handle the truncation
                      // We keep displaySurname as the full surname, RichText will add "..."
                    }
                  }
                }

                return RichText(
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.left,
                  text: TextSpan(
                    style: nameStyle, // Add base style for inheritance
                    children: [
                      // Always render title (with trailing space) like old code
                      TextSpan(text: '${playerCard.title} ', style: rankStyle),
                      if (displaySurname.isNotEmpty)
                        TextSpan(text: displaySurname, style: nameStyle),
                      if (displayFirstName.isNotEmpty)
                        TextSpan(text: displayFirstName, style: nameStyle),
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
              colorFilter: ColorFilter.mode(kpinColor, BlendMode.srcIn),
              height: playerView == PlayerView.gridView ? 12.h : 12.h,
              width: playerView == PlayerView.gridView ? 12.w : 12.w,
            ),
            SizedBox(width: playerView == PlayerView.gridView ? 3.w : 4.w),
          ],
          // Always show clock/time on the right - simplified structure to prevent overflow
          if (showClock)
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: clockPadding,
                vertical: playerView == PlayerView.gridView ? 1.sp : 0,
              ),
              decoration: BoxDecoration(
                color: isCurrentPlayer ? kDarkBlue : Colors.transparent,
                borderRadius: playerView == PlayerView.gridView
                    ? BorderRadius.circular(2)
                    : null,
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
