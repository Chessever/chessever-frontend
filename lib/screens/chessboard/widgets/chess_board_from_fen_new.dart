import 'dart:async';
import 'package:chessever2/screens/chessboard/widgets/context_pop_up_menu.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/chessboard/utils/game_share_utils.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new_worker.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/chessboard/widgets/evaluation_bar_widget.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/screens/chessboard/widgets/share_game_card_overlay.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/live_game_position_resolver.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/string_utils.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const String _kStartFen =
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

Setup? _tryParseFen(String fen) {
  if (fen.trim().isEmpty) return null;
  try {
    return Setup.parseFen(fen);
  } catch (_) {
    return null;
  }
}

String _resolveFen(String? fen) {
  final rawFen = (fen ?? '').trim();
  return _tryParseFen(rawFen) != null ? rawFen : _kStartFen;
}

String? _finalFenFromPgn(String? pgn) {
  return resolveFinalPositionFromPgn(pgn)?.fen;
}

bool _isGamebasePreviewGame(GamesTourModel game) {
  final marker = game.roundId.trim().toLowerCase();
  return marker == 'gamebase_search' ||
      marker == 'twic_profile' ||
      marker == 'twic_event';
}

final _gamebaseFinalFenProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, gameId) async {
      final normalizedGameId = gameId.trim();
      if (normalizedGameId.isEmpty) return null;

      final repo = ref.read(gamebaseRepositoryProvider);
      final gameWithPgn = await repo.getGameWithPgn(normalizedGameId);
      if (gameWithPgn == null) return null;

      final pgn =
          (gameWithPgn.pgn?.trim().isNotEmpty ?? false)
              ? gameWithPgn.pgn!.trim()
              : buildPgnFromGamebaseData(gameWithPgn.data);
      final resolvedFen = _finalFenFromPgn(pgn);
      if (resolvedFen == null) return null;
      return _tryParseFen(resolvedFen) != null ? resolvedFen : null;
    });

bool _shouldShowEvalBar(WidgetRef ref) {
  final settings = ref.watch(engineSettingsProviderNew).valueOrNull;
  return settings?.showEngineGauge ?? true;
}

bool _hideFinishedSpoilers(WidgetRef ref, GamesTourModel game) {
  final spoilerState = ref.watch(eventNoSpoilersProvider(game.tourId));
  return (spoilerState.isLoading || spoilerState.enabled) &&
      game.gameStatus.isFinished;
}

/// Resolved FEN provider that caches the resolution logic for a game model
@immutable
class _ResolvedFenKey {
  _ResolvedFenKey({
    required this.gameId,
    required this.fen,
    required this.pgn,
    required this.lastMove,
    required this.allowGamebaseFallback,
  }) : pgnHash = pgn?.hashCode ?? 0,
       pgnLength = pgn?.length ?? 0;

  factory _ResolvedFenKey.fromGame(GamesTourModel game) {
    return _ResolvedFenKey(
      gameId: game.gameId,
      fen: game.fen,
      pgn: game.pgn,
      lastMove: game.lastMove,
      allowGamebaseFallback: _isGamebasePreviewGame(game),
    );
  }

  final String gameId;
  final String? fen;
  final String? pgn;
  final int pgnHash;
  final int pgnLength;
  final String? lastMove;
  final bool allowGamebaseFallback;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _ResolvedFenKey &&
            other.gameId == gameId &&
            other.fen == fen &&
            other.pgnHash == pgnHash &&
            other.pgnLength == pgnLength &&
            other.pgn == pgn &&
            other.lastMove == lastMove &&
            other.allowGamebaseFallback == allowGamebaseFallback;
  }

  @override
  int get hashCode {
    return Object.hash(
      gameId,
      fen,
      pgnHash,
      pgnLength,
      lastMove,
      allowGamebaseFallback,
    );
  }
}

final _resolvedFenProvider = Provider.autoDispose
    .family<String, _ResolvedFenKey>((ref, key) {
      // Delay disposal by 3 seconds to prevent thrashing during fast scrolling
      final link = ref.keepAlive();
      final timer = Timer(const Duration(seconds: 3), () {
        link.close();
      });
      ref.onDispose(() => timer.cancel());

      final freshestFen = resolveFreshestGameFen(
        fen: key.fen,
        pgn: key.pgn,
        lastMove: key.lastMove,
      );
      if (freshestFen != null) {
        return freshestFen;
      }

      // Gamebase async fallback
      if (key.allowGamebaseFallback && !pgnHasMoves(key.pgn)) {
        final remoteFen =
            ref.watch(_gamebaseFinalFenProvider(key.gameId)).valueOrNull;
        if (remoteFen != null) return remoteFen;
      }

      return _kStartFen;
    });

/// Shows the share overlay for a game from the grid/list view.
///
/// Resolves PGN data via a 3-tier fallback (local → Supabase → Gamebase)
/// before opening the overlay, so that GIF export has move history.
Future<void> _showShareOverlay(
  BuildContext context,
  WidgetRef ref,
  GamesTourModel game,
) async {
  // ---------------------------------------------------------------------------
  // Resolve PGN move history (3-tier fallback, parse-and-accept)
  // ---------------------------------------------------------------------------
  String resolvedPgn = '';
  List<String> moveSans = const [];
  List<String> moveTimes = const [];
  int currentMoveIndex = -1;
  String? startingFen;

  // Collect candidate PGNs from all tiers as (source, pgn) pairs.
  // Each tier is wrapped in try/catch so a network failure doesn't block later tiers.
  final candidates = <(String source, String pgn)>[];

  // Tier 1: game.pgn (already available on the model)
  debugPrint(
    'GIF share [${game.gameId}]: Tier 1 game.pgn '
    '${game.pgn == null ? "null" : "(${game.pgn!.length} chars)"} '
    'hasMoves=${pgnHasMoves(game.pgn)}',
  );
  try {
    if (pgnHasMoves(game.pgn)) {
      candidates.add(('game.pgn', game.pgn!.trim()));
    }
  } catch (e) {
    debugPrint('GIF share [${game.gameId}]: Tier 1 failed: $e');
  }

  // Tier 2: Supabase getGamePgn
  try {
    final fetched = await ref
        .read(gameRepositoryProvider)
        .getGamePgn(game.gameId);
    debugPrint(
      'GIF share [${game.gameId}]: Tier 2 Supabase '
      '${fetched == null ? "null" : "(${fetched.length} chars)"} '
      'hasMoves=${pgnHasMoves(fetched)}',
    );
    if (pgnHasMoves(fetched)) {
      candidates.add(('Supabase', fetched!.trim()));
    }
  } catch (e) {
    debugPrint('GIF share [${game.gameId}]: Tier 2 failed: $e');
  }

  // Tier 3: Gamebase getGameWithPgn — only for Gamebase-sourced games
  // Non-Gamebase IDs (e.g. broadcast IDs like mrqvQ9VS) produce HTTP 400.
  if (_isGamebasePreviewGame(game)) {
    debugPrint('GIF share [${game.gameId}]: Tier 3 Gamebase attempted');
    try {
      final gameWithPgn = await ref
          .read(gamebaseRepositoryProvider)
          .getGameWithPgn(game.gameId);
      if (gameWithPgn != null) {
        if (pgnHasMoves(gameWithPgn.pgn)) {
          candidates.add(('Gamebase.pgn', gameWithPgn.pgn!.trim()));
        } else {
          final built = buildPgnFromGamebaseData(gameWithPgn.data);
          if (pgnHasMoves(built)) {
            candidates.add(('Gamebase.data', built!.trim()));
          }
        }
      }
    } catch (e) {
      debugPrint('GIF share [${game.gameId}]: Tier 3 failed: $e');
    }
  } else {
    debugPrint('GIF share [${game.gameId}]: Tier 3 skipped (not gamebase)');
  }

  // Deduplicate by PGN content so the same string isn't parsed twice
  final seen = <String>{};
  final uniqueCandidates = <(String, String)>[];
  for (final c in candidates) {
    if (seen.add(c.$2)) {
      uniqueCandidates.add(c);
    }
  }

  debugPrint(
    'GIF share [${game.gameId}]: ${uniqueCandidates.length} '
    'candidate(s) after dedup',
  );

  // Parse-and-accept: accept the first candidate that yields non-empty moveSans
  for (final (source, pgn) in uniqueCandidates) {
    try {
      final parseResult = await compute(parsePgnWorker, pgn);
      if (parseResult.moveSans.isNotEmpty) {
        resolvedPgn = pgn;
        moveSans = parseResult.moveSans;
        moveTimes = parseResult.moveTimes;
        currentMoveIndex = moveSans.length - 1;
        // Only set startingFen if it's a non-standard start position
        final startFen = parseResult.startingPos.fen;
        if (startFen !=
            'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1') {
          startingFen = startFen;
        }
        debugPrint(
          'GIF share [${game.gameId}]: accepted PGN from $source '
          '(${moveSans.length} moves)',
        );
        break;
      } else {
        debugPrint(
          'GIF share [${game.gameId}]: $source PGN parsed '
          'but yielded 0 moves',
        );
      }
    } catch (e) {
      debugPrint('GIF share [${game.gameId}]: $source PGN parse failed: $e');
    }
  }

  debugPrint(
    'GIF share [${game.gameId}]: '
    '${moveSans.isNotEmpty ? "resolved ${moveSans.length} moves" : "NO MOVES RESOLVED"}',
  );
  // On total failure: all remain empty/default — overlay opens but GIF
  // is unavailable. resolvedPgn stays '' (non-null String).

  // Guard: widget may have been disposed during async gap
  if (!context.mounted) return;

  // ---------------------------------------------------------------------------
  // Build board settings and open overlay
  // ---------------------------------------------------------------------------
  final boardSettingsAsync = ref.read(boardSettingsProviderNew);
  final boardSettingsNew =
      boardSettingsAsync.valueOrNull ?? const BoardSettingsNew();

  // Get the base color scheme from settings
  final baseColorScheme = boardSettingsNew.colorScheme;

  // Build board settings for the share overlay board
  // We use the theme colors but hide all highlights for clean screenshots
  // IMPORTANT: Disable animations for instant static frame capture in GIF generation
  final chessboardSettings = ChessboardSettings(
    enableCoordinates: false,
    animationDuration: Duration.zero, // Disable animations for screenshot/GIF
    colorScheme: ChessboardColorScheme(
      lightSquare: baseColorScheme.lightSquare,
      darkSquare: baseColorScheme.darkSquare,
      background: baseColorScheme.background,
      whiteCoordBackground: baseColorScheme.whiteCoordBackground,
      blackCoordBackground: baseColorScheme.blackCoordBackground,
      // Show last-move highlights in screenshots and GIF frames
      lastMove: baseColorScheme.lastMove,
      selected: HighlightDetails(
        solidColor: baseColorScheme.lightSquare.withValues(alpha: 0),
      ),
      validMoves: baseColorScheme.lightSquare.withValues(alpha: 0),
      validPremoves: baseColorScheme.lightSquare.withValues(alpha: 0),
    ),
    // Use piece set from settings
    pieceAssets: boardSettingsNew.pieceAssets,
    borderRadius: const BorderRadius.all(Radius.circular(0)),
    boxShadow: const [],
  );

  // Format tournament and round names
  final tournamentName =
      game.tourSlug != null ? StringUtils.slugToTitle(game.tourSlug!) : null;
  final roundInfo =
      game.roundSlug != null
          ? StringUtils.formatRoundLabel(game.roundSlug)
          : null;
  final shareUrl = buildGameShareUrl(game: game);

  final positionFen = _resolveFen(game.fen);
  final lastMove = _uciToMove(game.lastMove ?? '');

  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      pageBuilder:
          (context, animation, secondaryAnimation) => ShareGameCardOverlay(
            boardSettings: chessboardSettings,
            positionFen: positionFen,
            lastMove: lastMove,
            pgn: resolvedPgn,
            moveSans: moveSans,
            moveTimes: moveTimes,
            whitePlayerName: game.whitePlayer.name,
            blackPlayerName: game.blackPlayer.name,
            whitePlayerCountry: game.whitePlayer.federation,
            blackPlayerCountry: game.blackPlayer.federation,
            whitePlayerElo: game.whitePlayer.rating.toString(),
            blackPlayerElo: game.blackPlayer.rating.toString(),
            whitePlayerTitle: game.whitePlayer.title,
            blackPlayerTitle: game.blackPlayer.title,
            whitePlayerClock: game.whiteTimeDisplay,
            blackPlayerClock: game.blackTimeDisplay,
            tournamentName: tournamentName,
            roundInfo: roundInfo,
            currentMoveIndex: currentMoveIndex,
            evaluation: null, // No evaluation available from grid view
            mate: 0,
            isFlipped: false,
            gameStatus: game.gameStatus,
            isAtGameEnd:
                game.gameStatus != GameStatus.ongoing &&
                game.gameStatus != GameStatus.unknown,
            onClose: () => Navigator.of(context).pop(),
            shareUrl: shareUrl,
            gameId: game.gameId,
            startingFen: startingFen,
          ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    ),
  );
}

class ChessBoardFromFENNew extends ConsumerWidget {
  const ChessBoardFromFENNew({
    super.key,
    required this.gamesTourModel,
    required this.onChanged,
    required this.pinnedIds,
    required this.onPinToggle,
    this.fixedBottomSide,
    this.allowStockfishFallback = true,
    this.liveBatchKey,
  });

  final GamesTourModel gamesTourModel;
  final VoidCallback onChanged;
  final List<String> pinnedIds;
  final void Function(GamesTourModel game) onPinToggle;
  final Side? fixedBottomSide;
  final bool allowStockfishFallback;
  final LiveGamesBatchKey? liveBatchKey;

  bool get isPinned => pinnedIds.contains(gamesTourModel.gameId);

  void _showBlurredPopup(
    BuildContext context,
    WidgetRef ref,
    LongPressStartDetails details,
  ) {
    final RenderBox boardRenderBox = context.findRenderObject() as RenderBox;
    final Offset boardPosition = boardRenderBox.localToGlobal(Offset.zero);
    final Size boardSize = boardRenderBox.size;

    final double screenHeight = MediaQuery.of(context).size.height;
    const double popupHeight = 100;
    final double spaceBelow =
        screenHeight - (boardPosition.dy + boardSize.height);

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
                ? boardPosition.dy - popupHeight - 8.sp
                : boardPosition.dy + boardSize.height + 8.sp;
        return Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: () => Navigator.of(buildContext).pop(),
            child: Stack(
              children: [
                SelectiveBlurBackground(
                  clearPosition: boardPosition,
                  clearSize: boardSize,
                ),
                Positioned(
                  left: boardPosition.dx,
                  top: boardPosition.dy,
                  child: _ChessBoardContent(
                    gamesTourModel: gamesTourModel,
                    lastMove: _uciToMove(gamesTourModel.lastMove ?? ''),
                    boardSize: boardSize,
                    isPinned: isPinned,
                    fixedBottomSide: fixedBottomSide,
                    allowStockfishFallback: allowStockfishFallback,
                    liveBatchKey: liveBatchKey,
                  ),
                ),

                Positioned(
                  left: details.globalPosition.dx - 120.w,
                  top: menuTop,
                  child: ContextPopupMenu(
                    isPinned: isPinned,
                    onPinToggle: () {
                      onPinToggle(gamesTourModel);

                      Future.microtask(() {
                        if (!buildContext.mounted) return;
                        Navigator.pop(buildContext);
                      });
                    },
                    onShare: () {
                      Navigator.pop(buildContext);
                      _showShareOverlay(context, ref, gamesTourModel);
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hideFinishedSpoilers = _hideFinishedSpoilers(ref, gamesTourModel);
    final showEvalBar =
        _shouldShowEvalBar(ref) &&
        gamesTourModel.hasStarted &&
        !hideFinishedSpoilers;
    final sideBarWidth = showEvalBar ? 20.w : 0.w;

    return Padding(
      padding: EdgeInsets.only(left: 24.sp, right: 24.sp, bottom: 8.sp),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Get width AFTER padding is applied
          final availableWidth = constraints.maxWidth;
          // Board size is available width minus the evaluation bar
          final boardSize = availableWidth - sideBarWidth;

          return GestureDetector(
            onTap: () {
              HapticFeedbackService.cardTap();
              onChanged();
            },
            onLongPressStart: (details) {
              HapticFeedbackService.contextMenu();
              _showBlurredPopup(context, ref, details);
            },
            child: _ChessBoardLayout(
              gamesTourModel: gamesTourModel,
              lastMove: _uciToMove(gamesTourModel.lastMove ?? ''),
              sideBarWidth: sideBarWidth,
              boardSize: boardSize,
              isPinned: isPinned,
              showEvalBar: showEvalBar,
              fixedBottomSide: fixedBottomSide,
              allowStockfishFallback: allowStockfishFallback,
              liveBatchKey: liveBatchKey,
            ),
          );
        },
      ),
    );
  }
}

class GridChessBoardFromFENNew extends ConsumerWidget {
  const GridChessBoardFromFENNew({
    super.key,
    required this.gamesTourModel,
    required this.onChanged,
    required this.pinnedIds,
    required this.onPinToggle,
    this.fixedBottomSide,
    this.allowStockfishFallback = true,
    this.liveBatchKey,
  });

  final GamesTourModel gamesTourModel;
  final VoidCallback onChanged;
  final List<String> pinnedIds;
  final void Function(GamesTourModel game) onPinToggle;
  final Side? fixedBottomSide;
  final bool allowStockfishFallback;
  final LiveGamesBatchKey? liveBatchKey;

  bool get isPinned => pinnedIds.contains(gamesTourModel.gameId);

  void _showBlurredPopup({
    required BuildContext context,
    required WidgetRef ref,
    required double size,
    required double screenWidth,
    required double sideBarWidth,
    required bool showEvalBar,
    required LongPressStartDetails details,
  }) {
    final boardRenderBox = context.findRenderObject() as RenderBox;
    final boardPosition = boardRenderBox.localToGlobal(Offset.zero);
    final bottomSide = fixedBottomSide ?? Side.white;
    final topSide = _oppositeSide(bottomSide);

    final screenHeight = MediaQuery.of(context).size.height;
    final popupHeight = 100.h;
    final spaceBelow = screenHeight - (boardPosition.dy + screenWidth);

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
        return Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: () => Navigator.of(buildContext).pop(),
            child: Stack(
              children: [
                SelectiveBlurBackground(
                  clearPosition: boardPosition,
                  clearSize: Size(size, size),
                ),
                Positioned(
                  left: boardPosition.dx,
                  top: boardPosition.dy - (showAbove ? popupHeight : 0),
                  width: screenWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showAbove)
                        Padding(
                          padding: EdgeInsets.only(left: sideBarWidth),
                          child: ContextPopupMenu(
                            isPinned: isPinned,
                            onPinToggle: () {
                              onPinToggle(gamesTourModel);

                              Future.microtask(() {
                                if (!buildContext.mounted) return;
                                Navigator.pop(buildContext);
                              });
                            },
                            onShare: () {
                              Navigator.pop(buildContext);
                              _showShareOverlay(context, ref, gamesTourModel);
                            },
                          ),
                        ),
                      _PlayerRow(
                        gamesTourModel: gamesTourModel,
                        isWhitePlayer: topSide == Side.white,
                        isCurrentPlayer: gamesTourModel.activePlayer == topSide,
                        isPinned: isPinned,
                        playerView: PlayerView.gridView,
                        liveBatchKey: liveBatchKey,
                      ),
                      SizedBox(height: 4.h),
                      SizedBox(
                        height: size,
                        child: _ChessBoardWithEvaluation(
                          gamesTourModel: gamesTourModel,
                          lastMove: _uciToMove(gamesTourModel.lastMove ?? ''),
                          sideBarWidth: sideBarWidth,
                          boardSize: size,
                          playerView: PlayerView.gridView,
                          showEvalBar: showEvalBar,
                          showCoordinates: false,
                          orientation: bottomSide,
                          allowStockfishFallback: allowStockfishFallback,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      _PlayerRow(
                        gamesTourModel: gamesTourModel,
                        isWhitePlayer: bottomSide == Side.white,
                        isCurrentPlayer:
                            gamesTourModel.activePlayer == bottomSide,
                        isPinned: false,
                        playerView: PlayerView.gridView,
                        liveBatchKey: liveBatchKey,
                      ),

                      if (!showAbove)
                        Padding(
                          padding: EdgeInsets.only(left: sideBarWidth),
                          child: ContextPopupMenu(
                            isPinned: isPinned,
                            onPinToggle: () {
                              onPinToggle(gamesTourModel);

                              Future.microtask(() {
                                if (!buildContext.mounted) return;
                                Navigator.pop(buildContext);
                              });
                            },
                            onShare: () {
                              Navigator.pop(buildContext);
                              _showShareOverlay(context, ref, gamesTourModel);
                            },
                          ),
                        ),
                    ],
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hideFinishedSpoilers = _hideFinishedSpoilers(ref, gamesTourModel);
    final showEvalBar =
        _shouldShowEvalBar(ref) &&
        gamesTourModel.hasStarted &&
        !hideFinishedSpoilers;
    final sideBarWidth = showEvalBar ? 10.w : 0.w;
    final bottomSide = fixedBottomSide ?? Side.white;
    final topSide = _oppositeSide(bottomSide);

    // On phone, use the original fixed calculation for 2-column grid
    if (ResponsiveHelper.isPhone) {
      final screenWidth = (MediaQuery.of(context).size.width / 2) - 24.sp;
      final boardSize = screenWidth - sideBarWidth;
      return GestureDetector(
        onTap: () {
          HapticFeedbackService.cardTap();
          onChanged();
        },
        onLongPressStart: (details) {
          HapticFeedbackService.contextMenu();
          _showBlurredPopup(
            context: context,
            ref: ref,
            size: boardSize,
            screenWidth: screenWidth,
            sideBarWidth: sideBarWidth,
            showEvalBar: showEvalBar,
            details: details,
          );
        },
        child: SizedBox(
          width: screenWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PlayerRow(
                gamesTourModel: gamesTourModel,
                isWhitePlayer: topSide == Side.white,
                isCurrentPlayer: gamesTourModel.activePlayer == topSide,
                isPinned: isPinned,
                playerView: PlayerView.gridView,
                liveBatchKey: liveBatchKey,
              ),
              SizedBox(height: 4.h),
              _ChessBoardWithEvaluation(
                gamesTourModel: gamesTourModel,
                lastMove: _uciToMove(gamesTourModel.lastMove ?? ''),
                sideBarWidth: sideBarWidth,
                boardSize: boardSize,
                playerView: PlayerView.gridView,
                showEvalBar: showEvalBar,
                showCoordinates: false,
                orientation: bottomSide,
                allowStockfishFallback: allowStockfishFallback,
              ),
              SizedBox(height: 4.h),
              _PlayerRow(
                gamesTourModel: gamesTourModel,
                isWhitePlayer: bottomSide == Side.white,
                isCurrentPlayer: gamesTourModel.activePlayer == bottomSide,
                isPinned: false,
                playerView: PlayerView.gridView,
                liveBatchKey: liveBatchKey,
              ),
            ],
          ),
        ),
      );
    }

    // On tablet, use LayoutBuilder to adapt to parent constraints
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final boardSize = availableWidth - sideBarWidth;

        return GestureDetector(
          onTap: () {
            HapticFeedbackService.cardTap();
            onChanged();
          },
          onLongPressStart: (details) {
            HapticFeedbackService.contextMenu();
            _showBlurredPopup(
              context: context,
              ref: ref,
              size: boardSize,
              screenWidth: availableWidth,
              sideBarWidth: sideBarWidth,
              showEvalBar: showEvalBar,
              details: details,
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PlayerRow(
                gamesTourModel: gamesTourModel,
                isWhitePlayer: topSide == Side.white,
                isCurrentPlayer: gamesTourModel.activePlayer == topSide,
                isPinned: isPinned,
                playerView: PlayerView.gridView,
                liveBatchKey: liveBatchKey,
              ),
              SizedBox(height: 4.h),
              _ChessBoardWithEvaluation(
                gamesTourModel: gamesTourModel,
                lastMove: _uciToMove(gamesTourModel.lastMove ?? ''),
                sideBarWidth: sideBarWidth,
                boardSize: boardSize,
                playerView: PlayerView.gridView,
                showEvalBar: showEvalBar,
                showCoordinates: false,
                orientation: bottomSide,
                allowStockfishFallback: allowStockfishFallback,
              ),
              SizedBox(height: 4.h),
              _PlayerRow(
                gamesTourModel: gamesTourModel,
                isWhitePlayer: bottomSide == Side.white,
                isCurrentPlayer: gamesTourModel.activePlayer == bottomSide,
                isPinned: false,
                playerView: PlayerView.gridView,
                liveBatchKey: liveBatchKey,
              ),
            ],
          ),
        );
      },
    );
  }
}

Move? _uciToMove(String uci) {
  if (uci.length != 4 && uci.length != 5) {
    return null;
  }
  try {
    final from = _square(uci.substring(0, 2));
    final to = _square(uci.substring(2, 4));
    final promo = uci.length == 5 ? Role.fromChar(uci[4]) : null;
    return NormalMove(from: from, to: to, promotion: promo);
  } catch (_) {
    return null;
  }
}

Square _square(String name) => Square.fromName(name);

Side _oppositeSide(Side side) => side == Side.white ? Side.black : Side.white;

({double left, double top}) _orientedSquareOffset(
  Square square,
  double squareSize,
  Side orientation,
) {
  final file = square.file;
  final rank = square.rank;
  if (orientation == Side.black) {
    return (left: (7 - file) * squareSize, top: rank * squareSize);
  }
  return (left: file * squareSize, top: (7 - rank) * squareSize);
}

class _ChessBoardLayout extends ConsumerWidget {
  const _ChessBoardLayout({
    required this.gamesTourModel,
    required this.lastMove,
    required this.sideBarWidth,
    required this.boardSize,
    required this.isPinned,
    required this.showEvalBar,
    required this.fixedBottomSide,
    required this.allowStockfishFallback,
    required this.liveBatchKey,
  });

  final GamesTourModel gamesTourModel;
  final Move? lastMove;
  final double sideBarWidth;
  final double boardSize;
  final bool isPinned;
  final bool showEvalBar;
  final Side? fixedBottomSide;
  final bool allowStockfishFallback;
  final LiveGamesBatchKey? liveBatchKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottomSide = fixedBottomSide ?? Side.white;
    final topSide = _oppositeSide(bottomSide);

    return Column(
      children: [
        _PlayerRow(
          gamesTourModel: gamesTourModel,
          isWhitePlayer: topSide == Side.white,
          isCurrentPlayer: gamesTourModel.activePlayer == topSide,
          isPinned: isPinned,
          playerView: PlayerView.listView,
          liveBatchKey: liveBatchKey,
        ),
        SizedBox(height: 4.h),
        _ChessBoardWithEvaluation(
          gamesTourModel: gamesTourModel,
          lastMove: lastMove,
          sideBarWidth: sideBarWidth,
          boardSize: boardSize,
          playerView: PlayerView.listView,
          showEvalBar: showEvalBar,
          showCoordinates: false,
          orientation: bottomSide,
          allowStockfishFallback: allowStockfishFallback,
        ),
        SizedBox(height: 4.h),
        _PlayerRow(
          gamesTourModel: gamesTourModel,
          isWhitePlayer: bottomSide == Side.white,
          isCurrentPlayer: gamesTourModel.activePlayer == bottomSide,
          isPinned: false,
          playerView: PlayerView.listView,
          liveBatchKey: liveBatchKey,
        ),
      ],
    );
  }
}

class _ChessBoardContent extends ConsumerWidget {
  const _ChessBoardContent({
    required this.gamesTourModel,
    required this.lastMove,
    required this.boardSize,
    required this.isPinned,
    required this.fixedBottomSide,
    required this.allowStockfishFallback,
    required this.liveBatchKey,
  });

  final GamesTourModel gamesTourModel;
  final Move? lastMove;
  final Size boardSize;
  final bool isPinned;
  final Side? fixedBottomSide;
  final bool allowStockfishFallback;
  final LiveGamesBatchKey? liveBatchKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hideFinishedSpoilers = _hideFinishedSpoilers(ref, gamesTourModel);
    final showEvalBar =
        _shouldShowEvalBar(ref) &&
        gamesTourModel.hasStarted &&
        !hideFinishedSpoilers;
    final sideBarWidth = showEvalBar ? 20.w : 0.w;
    final bottomSide = fixedBottomSide ?? Side.white;
    final topSide = _oppositeSide(bottomSide);

    return SizedBox(
      width: boardSize.width,
      height: boardSize.height,
      child: Padding(
        padding: EdgeInsets.only(left: 24.sp, right: 24.sp, bottom: 8.sp),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Get width AFTER padding is applied
            final availableWidth = constraints.maxWidth;
            // Board size is available width minus the evaluation bar
            final chessBoardSize = availableWidth - sideBarWidth;

            return Column(
              children: [
                _PlayerRow(
                  gamesTourModel: gamesTourModel,
                  isWhitePlayer: topSide == Side.white,
                  isCurrentPlayer: gamesTourModel.activePlayer == topSide,
                  isPinned: isPinned,
                  playerView: PlayerView.listView,
                  liveBatchKey: liveBatchKey,
                ),
                SizedBox(height: 4.h),
                _ChessBoardWithEvaluation(
                  gamesTourModel: gamesTourModel,
                  lastMove: lastMove,
                  sideBarWidth: sideBarWidth,
                  boardSize: chessBoardSize,
                  playerView: PlayerView.listView,
                  showEvalBar: showEvalBar,
                  showCoordinates: false,
                  orientation: bottomSide,
                  allowStockfishFallback: allowStockfishFallback,
                ),
                SizedBox(height: 4.h),
                _PlayerRow(
                  gamesTourModel: gamesTourModel,
                  isWhitePlayer: bottomSide == Side.white,
                  isCurrentPlayer: gamesTourModel.activePlayer == bottomSide,
                  isPinned: false,
                  playerView: PlayerView.listView,
                  liveBatchKey: liveBatchKey,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.gamesTourModel,
    required this.isWhitePlayer,
    required this.isCurrentPlayer,
    required this.isPinned,
    required this.playerView,
    this.liveBatchKey,
  });

  final GamesTourModel gamesTourModel;
  final bool isWhitePlayer;
  final bool isCurrentPlayer;
  final bool isPinned;
  final PlayerView playerView;
  final LiveGamesBatchKey? liveBatchKey;

  @override
  Widget build(BuildContext context) {
    return PlayerFirstRowDetailWidget(
      gamesTourModel: gamesTourModel,
      isWhitePlayer: isWhitePlayer,
      isCurrentPlayer: isCurrentPlayer,
      playerView: playerView,
      isPinned: isPinned,
      showClock: gamesTourModel.hasStarted,
      liveBatchKey: liveBatchKey,
    );
  }
}

class _ChessBoardWithEvaluation extends ConsumerWidget {
  const _ChessBoardWithEvaluation({
    required this.gamesTourModel,
    required this.lastMove,
    required this.sideBarWidth,
    required this.boardSize,
    required this.playerView,
    required this.showEvalBar,
    required this.orientation,
    this.showCoordinates = true,
    this.allowStockfishFallback = true,
  });

  final GamesTourModel gamesTourModel;
  final Move? lastMove;
  final double sideBarWidth;
  final double boardSize;
  final PlayerView playerView;
  final bool showEvalBar;
  final Side orientation;
  final bool showCoordinates;
  final bool allowStockfishFallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Get effective game status for ended games
    final hideFinishedSpoilers = _hideFinishedSpoilers(ref, gamesTourModel);
    final gameStatus =
        hideFinishedSpoilers ? GameStatus.ongoing : gamesTourModel.gameStatus;
    final resolvedFen = ref.watch(
      _resolvedFenProvider(_ResolvedFenKey.fromGame(gamesTourModel)),
    );

    if (!showEvalBar || !gamesTourModel.hasStarted) {
      return _ChessBoardWidget(
        fen: resolvedFen,
        lastMove: lastMove,
        boardSize: boardSize,
        showCoordinates: showCoordinates,
        gameStatus: gameStatus,
        orientation: orientation,
      );
    }

    return Row(
      children: [
        EvaluationBarWidgetForGames(
          width: sideBarWidth,
          height: boardSize,
          fen: resolvedFen,
          playerView: playerView,
          isFlipped: orientation == Side.black,
          allowStockfishFallback: allowStockfishFallback,
        ),
        _ChessBoardWidget(
          fen: resolvedFen,
          lastMove: lastMove,
          boardSize: boardSize,
          showCoordinates: showCoordinates,
          gameStatus: gameStatus,
          orientation: orientation,
        ),
      ],
    );
  }
}

class _ChessBoardWidget extends ConsumerWidget {
  const _ChessBoardWidget({
    required this.fen,
    required this.lastMove,
    required this.boardSize,
    required this.orientation,
    this.showCoordinates = true,
    this.gameStatus,
  });

  final String? fen;
  final Move? lastMove;
  final double boardSize;
  final Side orientation;
  final bool showCoordinates;
  final GameStatus? gameStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardSettingsAsync = ref.watch(boardSettingsProviderNew);
    final boardSettings =
        boardSettingsAsync.valueOrNull ?? const BoardSettingsNew();

    // Check if game has ended with a winner or draw
    final isGameEnded = gameStatus?.isFinished ?? false;
    final isWhiteWins = gameStatus == GameStatus.whiteWins;
    final isBlackWins = gameStatus == GameStatus.blackWins;
    final isDraw = gameStatus == GameStatus.draw;

    // Parse FEN to find king positions
    final rawFen = (fen ?? '').trim();
    final setup = _tryParseFen(rawFen);
    String displayFen = setup != null ? rawFen : _kStartFen;
    Square? loserKingSquare;
    Square? whiteKingSquare;
    Square? blackKingSquare;

    if (isGameEnded && setup != null) {
      // Find kings directly from setup board pieces (much faster than Chess.fromSetup)
      for (final (square, piece) in setup.board.pieces) {
        if (piece.role == Role.king) {
          if (piece.color == Side.white) {
            whiteKingSquare = square;
          } else {
            blackKingSquare = square;
          }
        }
      }

      if (isWhiteWins && blackKingSquare != null) {
        loserKingSquare = blackKingSquare;
        displayFen = _removeKingFromFen(displayFen, loserKingSquare, 'k');
      } else if (isBlackWins && whiteKingSquare != null) {
        loserKingSquare = whiteKingSquare;
        displayFen = _removeKingFromFen(displayFen, loserKingSquare, 'K');
      }
    }

    final chessboard = RepaintBoundary(
      child: Container(
        height: boardSize,
        width: boardSize,
        decoration: BoxDecoration(
          // Light theme: layered drop shadow grounds the board on the
          // light-grey scaffold (Principle 3 — shadows over borders). Dark
          // theme keeps the original soft kBoardLightGrey shadow.
          boxShadow:
              context.isLightTheme
                  ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 1,
                      offset: const Offset(0, 1),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ]
                  : [
                    BoxShadow(
                      color: kBoardLightGrey.withValues(alpha: 0.5),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
        ),
        child: AbsorbPointer(
          child: Chessboard.fixed(
            size: boardSize,
            settings: ChessboardSettings(
              enableCoordinates:
                  showCoordinates && boardSettings.showCoordinates,
              // Use theme colors from settings with our custom app colors
              colorScheme: boardSettings.colorScheme,
              // Use piece set from settings
              pieceAssets: boardSettings.pieceAssets,
            ),
            orientation: orientation,
            fen: displayFen,
            lastMove: lastMove,
          ),
        ),
      ),
    );

    // Add fallen king overlay for wins
    if ((isWhiteWins || isBlackWins) && loserKingSquare != null) {
      final squareSize = boardSize / 8;
      final loserSide = isWhiteWins ? Side.black : Side.white;
      final pieceKind =
          loserSide == Side.white ? PieceKind.whiteKing : PieceKind.blackKing;
      final pieceImage = boardSettings.pieceAssets[pieceKind];

      final loserKingOffset = _orientedSquareOffset(
        loserKingSquare,
        squareSize,
        orientation,
      );

      return SizedBox(
        width: boardSize,
        height: boardSize,
        child: Stack(
          children: [
            chessboard,
            // Red background for loser's king square
            _SquareHighlight(
              left: loserKingOffset.left,
              top: loserKingOffset.top,
              squareSize: squareSize,
              color: const Color(0xCCF53236), // Red with alpha
            ),
            _SmallFallenKingOverlay(
              left: loserKingOffset.left,
              top: loserKingOffset.top,
              squareSize: squareSize,
              pieceImage: pieceImage!,
            ),
          ],
        ),
      );
    }

    // Add dove icons for draws
    if (isDraw && whiteKingSquare != null && blackKingSquare != null) {
      final squareSize = boardSize / 8;
      final whiteKingCg = Square.fromName(whiteKingSquare.name);
      final blackKingCg = Square.fromName(blackKingSquare.name);
      final whiteKingOffset = _orientedSquareOffset(
        whiteKingCg,
        squareSize,
        orientation,
      );
      final blackKingOffset = _orientedSquareOffset(
        blackKingCg,
        squareSize,
        orientation,
      );

      return SizedBox(
        width: boardSize,
        height: boardSize,
        child: Stack(
          children: [
            chessboard,
            // Mint/teal background for white king's square
            _SquareHighlight(
              left: whiteKingOffset.left,
              top: whiteKingOffset.top,
              squareSize: squareSize,
              color: const Color(0xCCADE1CD), // Mint green with alpha
            ),
            // Mint/teal background for black king's square
            _SquareHighlight(
              left: blackKingOffset.left,
              top: blackKingOffset.top,
              squareSize: squareSize,
              color: const Color(0xCCADE1CD), // Mint green with alpha
            ),
            _SmallPeaceIcon(
              square: whiteKingCg,
              squareSize: squareSize,
              orientation: orientation,
              delayMs: 0,
            ),
            _SmallPeaceIcon(
              square: blackKingCg,
              squareSize: squareSize,
              orientation: orientation,
              delayMs: 100,
            ),
          ],
        ),
      );
    }

    return chessboard;
  }

  /// Remove a king from FEN string to hide it when showing fallen king overlay
  static String _removeKingFromFen(String fen, Square square, String kingChar) {
    final parts = fen.split(' ');
    if (parts.isEmpty) return fen;

    final ranks = parts[0].split('/');
    final rankIndex = 7 - square.rank;
    if (rankIndex < 0 || rankIndex >= ranks.length) return fen;

    final rank = ranks[rankIndex];
    final expanded = StringBuffer();
    for (final char in rank.split('')) {
      final digit = int.tryParse(char);
      if (digit != null) {
        expanded.write('1' * digit);
      } else {
        expanded.write(char);
      }
    }

    final fileIndex = square.file;
    final chars = expanded.toString().split('');
    if (fileIndex >= 0 &&
        fileIndex < chars.length &&
        chars[fileIndex] == kingChar) {
      chars[fileIndex] = '1';
    }

    final compressed = StringBuffer();
    int emptyCount = 0;
    for (final char in chars) {
      if (char == '1') {
        emptyCount++;
      } else {
        if (emptyCount > 0) {
          compressed.write(emptyCount);
          emptyCount = 0;
        }
        compressed.write(char);
      }
    }
    if (emptyCount > 0) {
      compressed.write(emptyCount);
    }

    ranks[rankIndex] = compressed.toString();
    parts[0] = ranks.join('/');
    return parts.join(' ');
  }
}

/// Fallen king overlay for small boards (grid/list views)
class _SmallFallenKingOverlay extends StatefulWidget {
  final double left;
  final double top;
  final double squareSize;
  final ImageProvider pieceImage;

  const _SmallFallenKingOverlay({
    required this.left,
    required this.top,
    required this.squareSize,
    required this.pieceImage,
  });

  @override
  State<_SmallFallenKingOverlay> createState() =>
      _SmallFallenKingOverlayState();
}

class _SmallFallenKingOverlayState extends State<_SmallFallenKingOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _rotationAnimation = Tween<double>(begin: 0, end: -0.785398) // -45 degrees
    .chain(CurveTween(curve: Curves.elasticOut)).animate(_controller);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.left,
      top: widget.top,
      child: SizedBox(
        width: widget.squareSize,
        height: widget.squareSize,
        child: Center(
          child: AnimatedBuilder(
            animation: _rotationAnimation,
            builder: (context, child) {
              return Transform.rotate(
                angle: _rotationAnimation.value,
                alignment: Alignment.center,
                child: child,
              );
            },
            child: Image(image: widget.pieceImage, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}

/// Square highlight overlay for game ending effects
class _SquareHighlight extends StatelessWidget {
  final double left;
  final double top;
  final double squareSize;
  final Color color;

  const _SquareHighlight({
    required this.left,
    required this.top,
    required this.squareSize,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: top,
      child: Container(width: squareSize, height: squareSize, color: color),
    );
  }
}

/// Peace icon (dove) overlay for small boards (grid/list views)
class _SmallPeaceIcon extends StatefulWidget {
  final Square square;
  final double squareSize;
  final Side orientation;
  final int delayMs;

  const _SmallPeaceIcon({
    required this.square,
    required this.squareSize,
    required this.orientation,
    required this.delayMs,
  });

  @override
  State<_SmallPeaceIcon> createState() => _SmallPeaceIconState();
}

class _SmallPeaceIconState extends State<_SmallPeaceIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).chain(CurveTween(curve: Curves.elasticOut)).animate(_controller);

    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offset = _orientedSquareOffset(
      widget.square,
      widget.squareSize,
      widget.orientation,
    );

    // Scale down for smaller boards
    final containerSize = widget.squareSize * 0.28;

    return Positioned(
      left: offset.left + widget.squareSize - containerSize - 1,
      top: offset.top + 1,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            alignment: Alignment.topRight,
            child: child,
          );
        },
        child: Container(
          width: containerSize,
          height: containerSize,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Center(
            child: ColorFiltered(
              colorFilter: const ColorFilter.mode(
                Colors.black,
                BlendMode.srcIn,
              ),
              child: Text(
                '🕊️',
                style: TextStyle(fontSize: containerSize * 0.6),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
