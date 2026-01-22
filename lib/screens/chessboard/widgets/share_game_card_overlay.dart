import 'dart:io' as io;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  Future<void> _shareLink() async {
    try {
      await Share.share(
        _gameUrl,
        subject: 'Check out this chess game on ChessEver!',
        sharePositionOrigin: const Rect.fromLTWH(0, 0, 1, 1),
      );
    } catch (e) {
      debugPrint('Error sharing link: $e');
      _showMessage('Failed to share link', isError: true);
    }
  }

  Future<void> _copyLink() async {
    try {
      await Clipboard.setData(ClipboardData(text: _gameUrl));
      HapticFeedback.lightImpact();
      _showMessage('Link copied to clipboard!', isError: false);
    } catch (e) {
      debugPrint('Error copying link: $e');
      _showMessage('Failed to copy link', isError: true);
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
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 40.w),
                      child: Column(
                        children: [
                          // First row: Share Image + Download
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _shareImage,
                                  icon: Icon(Icons.image, size: 18.sp),
                                  label: Text(
                                    'Share Image',
                                    style: TextStyle(
                                      fontSize: 13.sp,
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
                              SizedBox(width: 12.w),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _downloadImage,
                                  icon: Icon(Icons.download, size: 18.sp),
                                  label: Text(
                                    'Download',
                                    style: TextStyle(
                                      fontSize: 13.sp,
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
                            ],
                          ),
                          SizedBox(height: 10.h),
                          // Second row: Share Link + Copy Link
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _shareLink,
                                  icon: Icon(Icons.link, size: 18.sp),
                                  label: Text(
                                    'Share Link',
                                    style: TextStyle(
                                      fontSize: 13.sp,
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
                              SizedBox(width: 12.w),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _copyLink,
                                  icon: Icon(Icons.copy, size: 18.sp),
                                  label: Text(
                                    'Copy Link',
                                    style: TextStyle(
                                      fontSize: 13.sp,
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
                            ],
                          ),
                        ],
                      ),
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
                SizedBox(
                  width: 20.w,
                  child: _buildEndScoreWidget(isWhitePlayer: topIsWhitePlayer),
                ),
                SizedBox(width: 8.w),
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
          // Board with evaluation bar - EXACT same structure as main chess board screen
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.sp),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final sideBarWidth = 20.w;
                final availableWidth = constraints.maxWidth;
                final boardSize = math.max(1.0, availableWidth - sideBarWidth);
                final fenParts = positionFen.split(' ');
                final overlayWhiteToMove =
                    fenParts.length > 1 ? fenParts[1] == 'w' : true;

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                SizedBox(
                  width: 20.w,
                  child: _buildEndScoreWidget(isWhitePlayer: bottomIsWhitePlayer),
                ),
                SizedBox(width: 8.w),
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
