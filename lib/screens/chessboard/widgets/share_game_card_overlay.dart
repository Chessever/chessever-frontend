import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/location_service_provider.dart';
import 'package:country_flags/country_flags.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ShareGameCardOverlay extends StatefulWidget {
  final Widget boardWidget;
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
  final VoidCallback onClose;

  const ShareGameCardOverlay({
    super.key,
    required this.boardWidget,
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
    required this.onClose,
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
      final file = File('${tempDir.path}/chessever_share.png');
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
    // Request permission
    if (Platform.isAndroid) {
      final androidVersion = await _getAndroidVersion();
      Permission permission;

      if (androidVersion >= 33) {
        permission = Permission.photos;
      } else {
        permission = Permission.storage;
      }

      final status = await permission.request();
      if (!status.isGranted) {
        _showMessage('Storage permission is required to save images', isError: true);
        return;
      }
    }

    final imageBytes = await _captureCard();
    if (imageBytes == null) {
      _showMessage('Failed to generate image', isError: true);
      return;
    }

    try {
      final result = await ImageGallerySaver.saveImage(
        imageBytes,
        quality: 100,
        name: 'chessever_${DateTime.now().millisecondsSinceEpoch}',
      );

      if (result != null && result['isSuccess'] == true) {
        _showMessage('Image saved to gallery!', isError: false);
      } else {
        _showMessage('Failed to save image', isError: true);
      }
    } catch (e) {
      debugPrint('Error saving: $e');
      _showMessage('Failed to save image', isError: true);
    }
  }

  Future<int> _getAndroidVersion() async {
    if (!Platform.isAndroid) return 0;
    try {
      final androidInfo = await Future.value(33); // Default to 33 for safety
      return androidInfo;
    } catch (e) {
      return 33;
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
                      _rotationY = (details.localPosition.dx / 350.w - 0.5) * 0.15;
                      _rotationX = -(details.localPosition.dy / 600.h - 0.5) * 0.15;
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
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.001)
                      ..rotateX(_rotationX)
                      ..rotateY(_rotationY),
                    transformAlignment: Alignment.center,
                    child: _ShareCard(
                      boardWidget: widget.boardWidget,
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
                      isPreview: true,
                    ),
                  ),
                ).animate().fadeIn(duration: 300.ms).scale(begin: Offset(0.95, 0.95), duration: 300.ms),
                SizedBox(height: 20.h),
                if (_isGenerating)
                  CircularProgressIndicator(color: kPrimaryColor, strokeWidth: 2)
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
                            label: Text('Download', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kBlack2Color,
                              foregroundColor: kWhiteColor,
                              padding: EdgeInsets.symmetric(vertical: 12.h),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10.br),
                                side: BorderSide(color: kWhiteColor70, width: 1),
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
                            label: Text('Share', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kPrimaryColor,
                              foregroundColor: kWhiteColor,
                              padding: EdgeInsets.symmetric(vertical: 12.h),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.br)),
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
                boardWidget: widget.boardWidget,
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
                isPreview: false,
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
  final Widget boardWidget;
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
  final bool isPreview;

  const _ShareCard({
    required this.boardWidget,
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
    this.isPreview = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use the actual moveSans from analysis state instead of parsing PGN
    final moves = moveSans;

    final whiteCountry = whitePlayerCountry != null
        ? ref.read(locationServiceProvider).getValidCountryCode(whitePlayerCountry!)
        : '';
    final blackCountry = blackPlayerCountry != null
        ? ref.read(locationServiceProvider).getValidCountryCode(blackPlayerCountry!)
        : '';

    return Container(
      width: 350.w,
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
              style: TextStyle(
                color: kWhiteColor70,
                fontSize: 9.sp,
              ),
            ),
          SizedBox(height: 12.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: Row(
              children: [
                Container(
                  width: 10.w,
                  height: 10.w,
                  decoration: BoxDecoration(
                    color: kDarkGreyColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: kWhiteColor70, width: 1),
                  ),
                ),
                SizedBox(width: 8.w),
                if (blackCountry.isNotEmpty) ...[
                  CountryFlag.fromCountryCode(blackCountry, height: 12.h, width: 16.w),
                  SizedBox(width: 8.w),
                ],
                if (blackPlayerTitle != null) ...[
                  Text(
                    blackPlayerTitle!,
                    style: TextStyle(color: kPrimaryColor, fontSize: 10.sp, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(width: 6.w),
                ],
                Expanded(
                  child: Text(
                    blackPlayerName,
                    style: TextStyle(color: kWhiteColor, fontSize: 11.sp, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (blackPlayerElo != null)
                  Text(
                    blackPlayerElo!,
                    style: TextStyle(color: kLightYellowColor, fontSize: 10.sp, fontWeight: FontWeight.w600),
                  ),
                if (blackPlayerClock != null) ...[
                  SizedBox(width: 8.w),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(4.br),
                    ),
                    child: Text(
                      blackPlayerClock!,
                      style: TextStyle(color: kWhiteColor, fontSize: 9.sp, fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: 12.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8.br),
              child: AspectRatio(aspectRatio: 1, child: boardWidget),
            ),
          ),
          SizedBox(height: 12.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: Row(
              children: [
                Container(
                  width: 10.w,
                  height: 10.w,
                  decoration: BoxDecoration(
                    color: kWhiteColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: kWhiteColor70, width: 1),
                  ),
                ),
                SizedBox(width: 8.w),
                if (whiteCountry.isNotEmpty) ...[
                  CountryFlag.fromCountryCode(whiteCountry, height: 12.h, width: 16.w),
                  SizedBox(width: 8.w),
                ],
                if (whitePlayerTitle != null) ...[
                  Text(
                    whitePlayerTitle!,
                    style: TextStyle(color: kPrimaryColor, fontSize: 10.sp, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(width: 6.w),
                ],
                Expanded(
                  child: Text(
                    whitePlayerName,
                    style: TextStyle(color: kWhiteColor, fontSize: 11.sp, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (whitePlayerElo != null)
                  Text(
                    whitePlayerElo!,
                    style: TextStyle(color: kLightYellowColor, fontSize: 10.sp, fontWeight: FontWeight.w600),
                  ),
                if (whitePlayerClock != null) ...[
                  SizedBox(width: 8.w),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(4.br),
                    ),
                    child: Text(
                      whitePlayerClock!,
                      style: TextStyle(color: kWhiteColor, fontSize: 9.sp, fontFamily: 'monospace'),
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
                const fullMovesToShowBefore = 20; // 20 full moves = 40 individual half-moves
                const totalIndividualMoves = fullMovesToShowBefore * 2; // 40 individual half-moves

                int startIndex;
                int endIndex;

                if (moves.length <= totalIndividualMoves) {
                  // Show all moves if less than or equal to 40
                  startIndex = 0;
                  endIndex = moves.length;
                } else {
                  // Show current move as the LAST one + 39 moves before it (total 40)
                  endIndex = currentMoveIndex + 1; // Include current move
                  startIndex = (endIndex - totalIndividualMoves).clamp(0, moves.length);

                  // If we can't get 40 moves before current (because current is near start),
                  // extend to include more moves after current
                  if (startIndex == 0 && endIndex < totalIndividualMoves) {
                    endIndex = totalIndividualMoves.clamp(0, moves.length);
                  }
                }

                final displayMoves = moves.sublist(startIndex, endIndex);
                final showStartEllipsis = startIndex > 0;
                final showEndEllipsis = endIndex < moves.length;

                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  child: Wrap(
                    spacing: 2.sp,
                    runSpacing: 2.sp,
                    children: [
                      if (showStartEllipsis)
                        Text(
                          '...',
                          style: TextStyle(
                            color: kWhiteColor70,
                            fontSize: 8.5.sp,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ...displayMoves.asMap().entries.map((entry) {
                        final moveIndex = startIndex + entry.key;
                        final move = entry.value;
                        final isCurrentMove = moveIndex == currentMoveIndex;

                        // USE ACTUAL MOVE NUMBERS FROM THE GAME - DON'T RENUMBER
                        final fullMoveNumber = (moveIndex / 2).floor() + 1;
                        final isWhiteMove = moveIndex % 2 == 0;

                        // EXACT same formatting as chess board screen
                        final displayText = isWhiteMove ? '$fullMoveNumber. $move' : move;

                        return Container(
                          padding: EdgeInsets.symmetric(horizontal: 6.sp, vertical: 2.sp),
                          decoration: BoxDecoration(
                            color: isCurrentMove ? kWhiteColor70.withValues(alpha: 0.4) : Colors.transparent,
                            borderRadius: BorderRadius.circular(4.sp),
                            border: Border.all(
                              color: isCurrentMove ? kWhiteColor : Colors.transparent,
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            displayText,
                            style: TextStyle(
                              color: isCurrentMove ? kWhiteColor : kWhiteColor70,
                              fontSize: 8.5.sp,
                              fontFamily: 'monospace',
                              fontWeight: isCurrentMove ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        );
                      }),
                      if (showEndEllipsis)
                        Text(
                          '...',
                          style: TextStyle(
                            color: kWhiteColor70,
                            fontSize: 8.5.sp,
                            fontFamily: 'monospace',
                          ),
                        ),
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
  }
}
