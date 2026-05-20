import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/supabase/chess_player/chess_player_repository.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/group_event/providers/countryman_games_tour_screen_provider.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/score_card_screen.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/live_game_card_provider.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/chess_title_utils.dart';
import 'package:chessever2/utils/location_service_provider.dart';
import 'package:chessever2/utils/pgn_clock_utils.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/twic_player_enrichment.dart';
import 'package:chessever2/widgets/atomic_countdown_text.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:dartchess/dartchess.dart';
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
  final PlayerProfileDataSource playerProfileDataSource;
  final bool showClock;
  final LiveGamesBatchKey? liveBatchKey;
  final ValueChanged<String>? onEditName;

  const PlayerFirstRowDetailWidget({
    super.key,
    required this.playerView,
    required this.isWhitePlayer,
    required this.gamesTourModel,
    this.isCurrentPlayer = false,
    this.chessBoardState,
    this.isPinned = false,
    this.playerProfileDataSource = PlayerProfileDataSource.supabase,
    this.showClock = true,
    this.liveBatchKey,
    this.onEditName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baseGameModel = chessBoardState?.game ?? gamesTourModel;
    final scopedClockGame =
        showClock && baseGameModel.gameStatus.isOngoing
            ? watchLiveGameClock(ref, baseGameModel, batchKey: liveBatchKey)
            : null;
    final effectiveGameModel = scopedClockGame ?? baseGameModel;
    final playerCard = useMemoized(() {
      return isWhitePlayer
          ? effectiveGameModel.whitePlayer
          : effectiveGameModel.blackPlayer;
    }, [effectiveGameModel, isWhitePlayer]);
    final enrichedPlayerFuture = useMemoized(
      () async {
        final fideId = playerCard.fideId;
        final gamebasePlayerId = playerCard.gamebasePlayerId?.trim();
        final needsEnrichment =
            playerCard.title.trim().isEmpty ||
            playerCard.countryCode.trim().isEmpty ||
            fideId == null ||
            fideId <= 0;
        if (!needsEnrichment) {
          return playerCard;
        }

        var enrichedCard = playerCard;
        if (fideId != null && fideId > 0) {
          final supabasePlayer = await ref
              .read(chessPlayerRepositoryProvider)
              .getPlayerByFideId(fideId);
          if (supabasePlayer != null) {
            enrichedCard = enrichPlayerCardFromChessPlayers(enrichedCard, {
              fideId: supabasePlayer,
            });
          }
        }

        final stillMissingSurfaceData =
            enrichedCard.title.trim().isEmpty ||
            enrichedCard.countryCode.trim().isEmpty ||
            enrichedCard.fideId == null ||
            enrichedCard.fideId! <= 0;
        if (stillMissingSurfaceData &&
            gamebasePlayerId != null &&
            gamebasePlayerId.isNotEmpty) {
          final gamebasePlayer = await ref
              .read(gamebaseRepositoryProvider)
              .getPlayerById(gamebasePlayerId);
          if (gamebasePlayer != null) {
            final resolvedFideId = int.tryParse(gamebasePlayer.fideId);
            enrichedCard = enrichedCard.copyWith(
              title:
                  enrichedCard.title.trim().isNotEmpty
                      ? enrichedCard.title
                      : ChessTitleUtils.normalize(gamebasePlayer.title),
              countryCode:
                  enrichedCard.countryCode.trim().isNotEmpty
                      ? enrichedCard.countryCode
                      : gamebasePlayer.fed,
              rating:
                  enrichedCard.rating > 0
                      ? enrichedCard.rating
                      : (gamebasePlayer.ratingClassical ??
                          gamebasePlayer.highestRating ??
                          0),
              fideId:
                  (enrichedCard.fideId != null && enrichedCard.fideId! > 0)
                      ? enrichedCard.fideId
                      : (resolvedFideId != null && resolvedFideId > 0)
                      ? resolvedFideId
                      : enrichedCard.fideId,
            );
          }
        }

        final resolvedFideId = enrichedCard.fideId;
        final stillMissingFromSupabase =
            resolvedFideId != null &&
            resolvedFideId > 0 &&
            (enrichedCard.title.trim().isEmpty ||
                enrichedCard.countryCode.trim().isEmpty);
        if (stillMissingFromSupabase) {
          final supabasePlayer = await ref
              .read(chessPlayerRepositoryProvider)
              .getPlayerByFideId(resolvedFideId);
          if (supabasePlayer != null) {
            enrichedCard = enrichPlayerCardFromChessPlayers(enrichedCard, {
              resolvedFideId: supabasePlayer,
            });
          }
        }

        return enrichedCard;
      },
      [
        playerCard.fideId,
        playerCard.title,
        playerCard.countryCode,
        playerCard.gamebasePlayerId,
        playerCard.name,
        playerCard.rating,
      ],
    );
    final enrichedPlayerSnapshot = useFuture(enrichedPlayerFuture);
    final effectivePlayerCard = enrichedPlayerSnapshot.data ?? playerCard;
    final validCountryCode = ref
        .read(locationServiceProvider)
        .getValidCountryCode(effectivePlayerCard.countryCode);

    // Calculate move time from state if available, otherwise use game model's time
    final moveTime = useMemoized(() {
      String? calculatedMoveTime;

      final effectiveMoveIndex =
          chessBoardState?.isAnalysisMode == true
              ? chessBoardState!.analysisState.currentMoveIndex
              : chessBoardState?.currentMoveIndex ?? -1;

      if (chessBoardState != null &&
          chessBoardState!.moveTimes.isNotEmpty &&
          effectiveMoveIndex >= 0) {
        // Historical clock display is tied to the last move made by this player
        // up to the currently navigated mainline ply.
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
              ? effectiveGameModel.whiteTimeDisplay
              : effectiveGameModel.blackTimeDisplay;

      if (calculatedMoveTime.trim().isEmpty) {
        calculatedMoveTime = null;
      }

      return calculatedMoveTime;
    }, [chessBoardState, isWhitePlayer, effectiveGameModel]);

    final hasClockData =
        hasUsableClockDisplay(moveTime) ||
        (isWhitePlayer
            ? effectiveGameModel.whiteClockSeconds != null ||
                effectiveGameModel.whiteClockCentiseconds > 0
            : effectiveGameModel.blackClockSeconds != null ||
                effectiveGameModel.blackClockCentiseconds > 0);

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
              color: context.colors.textPrimary,
              height: 1.15,
              letterSpacing: 0,
            )
            : playerView == PlayerView.gridView
            ? TextStyle(
              fontSize: 8.f,
              fontWeight: FontWeight.w600,
              color: context.colors.textPrimary,
              height: 1.15,
              letterSpacing: -0.15,
            )
            : AppTypography.textXsMedium.copyWith(
              color: context.colors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 14.f,
              height: 1.2,
            );

    final ratingStyle =
        playerView == PlayerView.listView
            ? TextStyle(
              fontSize: 8.5.f,
              fontWeight: FontWeight.w500,
              color: context.colors.textPrimaryMuted,
              height: 1.15,
              letterSpacing: 0,
            )
            : playerView == PlayerView.gridView
            ? TextStyle(
              fontSize: 7.5.f,
              fontWeight: FontWeight.w500,
              color: context.colors.textPrimaryMuted,
              height: 1.15,
              letterSpacing: -0.15,
            )
            : AppTypography.textXsMedium.copyWith(
              color: context.colors.textPrimaryMuted,
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
              color: isCurrentPlayer ? context.colors.textPrimaryMuted : context.colors.textPrimary,
              height: 1.15,
              letterSpacing: 0,
              fontFeatures: const [FontFeature.tabularFigures()],
            )
            : playerView == PlayerView.gridView
            ? TextStyle(
              fontSize: 8.f,
              fontWeight: FontWeight.w600,
              color: isCurrentPlayer ? context.colors.textPrimaryMuted : context.colors.textPrimary,
              height: 1.15,
              letterSpacing: -0.2,
              fontFeatures: const [FontFeature.tabularFigures()],
            )
            : AppTypography.textXsMedium.copyWith(
              color: isCurrentPlayer ? context.colors.textPrimaryMuted : context.colors.textPrimary,
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
        playerView == PlayerView.listView
            ? 0.sp
            : // NO margin - container has padding!
            playerView == PlayerView.gridView
            ? 0.sp
            : 16.sp; // BoardView needs margin

    final endPadding = boardMargin; // Right margin matches left margin

    final engineGaugeWidth = useMemoized(() {
      // Check if engine gauge is enabled in settings
      final settings = ref.watch(engineSettingsProviderNew).valueOrNull;
      final showEvalBarInSettings =
          (settings?.showEngineAnalysis ?? true) &&
          (settings?.showEngineGauge ?? true);

      // We only show the gauge area if:
      // 1. The game is finished (to show 1, 0, or 1/2)
      // 2. The game is ongoing AND started AND gauge is enabled in settings
      final isFinished = effectiveGameModel.gameStatus.isFinished;
      final effectivelyShowingEvalBar =
          showEvalBarInSettings &&
          effectiveGameModel.hasStarted &&
          effectiveGameModel.gameStatus.isOngoing;

      if (isFinished || effectivelyShowingEvalBar) {
        return playerView == PlayerView.gridView ? 10.w : 20.w;
      }
      return 0.0;
    }, [ref.watch(engineSettingsProviderNew), effectiveGameModel, playerView]);

    // Clock padding - add small horizontal padding to prevent flickering and provide stability
    final clockPadding = playerView == PlayerView.gridView ? 4.w : 6.w;

    return GestureDetector(
      onTap: () async {
        final standingsAsync = ref.read(playerTourScreenProvider);

        // Create fallback player model from game data - always has fideId if available
        final fallbackPlayer = PlayerStandingModel(
          countryCode: effectivePlayerCard.countryCode,
          title:
              effectivePlayerCard.title.isNotEmpty
                  ? effectivePlayerCard.title
                  : null,
          name: effectivePlayerCard.name,
          score: effectivePlayerCard.rating,
          scoreChange: 0,
          matchScore: null,
          fideId: effectivePlayerCard.fideId,
          gamebasePlayerId: effectivePlayerCard.gamebasePlayerId,
        );

        // Try to find player in tournament standings, otherwise use fallback
        var playerStanding =
            standingsAsync.whenOrNull(
              data:
                  (standings) => standings.firstWhere(
                    (player) => player.name == effectivePlayerCard.name,
                    orElse: () => fallbackPlayer,
                  ),
            ) ??
            fallbackPlayer;

        // IMPORTANT: If standings player has null fideId but game data has it,
        // use the fideId from game data (playerCard) - this is more reliable
        // since games.players always has fideId from broadcast while tours.players
        // may sometimes be missing it
        if (playerStanding.fideId == null &&
            effectivePlayerCard.fideId != null) {
          playerStanding = playerStanding.copyWith(
            fideId: effectivePlayerCard.fideId,
          );
        }
        if (playerStanding.gamebasePlayerId == null &&
            effectivePlayerCard.gamebasePlayerId != null &&
            effectivePlayerCard.gamebasePlayerId!.isNotEmpty) {
          playerStanding = playerStanding.copyWith(
            gamebasePlayerId: effectivePlayerCard.gamebasePlayerId,
          );
        }

        // Fill missing title/federation from chess_players by FIDE ID.
        if (playerStanding.fideId != null &&
            ((playerStanding.title?.trim().isEmpty ?? true) ||
                playerStanding.countryCode.trim().isEmpty)) {
          try {
            final chessPlayer = await ref
                .read(chessPlayerRepositoryProvider)
                .getPlayerByFideId(playerStanding.fideId!);
            if (chessPlayer != null) {
              playerStanding = playerStanding.copyWith(
                title:
                    (playerStanding.title?.trim().isNotEmpty ?? false)
                        ? playerStanding.title
                        : chessPlayer.title,
                countryCode:
                    playerStanding.countryCode.trim().isNotEmpty
                        ? playerStanding.countryCode
                        : (chessPlayer.country ?? ''),
                score:
                    playerStanding.score > 0
                        ? playerStanding.score
                        : (chessPlayer.rating ?? playerStanding.score),
              );
            }
          } catch (_) {
            // Non-critical: score card can still render with existing values.
          }
        }

        // TWIC/Gamebase route: resolve fideId from gamebasePlayerId if missing.
        // The gamebase search API may not include fideId in preview data, but
        // the player record has it. Resolve it so ScoreCardScreen can fetch
        // ratings per time control and player photo.
        if (playerStanding.fideId == null &&
            playerStanding.gamebasePlayerId != null &&
            playerStanding.gamebasePlayerId!.isNotEmpty) {
          try {
            final gamebaseRepo = ref.read(gamebaseRepositoryProvider);
            final gamebasePlayer = await gamebaseRepo.getPlayerById(
              playerStanding.gamebasePlayerId!,
            );
            if (gamebasePlayer != null) {
              final resolvedFideId = int.tryParse(gamebasePlayer.fideId);
              final normalizedTitle = ChessTitleUtils.normalize(
                gamebasePlayer.title,
              );
              final currentCountry = playerStanding.countryCode.trim();
              final fallbackRating =
                  gamebasePlayer.ratingClassical ??
                  gamebasePlayer.highestRating ??
                  0;

              playerStanding = playerStanding.copyWith(
                fideId:
                    (resolvedFideId != null && resolvedFideId > 0)
                        ? resolvedFideId
                        : playerStanding.fideId,
                title:
                    (playerStanding.title?.trim().isNotEmpty ?? false)
                        ? playerStanding.title
                        : (normalizedTitle.isNotEmpty ? normalizedTitle : null),
                countryCode:
                    currentCountry.isNotEmpty
                        ? currentCountry
                        : gamebasePlayer.fed,
                score:
                    playerStanding.score > 0
                        ? playerStanding.score
                        : fallbackRating,
              );
            }
          } catch (_) {
            // Non-critical: score card will fall back to name-based lookup
          }
        }

        if (!context.mounted) return;

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
            gamesContext =
                null; // Let ScoreCardScreen fetch via playerGamesProvider
            hasEventContext = false;
            break;
          case ChessboardView.tour:
            if (playerProfileDataSource == PlayerProfileDataSource.twic) {
              // TWIC route: no broadcast model, use board screen's game list
              // filtered to the current event for score card context.
              ref.read(selectedBroadcastModelProvider.notifier).state = null;
              final allBoardGames = ref.read(chessBoardAllGamesProvider);
              final currentEvent = effectiveGameModel.tourId;
              if (currentEvent.isNotEmpty && allBoardGames.isNotEmpty) {
                gamesContext =
                    allBoardGames
                        .where((g) => g.tourId == currentEvent)
                        .toList();
              }
              gamesContext =
                  (gamesContext != null && gamesContext.isNotEmpty)
                      ? gamesContext
                      : [gamesTourModel];
              hasEventContext = true;
            } else {
              // For tournament view, selectedBroadcastModelProvider will be set
              // ScoreCardScreen will use gamesTourScreenProvider directly
              gamesContext = null;
              hasEventContext = true; // Tournament context
            }
            break;
          case ChessboardView.countryman:
            // For countrymen view, filter games by the current game's tournament
            // This ensures ScoreCardScreen shows only games from that specific event
            ref.read(selectedBroadcastModelProvider.notifier).state = null;
            final allCountrymanGames =
                ref
                    .read(countrymanGamesTourScreenProvider)
                    .valueOrNull
                    ?.gamesTourModels ??
                [];
            final currentTourIdCountryman = effectiveGameModel.tourId;
            if (currentTourIdCountryman.isNotEmpty) {
              gamesContext =
                  allCountrymanGames
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
            if (effectiveGameModel.tourId.isNotEmpty) {
              // Pass current game - ScoreCardScreen will fetch all event games via tourId
              gamesContext = [effectiveGameModel];
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
        if ((gamesContext == null || gamesContext.isEmpty) &&
            effectiveGameModel.tourId.isNotEmpty) {
          gamesContext = [effectiveGameModel];
          hasEventContext = true;
        }

        // Set the games context and event context flag for ScoreCardScreen
        ref.read(scoreCardGamesContextProvider.notifier).state = gamesContext;
        ref.read(scoreCardHasEventContextProvider.notifier).state =
            hasEventContext;
        ref.read(scoreCardPlayerProfileDataSourceProvider.notifier).state =
            playerProfileDataSource;

        if (!context.mounted) return;
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
              child:
                  effectiveGameModel.gameStatus.isFinished
                      ? Center(
                        child: Builder(
                          builder: (context) {
                            final status = effectiveGameModel.gameStatus;
                            final isDraw = status == GameStatus.draw;
                            final isWin =
                                (status == GameStatus.whiteWins &&
                                    isWhitePlayer) ||
                                (status == GameStatus.blackWins &&
                                    !isWhitePlayer);
                            final label =
                                isDraw ? '½' : (isWin ? '1' : '0');
                            final isBoardView =
                                playerView == PlayerView.boardView;
                            final resultColor = isBoardView
                                ? context.colors.textPrimary
                                : isDraw
                                    ? context.colors.textPrimaryMuted
                                    : isWin
                                        ? kPrimaryColor
                                        : context.colors.textPrimary;
                            final scoreFontSize =
                                playerView == PlayerView.listView
                                    ? 12.f
                                    : playerView == PlayerView.gridView
                                        ? 13.f
                                        : 15.f;
                            return Text(
                              label,
                              style: TextStyle(
                                fontSize: scoreFontSize,
                                fontWeight: FontWeight.w700,
                                color: resultColor,
                                height: 1.0,
                                letterSpacing: -0.2,
                              ),
                              strutStyle: const StrutStyle(
                                forceStrutHeight: true,
                                height: 1.0,
                                leading: 0,
                              ),
                              textAlign: TextAlign.center,
                            );
                          },
                        ),
                      )
                      : null,
            ),
            if (effectiveGameModel.gameStatus.isFinished)
              SizedBox(
                width:
                    playerView == PlayerView.gridView
                        ? 4.w
                        : playerView == PlayerView.listView
                            ? 5.w
                            : 6.w,
              ),
            FederationFlag(
              federation:
                  effectivePlayerCard.countryCode.trim().isNotEmpty
                      ? effectivePlayerCard.countryCode
                      : (validCountryCode.isNotEmpty
                          ? validCountryCode
                          : 'FID'),
              height: flagHeight,
              width: flagWidth,
              borderRadius: BorderRadius.circular(2.br),
            ),
            SizedBox(width: elementSpacing),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Reserve space for edit icon if present
                  final editIconSpace = onEditName != null ? 4.w + 14.ic : 0.0;
                  final availableWidth = constraints.maxWidth - editIconSpace;

                  // Parse name parts - format is "Surname, Given Names"
                  final fullName = effectivePlayerCard.name;
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
                  final rating =
                      effectivePlayerCard.rating > 0
                          ? ' ${effectivePlayerCard.rating}'
                          : '';

                  // Create text painter to measure text width
                  final textPainter = TextPainter(
                    textDirection: TextDirection.ltr,
                    maxLines: 1,
                  );

                  // Smart truncation: ALWAYS prioritize showing full surname
                  // Only abbreviate/truncate other parts, never reduce surname to initials
                  String displaySurname = surname;
                  String displayFirstName =
                      firstName.isNotEmpty ? ', $firstName' : '';

                  if (surname.isNotEmpty) {
                    // Strategy 1: Try full surname + full first name
                    textPainter.text = TextSpan(
                      children: [
                        TextSpan(
                          text: '${effectivePlayerCard.title} ',
                          style: rankStyle,
                        ),
                        TextSpan(text: surname, style: nameStyle),
                        if (firstName.isNotEmpty)
                          TextSpan(text: ', $firstName', style: nameStyle),
                        TextSpan(text: rating, style: ratingStyle),
                      ],
                    );
                    textPainter.layout();

                    // If doesn't fit, start trimming (but keep full surname!)
                    if (textPainter.width > availableWidth &&
                        firstName.isNotEmpty) {
                      // Strategy 2: Keep full surname + abbreviate first name
                      final firstNameParts = firstName.split(' ');
                      final abbreviatedFirst = firstNameParts
                          .where((part) => part.isNotEmpty)
                          .map((part) => '${part[0]}.')
                          .join(' ');
                      displayFirstName = ', $abbreviatedFirst';

                      textPainter.text = TextSpan(
                        children: [
                          TextSpan(
                            text: '${effectivePlayerCard.title} ',
                            style: rankStyle,
                          ),
                          TextSpan(text: surname, style: nameStyle),
                          TextSpan(text: displayFirstName, style: nameStyle),
                          TextSpan(text: rating, style: ratingStyle),
                        ],
                      );
                      textPainter.layout();

                      // Strategy 3: If still doesn't fit, drop first name entirely
                      if (textPainter.width > availableWidth) {
                        displayFirstName = '';

                        textPainter.text = TextSpan(
                          children: [
                            TextSpan(
                              text: '${effectivePlayerCard.title} ',
                              style: rankStyle,
                            ),
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

                  final nameWidget = RichText(
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    softWrap: false,
                    textAlign: TextAlign.left,
                    text: TextSpan(
                      style: nameStyle, // Add base style for inheritance
                      children: [
                        // Always render title (with trailing space) like old code
                        TextSpan(
                          text: '${effectivePlayerCard.title} ',
                          style: rankStyle,
                        ),
                        if (displaySurname.isNotEmpty)
                          TextSpan(text: displaySurname, style: nameStyle),
                        if (displayFirstName.isNotEmpty)
                          TextSpan(text: displayFirstName, style: nameStyle),
                        TextSpan(text: rating, style: ratingStyle),
                      ],
                    ),
                  );

                  if (onEditName != null) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(child: nameWidget),
                        SizedBox(width: 4.w),
                        GestureDetector(
                          onTap:
                              () => _showEditNameDialog(
                                context,
                                effectivePlayerCard.name,
                                onEditName!,
                              ),
                          child: Icon(
                            Icons.edit,
                            size: 14.ic,
                            color: Colors.white.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    );
                  }

                  return nameWidget;
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
            if (showClock && hasClockData)
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: clockPadding,
                  vertical: playerView == PlayerView.gridView ? 1.sp : 0,
                ),
                decoration: BoxDecoration(
                  color: isCurrentPlayer ? kDarkBlue : Colors.transparent,
                  borderRadius:
                      playerView == PlayerView.gridView
                          ? BorderRadius.circular(2)
                          : null,
                ),
                child: _PlayerClock(
                  isWhitePlayer: isWhitePlayer,
                  gamesTourModel: effectiveGameModel,
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

void _showEditNameDialog(
  BuildContext context,
  String currentName,
  ValueChanged<String> onSave,
) {
  final controller = TextEditingController(text: currentName);
  showDialog<void>(
    context: context,
    builder:
        (context) => AlertDialog(
          backgroundColor: context.colors.surface,
          title: Text(
            'Edit Player Name',
            style: TextStyle(color: Colors.white, fontSize: 16.f),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: TextStyle(color: Colors.white, fontSize: 14.f),
            decoration: InputDecoration(
              hintText: 'Player name',
              hintStyle: TextStyle(color: Colors.white38, fontSize: 14.f),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white70),
              ),
            ),
            onSubmitted: (value) {
              final trimmed = value.trim();
              if (trimmed.isNotEmpty && trimmed != currentName) {
                onSave(trimmed);
              }
              Navigator.of(context).pop();
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.white54, fontSize: 14.f),
              ),
            ),
            TextButton(
              onPressed: () {
                final trimmed = controller.text.trim();
                if (trimmed.isNotEmpty && trimmed != currentName) {
                  onSave(trimmed);
                }
                Navigator.of(context).pop();
              },
              child: Text(
                'Save',
                style: TextStyle(color: Colors.white, fontSize: 14.f),
              ),
            ),
          ],
        ),
  );
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
    final effectiveGameModel = chessBoardState?.game ?? gamesTourModel;
    final currentPosition =
        chessBoardState?.isAnalysisMode == true
            ? chessBoardState?.analysisState.position
            : chessBoardState?.position;
    final effectiveMoveIndex =
        chessBoardState?.isAnalysisMode == true
            ? chessBoardState!.analysisState.currentMoveIndex
            : chessBoardState?.currentMoveIndex ?? -1;
    final latestMainlineIndex =
        chessBoardState == null ? -1 : chessBoardState!.moveSans.length - 1;
    final isShowingLivePosition =
        chessBoardState == null
            ? true
            : isShowingLiveBoardPosition(
              currentFen: currentPosition?.fen,
              liveFen: effectiveGameModel.fen,
              currentMoveIndex: effectiveMoveIndex,
              latestMainlineIndex: latestMainlineIndex,
              isInAnalysisVariation:
                  chessBoardState!.analysisState.isInAnalysisVariation,
            );

    final liveActivePlayer = effectiveGameModel.activePlayer;
    final isLiveCurrentPlayer =
        liveActivePlayer != null &&
        ((isWhitePlayer && liveActivePlayer == Side.white) ||
            (!isWhitePlayer && liveActivePlayer == Side.black));
    final shouldCountForThisPlayer =
        isShowingLivePosition ? isLiveCurrentPlayer : isCurrentPlayer;

    // Determine if this player's clock should be counting down
    // Only countdown for live games when at the latest move and it's this player's turn
    // NEVER countdown when exploring analysis variations - always show static clock time
    final isClockRunning =
        effectiveGameModel.gameStatus.isOngoing &&
        effectiveGameModel.lastMoveTime != null &&
        shouldCountForThisPlayer &&
        isShowingLivePosition &&
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
            ? effectiveGameModel.whiteClockCentiseconds
            : effectiveGameModel.blackClockCentiseconds;
    final liveClockSeconds =
        isWhitePlayer
            ? effectiveGameModel.whiteClockSeconds
            : effectiveGameModel.blackClockSeconds;

    return AtomicCountdownText(
      // Force a fresh countdown widget when either the reference time or the
      // live clock snapshot changes.
      key: ValueKey(
        '${effectiveGameModel.lastMoveTime?.millisecondsSinceEpoch ?? 0}:${liveClockSeconds ?? -1}',
      ),
      moveTime:
          moveTime, // Primary for past moves: PGN-parsed move times (more accurate for historical display)
      clockSeconds:
          // Prefer streamed clock snapshots whenever the board is on the live
          // position. PGN clock tags are only used for historical navigation.
          isShowingLivePosition ? liveClockSeconds : null,
      clockCentiseconds:
          clockCentiseconds, // Fallback source: raw database clock
      lastMoveTime:
          effectiveGameModel.lastMoveTime, // Critical for live countdown timing
      isActive: isClockRunning,
      style: timeStyle,
    );
  }
}
