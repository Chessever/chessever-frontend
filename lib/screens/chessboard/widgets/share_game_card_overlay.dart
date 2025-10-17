import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';

/// A beautiful branded share card overlay with smooth animations
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
      final directory = Platform.isIOS
          ? await getApplicationDocumentsDirectory()
          : await getExternalStorageDirectory();

      if (directory == null) {
        _showError('Could not access storage');
        return;
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${directory.path}/chessever_$timestamp.png');
      await file.writeAsBytes(imageBytes);

      _showSuccess('Image saved successfully!');
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.br)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.br)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.95),
      child: SafeArea(
        child: Stack(
          children: [
            // Animated background gradient
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topCenter,
                    radius: 1.5,
                    colors: [
                      kGreenColor.withValues(alpha: 0.1),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            )
                .animate(onPlay: (controller) => controller.repeat(reverse: true))
                .fadeIn(duration: 2.seconds)
                .scale(
                  begin: const Offset(0.8, 0.8),
                  end: const Offset(1.2, 1.2),
                  duration: 4.seconds,
                ),

            // Close button
            Positioned(
              top: 16.h,
              right: 16.w,
              child: IconButton(
                icon: Icon(Icons.close_rounded, color: Colors.white, size: 32.ic),
                onPressed: widget.onClose,
              ),
            )
                .animate()
                .fadeIn(delay: 300.ms, duration: 400.ms)
                .slideX(begin: 0.3, end: 0),

            // Main content
            Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 60.h),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // The share card
                    Screenshot(
                      controller: _screenshotController,
                      child: _ShareCard(
                        boardWidget: widget.boardWidget,
                        pgn: widget.pgn,
                        whitePlayerName: widget.whitePlayerName,
                        blackPlayerName: widget.blackPlayerName,
                        whitePlayerCountry: widget.whitePlayerCountry,
                        blackPlayerCountry: widget.blackPlayerCountry,
                      ),
                    )
                        .animate()
                        .fadeIn(duration: 500.ms)
                        .scale(
                          begin: const Offset(0.8, 0.8),
                          end: const Offset(1.0, 1.0),
                          curve: Curves.easeOutBack,
                          duration: 600.ms,
                        )
                        .shimmer(
                          delay: 800.ms,
                          duration: 1200.ms,
                          color: kGreenColor.withValues(alpha: 0.3),
                        ),

                    SizedBox(height: 40.h),

                    // Action buttons
                    if (_isGenerating)
                      Column(
                        children: [
                          CircularProgressIndicator(color: kGreenColor),
                          SizedBox(height: 12.h),
                          Text(
                            'Generating image...',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14.sp,
                            ),
                          ),
                        ],
                      )
                          .animate(onPlay: (controller) => controller.repeat())
                          .fadeIn(duration: 500.ms)
                          .then()
                          .fadeOut(duration: 500.ms)
                    else
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _ActionButton(
                            icon: Icons.file_download_rounded,
                            label: 'Download',
                            onPressed: _downloadImage,
                          )
                              .animate()
                              .fadeIn(delay: 400.ms, duration: 400.ms)
                              .slideY(begin: 0.3, end: 0),

                          SizedBox(width: 20.w),

                          _ActionButton(
                            icon: Icons.share_rounded,
                            label: 'Share',
                            onPressed: _shareImage,
                            isPrimary: true,
                          )
                              .animate()
                              .fadeIn(delay: 500.ms, duration: 400.ms)
                              .slideY(begin: 0.3, end: 0)
                              .shimmer(
                                delay: 1.seconds,
                                duration: 1500.ms,
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
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
  final String? whitePlayerCountry;
  final String? blackPlayerCountry;

  const _ShareCard({
    required this.boardWidget,
    required this.pgn,
    required this.whitePlayerName,
    required this.blackPlayerName,
    this.whitePlayerCountry,
    this.blackPlayerCountry,
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
      width: 380.w,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1a1a1c),
            const Color(0xFF0a0a0c),
          ],
        ),
        borderRadius: BorderRadius.circular(24.br),
        border: Border.all(
          color: kGreenColor.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: kGreenColor.withValues(alpha: 0.2),
            blurRadius: 30,
            spreadRadius: 5,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 20,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Logo section with premium background
          Container(
            width: double.infinity,
            height: 140.h,
            decoration: BoxDecoration(
              image: const DecorationImage(
                image: AssetImage('assets/pngs/premium2.png'),
                fit: BoxFit.cover,
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(24.br),
                topRight: Radius.circular(24.br),
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.3),
                    Colors.black.withValues(alpha: 0.7),
                  ],
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24.br),
                  topRight: Radius.circular(24.br),
                ),
              ),
              child: Center(
                child: Image.asset(
                  'assets/pngs/chessever.png',
                  height: 80.h,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),

          SizedBox(height: 24.h),

          // Player names with VS
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w),
            child: Row(
              children: [
                Expanded(
                  child: _PlayerBadge(
                    name: whitePlayerName,
                    country: whitePlayerCountry,
                    isWhite: true,
                  ),
                ),
                Container(
                  margin: EdgeInsets.symmetric(horizontal: 12.w),
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [kGreenColor.withValues(alpha: 0.2), kGreenColor.withValues(alpha: 0.1)],
                    ),
                    borderRadius: BorderRadius.circular(12.br),
                    border: Border.all(color: kGreenColor.withValues(alpha: 0.5), width: 1),
                  ),
                  child: Text(
                    'VS',
                    style: TextStyle(
                      color: kGreenColor,
                      fontSize: 16.sp,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                Expanded(
                  child: _PlayerBadge(
                    name: blackPlayerName,
                    country: blackPlayerCountry,
                    isWhite: false,
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: 24.h),

          // Chess board with glow effect
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12.br),
                boxShadow: [
                  BoxShadow(
                    color: kGreenColor.withValues(alpha: 0.3),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12.br),
                child: SizedBox(
                  width: 332.w,
                  height: 332.w,
                  child: boardWidget,
                ),
              ),
            ),
          ),

          SizedBox(height: 24.h),

          // Moves display
          if (moves.isNotEmpty)
            Container(
              margin: EdgeInsets.symmetric(horizontal: 24.w),
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16.br),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.history,
                        color: kGreenColor,
                        size: 18.ic,
                      ),
                      SizedBox(width: 8.w),
                      Text(
                        'Game Moves',
                        style: TextStyle(
                          color: kGreenColor,
                          fontSize: 14.sp,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                        decoration: BoxDecoration(
                          color: kGreenColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8.br),
                        ),
                        child: Text(
                          '${moves.length} moves',
                          style: TextStyle(
                            color: kGreenColor,
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12.h),
                  Wrap(
                    spacing: 6.w,
                    runSpacing: 6.h,
                    children: moves.take(16).map((move) {
                      return Container(
                        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withValues(alpha: 0.1),
                              Colors.white.withValues(alpha: 0.05),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(8.br),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          move,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace',
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  if (moves.length > 16)
                    Padding(
                      padding: EdgeInsets.only(top: 8.h),
                      child: Text(
                        '+${moves.length - 16} more moves',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 11.sp,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            ),

          SizedBox(height: 24.h),
        ],
      ),
    );
  }
}

class _PlayerBadge extends StatelessWidget {
  final String name;
  final String? country;
  final bool isWhite;

  const _PlayerBadge({
    required this.name,
    this.country,
    required this.isWhite,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.1),
            Colors.white.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(
          color: isWhite
              ? Colors.white.withValues(alpha: 0.3)
              : Colors.grey.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment:
            isWhite ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isWhite) ...[
                Container(
                  width: 12.w,
                  height: 12.w,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.5),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 6.w),
              ],
              Flexible(
                child: Text(
                  name,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: isWhite ? TextAlign.left : TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!isWhite) ...[
                SizedBox(width: 6.w),
                Container(
                  width: 12.w,
                  height: 12.w,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade800,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white30, width: 1),
                  ),
                ),
              ],
            ],
          ),
          if (country != null && country!.isNotEmpty) ...[
            SizedBox(height: 4.h),
            Text(
              country!,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 10.sp,
                fontWeight: FontWeight.w500,
              ),
              textAlign: isWhite ? TextAlign.left : TextAlign.right,
            ),
          ],
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
        borderRadius: BorderRadius.circular(16.br),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 16.h),
          decoration: BoxDecoration(
            gradient: isPrimary
                ? LinearGradient(
                    colors: [kGreenColor, kGreenColor.withValues(alpha: 0.8)],
                  )
                : null,
            color: isPrimary ? null : Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16.br),
            border: Border.all(
              color: isPrimary ? kGreenColor : Colors.white.withValues(alpha: 0.2),
              width: 1.5,
            ),
            boxShadow: isPrimary
                ? [
                    BoxShadow(
                      color: kGreenColor.withValues(alpha: 0.4),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: Colors.white,
                size: 22.ic,
              ),
              SizedBox(width: 10.w),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
