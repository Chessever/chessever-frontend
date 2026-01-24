import 'dart:io' as io;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
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
  final ScreenshotController _gifFrameController = ScreenshotController();
  bool _isGenerating = false;
  bool _isGeneratingGif = false;
  double _gifProgress = 0.0;
  bool _showEvalBar = true;
  double _rotationX = 0.0;
  double _rotationY = 0.0;

  // For GIF generation - current frame position
  String? _gifFrameFen;
  Move? _gifFrameLastMove;

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

  String get _gameUrl => 'https://chessever.com/games/${widget.gameId}';

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
        text: _gameUrl,
        sharePositionOrigin: const Rect.fromLTWH(0, 0, 1, 1),
      );
    } catch (e) {
      debugPrint('Error sharing: $e');
      _showMessage('Failed to share image', isError: true);
    }
  }

  Future<void> _copyPgn() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.pgn));
      HapticFeedback.lightImpact();
      _showMessage('PGN copied to clipboard!', isError: false);
    } catch (e) {
      debugPrint('Error copying PGN: $e');
      _showMessage('Failed to copy PGN', isError: true);
    }
  }

  Future<void> _shareGif() async {
    if (_isGeneratingGif) return;

    final movesToAnimate = widget.moveSans.take(widget.currentMoveIndex + 1).toList();
    if (movesToAnimate.isEmpty) {
      _showMessage('No moves to animate', isError: true);
      return;
    }

    setState(() {
      _isGeneratingGif = true;
      _gifProgress = 0.0;
    });

    try {
      // Start from initial position
      Position position = Chess.initial;
      final frames = <img.Image>[];

      // Capture initial position
      setState(() {
        _gifFrameFen = position.fen;
        _gifFrameLastMove = null;
      });
      await Future.delayed(const Duration(milliseconds: 100));
      await WidgetsBinding.instance.endOfFrame;
      final initialFrame = await _gifFrameController.capture(pixelRatio: 2.0);
      if (initialFrame != null) {
        final decoded = img.decodeImage(initialFrame);
        if (decoded != null) {
          frames.add(decoded);
        }
      }

      // Apply each move and capture
      for (int i = 0; i < movesToAnimate.length; i++) {
        final san = movesToAnimate[i];
        final move = position.parseSan(san);
        if (move == null) continue;

        position = position.play(move);

        // Cast to NormalMove to get from/to squares for display
        final normalMove = move as NormalMove;
        final lastMove = NormalMove(from: normalMove.from, to: normalMove.to);

        setState(() {
          _gifFrameFen = position.fen;
          _gifFrameLastMove = lastMove;
          _gifProgress = (i + 1) / movesToAnimate.length;
        });

        // Wait for render
        await Future.delayed(const Duration(milliseconds: 80));
        await WidgetsBinding.instance.endOfFrame;

        final frameBytes = await _gifFrameController.capture(pixelRatio: 2.0);
        if (frameBytes != null) {
          final decoded = img.decodeImage(frameBytes);
          if (decoded != null) {
            frames.add(decoded);
          }
        }
      }

      if (frames.isEmpty) {
        _showMessage('Failed to generate frames', isError: true);
        return;
      }

      // Encode GIF
      setState(() => _gifProgress = 0.95);

      final gif = img.GifEncoder();
      for (final frame in frames) {
        // Add frame with 500ms delay (50 = 0.5 seconds in GIF time units of 1/100th sec)
        gif.addFrame(frame, duration: 50);
      }
      // Hold last frame longer
      if (frames.isNotEmpty) {
        gif.addFrame(frames.last, duration: 200);
      }

      final gifBytes = gif.finish();
      if (gifBytes == null) {
        _showMessage('Failed to encode GIF', isError: true);
        return;
      }

      // Save and share
      final tempDir = await getTemporaryDirectory();
      final file = io.File('${tempDir.path}/chessever_game.gif');
      await file.writeAsBytes(gifBytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: _gameUrl,
        sharePositionOrigin: const Rect.fromLTWH(0, 0, 1, 1),
      );
    } catch (e) {
      debugPrint('Error generating GIF: $e');
      _showMessage('Failed to generate GIF', isError: true);
    } finally {
      setState(() {
        _isGeneratingGif = false;
        _gifProgress = 0.0;
        _gifFrameFen = null;
        _gifFrameLastMove = null;
      });
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
                            showEvalBar: _showEvalBar,
                            gameId: widget.gameId,
                          ),
                        ),
                      )
                      .animate()
                      .fadeIn(duration: 300.ms)
                      .scale(begin: Offset(0.95, 0.95), duration: 300.ms),
                  SizedBox(height: 16.h),
                  // Eval bar toggle
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Show Eval Bar',
                        style: TextStyle(
                          color: kWhiteColor70,
                          fontSize: 13.sp,
                        ),
                      ),
                      SizedBox(width: 8.w),
                      SizedBox(
                        height: 24.h,
                        child: Switch.adaptive(
                          value: _showEvalBar,
                          onChanged: (value) {
                            setState(() => _showEvalBar = value);
                          },
                          activeTrackColor: kPrimaryColor,
                          activeThumbColor: kWhiteColor,
                        ),
                      ),
                    ],
                  ).animate().fadeIn(delay: 150.ms, duration: 300.ms),
                  SizedBox(height: 16.h),
                  if (_isGenerating || _isGeneratingGif)
                    Column(
                      children: [
                        if (_isGeneratingGif) ...[
                          Text(
                            'Generating GIF... ${(_gifProgress * 100).toInt()}%',
                            style: TextStyle(
                              color: kWhiteColor70,
                              fontSize: 12.sp,
                            ),
                          ),
                          SizedBox(height: 8.h),
                          SizedBox(
                            width: 200.w,
                            child: LinearProgressIndicator(
                              value: _gifProgress,
                              backgroundColor: kBlack2Color,
                              valueColor: AlwaysStoppedAnimation(kPrimaryColor),
                            ),
                          ),
                        ] else
                          CircularProgressIndicator(
                            color: kPrimaryColor,
                            strokeWidth: 2,
                          ),
                      ],
                    )
                  else
                    Column(
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _shareImage,
                              icon: Icon(Icons.image, size: 18.sp),
                              label: Text(
                                'Image',
                                style: TextStyle(
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kPrimaryColor,
                                foregroundColor: kWhiteColor,
                                padding: EdgeInsets.symmetric(
                                  vertical: 14.h,
                                  horizontal: 24.w,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10.br),
                                ),
                              ),
                            ),
                            SizedBox(width: 10.w),
                            ElevatedButton.icon(
                              onPressed: _shareGif,
                              icon: Icon(Icons.gif_box, size: 18.sp),
                              label: Text(
                                'GIF',
                                style: TextStyle(
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kPrimaryColor,
                                foregroundColor: kWhiteColor,
                                padding: EdgeInsets.symmetric(
                                  vertical: 14.h,
                                  horizontal: 24.w,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10.br),
                                ),
                              ),
                            ),
                            SizedBox(width: 10.w),
                            ElevatedButton.icon(
                              onPressed: _copyPgn,
                              icon: Icon(Icons.copy, size: 18.sp),
                              label: Text(
                                'PGN',
                                style: TextStyle(
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kBlack2Color,
                                foregroundColor: kWhiteColor,
                                padding: EdgeInsets.symmetric(
                                  vertical: 14.h,
                                  horizontal: 24.w,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10.br),
                                  side: BorderSide(
                                    color: kWhiteColor70,
                                    width: 1,
                                  ),
                                ),
                              ),
                            ),
                          ],
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
                  showEvalBar: _showEvalBar,
                  gameId: widget.gameId,
                ),
              ),
            ),
            // Offscreen GIF frame for capturing animation frames
            if (_gifFrameFen != null)
              Positioned(
                left: -10000,
                top: -10000,
                child: Screenshot(
                  controller: _gifFrameController,
                  child: _ShareCard(
                    boardSettings: widget.boardSettings,
                    positionFen: _gifFrameFen!,
                    lastMove: _gifFrameLastMove,
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
                    // Don't show clocks in GIF frames
                    whitePlayerClock: null,
                    blackPlayerClock: null,
                    tournamentName: widget.tournamentName,
                    roundInfo: widget.roundInfo,
                    currentMoveIndex: widget.currentMoveIndex,
                    // Don't show eval in GIF
                    evaluation: null,
                    mate: 0,
                    isFlipped: widget.isFlipped,
                    gameStatus: widget.gameStatus,
                    isPreview: false,
                    showEvalBar: false,
                    gameId: widget.gameId,
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
  final bool showEvalBar;
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
    this.showEvalBar = true,
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

    // Determine which player info to show at top and bottom based on isFlipped
    // When not flipped: black at top, white at bottom (normal view)
    // When flipped: white at top, black at bottom (reversed view)
    final topPlayerName = isFlipped ? whitePlayerName : blackPlayerName;
    final topPlayerCountry = isFlipped ? whiteCountry : blackCountry;
    final topPlayerElo = isFlipped ? whitePlayerElo : blackPlayerElo;
    final topPlayerTitle = isFlipped ? whitePlayerTitle : blackPlayerTitle;
    final topPlayerClock = isFlipped ? whitePlayerClock : blackPlayerClock;
    final topIsWhitePlayer = isFlipped;

    final bottomPlayerName = isFlipped ? blackPlayerName : whitePlayerName;
    final bottomPlayerCountry = isFlipped ? blackCountry : whiteCountry;
    final bottomPlayerElo = isFlipped ? blackPlayerElo : whitePlayerElo;
    final bottomPlayerTitle = isFlipped ? blackPlayerTitle : whitePlayerTitle;
    final bottomPlayerClock = isFlipped ? blackPlayerClock : whitePlayerClock;
    final bottomIsWhitePlayer = !isFlipped;

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
                if (showEvalBar) ...[
                  SizedBox(
                    width: 20.w,
                    child: _buildEndScoreWidget(isWhitePlayer: topIsWhitePlayer),
                  ),
                  SizedBox(width: 8.w),
                ],
                if (topPlayerCountry.isNotEmpty) ...[
                  CountryFlag.fromCountryCode(
                    topPlayerCountry,
                    height: 12.h,
                    width: 16.w,
                  ),
                  SizedBox(width: 8.w),
                ],
                if (topPlayerTitle != null) ...[
                  Text(
                    topPlayerTitle,
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
                    topPlayerName,
                    style: TextStyle(
                      color: kWhiteColor,
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (topPlayerElo != null)
                  Text(
                    topPlayerElo,
                    style: TextStyle(
                      color: kLightYellowColor,
                      fontSize: 10.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (topPlayerClock != null) ...[
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
                      topPlayerClock,
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
          // Board with optional evaluation bar
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.sp),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final sideBarWidth = showEvalBar ? 20.w : 0.0;
                final availableWidth = constraints.maxWidth;
                final boardSize = math.max(1.0, availableWidth - sideBarWidth);
                final fenParts = positionFen.split(' ');
                final overlayWhiteToMove =
                    fenParts.length > 1 ? fenParts[1] == 'w' : true;

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showEvalBar)
                      SizedBox(
                        width: sideBarWidth,
                        height: boardSize,
                        child: EvaluationBarWidget(
                          width: sideBarWidth,
                          height: boardSize,
                          evaluation: evaluation,
                          mate: mate != 0 ? mate : null,
                          isEvaluating: evaluation == null && mate == 0,
                          isFlipped: isFlipped,
                          isWhiteToMove: overlayWhiteToMove,
                          positionKey: positionFen,
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
                if (showEvalBar) ...[
                  SizedBox(
                    width: 20.w,
                    child: _buildEndScoreWidget(isWhitePlayer: bottomIsWhitePlayer),
                  ),
                  SizedBox(width: 8.w),
                ],
                if (bottomPlayerCountry.isNotEmpty) ...[
                  CountryFlag.fromCountryCode(
                    bottomPlayerCountry,
                    height: 12.h,
                    width: 16.w,
                  ),
                  SizedBox(width: 8.w),
                ],
                if (bottomPlayerTitle != null) ...[
                  Text(
                    bottomPlayerTitle,
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
                    bottomPlayerName,
                    style: TextStyle(
                      color: kWhiteColor,
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (bottomPlayerElo != null)
                  Text(
                    bottomPlayerElo,
                    style: TextStyle(
                      color: kLightYellowColor,
                      fontSize: 10.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (bottomPlayerClock != null) ...[
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
                      bottomPlayerClock,
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
