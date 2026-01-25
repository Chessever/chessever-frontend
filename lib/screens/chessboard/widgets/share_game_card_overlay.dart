import 'dart:io' as io;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';

/// Raw frame data for GIF encoding (avoids PNG encoding/decoding issues on iOS P3 displays)
class _RawFrame {
  final Uint8List rgba;
  final int width;
  final int height;
  _RawFrame(this.rgba, this.width, this.height);
}

/// Result class to pass back both data and error info from isolate
class _GifEncodeResult {
  final Uint8List? data;
  final String? error;
  final int framesProcessed;
  _GifEncodeResult({this.data, this.error, this.framesProcessed = 0});
}

/// Input data for isolate - contains raw RGBA frames
class _GifEncodeInput {
  final List<Uint8List> rgbaFrames;
  final List<int> widths;
  final List<int> heights;
  _GifEncodeInput(this.rgbaFrames, this.widths, this.heights);
}

/// Top-level function for GIF encoding in isolate (MUST be top-level or static)
/// Takes raw RGBA pixel data to avoid PNG decoding issues on iOS P3 displays
/// Duration is in 1/100 second units (centiseconds): 100 = 1 second
_GifEncodeResult _encodeGifFromRawFrames(_GifEncodeInput input) {
  if (input.rgbaFrames.isEmpty) {
    return _GifEncodeResult(error: 'No frames provided');
  }

  try {
    // Create encoder with default delay of 80 centiseconds (0.8s per move)
    final gif = img.GifEncoder(delay: 80);
    int framesAdded = 0;
    final errors = <String>[];

    for (int i = 0; i < input.rgbaFrames.length; i++) {
      try {
        final width = input.widths[i];
        final height = input.heights[i];
        final rgba = input.rgbaFrames[i];

        // Validate data
        final expectedSize = width * height * 4;
        if (rgba.length != expectedSize) {
          errors.add('Frame $i: size mismatch (got ${rgba.length}, expected $expectedSize)');
          continue;
        }

        // Create image from raw RGBA bytes
        final image = img.Image(width: width, height: height);

        // Copy RGBA data to image (more efficient bulk copy)
        for (int y = 0; y < height; y++) {
          for (int x = 0; x < width; x++) {
            final idx = (y * width + x) * 4;
            image.setPixelRgba(x, y, rgba[idx], rgba[idx + 1], rgba[idx + 2], rgba[idx + 3]);
          }
        }

        // 80 centiseconds = 800ms per frame, 300 centiseconds = 3s for last frame
        final isLastFrame = i == input.rgbaFrames.length - 1;
        gif.addFrame(image, duration: isLastFrame ? 300 : 80);
        framesAdded++;
      } catch (e) {
        errors.add('Frame $i error: $e');
        continue;
      }
    }

    if (framesAdded == 0) {
      return _GifEncodeResult(
        error: 'No frames processed. Errors: ${errors.join("; ")}',
        framesProcessed: 0,
      );
    }

    final result = gif.finish();
    if (result == null || result.isEmpty) {
      return _GifEncodeResult(
        error: 'GifEncoder.finish() returned null/empty',
        framesProcessed: framesAdded,
      );
    }

    return _GifEncodeResult(data: result, framesProcessed: framesAdded);
  } catch (e, st) {
    return _GifEncodeResult(error: 'Encoding exception: $e\nStack: $st');
  }
}

class ShareGameCardOverlay extends StatefulWidget {
  final ChessboardSettings boardSettings;
  final String positionFen;
  final Move? lastMove;
  final String pgn;
  final List<String> moveSans; // The actual move list from analysis state
  final List<String> moveTimes; // Clock times for each move (for GIF animation)
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
    this.moveTimes = const [], // Default to empty for backwards compatibility
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
  final GlobalKey _gifFrameKey = GlobalKey(); // For raw pixel capture
  bool _isGenerating = false;
  bool _isGeneratingGif = false;
  double _gifProgress = 0.0;
  bool _showEvalBar = true;
  double _rotationX = 0.0;
  double _rotationY = 0.0;

  // GIF frame state
  String? _gifFrameFen;
  NormalMove? _gifFrameLastMove;
  String? _gifFrameWhiteClock;
  String? _gifFrameBlackClock;

  // Board settings with animations disabled for instant frame capture
  ChessboardSettings get _gifBoardSettings => ChessboardSettings(
        enableCoordinates: widget.boardSettings.enableCoordinates,
        colorScheme: widget.boardSettings.colorScheme,
        pieceAssets: widget.boardSettings.pieceAssets,
        borderRadius: widget.boardSettings.borderRadius,
        boxShadow: widget.boardSettings.boxShadow,
        // CRITICAL: Disable animations for instant static frame capture
        animationDuration: Duration.zero,
      );

  /// Calculate clock times at a given move index
  /// Returns (whiteClock, blackClock) tuple
  (String?, String?) _getClocksAtMoveIndex(int moveIndex) {
    if (widget.moveTimes.isEmpty) {
      return (null, null);
    }

    String? whiteClock;
    String? blackClock;

    // Find white's most recent clock (white moves are at even indices: 0, 2, 4...)
    for (int i = moveIndex; i >= 0; i--) {
      if (i % 2 == 0 && i < widget.moveTimes.length) {
        whiteClock = widget.moveTimes[i];
        break;
      }
    }

    // Find black's most recent clock (black moves are at odd indices: 1, 3, 5...)
    for (int i = moveIndex; i >= 0; i--) {
      if (i % 2 == 1 && i < widget.moveTimes.length) {
        blackClock = widget.moveTimes[i];
        break;
      }
    }

    return (whiteClock, blackClock);
  }

  /// Capture raw RGBA pixel data from the RepaintBoundary
  /// This avoids PNG encoding issues on iOS P3 displays
  Future<_RawFrame?> _captureRawFrame(double pixelRatio) async {
    try {
      final boundary = _gifFrameKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        debugPrint('GIF: RepaintBoundary not found');
        return null;
      }

      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) {
        debugPrint('GIF: toByteData returned null');
        return null;
      }

      return _RawFrame(
        byteData.buffer.asUint8List(),
        image.width,
        image.height,
      );
    } catch (e) {
      debugPrint('GIF: Raw capture error: $e');
      return null;
    }
  }

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

  Future<void> _shareGif() async {
    if (_isGeneratingGif) return;

    final movesToAnimate =
        widget.moveSans.take(widget.currentMoveIndex + 1).toList();
    if (movesToAnimate.isEmpty) {
      _showMessage('No moves to animate', isError: true);
      return;
    }

    setState(() {
      _isGeneratingGif = true;
      _gifProgress = 0.0;
    });

    try {
      // Phase 1: Capture raw RGBA frames (avoids PNG encoding issues on iOS P3 displays)
      Position position = Chess.initial;
      final rawFrames = <_RawFrame>[];
      const pixelRatio = 1.5; // Lower ratio for smaller file size and faster encoding

      // Initial position - set state and wait for widget to build
      // At initial position (before any moves), no clocks to show yet
      setState(() {
        _gifFrameFen = position.fen;
        _gifFrameLastMove = null;
        _gifFrameWhiteClock = null;
        _gifFrameBlackClock = null;
      });
      // Wait for widget to build and paint
      await WidgetsBinding.instance.endOfFrame;
      await Future.delayed(const Duration(milliseconds: 50));

      final initial = await _captureRawFrame(pixelRatio);
      if (initial != null) {
        debugPrint('GIF: Initial frame captured (${initial.width}x${initial.height}, ${initial.rgba.length} bytes)');
        rawFrames.add(initial);
      } else {
        debugPrint('GIF WARNING: Initial frame capture returned null');
      }

      debugPrint('GIF: Processing ${movesToAnimate.length} moves...');

      // Each move - capture only the final position (no animation frames)
      for (int i = 0; i < movesToAnimate.length; i++) {
        final move = position.parseSan(movesToAnimate[i]);
        if (move == null) continue;
        position = position.play(move);

        // Extract from/to squares safely for any move type
        NormalMove? lastMoveForDisplay;
        if (move is NormalMove) {
          lastMoveForDisplay = NormalMove(from: move.from, to: move.to);
        } else {
          // For castling and other special moves, skip highlighting
          lastMoveForDisplay = null;
        }

        // Get clock times at this move index
        final (whiteClock, blackClock) = _getClocksAtMoveIndex(i);

        setState(() {
          _gifFrameFen = position.fen;
          _gifFrameLastMove = lastMoveForDisplay;
          _gifFrameWhiteClock = whiteClock;
          _gifFrameBlackClock = blackClock;
          _gifProgress = (i + 1) / movesToAnimate.length * 0.7; // 70% for capture
        });

        // Minimal wait - animations are disabled so position is instantly set
        await WidgetsBinding.instance.endOfFrame;
        await Future.delayed(const Duration(milliseconds: 30));

        final frame = await _captureRawFrame(pixelRatio);
        if (frame != null) rawFrames.add(frame);
      }

      if (rawFrames.isEmpty) {
        debugPrint('GIF ERROR: No frames were captured');
        _showMessage('No frames captured - check board rendering', isError: true);
        return;
      }

      debugPrint('GIF: Captured ${rawFrames.length} raw frames');

      // Prepare input for isolate
      final input = _GifEncodeInput(
        rawFrames.map((f) => f.rgba).toList(),
        rawFrames.map((f) => f.width).toList(),
        rawFrames.map((f) => f.height).toList(),
      );

      // Phase 2: Encode GIF in isolate (heavy work off main thread)
      setState(() => _gifProgress = 0.8);

      _GifEncodeResult result;
      try {
        result = await compute(_encodeGifFromRawFrames, input);
        debugPrint('GIF: Isolate encoding completed');
      } catch (e, st) {
        // Isolate failed (common on some iOS devices), try synchronously
        debugPrint('GIF: Isolate failed: $e');
        debugPrint('GIF: Isolate stack: $st');
        debugPrint('GIF: Trying synchronous encoding...');
        result = _encodeGifFromRawFrames(input);
      }

      if (result.error != null) {
        debugPrint('GIF ERROR: ${result.error}');
        debugPrint('GIF: Frames processed: ${result.framesProcessed}');
        // Show truncated error in UI for debugging on real devices
        final shortError = result.error!.length > 100
            ? result.error!.substring(0, 100)
            : result.error!;
        _showMessage('GIF encode failed: $shortError', isError: true);
        return;
      }

      final gifBytes = result.data;
      if (gifBytes == null || gifBytes.isEmpty) {
        debugPrint('GIF ERROR: Result data is null or empty');
        _showMessage('GIF encode returned empty data', isError: true);
        return;
      }

      debugPrint('GIF: Encoded ${gifBytes.length} bytes (${result.framesProcessed} frames)');

      // Phase 3: Save and share
      setState(() => _gifProgress = 0.95);
      final tempDir = await getTemporaryDirectory();
      final file = io.File('${tempDir.path}/chessever_game.gif');
      await file.writeAsBytes(gifBytes);

      debugPrint('GIF: Saved to ${file.path}');

      await Share.shareXFiles(
        [XFile(file.path)],
        text: _gameUrl,
        sharePositionOrigin: const Rect.fromLTWH(0, 0, 1, 1),
      );
    } catch (e, st) {
      debugPrint('GIF error: $e');
      debugPrint('GIF stack: $st');
      _showMessage('Failed to generate GIF', isError: true);
    } finally {
      setState(() {
        _isGeneratingGif = false;
        _gifProgress = 0.0;
        _gifFrameFen = null;
        _gifFrameLastMove = null;
        _gifFrameWhiteClock = null;
        _gifFrameBlackClock = null;
      });
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

  Widget _buildEvalToggle() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: kBlack2Color,
        borderRadius: BorderRadius.circular(20.br),
        border: Border.all(color: kBlack3Color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.analytics_outlined,
            size: 16.sp,
            color: _showEvalBar ? kPrimaryColor : kWhiteColor70,
          ),
          SizedBox(width: 8.w),
          Text(
            'Eval Bar',
            style: TextStyle(
              color: _showEvalBar ? kWhiteColor : kWhiteColor70,
              fontSize: 13.sp,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(width: 10.w),
          // Custom mini toggle
          GestureDetector(
            onTap: () => setState(() => _showEvalBar = !_showEvalBar),
            child: AnimatedContainer(
              duration: 200.ms,
              width: 40.w,
              height: 22.h,
              decoration: BoxDecoration(
                color: _showEvalBar ? kPrimaryColor : kBlack3Color,
                borderRadius: BorderRadius.circular(11.br),
                border: Border.all(
                  color: _showEvalBar ? kPrimaryColor : kDividerColor,
                  width: 1,
                ),
              ),
              child: AnimatedAlign(
                duration: 200.ms,
                alignment:
                    _showEvalBar ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: EdgeInsets.all(2),
                  width: 18.h,
                  height: 18.h,
                  decoration: BoxDecoration(
                    color: kWhiteColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 2,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 12.h),
          decoration: BoxDecoration(
            color: isPrimary ? kPrimaryColor : kBlack3Color,
            borderRadius: BorderRadius.circular(8.br),
            border: isPrimary ? null : Border.all(color: kDividerColor, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18.sp,
                color: isPrimary ? kWhiteColor : kWhiteColor,
              ),
              SizedBox(width: 8.w),
              Text(
                label,
                style: TextStyle(
                  color: isPrimary ? kWhiteColor : kWhiteColor,
                  fontSize: 13.sp,
                  fontWeight: isPrimary ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Container(
      width: 370.w,
      padding: EdgeInsets.all(4.w),
      decoration: BoxDecoration(
        color: kBlack2Color,
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(color: kBlack3Color),
      ),
      child: Row(
        children: [
          _buildActionButton(
            icon: Icons.image_outlined,
            label: 'Share Image',
            onTap: _shareImage,
            isPrimary: true,
          ),
          SizedBox(width: 4.w),
          _buildActionButton(
            icon: Icons.gif_box_outlined,
            label: 'Share GIF',
            onTap: _shareGif,
          ),
          SizedBox(width: 4.w),
          _buildActionButton(
            icon: Icons.copy_outlined,
            label: 'Copy PGN',
            onTap: _copyPgn,
          ),
        ],
      ),
    );
  }

  Widget _buildGifProgress() {
    return Container(
      width: 370.w,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
      decoration: BoxDecoration(
        color: kBlack2Color,
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(color: kBlack3Color),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 16.w,
                height: 16.h,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: kPrimaryColor,
                ),
              ),
              SizedBox(width: 10.w),
              Text(
                'Generating GIF... ${(_gifProgress * 100).toInt()}%',
                style: TextStyle(
                  color: kWhiteColor,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          // Linear progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4.br),
            child: LinearProgressIndicator(
              value: _gifProgress,
              backgroundColor: kBlack3Color,
              valueColor: AlwaysStoppedAnimation<Color>(kPrimaryColor),
              minHeight: 6.h,
            ),
          ),
        ],
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
                  // Eval bar toggle - modern pill style
                  _buildEvalToggle()
                      .animate()
                      .fadeIn(delay: 150.ms, duration: 300.ms),
                  SizedBox(height: 16.h),
                  // Action buttons or progress
                  if (_isGenerating)
                    CircularProgressIndicator(
                      color: kPrimaryColor,
                      strokeWidth: 2,
                    )
                  else if (_isGeneratingGif)
                    _buildGifProgress()
                        .animate()
                        .fadeIn(duration: 200.ms)
                  else
                    _buildActionButtons()
                        .animate()
                        .fadeIn(delay: 200.ms, duration: 300.ms),
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
            // Offscreen GIF frame widget - uses RepaintBoundary with GlobalKey for raw RGBA capture
            // This avoids PNG encoding issues on iOS P3 displays
            // Uses board settings with animations DISABLED for instant static frame capture
            Positioned(
              left: -10000,
              top: -10000,
              child: RepaintBoundary(
                key: _gifFrameKey,
                child: _ShareCard(
                  boardSettings: _gifBoardSettings, // Animation disabled settings
                  positionFen: _gifFrameFen ?? widget.positionFen,
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
                  whitePlayerClock: _gifFrameWhiteClock, // Dynamic clock per frame
                  blackPlayerClock: _gifFrameBlackClock, // Dynamic clock per frame
                  tournamentName: widget.tournamentName,
                  roundInfo: widget.roundInfo,
                  currentMoveIndex: widget.currentMoveIndex,
                  evaluation: null, // No eval in GIF
                  mate: 0,
                  isFlipped: widget.isFlipped,
                  gameStatus: widget.gameStatus,
                  isPreview: false,
                  showEvalBar: false, // No eval bar in GIF
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
    final scoreStyle = AppTypography.textXsBold.copyWith(
      color: kWhiteColor,
      fontSize: 14.sp, // Bigger for better proportion
      fontWeight: FontWeight.w700,
      height: 1.0,
    );

    switch (gameStatus) {
      case GameStatus.whiteWins:
        return Text(
          isWhitePlayer ? '1' : '0',
          style: scoreStyle,
          textAlign: TextAlign.center,
        );
      case GameStatus.blackWins:
        return Text(
          isWhitePlayer ? '0' : '1',
          style: scoreStyle,
          textAlign: TextAlign.center,
        );
      case GameStatus.draw:
        return Text(
          '½',
          style: scoreStyle,
          textAlign: TextAlign.center,
        );
      case GameStatus.ongoing:
      case GameStatus.unknown:
        return SizedBox.shrink();
    }
  }

  /// Build player row matching PlayerFirstRowDetailWidget boardView style exactly
  Widget _buildPlayerRow({
    required String playerName,
    required String playerCountry,
    required String? playerElo,
    required String? playerTitle,
    required String? playerClock,
    required bool isWhitePlayer,
    required double sideBarWidth,
  }) {
    // Text styles matching PlayerFirstRowDetailWidget boardView
    final titleStyle = AppTypography.textXsMedium.copyWith(
      color: kLightYellowColor,
      fontWeight: FontWeight.w700,
      fontSize: 14.sp,
      height: 1.2,
    );

    final nameStyle = AppTypography.textXsMedium.copyWith(
      color: kWhiteColor,
      fontWeight: FontWeight.w600,
      fontSize: 14.sp,
      height: 1.2,
    );

    // Rating style - matches PlayerFirstRowDetailWidget (kWhiteColor70)
    final ratingStyle = AppTypography.textXsMedium.copyWith(
      color: kWhiteColor70,
      fontWeight: FontWeight.w600,
      fontSize: 14.sp,
      height: 1.2,
    );

    final timeStyle = AppTypography.textXsMedium.copyWith(
      color: kWhiteColor,
      fontSize: 14.sp,
      fontWeight: FontWeight.w500,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    // Flag sizing matching boardView
    const flagHeight = 12.0;
    const flagWidth = 16.0;
    const elementSpacing = 8.0;

    // Parse name parts - format is "Surname, Given Names"
    final nameParts = playerName.split(',').map((e) => e.trim()).toList();
    final surname = nameParts.isNotEmpty ? nameParts[0] : '';
    final firstName = nameParts.length > 1 ? nameParts[1] : '';
    final rating = playerElo != null ? ' $playerElo' : '';
    final title = playerTitle ?? '';

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Row(
        children: [
          // Score area - matches eval bar width
          SizedBox(
            width: sideBarWidth.w,
            child: Center(child: _buildEndScoreWidget(isWhitePlayer: isWhitePlayer)),
          ),
          SizedBox(width: elementSpacing.w),
          // Country flag
          if (playerCountry.toUpperCase() == 'FID') ...[
            Image.asset(
              PngAsset.fideLogo,
              height: flagHeight.h,
              width: flagWidth.w,
              fit: BoxFit.cover,
              cacheWidth: 48,
              cacheHeight: 36,
            ),
            SizedBox(width: elementSpacing.w),
          ] else if (playerCountry.isNotEmpty) ...[
            CountryFlag.fromCountryCode(
              playerCountry,
              height: flagHeight.h,
              width: flagWidth.w,
            ),
            SizedBox(width: elementSpacing.w),
          ] else
            SizedBox(width: elementSpacing.w),
          // Name + Rating with smart truncation (matching PlayerFirstRowDetailWidget)
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final textPainter = TextPainter(
                  textDirection: TextDirection.ltr,
                  maxLines: 1,
                );

                String displaySurname = surname;
                String displayFirstName = firstName.isNotEmpty ? ', $firstName' : '';

                if (surname.isNotEmpty) {
                  // Strategy 1: Try full surname + full first name + rating
                  textPainter.text = TextSpan(
                    children: [
                      if (title.isNotEmpty) TextSpan(text: '$title ', style: titleStyle),
                      TextSpan(text: surname, style: nameStyle),
                      if (firstName.isNotEmpty) TextSpan(text: ', $firstName', style: nameStyle),
                      TextSpan(text: rating, style: ratingStyle),
                    ],
                  );
                  textPainter.layout();

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
                        if (title.isNotEmpty) TextSpan(text: '$title ', style: titleStyle),
                        TextSpan(text: surname, style: nameStyle),
                        TextSpan(text: displayFirstName, style: nameStyle),
                        TextSpan(text: rating, style: ratingStyle),
                      ],
                    );
                    textPainter.layout();

                    // Strategy 3: If still doesn't fit, drop first name entirely
                    if (textPainter.width > constraints.maxWidth) {
                      displayFirstName = '';
                    }
                  }
                }

                return RichText(
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.left,
                  text: TextSpan(
                    style: nameStyle,
                    children: [
                      if (title.isNotEmpty) TextSpan(text: '$title ', style: titleStyle),
                      if (displaySurname.isNotEmpty) TextSpan(text: displaySurname, style: nameStyle),
                      if (displayFirstName.isNotEmpty) TextSpan(text: displayFirstName, style: nameStyle),
                      TextSpan(text: rating, style: ratingStyle),
                    ],
                  ),
                );
              },
            ),
          ),
          // Clock time on far right (if available)
          if (playerClock != null) ...[
            SizedBox(width: 8.w),
            Text(
              playerClock,
              style: timeStyle,
            ),
          ],
        ],
      ),
    );
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

    // Always reserve space for eval bar to prevent layout shift
    const sideBarWidth = 20.0;

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
          // Top player row - matching PlayerFirstRowDetailWidget exactly
          _buildPlayerRow(
            playerName: topPlayerName,
            playerCountry: topPlayerCountry,
            playerElo: topPlayerElo,
            playerTitle: topPlayerTitle,
            playerClock: topPlayerClock,
            isWhitePlayer: topIsWhitePlayer,
            sideBarWidth: sideBarWidth,
          ),
          SizedBox(height: 12.h),
          // Board with optional evaluation bar
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.sp),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Always reserve space for eval bar
                final reservedWidth = sideBarWidth.w;
                final availableWidth = constraints.maxWidth;
                final boardSize = math.max(1.0, availableWidth - reservedWidth);
                final fenParts = positionFen.split(' ');
                final overlayWhiteToMove =
                    fenParts.length > 1 ? fenParts[1] == 'w' : true;

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Always render eval bar container, use opacity for visibility
                    SizedBox(
                      width: reservedWidth,
                      height: boardSize,
                      child: AnimatedOpacity(
                        opacity: showEvalBar ? 1.0 : 0.0,
                        duration: Duration(milliseconds: 200),
                        child: EvaluationBarWidget(
                          width: reservedWidth,
                          height: boardSize,
                          evaluation: evaluation,
                          mate: mate != 0 ? mate : null,
                          isEvaluating: evaluation == null && mate == 0,
                          isFlipped: isFlipped,
                          isWhiteToMove: overlayWhiteToMove,
                          positionKey: positionFen,
                        ),
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
          // Bottom player row - matching PlayerFirstRowDetailWidget exactly
          _buildPlayerRow(
            playerName: bottomPlayerName,
            playerCountry: bottomPlayerCountry,
            playerElo: bottomPlayerElo,
            playerTitle: bottomPlayerTitle,
            playerClock: bottomPlayerClock,
            isWhitePlayer: bottomIsWhitePlayer,
            sideBarWidth: sideBarWidth,
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
