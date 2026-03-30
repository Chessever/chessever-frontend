import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/chess_progress_bar.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/string_utils_provider.dart';
import 'package:chessever2/widgets/app_button.dart';
import 'package:chessever2/widgets/atomic_countdown_text.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';
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
    return TappableScale(
      onTap: () {
        HapticFeedbackService.cardTap();
        onTap();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: (details) {
          HapticFeedbackService.contextMenu();
          _showBlurredPopup(context, ref: ref, details: details);
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
      ),
    );
  }

  void _showBlurredPopup(
    BuildContext context, {
    required WidgetRef ref,
    required LongPressStartDetails details,
  }) {
    final RenderBox cardRenderBox = context.findRenderObject() as RenderBox;
    final Offset cardPosition = cardRenderBox.localToGlobal(Offset.zero);
    final Size cardSize = cardRenderBox.size;

    final double screenHeight = MediaQuery.of(context).size.height;
    final double popupHeight = 81.h;
    final double spaceBelow =
        screenHeight - (cardPosition.dy + cardSize.height);

    bool showAbove = spaceBelow < popupHeight;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: Duration.zero, // Motor handles animation
      pageBuilder: (
        BuildContext buildContext,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
      ) {
        final double menuTop =
            showAbove
                ? cardPosition.dy - popupHeight - 8.sp
                : cardPosition.dy + cardSize.height + 8.sp;
        return _MotorPopupWrapper(
          cardPosition: cardPosition,
          cardSize: cardSize,
          menuPosition: Offset(details.globalPosition.dx - 60.w, menuTop),
          matchComparison: matchComparison,
          isPinned: isPinned,
          onDismiss: () => Navigator.of(buildContext).pop(),
          onPinToggle: () {
            onPinToggle(matchComparison.game);
            Future.microtask(() {
              Navigator.pop(buildContext);
            });
          },
          onShare: () {
            Navigator.pop(buildContext);
          },
        );
      },
    );
  }
}

class _GameCardContent extends ConsumerWidget {
  const _GameCardContent({
    required this.matchComparison,
    this.showClock = true,
  });

  final MatchWithComparison matchComparison;
  final bool showClock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _TopSection(matchComparison: matchComparison),
        _BottomSection(matchComparison: matchComparison, showClock: showClock),
      ],
    );
  }
}

/// Public wrapper for GameCardContent to be used in other screens
class GamesTourGameCardBody extends ConsumerWidget {
  const GamesTourGameCardBody({
    required this.matchComparison,
    this.eventName,
    this.showClock = true,
    super.key,
  });

  final MatchWithComparison matchComparison;
  final String? eventName;
  final bool showClock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Event name header (only shown when eventName is provided)
        if (eventName != null && eventName!.isNotEmpty)
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
            decoration: BoxDecoration(
              color: kBlack3Color,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12.br),
                topRight: Radius.circular(12.br),
              ),
            ),
            child: Text(
              eventName!,
              style: AppTypography.textXsMedium.copyWith(
                color: kWhiteColor.withValues(alpha: 0.7),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        // Main card content with adjusted corners
        ClipRRect(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(
              eventName != null && eventName!.isNotEmpty ? 0 : 12.br,
            ),
            topRight: Radius.circular(
              eventName != null && eventName!.isNotEmpty ? 0 : 12.br,
            ),
            bottomLeft: Radius.circular(12.br),
            bottomRight: Radius.circular(12.br),
          ),
          child: _GameCardContent(
            matchComparison: matchComparison,
            showClock: showClock,
          ),
        ),
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
      padding: EdgeInsets.symmetric(horizontal: 16.sp),
      decoration: BoxDecoration(
        color: kWhiteColor70,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(12.br),
          topRight: Radius.circular(12.br),
        ),
      ),
      child: Row(
        children: [
          Expanded(child: _GamesRound(player: player1)),
          Expanded(child: _CenterContent(matchWithComparison: matchComparison)),
          Expanded(child: _GamesRound(player: player2)),
        ],
      ),
    );
  }
}

class _CenterContent extends ConsumerWidget {
  const _CenterContent({required this.matchWithComparison});

  final MatchWithComparison matchWithComparison;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use effectiveGameStatus to handle DB update lag
    final effectiveStatus = matchWithComparison.game.effectiveGameStatus;

    // Check if engine gauge is enabled in settings
    final showEngineGauge = ref.watch(
      engineSettingsProviderNew.select(
        (state) => state.valueOrNull?.showEngineGauge ?? true,
      ),
    );

    // If game is not ongoing, show result text
    if (effectiveStatus != GameStatus.ongoing) {
      return Center(
        child: StatusText(status: _displayTextSupporter(matchWithComparison)),
      );
    }

    // If game hasn't started yet, show "VS" instead of eval bar
    if (!matchWithComparison.game.hasStarted) {
      return Center(child: StatusText(status: 'VS', color: kBlack2Color));
    }

    // If engine gauge is disabled, show "LIVE" indicator instead of progress bar
    if (!showEngineGauge) {
      return Center(child: StatusText(status: 'LIVE', color: kPrimaryColor));
    }

    // Show the eval progress bar
    return Center(
      child:
          matchWithComparison.comparison == MatchComparison.sameOrder
              ? ChessProgressBar(gamesTourModel: matchWithComparison.game)
              : ChessProgressBar.reversedMode(
                gamesTourModel: matchWithComparison.game,
              ),
    );
  }
}

class _BottomSection extends ConsumerWidget {
  const _BottomSection({required this.matchComparison, this.showClock = true});

  final MatchWithComparison matchComparison;
  final bool showClock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastMoveWidget = Expanded(
      child: _LastMoveNotation(
        lastMove: matchComparison.game.lastMove,
        fen: matchComparison.game.fen,
      ),
    );

    // When clocks are hidden or game hasn't started, handle accordingly
    if (!showClock || !matchComparison.game.hasStarted) {
      return Container(
        height: 24.h,
        padding: EdgeInsets.symmetric(horizontal: 16.sp),
        decoration: BoxDecoration(
          color: kBlack2Color,
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(12.br),
            bottomRight: Radius.circular(12.br),
          ),
        ),
        child: Row(children: [lastMoveWidget]),
      );
    }

    return Container(
      height: 24.h,
      padding: EdgeInsets.symmetric(horizontal: 16.sp),
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
                  SizedBox(
                    width: 60.w, // Fixed width for clock
                    child: _TimerWidget(
                      turn: matchComparison.game.activePlayer == Side.white,
                      time: matchComparison.game.whiteTimeDisplay,
                      gamesTourModel: matchComparison.game,
                      isWhitePlayer: true,
                    ),
                  ),
                  lastMoveWidget,
                  SizedBox(
                    width: 60.w, // Fixed width for clock
                    child: _TimerWidget(
                      turn: matchComparison.game.activePlayer == Side.black,
                      time: matchComparison.game.blackTimeDisplay,
                      gamesTourModel: matchComparison.game,
                      isWhitePlayer: false,
                    ),
                  ),
                ]
                : [
                  SizedBox(
                    width: 60.w, // Fixed width for clock
                    child: _TimerWidget(
                      turn: matchComparison.game.activePlayer == Side.black,
                      time: matchComparison.game.blackTimeDisplay,
                      gamesTourModel: matchComparison.game,
                      isWhitePlayer: false,
                    ),
                  ),
                  lastMoveWidget,
                  SizedBox(
                    width: 60.w, // Fixed width for clock
                    child: _TimerWidget(
                      turn: matchComparison.game.activePlayer == Side.white,
                      time: matchComparison.game.whiteTimeDisplay,
                      gamesTourModel: matchComparison.game,
                      isWhitePlayer: true,
                    ),
                  ),
                ],
      ),
    );
  }
}

class _GamesRound extends ConsumerWidget {
  const _GamesRound({required this.player, super.key});

  final PlayerCard player;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final federationForFlag =
        player.countryCode.trim().isNotEmpty
            ? player.countryCode
            : (player.federation.trim().isNotEmpty ? player.federation : 'FID');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          ref.read(stringUtilsProvider).getTrimmedString(player.name),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.textXsMedium.copyWith(color: kBlackColor),
        ),
        Row(
          children: [
            FederationFlag(
              federation: federationForFlag,
              height: 12.h,
              width: 16.w,
              borderRadius: BorderRadius.circular(2.br),
            ),
            SizedBox(width: 4.w),
            Flexible(
              child: Text(
                '${player.title} ${player.rating}',
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

    return Center(
      child: AtomicCountdownText(
        clockSeconds:
            clockSeconds, // Primary source: time in seconds from last_clock fields
        clockCentiseconds:
            clockCentiseconds, // Fallback source: raw database clock
        lastMoveTime: gamesTourModel.lastMoveTime,
        isActive:
            isClockRunning, // Clock frozen if game is effectively finished
        style: AppTypography.textXsMedium.copyWith(
          color:
              isGameFinished
                  ? kWhiteColor
                  : (turn ? kPrimaryColor : kWhiteColor),
        ),
      ),
    );
  }
}

class _LastMoveNotation extends StatelessWidget {
  const _LastMoveNotation({required this.lastMove, required this.fen});

  final String? lastMove;
  final String? fen;

  /// Extracts move number and side from FEN
  /// Returns (moveNumber, wasWhiteMove) or null if parsing fails
  (int, bool)? _getMoveInfo() {
    if (fen == null || fen!.isEmpty) return null;

    try {
      final parts = fen!.split(' ');
      if (parts.length < 6) return null;

      final sideToMove = parts[1]; // 'w' or 'b'
      final fullmoveNumber = int.tryParse(parts[5]);

      if (fullmoveNumber == null) return null;

      // If it's black's turn, white just moved (use fullmove number)
      // If it's white's turn, black just moved (use fullmove - 1)
      if (sideToMove == 'b') {
        return (fullmoveNumber, true); // White just moved
      } else {
        return (fullmoveNumber - 1, false); // Black just moved
      }
    } catch (e) {
      return null;
    }
  }

  /// Converts UCI move (like "b8e8") to SAN notation (like "Re8", "Nf3", etc.)
  String? _convertUciToSan() {
    if (lastMove == null || lastMove!.isEmpty) {
      return null;
    }

    // If FEN is not available, at least show the destination square
    if (fen == null || fen!.isEmpty) {
      // Extract just the destination square from UCI
      if (lastMove!.length >= 4) {
        return lastMove!.substring(2, 4);
      }
      return null;
    }

    try {
      // Parse UCI move manually (format: "e2e4" or "e7e8q" for promotion)
      if (lastMove!.length < 4) return null;

      final fromSquare = lastMove!.substring(0, 2);
      final toSquare = lastMove!.substring(2, 4);
      final promotion = lastMove!.length == 5 ? lastMove![4] : null;

      // Parse the current FEN (position AFTER the move)
      final currentSetup = Setup.parseFen(fen!);
      final currentPosition = Chess.fromSetup(currentSetup);

      // Parse destination square using dartchess
      final move = Move.parse(lastMove!);
      if (move == null) {
        // If Move.parse fails, just return destination square
        return toSquare;
      }

      // Get the piece at the destination square in current position
      final destSquare = move.to;
      final piece = currentPosition.board.pieceAt(destSquare);

      if (piece == null) {
        // Castling moves: O-O or O-O-O
        if ((fromSquare == 'e1' && (toSquare == 'g1' || toSquare == 'c1')) ||
            (fromSquare == 'e8' && (toSquare == 'g8' || toSquare == 'c8'))) {
          return toSquare == 'g1' || toSquare == 'g8' ? 'O-O' : 'O-O-O';
        }
        // Move might have been a capture, just return destination
        return toSquare;
      }

      // Format the move based on piece type
      final pieceSymbol = _getPieceSymbol(piece.role);
      final moveStr = StringBuffer();

      // Add piece symbol (except for pawns)
      if (piece.role != Role.pawn) {
        moveStr.write(pieceSymbol);
      }

      // For pawn captures, include the file
      if (piece.role == Role.pawn && fromSquare[0] != toSquare[0]) {
        moveStr.write(fromSquare[0]); // from file letter
        moveStr.write('x');
      }

      // Add destination square
      moveStr.write(toSquare);

      // Add promotion piece if any
      if (promotion != null) {
        moveStr.write('=');
        moveStr.write(promotion.toUpperCase());
      }

      // Add check/checkmate symbols if needed
      if (currentPosition.isCheckmate) {
        moveStr.write('#');
      } else if (currentPosition.isCheck) {
        moveStr.write('+');
      }

      return moveStr.toString();
    } catch (e) {
      // If conversion fails, at least return the destination square
      if (lastMove!.length >= 4) {
        return lastMove!.substring(2, 4);
      }
      return null;
    }
  }

  String _getPieceSymbol(Role role) {
    switch (role) {
      case Role.king:
        return 'K';
      case Role.queen:
        return 'Q';
      case Role.rook:
        return 'R';
      case Role.bishop:
        return 'B';
      case Role.knight:
        return 'N';
      case Role.pawn:
        return '';
    }
  }

  /// Formats the move with move number (e.g., "49.Ba3" or "49...Ba3")
  String _formatMoveWithNumber(String move) {
    final moveInfo = _getMoveInfo();
    if (moveInfo == null) return move;

    final (moveNumber, wasWhiteMove) = moveInfo;
    if (moveNumber <= 0) return move;

    if (wasWhiteMove) {
      return '$moveNumber.$move';
    } else {
      return '$moveNumber...$move';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Try to convert UCI to SAN
    final sanMove = _convertUciToSan();

    // Display the converted SAN move if successful
    // If conversion fails but we have lastMove, show the raw lastMove as fallback
    // This ensures we always show something if a move exists
    final moveNotation = sanMove ?? lastMove;

    if (moveNotation == null || moveNotation.isEmpty) {
      return const SizedBox.shrink();
    }

    // Format with move number
    final displayText = _formatMoveWithNumber(moveNotation);

    return Center(
      child: Text(
        displayText,
        style: AppTypography.textXsMedium.copyWith(color: kWhiteColor),
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
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

/// Motor-powered popup wrapper for smooth spring animations
class _MotorPopupWrapper extends StatefulWidget {
  const _MotorPopupWrapper({
    required this.cardPosition,
    required this.cardSize,
    required this.menuPosition,
    required this.matchComparison,
    required this.isPinned,
    required this.onDismiss,
    required this.onPinToggle,
    required this.onShare,
  });

  final Offset cardPosition;
  final Size cardSize;
  final Offset menuPosition;
  final MatchWithComparison matchComparison;
  final bool isPinned;
  final VoidCallback onDismiss;
  final VoidCallback onPinToggle;
  final VoidCallback onShare;

  @override
  State<_MotorPopupWrapper> createState() => _MotorPopupWrapperState();
}

class _MotorPopupWrapperState extends State<_MotorPopupWrapper> {
  double _animationProgress = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _animationProgress = 1.0;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleMotionBuilder(
      motion: const CupertinoMotion.bouncy(),
      value: _animationProgress,
      builder: (context, value, child) {
        final scale = 0.9 + (0.1 * value);
        final opacity = value.clamp(0.0, 1.0);

        return Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: widget.onDismiss,
            child: Stack(
              children: [
                // Backdrop with animated opacity
                Opacity(
                  opacity: opacity,
                  child: SelectiveBlurBackground(
                    clearPosition: widget.cardPosition,
                    clearSize: widget.cardSize,
                  ),
                ),
                // Card content
                Positioned(
                  left: widget.cardPosition.dx,
                  top: widget.cardPosition.dy,
                  child: GestureDetector(
                    onTap: widget.onDismiss,
                    child: SizedBox(
                      width: widget.cardSize.width,
                      height: widget.cardSize.height,
                      child: Stack(
                        children: [
                          _GameCardContent(
                            matchComparison: widget.matchComparison,
                          ),
                          if (widget.isPinned)
                            PinIconOverlay(right: 8.sp, top: 4.sp),
                        ],
                      ),
                    ),
                  ),
                ),
                // Context menu with scale animation
                Positioned(
                  left: widget.menuPosition.dx,
                  top: widget.menuPosition.dy,
                  child: Opacity(
                    opacity: opacity,
                    child: Transform.scale(
                      scale: scale,
                      child: ContextPopupMenu(
                        isPinned: widget.isPinned,
                        onPinToggle: widget.onPinToggle,
                        onShare: widget.onShare,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
