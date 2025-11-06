import 'dart:io' as io;
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:gal/gal.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/location_service_provider.dart';
import 'package:country_flags/country_flags.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/screens/chessboard/widgets/evaluation_bar_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';

class ShareGameCardOverlay extends StatefulWidget {
  final ChessboardSettings boardSettings;
  final String positionFen;
  final Move? lastMove;
  final String pgn;
  final List<String> moveSans; // The actual move list from analysis state
  final String whitePlayerName;
  final String blackPlayerName;
  final String? whitePlayerCountry;
  final String? blackPlayerCountry;
  final String? whitePlayerElo;
  final String? blackPlayerElo;
  final String? whitePlayerTitle;
  final String? blackPlayerTitle;
  final String? whitePlayerClock;
  final String? blackPlayerClock;
  final String? tournamentName;
  final String? roundInfo;
  final int currentMoveIndex;
  final double? evaluation;
  final int mate;
  final bool isFlipped;
  final GameStatus gameStatus;
  final VoidCallback onClose;
  final String gameId; // CRITICAL: Include game ID for correct eval caching

  const ShareGameCardOverlay({
    super.key,
    required this.boardSettings,
    required this.positionFen,
    required this.lastMove,
    required this.pgn,
    required this.moveSans,
    required this.whitePlayerName,
    required this.blackPlayerName,
    this.whitePlayerCountry,
    this.blackPlayerCountry,
    this.whitePlayerElo,
    this.blackPlayerElo,
    this.whitePlayerTitle,
    this.blackPlayerTitle,
    this.whitePlayerClock,
    this.blackPlayerClock,
    this.tournamentName,
    this.roundInfo,
    required this.currentMoveIndex,
    required this.evaluation,
    required this.mate,
    required this.isFlipped,
    required this.gameStatus,
    required this.onClose,
    required this.gameId, // REQUIRED for correct eval caching
  });

  @override
  State<ShareGameCardOverlay> createState() => _ShareGameCardOverlayState();
}

class _ShareGameCardOverlayState extends State<ShareGameCardOverlay> {
  final ScreenshotController _fullScreenshotController = ScreenshotController();
  bool _isGenerating = false;
  double _rotationX = 0.0;
  double _rotationY = 0.0;

  Future<Uint8List?> _captureCard() async {
    try {
      setState(() => _isGenerating = true);

      // Wait for the widget tree to stabilize and complete painting
      // This ensures the offscreen widget is fully rendered before capture
      await Future.delayed(const Duration(milliseconds: 100));

      // Wait for the current frame to finish
      await WidgetsBinding.instance.endOfFrame;

      // Wait one more frame to be absolutely sure painting is complete
      await Future.delayed(const Duration(milliseconds: 50));

      // Capture the full card (offscreen) with all moves
      final image = await _fullScreenshotController.capture(pixelRatio: 3.0);
      return image;
    } catch (e) {
      debugPrint('Error capturing screenshot: $e');
      return null;
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  Future<void> _shareImage() async {
    final imageBytes = await _captureCard();
    if (imageBytes == null) {
      _showMessage('Failed to generate image', isError: true);
      return;
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final file = io.File('${tempDir.path}/chessever_share.png');
      await file.writeAsBytes(imageBytes);

      // Fix for iOS 16+ share dialog bug
      // Use minimal rect instead of calculating from context
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Check out this chess game on ChessEver!',
        sharePositionOrigin: const Rect.fromLTWH(0, 0, 1, 1),
      );
    } catch (e) {
      debugPrint('Error sharing: $e');
      _showMessage('Failed to share image', isError: true);
    }
  }

  Future<void> _downloadImage() async {
    // Check and request permission using Gal's built-in permission handling
    final hasAccess = await Gal.hasAccess();
    if (!hasAccess) {
      final granted = await Gal.requestAccess();
      if (!granted) {
        _showMessage(
          'Storage permission is required to save images',
          isError: true,
        );
        return;
      }
    }

    final imageBytes = await _captureCard();
    if (imageBytes == null) {
      _showMessage('Failed to generate image', isError: true);
      return;
    }

    try {
      // Use Gal's putImageBytes method to save the image
      await Gal.putImageBytes(imageBytes);
      _showMessage('Image saved to gallery!', isError: false);
    } on GalException catch (e) {
      debugPrint('Gal error: ${e.type}');
      String errorMessage = 'Failed to save image';

      switch (e.type) {
        case GalExceptionType.accessDenied:
          errorMessage = 'Permission denied to save images';
          break;
        case GalExceptionType.notEnoughSpace:
          errorMessage = 'Not enough storage space';
          break;
        case GalExceptionType.notSupportedFormat:
          errorMessage = 'Image format not supported';
          break;
        case GalExceptionType.unexpected:
          errorMessage = 'Unexpected error occurred';
          break;
      }

      _showMessage(errorMessage, isError: true);
    } catch (e) {
      debugPrint('Error saving: $e');
      _showMessage('Failed to save image', isError: true);
    }
  }

  void _showMessage(String message, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? kRedColor : kPrimaryColor,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        color: Colors.black.withValues(alpha: 0.7),
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: widget.onClose,
                behavior: HitTestBehavior.opaque,
                child: Container(color: Colors.transparent),
              ),
            ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Visible preview card with 3D effect
                  GestureDetector(
                        onPanUpdate: (details) {
                          setState(() {
                            _rotationY =
                                (details.localPosition.dx / 350.w - 0.5) * 0.15;
                            _rotationX =
                                -(details.localPosition.dy / 600.h - 0.5) *
                                0.15;
                          });
                        },
                        onPanEnd: (details) {
                          setState(() {
                            _rotationX = 0.0;
                            _rotationY = 0.0;
                          });
                        },
                        child: AnimatedContainer(
                          duration: Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                          transform:
                              Matrix4.identity()
                                ..setEntry(3, 2, 0.001)
                                ..rotateX(_rotationX)
                                ..rotateY(_rotationY),
                          transformAlignment: Alignment.center,
                          child: _ShareCard(
                            boardSettings: widget.boardSettings,
                            positionFen: widget.positionFen,
                            lastMove: widget.lastMove,
                            onClose: widget.onClose,
                            pgn: widget.pgn,
                            moveSans: widget.moveSans,
                            whitePlayerName: widget.whitePlayerName,
                            blackPlayerName: widget.blackPlayerName,
                            whitePlayerCountry: widget.whitePlayerCountry,
                            blackPlayerCountry: widget.blackPlayerCountry,
                            whitePlayerElo: widget.whitePlayerElo,
                            blackPlayerElo: widget.blackPlayerElo,
                            whitePlayerTitle: widget.whitePlayerTitle,
                            blackPlayerTitle: widget.blackPlayerTitle,
                            whitePlayerClock: widget.whitePlayerClock,
                            blackPlayerClock: widget.blackPlayerClock,
                            tournamentName: widget.tournamentName,
                            roundInfo: widget.roundInfo,
                            currentMoveIndex: widget.currentMoveIndex,
                            evaluation: widget.evaluation,
                            mate: widget.mate,
                            isFlipped: widget.isFlipped,
                            gameStatus: widget.gameStatus,
                            isPreview: true,
                            gameId: widget.gameId, // Pass game ID for correct caching
                          ),
                        ),
                      )
                      .animate()
                      .fadeIn(duration: 300.ms)
                      .scale(begin: Offset(0.95, 0.95), duration: 300.ms),
                  SizedBox(height: 20.h),
                  if (_isGenerating)
                    CircularProgressIndicator(
                      color: kPrimaryColor,
                      strokeWidth: 2,
                    )
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(left: 40.w),
                            child: ElevatedButton.icon(
                              onPressed: _downloadImage,
                              icon: Icon(Icons.download, size: 20.sp),
                              label: Text(
                                'Download',
                                style: TextStyle(
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kBlack2Color,
                                foregroundColor: kWhiteColor,
                                padding: EdgeInsets.symmetric(vertical: 12.h),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10.br),
                                  side: BorderSide(
                                    color: kWhiteColor70,
                                    width: 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 16.w),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(right: 40.w),
                            child: ElevatedButton.icon(
                              onPressed: _shareImage,
                              icon: Icon(Icons.share, size: 20.sp),
                              label: Text(
                                'Share',
                                style: TextStyle(
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kPrimaryColor,
                                foregroundColor: kWhiteColor,
                                padding: EdgeInsets.symmetric(vertical: 12.h),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10.br),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ).animate().fadeIn(delay: 200.ms, duration: 300.ms),
                ],
              ),
            ),
            // Offscreen full card for screenshot (with all moves)
            // Position off-screen instead of using Offstage to ensure proper rendering
            Positioned(
              left: -10000,
              top: -10000,
              child: Screenshot(
                controller: _fullScreenshotController,
                child: _ShareCard(
                  boardSettings: widget.boardSettings,
                  positionFen: widget.positionFen,
                  lastMove: widget.lastMove,
                  onClose: null,
                  pgn: widget.pgn,
                  moveSans: widget.moveSans,
                  whitePlayerName: widget.whitePlayerName,
                  blackPlayerName: widget.blackPlayerName,
                  whitePlayerCountry: widget.whitePlayerCountry,
                  blackPlayerCountry: widget.blackPlayerCountry,
                  whitePlayerElo: widget.whitePlayerElo,
                  blackPlayerElo: widget.blackPlayerElo,
                  whitePlayerTitle: widget.whitePlayerTitle,
                  blackPlayerTitle: widget.blackPlayerTitle,
                  whitePlayerClock: widget.whitePlayerClock,
                  blackPlayerClock: widget.blackPlayerClock,
                  tournamentName: widget.tournamentName,
                  roundInfo: widget.roundInfo,
                  currentMoveIndex: widget.currentMoveIndex,
                  evaluation: widget.evaluation,
                  mate: widget.mate,
                  isFlipped: widget.isFlipped,
                  gameStatus: widget.gameStatus,
                  isPreview: false,
                  gameId: widget.gameId, // Pass game ID for correct caching
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareCard extends ConsumerWidget {
  final ChessboardSettings boardSettings;
  final String positionFen;
  final Move? lastMove;
  final VoidCallback? onClose;
  final String pgn;
  final List<String> moveSans; // The actual move list from analysis state
  final String whitePlayerName;
  final String blackPlayerName;
  final String? whitePlayerCountry;
  final String? blackPlayerCountry;
  final String? whitePlayerElo;
  final String? blackPlayerElo;
  final String? whitePlayerTitle;
  final String? blackPlayerTitle;
  final String? whitePlayerClock;
  final String? blackPlayerClock;
  final String? tournamentName;
  final String? roundInfo;
  final int currentMoveIndex;
  final double? evaluation;
  final int mate;
  final bool isFlipped;
  final GameStatus gameStatus;
  final bool isPreview;
  final String gameId; // CRITICAL: Include game ID for correct eval caching

  const _ShareCard({
    required this.boardSettings,
    required this.positionFen,
    required this.lastMove,
    this.onClose,
    required this.pgn,
    required this.moveSans,
    required this.whitePlayerName,
    required this.blackPlayerName,
    this.whitePlayerCountry,
    this.blackPlayerCountry,
    this.whitePlayerElo,
    this.blackPlayerElo,
    this.whitePlayerTitle,
    this.blackPlayerTitle,
    this.whitePlayerClock,
    this.blackPlayerClock,
    this.tournamentName,
    this.roundInfo,
    required this.currentMoveIndex,
    required this.evaluation,
    required this.mate,
    required this.isFlipped,
    required this.gameStatus,
    this.isPreview = false,
    required this.gameId, // REQUIRED for correct eval caching
  });

  Widget _buildEndScoreWidget({required bool isWhitePlayer}) {
    // For finished games, display end scores similar to main chess board screen
    switch (gameStatus) {
      case GameStatus.whiteWins:
        return Text(
          isWhitePlayer ? '1' : '0',
          style: AppTypography.textXsBold.copyWith(
            color: kWhiteColor,
            fontSize: 12.sp,
          ),
          textAlign: TextAlign.center,
        );
      case GameStatus.blackWins:
        return Text(
          isWhitePlayer ? '0' : '1',
          style: AppTypography.textXsBold.copyWith(
            color: kWhiteColor,
            fontSize: 12.sp,
          ),
          textAlign: TextAlign.center,
        );
      case GameStatus.draw:
        return Text(
          '½',
          style: AppTypography.textXsBold.copyWith(
            color: kWhiteColor,
            fontSize: 12.sp,
          ),
          textAlign: TextAlign.center,
        );
      case GameStatus.ongoing:
      case GameStatus.unknown:
        return SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use the actual moveSans from analysis state instead of parsing PGN
    final moves = moveSans;

    final whiteCountry =
        whitePlayerCountry != null
            ? ref
                .read(locationServiceProvider)
                .getValidCountryCode(whitePlayerCountry!)
            : '';
    final blackCountry =
        blackPlayerCountry != null
            ? ref
                .read(locationServiceProvider)
                .getValidCountryCode(blackPlayerCountry!)
            : '';
    final boardOrientation = isFlipped ? Side.black : Side.white;

    final cardContent = Container(
      width: 370.w,
      decoration: BoxDecoration(
        color: kBackgroundColor,
        borderRadius: BorderRadius.circular(16.br),
        border: Border.all(color: kDividerColor, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            offset: Offset(0, 4),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 12.h),
          Image.asset('assets/pngs/premium2.png', height: 30.h),
          SizedBox(height: 6.h),
          Text(
            'ChessEver',
            style: TextStyle(
              color: kPrimaryColor,
              fontSize: 14.sp,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (tournamentName != null) ...[
            SizedBox(height: 6.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: Text(
                tournamentName!,
                style: TextStyle(
                  color: kWhiteColor,
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          if (roundInfo != null)
            Text(
              roundInfo!,
              style: TextStyle(color: kWhiteColor70, fontSize: 9.sp),
            ),
          SizedBox(height: 12.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: Row(
              children: [
                // Display end score for finished games (aligned with eval bar position)
                SizedBox(
                  width: 20.w,
                  child: _buildEndScoreWidget(isWhitePlayer: false),
                ),
                SizedBox(width: 8.w),
                if (blackCountry.isNotEmpty) ...[
                  CountryFlag.fromCountryCode(
                    blackCountry,
                    height: 12.h,
                    width: 16.w,
                  ),
                  SizedBox(width: 8.w),
                ],
                if (blackPlayerTitle != null) ...[
                  Text(
                    blackPlayerTitle!,
                    style: TextStyle(
                      color: kPrimaryColor,
                      fontSize: 10.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(width: 6.w),
                ],
                Expanded(
                  child: Text(
                    blackPlayerName,
                    style: TextStyle(
                      color: kWhiteColor,
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (blackPlayerElo != null)
                  Text(
                    blackPlayerElo!,
                    style: TextStyle(
                      color: kLightYellowColor,
                      fontSize: 10.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (blackPlayerClock != null) ...[
                  SizedBox(width: 8.w),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 6.w,
                      vertical: 2.h,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(4.br),
                    ),
                    child: Text(
                      blackPlayerClock!,
                      style: TextStyle(
                        color: kWhiteColor,
                        fontSize: 9.sp,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: 12.h),
          // Board with evaluation bar - EXACT same structure as main chess board screen
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.sp),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final sideBarWidth = 20.w;
                final availableWidth = constraints.maxWidth;
                final boardSize = math.max(1.0, availableWidth - sideBarWidth);

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: sideBarWidth,
                      height: boardSize,
                      child: EvaluationBarWidget(
                        width: sideBarWidth,
                        height: boardSize,
                        evaluation: null,
                        mate: null,
                        isEvaluating: true,
                        isFlipped: isFlipped,
                      ),
                    ),
                    SizedBox(
                      width: boardSize,
                      height: boardSize,
                      child: Chessboard(
                        size: boardSize,
                        fen: positionFen,
                        orientation: boardOrientation,
                        lastMove: lastMove,
                        game: null,
                        settings: boardSettings,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          SizedBox(height: 12.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: Row(
              children: [
                // Display end score for finished games (aligned with eval bar position)
                SizedBox(
                  width: 20.w,
                  child: _buildEndScoreWidget(isWhitePlayer: true),
                ),
                SizedBox(width: 8.w),
                if (whiteCountry.isNotEmpty) ...[
                  CountryFlag.fromCountryCode(
                    whiteCountry,
                    height: 12.h,
                    width: 16.w,
                  ),
                  SizedBox(width: 8.w),
                ],
                if (whitePlayerTitle != null) ...[
                  Text(
                    whitePlayerTitle!,
                    style: TextStyle(
                      color: kPrimaryColor,
                      fontSize: 10.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(width: 6.w),
                ],
                Expanded(
                  child: Text(
                    whitePlayerName,
                    style: TextStyle(
                      color: kWhiteColor,
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (whitePlayerElo != null)
                  Text(
                    whitePlayerElo!,
                    style: TextStyle(
                      color: kLightYellowColor,
                      fontSize: 10.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (whitePlayerClock != null) ...[
                  SizedBox(width: 8.w),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 6.w,
                      vertical: 2.h,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(4.br),
                    ),
                    child: Text(
                      whitePlayerClock!,
                      style: TextStyle(
                        color: kWhiteColor,
                        fontSize: 9.sp,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (moves.isNotEmpty) ...[
            SizedBox(height: 16.h),
            // Show current position as the LAST move + previous 20 full moves (40 individual moves)
            // Keep ACTUAL move numbers from the game - don't renumber from 1
            Builder(
              builder: (context) {
                // Show 20 full moves BEFORE the current position + the current position
                // So if current position is move 50, show moves 11-50 (40 moves total)
                const fullMovesToShowBefore =
                    20; // 20 full moves = 40 individual half-moves
                const totalIndividualMoves =
                    fullMovesToShowBefore * 2; // 40 individual half-moves

                int startIndex;
                int endIndex;

                if (moves.length <= totalIndividualMoves) {
                  // Show all moves if less than or equal to 40
                  startIndex = 0;
                  endIndex = moves.length;
                } else {
                  // Show current move as the LAST one + 39 moves before it (total 40)
                  endIndex = currentMoveIndex + 1; // Include current move
                  startIndex = (endIndex - totalIndividualMoves).clamp(
                    0,
                    moves.length,
                  );

                  // If we can't get 40 moves before current (because current is near start),
                  // extend to include more moves after current
                  if (startIndex == 0 && endIndex < totalIndividualMoves) {
                    endIndex = totalIndividualMoves.clamp(0, moves.length);
                  }
                }

                final displayMoves = moves.sublist(startIndex, endIndex);

                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  child: Wrap(
                    spacing: 2.sp,
                    runSpacing: 2.sp,
                    children: [
                      ...displayMoves.asMap().entries.map((entry) {
                        final moveIndex = startIndex + entry.key;
                        final move = entry.value;
                        final isCurrentMove = moveIndex == currentMoveIndex;

                        // USE ACTUAL MOVE NUMBERS FROM THE GAME - DON'T RENUMBER
                        final fullMoveNumber = (moveIndex / 2).floor() + 1;
                        final isWhiteMove = moveIndex % 2 == 0;

                        // EXACT same formatting as chess board screen
                        final displayText =
                            isWhiteMove ? '$fullMoveNumber. $move' : move;

                        return Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 6.sp,
                            vertical: 2.sp,
                          ),
                          decoration: BoxDecoration(
                            color:
                                isCurrentMove
                                    ? kWhiteColor70.withValues(alpha: 0.4)
                                    : Colors.transparent,
                            borderRadius: BorderRadius.circular(4.sp),
                            border: Border.all(
                              color:
                                  isCurrentMove
                                      ? kWhiteColor
                                      : Colors.transparent,
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            displayText,
                            style: TextStyle(
                              color:
                                  isCurrentMove ? kWhiteColor : kWhiteColor70,
                              fontSize: 8.5.sp,
                              fontFamily: 'monospace',
                              fontWeight:
                                  isCurrentMove
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                );
              },
            ),
          ],
          SizedBox(height: 16.h),
        ],
      ),
    );

    if (!isPreview || onClose == null) {
      return cardContent;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        cardContent,
        Positioned(
          top: 8.w,
          right: 8.w,
          child: GestureDetector(
            onTap: onClose,
            child: Container(
              padding: EdgeInsets.all(6.w),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.close, size: 16.sp, color: kWhiteColor),
            ),
          ),
        ),
      ],
    );
  }
}
