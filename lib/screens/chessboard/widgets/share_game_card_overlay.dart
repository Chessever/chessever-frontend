import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';

/// A minimal share card overlay
class ShareGameCardOverlay extends StatefulWidget {
  final Widget boardWidget;
  final String pgn;
  final String whitePlayerName;
  final String blackPlayerName;
  final String? whitePlayerCountry;
  final String? blackPlayerCountry;
  final VoidCallback onClose;

  const ShareGameCardOverlay({
    super.key,
    required this.boardWidget,
    required this.pgn,
    required this.whitePlayerName,
    required this.blackPlayerName,
    this.whitePlayerCountry,
    this.blackPlayerCountry,
    required this.onClose,
  });

  @override
  State<ShareGameCardOverlay> createState() => _ShareGameCardOverlayState();
}

class _ShareGameCardOverlayState extends State<ShareGameCardOverlay> {
  final ScreenshotController _screenshotController = ScreenshotController();
  bool _isGenerating = false;

  Future<Uint8List?> _captureCard() async {
    try {
      setState(() => _isGenerating = true);
      final image = await _screenshotController.capture(
        pixelRatio: 3.0,
      );
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
      _showError('Failed to generate share image');
      return;
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/chessever_share.png');
      await file.writeAsBytes(imageBytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Check out this chess game on Chessever!',
      );
    } catch (e) {
      debugPrint('Error sharing image: $e');
      _showError('Failed to share image');
    }
  }

  Future<void> _downloadImage() async {
    final imageBytes = await _captureCard();
    if (imageBytes == null) {
      _showError('Failed to generate image');
      return;
    }

    try {
      // Save to gallery (works for both iOS and Android)
      final result = await ImageGallerySaver.saveImage(
        imageBytes,
        quality: 100,
        name: 'chessever_${DateTime.now().millisecondsSinceEpoch}',
      );

      if (result['isSuccess'] == true) {
        _showSuccess('Image saved to gallery!');
      } else {
        _showError('Failed to save image to gallery');
      }
    } catch (e) {
      debugPrint('Error downloading image: $e');
      _showError('Failed to save image');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: kGreenColor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onClose,
      child: Material(
        color: Colors.black.withValues(alpha: 0.7),
        child: SafeArea(
          child: GestureDetector(
            onTap: () {}, // Prevent taps from bubbling to parent
            child: Stack(
              children: [
                // Close button
                Positioned(
                  top: 16.h,
                  right: 16.w,
                  child: IconButton(
                    icon: Icon(Icons.close, color: Colors.white, size: 28.sp),
                    onPressed: widget.onClose,
                  ),
                )
                    .animate()
                    .fadeIn(delay: 200.ms, duration: 300.ms),

                // Main content
                Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(24.w, 60.h, 24.w, 24.h),
                        child: Column(
                          children: [
                            // The share card
                            Screenshot(
                              controller: _screenshotController,
                              child: _ShareCard(
                                boardWidget: widget.boardWidget,
                                pgn: widget.pgn,
                                whitePlayerName: widget.whitePlayerName,
                                blackPlayerName: widget.blackPlayerName,
                              ),
                            )
                                .animate()
                                .fadeIn(duration: 400.ms)
                                .scale(
                                  begin: const Offset(0.9, 0.9),
                                  end: const Offset(1.0, 1.0),
                                  curve: Curves.easeOut,
                                  duration: 400.ms,
                                ),
                          ],
                        ),
                      ),
                    ),

                    // Action buttons (fixed at bottom)
                    Container(
                      padding: EdgeInsets.all(24.w),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        border: Border(
                          top: BorderSide(
                            color: Colors.white.withValues(alpha: 0.1),
                            width: 1,
                          ),
                        ),
                      ),
                      child: _isGenerating
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(
                                    color: kGreenColor,
                                    strokeWidth: 2,
                                  ),
                                  SizedBox(height: 8.h),
                                  Text(
                                    'Generating...',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14.sp,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Row(
                              children: [
                                Expanded(
                                  child: _ActionButton(
                                    icon: Icons.download,
                                    label: 'Download',
                                    onPressed: _downloadImage,
                                  ),
                                ),
                                SizedBox(width: 16.w),
                                Expanded(
                                  child: _ActionButton(
                                    icon: Icons.share,
                                    label: 'Share',
                                    onPressed: _shareImage,
                                    isPrimary: true,
                                  ),
                                ),
                              ],
                            )
                              .animate()
                              .fadeIn(delay: 300.ms, duration: 300.ms)
                              .slideY(begin: 0.2, end: 0),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShareCard extends StatelessWidget {
  final Widget boardWidget;
  final String pgn;
  final String whitePlayerName;
  final String blackPlayerName;

  const _ShareCard({
    required this.boardWidget,
    required this.pgn,
    required this.whitePlayerName,
    required this.blackPlayerName,
  });

  List<String> _parsePgnMoves(String pgn) {
    final movePattern = RegExp(r'\d+\.\s*([a-hO-][a-h1-8xO+#=-]+)\s*([a-hO-][a-h1-8xO+#=-]+)?');
    final matches = movePattern.allMatches(pgn);

    final moves = <String>[];
    for (final match in matches) {
      if (match.group(1) != null) moves.add(match.group(1)!);
      if (match.group(2) != null) moves.add(match.group(2)!);
    }

    return moves;
  }

  @override
  Widget build(BuildContext context) {
    final moves = _parsePgnMoves(pgn);

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxWidth: 400.w),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a1c),
        borderRadius: BorderRadius.circular(16.br),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Logo
          Padding(
            padding: EdgeInsets.all(24.w),
            child: Image.asset(
              'assets/pngs/chessever.png',
              height: 40.h,
              fit: BoxFit.contain,
            ),
          ),

          // Players
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    whitePlayerName,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12.w),
                  child: Text(
                    'vs',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    blackPlayerName,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: 20.h),

          // Board
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8.br),
              child: AspectRatio(
                aspectRatio: 1,
                child: boardWidget,
              ),
            ),
          ),

          SizedBox(height: 20.h),

          // Moves
          if (moves.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(24.w, 0, 24.w, 24.h),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8.br),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Moves',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    SizedBox(height: 12.h),
                    Wrap(
                      spacing: 6.w,
                      runSpacing: 6.h,
                      children: moves.map((move) {
                        return Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8.w,
                            vertical: 4.h,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(4.br),
                          ),
                          child: Text(
                            move,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11.sp,
                              fontWeight: FontWeight.w500,
                              fontFamily: 'monospace',
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool isPrimary;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12.br),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 14.h),
          decoration: BoxDecoration(
            color: isPrimary
                ? kGreenColor
                : Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12.br),
            border: isPrimary
                ? null
                : Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 1,
                  ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: Colors.white,
                size: 20.sp,
              ),
              SizedBox(width: 8.w),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
