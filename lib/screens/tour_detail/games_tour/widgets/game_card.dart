import 'dart:ui';

import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/chess_progress_bar.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/string_utils_provider.dart';
import 'package:chessever2/widgets/app_button.dart';
import 'package:chessever2/widgets/atomic_countdown_text.dart';
import 'package:chessever2/widgets/backfilled_federation_flag.dart';
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
    this.allowStockfishFallback = true,
    super.key,
  });

  final MatchWithComparison matchComparison;
  final void Function(GamesTourModel game) onPinToggle;
  final List<String> pinnedIds;
  final Function() onTap;
  final bool allowStockfishFallback;

  bool get isPinned => pinnedIds.contains(matchComparison.game.gameId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final body = SizedBox(
      width: double.infinity,
      child: Stack(
        children: [
          _GameCardContent(
            matchComparison: matchComparison,
            allowStockfishFallback: allowStockfishFallback,
          ),
          if (isPinned) PinIconOverlay(right: 8.sp, top: 2.sp),
        ],
      ),
    );

    // In light theme, lift the card with the same iOS-style treatment as the
    // settings page _SettingCard: faint divider border + soft shadow. The
    // inner sections already round to 12br, so the outer wrapper matches.
    // Dark theme is unchanged — no wrapper.
    final wrapped = context.isLightTheme
        ? DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12.br),
              border: Border.all(
                color: context.colors.divider.withValues(alpha: 0.5),
              ),
              boxShadow: [
                BoxShadow(
                  color: context.colors.shadow,
                  blurRadius: 10,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12.br),
              child: body,
            ),
          )
        : body;

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
        child: wrapped,
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
              if (!buildContext.mounted) return;
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
    this.allowStockfishFallback = true,
  });

  final MatchWithComparison matchComparison;
  final bool showClock;
  final bool allowStockfishFallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _TopSection(
          matchComparison: matchComparison,
          allowStockfishFallback: allowStockfishFallback,
        ),
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
    this.allowStockfishFallback = true,
    super.key,
  });

  final MatchWithComparison matchComparison;
  final String? eventName;
  final bool showClock;
  final bool allowStockfishFallback;

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
              color: context.colors.surfaceRecessed,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12.br),
                topRight: Radius.circular(12.br),
              ),
            ),
            child: Text(
              eventName!,
              style: AppTypography.textXsMedium.copyWith(
                color: context.colors.textPrimary.withValues(alpha: 0.7),
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
            allowStockfishFallback: allowStockfishFallback,
          ),
        ),
      ],
    );
  }
}

class _TopSection extends ConsumerWidget {
  const _TopSection({
    required this.matchComparison,
    required this.allowStockfishFallback,
  });

  final MatchWithComparison matchComparison;
  final bool allowStockfishFallback;

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
    // Light theme: use a flat white surface card for the chip strip and let
    // the divider separate it from the bottom row. Dark theme keeps the
    // historical translucent-text-as-bg trick that the user signed off on.
    final isLight = context.isLightTheme;
    return Container(
      height: 60.h,
      padding: EdgeInsets.symmetric(horizontal: 16.sp),
      decoration: BoxDecoration(
        color: isLight ? context.colors.surface : context.colors.textPrimaryMuted,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(12.br),
          topRight: Radius.circular(12.br),
        ),
        border: isLight
            ? Border(
                bottom: BorderSide(
                  color: context.colors.divider.withValues(alpha: 0.6),
                  width: 1,
                ),
              )
            : null,
      ),
      child: Row(
        children: [
          Expanded(child: _GamesRound(player: player1)),
          Expanded(
            child: _CenterContent(
              matchWithComparison: matchComparison,
              allowStockfishFallback: allowStockfishFallback,
            ),
          ),
          Expanded(child: _GamesRound(player: player2)),
        ],
      ),
    );
  }
}

class _CenterContent extends ConsumerWidget {
  const _CenterContent({
    required this.matchWithComparison,
    required this.allowStockfishFallback,
  });

  final MatchWithComparison matchWithComparison;
  final bool allowStockfishFallback;

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

    // Status text sits on the chip strip — light theme = white surface so we
    // need a dark ink, dark theme = translucent-light bg so the original
    // kBlackColor / surface tokens read fine.
    final isLight = context.isLightTheme;

    // If game is not ongoing, show result text
    if (effectiveStatus != GameStatus.ongoing) {
      return Center(
        child: StatusText(
          status: _displayTextSupporter(matchWithComparison),
          color: isLight ? context.colors.textPrimary : kBlackColor,
        ),
      );
    }

    // If game hasn't started yet, show "VS" instead of eval bar
    if (!matchWithComparison.game.hasStarted) {
      return Center(
        child: StatusText(
          status: 'VS',
          color: isLight ? context.colors.textSecondary : context.colors.surface,
        ),
      );
    }

    // If engine gauge is disabled, show "LIVE" indicator instead of progress bar
    if (!showEngineGauge) {
      return Center(child: StatusText(status: 'LIVE', color: kPrimaryColor));
    }

    // Show the eval progress bar
    return Center(
      child:
          matchWithComparison.comparison == MatchComparison.sameOrder
              ? ChessProgressBar(
                gamesTourModel: matchWithComparison.game,
                allowStockfishFallback: allowStockfishFallback,
              )
              : ChessProgressBar.reversedMode(
                gamesTourModel: matchWithComparison.game,
                allowStockfishFallback: allowStockfishFallback,
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
          color: context.colors.surface,
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
        color: context.colors.surface,
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
  const _GamesRound({required this.player});

  final PlayerCard player;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final federationForFlag =
        player.countryCode.trim().isNotEmpty
            ? player.countryCode
            : player.federation;

    // Light theme: chip strip is a white surface, so name uses textPrimary
    // and rating uses textSecondary for hierarchy. Dark theme: chip strip is
    // a translucent-light bg, original kBlackColor / surface tokens read OK.
    final isLight = context.isLightTheme;
    final nameColor = isLight ? context.colors.textPrimary : kBlackColor;
    final ratingColor = isLight
        ? context.colors.textSecondary
        : context.colors.surface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          ref.read(stringUtilsProvider).getTrimmedString(player.name),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.textXsMedium.copyWith(color: nameColor),
        ),
        Row(
          children: [
            BackfilledFederationFlag(
              federation: federationForFlag,
              fideId: player.fideId,
              height: 12.h,
              width: 16.w,
              borderRadius: BorderRadius.circular(2.br),
            ),
            SizedBox(width: 4.w),
            Flexible(
              child: Text(
                '${player.title} ${player.rating}',
                style: AppTypography.textXsMedium.copyWith(color: ratingColor),
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
                  ? context.colors.textPrimary
                  : (turn ? kPrimaryColor : context.colors.textPrimary),
        ),
      ),
    );
  }
}

class _LastMoveNotation extends StatelessWidget {
  const _LastMoveNotation({required this.lastMove, required this.fen});

  final String? lastMove;
  final String? fen;
  static final RegExp _uciMovePattern = RegExp(
    r'^[a-h][1-8][a-h][1-8][qrbn]?$',
  );

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
    final uci = lastMove?.trim().toLowerCase();
    if (uci == null || uci.isEmpty) {
      return null;
    }

    if (!_uciMovePattern.hasMatch(uci)) return null;

    if (uci.length < 4) return null;

    final fromSquare = uci.substring(0, 2);
    final toSquare = uci.substring(2, 4);
    final promotion = uci.length == 5 ? uci[4] : null;
    final castlingSan = _castlingSan(fromSquare, toSquare);

    // If FEN is not available, at least show the destination square
    if (fen == null || fen!.isEmpty) return castlingSan ?? toSquare;

    try {
      // Parse the current FEN (position AFTER the move)
      final currentSetup = Setup.parseFen(fen!);
      final currentPosition = Chess.fromSetup(currentSetup);

      if (castlingSan != null) {
        return _withCheckSuffix(castlingSan, currentPosition);
      }

      // Parse destination square using dartchess
      final move = Move.parse(uci);
      if (move == null) {
        // If Move.parse fails, just return destination square
        return toSquare;
      }

      // Get the piece at the destination square in current position
      final destSquare = move.to;
      final piece = currentPosition.board.pieceAt(destSquare);

      if (piece == null) {
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
      return castlingSan ?? toSquare;
    }
  }

  String? _castlingSan(String fromSquare, String toSquare) {
    final rank = switch (fromSquare) {
      'e1' => '1',
      'e8' => '8',
      _ => null,
    };
    if (rank == null) return null;

    if (toSquare == 'g$rank' || toSquare == 'h$rank') return 'O-O';
    if (toSquare == 'c$rank' || toSquare == 'a$rank') return 'O-O-O';
    return null;
  }

  String _withCheckSuffix(String san, Position position) {
    if (position.isCheckmate) return '$san#';
    if (position.isCheck) return '$san+';
    return san;
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
    final displayText = formatGameCardLastMoveNotation(
      lastMove: lastMove,
      fen: fen,
    );

    if (displayText == null || displayText.isEmpty) {
      return const SizedBox.shrink();
    }

    return Center(
      child: Text(
        displayText,
        style: AppTypography.textXsMedium.copyWith(
          color: context.colors.textPrimary,
        ),
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
    );
  }
}

String? formatGameCardLastMoveNotation({
  required String? lastMove,
  required String? fen,
}) {
  final notation = _LastMoveNotation(lastMove: lastMove, fen: fen);
  final moveNotation = notation._convertUciToSan() ?? lastMove;
  if (moveNotation == null || moveNotation.isEmpty) return null;
  return notation._formatMoveWithNumber(moveNotation);
}

String _displayTextSupporter(MatchWithComparison game) {
  // Use effectiveGameStatus to show correct result even if DB hasn't updated
  final effectiveStatus = game.game.effectiveGameStatus;

  if (game.comparison == MatchComparison.sameOrder) {
    switch (effectiveStatus) {
      case GameStatus.whiteWins:
        return '1–0';
      case GameStatus.blackWins:
        return '0–1';
      case GameStatus.draw:
        return '½–½';
      case GameStatus.ongoing:
        return '*';
      case GameStatus.unknown:
        return '';
    }
  } else {
    switch (effectiveStatus) {
      case GameStatus.whiteWins:
        return '0–1';
      case GameStatus.blackWins:
        return '1–0';
      case GameStatus.draw:
        return '½–½';
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
        final menuScale = 0.9 + (0.1 * value);
        final cardScale = 0.96 + (0.04 * value);
        final opacity = value.clamp(0.0, 1.0);
        final cardLift = (1.0 - value) * 10.h;

        return Material(
          color: Colors.transparent,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onDismiss,
            child: Stack(
              children: [
                // Stronger blur + dim scrim so background imagery does not
                // visually compete with the focused card.
                Positioned.fill(
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: opacity,
                      child: ClipRect(
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: Container(
                            color: context.colors.background.withValues(alpha: 0.72),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Focused card replica
                Positioned(
                  left: widget.cardPosition.dx,
                  top: widget.cardPosition.dy - cardLift,
                  child: Opacity(
                    opacity: opacity,
                    child: Transform.scale(
                      scale: cardScale,
                      alignment: Alignment.center,
                      child: GestureDetector(
                        onTap: widget.onDismiss,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12.br),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.42),
                                blurRadius: 28,
                                spreadRadius: 2,
                                offset: const Offset(0, 18),
                              ),
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
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
                      scale: menuScale,
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
