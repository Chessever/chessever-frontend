import 'dart:async';
import 'dart:io' as io;
import 'dart:math' as math;

import 'package:chessever2/services/cloudflare_gif_service.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/share_card.dart';
import 'package:chessever2/utils/location_service_provider.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/screens/chessboard/widgets/evaluation_bar_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:motor/motor.dart';

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
  final bool
  isAtGameEnd; // Whether viewing the actual final position of the game
  final VoidCallback onClose;
  final String? shareUrl;
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
    this.isAtGameEnd = false,
    required this.onClose,
    this.shareUrl,
    required this.gameId, // REQUIRED for correct eval caching
  });

  @override
  State<ShareGameCardOverlay> createState() => _ShareGameCardOverlayState();
}

class _ShareGameCardOverlayState extends State<ShareGameCardOverlay> {
  final ScreenshotController _fullScreenshotController = ScreenshotController();
  bool _isGenerating = false;
  bool _isGeneratingGif = false;
  String _gifProgressLabel = 'Submitting cloud job…';
  double? _gifProgress;
  String? _generatedGifPath;
  bool _showGifPreview = false;
  bool _showEvalBar = true;
  double _rotationX = 0.0;
  double _rotationY = 0.0;

  bool _cancelled = false; // Set on dispose to abort in-flight GIF generation

  @override
  void dispose() {
    _cancelled = true;
    unawaited(_deleteTemporaryGif(_generatedGifPath));
    super.dispose();
  }

  Future<void> _captureShareMessage(
    String message, {
    required String stage,
    Map<String, dynamic>? extras,
  }) async {
    try {
      const shareUrlKey = 'shareUrl';
      final resolvedShareUrl =
          (extras?[shareUrlKey] as String?) ?? _effectiveShareUrl;
      // Info-level share telemetry belongs in breadcrumbs, not as standalone
      // Sentry issues. captureMessage surfaced "share image completed"/"started"
      // as top "errors" by user count (CHESSEVER-15Y) despite being successes.
      Sentry.addBreadcrumb(
        Breadcrumb(
          category: 'share_game',
          message: message,
          type: 'user',
          level: SentryLevel.info,
          data: {
            'stage': stage,
            'gameId': widget.gameId,
            'shareUrl': resolvedShareUrl,
            'hasShareUrl': resolvedShareUrl?.isNotEmpty == true,
            ...?extras,
          }.map((key, value) => MapEntry(key, value?.toString())),
        ),
      );
    } catch (_) {}
  }

  Future<void> _captureShareException(
    Object error,
    StackTrace stackTrace, {
    required String stage,
    Map<String, dynamic>? extras,
  }) async {
    try {
      const shareUrlKey = 'shareUrl';
      final resolvedShareUrl =
          (extras?[shareUrlKey] as String?) ?? _effectiveShareUrl;
      await Sentry.captureException(
        error,
        stackTrace: stackTrace,
        withScope: (scope) {
          scope.setTag('area', 'share_game');
          scope.setTag('stage', stage);
          scope.setContexts(
            'share_game',
            {
              'gameId': widget.gameId,
              'shareUrl': resolvedShareUrl,
              'hasShareUrl': resolvedShareUrl?.isNotEmpty == true,
              ...?extras,
            }.map((key, value) => MapEntry(key, value?.toString())),
          );
        },
      ).timeout(const Duration(seconds: 2));
    } catch (_) {}
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

  String? get _effectiveShareUrl {
    final explicit = widget.shareUrl?.trim();
    if (explicit == null || explicit.isEmpty) return null;
    return explicit;
  }

  String get _shareSubject {
    final tournamentName = widget.tournamentName?.trim();
    final roundInfo = widget.roundInfo?.trim();

    if (tournamentName != null && tournamentName.isNotEmpty) {
      if (roundInfo != null && roundInfo.isNotEmpty) {
        return '$tournamentName • $roundInfo';
      }
      return tournamentName;
    }

    return 'Chessever Game';
  }

  Future<void> _shareFiles(List<XFile> files) {
    unawaited(
      _captureShareMessage(
        'share game files invoked',
        stage: 'share_files',
        extras: {
          'fileCount': files.length,
          'subject': _shareSubject,
          'shareUrl': _effectiveShareUrl,
        },
      ),
    );
    // Text is dropped on Android inside the helper (X eats EXTRA_STREAM when
    // EXTRA_TEXT is set); the overlay's link bar still exposes the URL.
    return shareFilesWithText(
      files,
      subject: _shareSubject,
      text: _effectiveShareUrl,
      sharePositionOrigin: const Rect.fromLTWH(0, 0, 1, 1),
    );
  }

  Future<void> _shareImage() async {
    if (_showGifPreview && mounted) {
      setState(() => _showGifPreview = false);
      await WidgetsBinding.instance.endOfFrame;
    }
    unawaited(
      _captureShareMessage('share image started', stage: 'share_image_started'),
    );
    final imageBytes = await _captureCard();
    if (imageBytes == null) {
      _showMessage('Failed to generate image', isError: true);
      return;
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final file = io.File('${tempDir.path}/chessever_share.png');
      await file.writeAsBytes(imageBytes);

      await _shareFiles([XFile(file.path)]);
      unawaited(
        _captureShareMessage(
          'share image completed',
          stage: 'share_image_completed',
          extras: {
            'imageSize': imageBytes.length,
            'shareUrl': _effectiveShareUrl,
          },
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('Error sharing: $e');
      unawaited(
        _captureShareException(
          e,
          stackTrace,
          stage: 'share_image',
          extras: {'imageSize': imageBytes.length},
        ),
      );
      _showMessage('Failed to share image', isError: true);
    }
  }

  Future<void> _shareGif() async {
    if (_isGeneratingGif) return;
    _cancelled = false;

    final existingPath = _generatedGifPath;
    if (existingPath != null) {
      if (await io.File(existingPath).exists()) {
        if (mounted) {
          setState(() => _showGifPreview = true);
          await WidgetsBinding.instance.endOfFrame;
        }
        try {
          await _shareFiles([XFile(existingPath)]);
        } catch (error, stackTrace) {
          debugPrint('Failed to share generated GIF: $error\n$stackTrace');
          _showMessage('Failed to share GIF', isError: true);
        }
        return;
      }
      if (mounted) {
        setState(() {
          _generatedGifPath = null;
          _showGifPreview = false;
        });
      }
    }

    if (!pgnHasMoves(widget.pgn)) {
      // No moves to animate — fall back to static image export
      await _shareImage();
      return;
    }

    setState(() {
      _isGeneratingGif = true;
      _gifProgressLabel = 'Submitting cloud job…';
      _gifProgress = null;
    });

    CloudflareGifService? service;
    String? temporaryPath;
    try {
      service = CloudflareGifService.fromEnvironment();
      final job = await service.submitJob(
        pgn: widget.pgn,
        flipped: widget.isFlipped,
        metadata: _cloudGifMetadata(),
      );
      debugPrint('Cloud GIF job submitted: ${job.id}');
      final completed = await service.waitUntilComplete(
        job.id,
        isCancelled: () => _cancelled || !mounted,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _gifProgressLabel = _cloudGifProgressText(progress);
            _gifProgress =
                progress.totalFrames > 0
                    ? (progress.completedFrames / progress.totalFrames).clamp(
                      0.0,
                      1.0,
                    )
                    : null;
          });
        },
      );
      if (!mounted || _cancelled) return;

      setState(() {
        _gifProgressLabel = 'Downloading GIF…';
        _gifProgress = null;
      });
      final tempDir = await getTemporaryDirectory();
      temporaryPath =
          '${tempDir.path}${io.Platform.pathSeparator}'
          'chessever_game_${DateTime.now().microsecondsSinceEpoch}.gif';
      await service.downloadToFile(
        jobId: completed.id,
        outputPath: temporaryPath,
      );
      if (!mounted || _cancelled) return;

      final previousPath = _generatedGifPath;
      setState(() {
        _generatedGifPath = temporaryPath;
        _showGifPreview = true;
      });
      final generatedPath = temporaryPath;
      temporaryPath = null;
      unawaited(_deleteTemporaryGif(previousPath));

      await WidgetsBinding.instance.endOfFrame;
      await _shareFiles([XFile(generatedPath)]);
    } on CloudflareGifCancelled {
      // Closing the overlay stops polling only. A repeat submission resumes
      // the deterministic Cloudflare job.
    } on CloudflareGifException catch (error) {
      debugPrint(
        'Cloud GIF failed: code=${error.code}, '
        'status=${error.statusCode ?? 'n/a'}, message=${error.message}',
      );
      _showMessage('${error.message} [${error.code}]', isError: true);
    } catch (error, stackTrace) {
      debugPrint('Unexpected Cloud GIF failure: $error\n$stackTrace');
      unawaited(
        _captureShareException(
          error,
          stackTrace,
          stage: 'share_cloud_gif',
          extras: {'errorCode': 'unexpected_client_error'},
        ),
      );
      _showMessage(
        'Cloud GIF generation failed. [unexpected_client_error]',
        isError: true,
      );
    } finally {
      service?.close();
      if (temporaryPath != null) {
        await _deleteTemporaryGif(temporaryPath);
      }
      if (mounted) {
        setState(() {
          _isGeneratingGif = false;
          _gifProgress = null;
        });
      }
    }
  }

  Future<void> _deleteTemporaryGif(String? path) async {
    if (path == null) return;
    try {
      final file = io.File(path);
      if (await file.exists()) await file.delete();
    } catch (error) {
      debugPrint('Failed to remove temporary GIF: $error');
    }
  }

  Map<String, Object?> _cloudGifMetadata() {
    int? rating(String? value) {
      final parsed = int.tryParse(value?.trim() ?? '');
      return parsed != null && parsed > 0 ? parsed : null;
    }

    final eventParts = <String>[
      if (widget.tournamentName?.trim().isNotEmpty ?? false)
        widget.tournamentName!.trim(),
      if (widget.roundInfo?.trim().isNotEmpty ?? false)
        widget.roundInfo!.trim(),
    ];
    final result = switch (widget.gameStatus) {
      GameStatus.whiteWins => '1-0',
      GameStatus.blackWins => '0-1',
      GameStatus.draw => '1/2-1/2',
      GameStatus.ongoing => '*',
      GameStatus.unknown => '',
    };

    return <String, Object?>{
      'white': widget.whitePlayerName,
      'black': widget.blackPlayerName,
      if (widget.whitePlayerTitle?.trim().isNotEmpty ?? false)
        'whiteTitle': widget.whitePlayerTitle!.trim(),
      if (widget.blackPlayerTitle?.trim().isNotEmpty ?? false)
        'blackTitle': widget.blackPlayerTitle!.trim(),
      if (rating(widget.whitePlayerElo) case final whiteRating?)
        'whiteRating': whiteRating,
      if (rating(widget.blackPlayerElo) case final blackRating?)
        'blackRating': blackRating,
      if (widget.whitePlayerCountry?.trim().isNotEmpty ?? false)
        'whiteFederation': widget.whitePlayerCountry!.trim(),
      if (widget.blackPlayerCountry?.trim().isNotEmpty ?? false)
        'blackFederation': widget.blackPlayerCountry!.trim(),
      if (eventParts.isNotEmpty) 'event': eventParts.join(' • '),
      if (result.isNotEmpty) 'result': result,
    };
  }

  String _cloudGifProgressText(CloudflareGifJob job) {
    final frames =
        job.totalFrames > 0
            ? ' ${job.completedFrames.clamp(0, job.totalFrames)}/${job.totalFrames}'
            : '';
    return switch (job.stage) {
      CloudflareGifJobStatus.queued => 'Queued in Cloudflare…',
      CloudflareGifJobStatus.analyzing => 'Analyzing positions$frames…',
      CloudflareGifJobStatus.rendering => 'Rendering frames$frames…',
      CloudflareGifJobStatus.encoding => 'Encoding GIF…',
      CloudflareGifJobStatus.storing => 'Finalizing GIF…',
      CloudflareGifJobStatus.succeeded => 'GIF ready',
      CloudflareGifJobStatus.failed => 'GIF generation failed',
    };
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

  Future<void> _copyShareUrl() async {
    final shareUrl = _effectiveShareUrl;
    if (shareUrl == null || shareUrl.isEmpty) return;

    try {
      await Clipboard.setData(ClipboardData(text: shareUrl));
      HapticFeedback.lightImpact();
      _showMessage('Copied to clipboard', isError: false);
    } catch (e) {
      debugPrint('Error copying share URL: $e');
      _showMessage('Failed to copy link', isError: true);
    }
  }

  void _showMessage(String message, {required bool isError}) {
    if (!mounted) return;
    showAppSnack(
      context,
      message,
      tone: isError ? AppSnackTone.danger : AppSnackTone.success,
    );
  }

  Widget _buildEvalToggle() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(20.br),
        border: Border.all(color: context.colors.surfaceRecessed),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.analytics_outlined,
            size: 16.sp,
            color:
                _showEvalBar ? kPrimaryColor : context.colors.textPrimaryMuted,
          ),
          SizedBox(width: 8.w),
          Text(
            'Eval Bar',
            style: TextStyle(
              color:
                  _showEvalBar
                      ? context.colors.textPrimary
                      : context.colors.textPrimaryMuted,
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
                color:
                    _showEvalBar
                        ? kPrimaryColor
                        : context.colors.surfaceRecessed,
                borderRadius: BorderRadius.circular(11.br),
                border: Border.all(
                  color: _showEvalBar ? kPrimaryColor : context.colors.divider,
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
                    color: context.colors.textPrimary,
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
    bool enabled = true,
    String? disabledMessage,
  }) {
    final effectiveOnTap =
        enabled
            ? onTap
            : () =>
                _showMessage(disabledMessage ?? 'Not available', isError: true);

    final content = Container(
      padding: EdgeInsets.symmetric(vertical: 12.h),
      decoration: BoxDecoration(
        color: isPrimary ? kPrimaryColor : context.colors.surfaceRecessed,
        borderRadius: BorderRadius.circular(8.br),
        border:
            isPrimary
                ? null
                : Border.all(color: context.colors.divider, width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 18.sp,
            color:
                isPrimary
                    ? context.colors.textPrimary
                    : context.colors.textPrimary,
          ),
          SizedBox(width: 8.w),
          Text(
            label,
            style: TextStyle(
              color:
                  isPrimary
                      ? context.colors.textPrimary
                      : context.colors.textPrimary,
              fontSize: 13.sp,
              fontWeight: isPrimary ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );

    return Expanded(
      child: GestureDetector(
        onTap: effectiveOnTap,
        child: enabled ? content : Opacity(opacity: 0.4, child: content),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Container(
      width: 370.w,
      padding: EdgeInsets.all(4.w),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(color: context.colors.surfaceRecessed),
      ),
      child: Row(
        children: [
          _buildActionButton(
            icon: Icons.image_outlined,
            label: 'Share Image',
            onTap: _shareImage,
            isPrimary: !_showGifPreview,
          ),
          SizedBox(width: 4.w),
          _buildActionButton(
            icon: Icons.gif_box_outlined,
            label: 'Share GIF',
            onTap: _shareGif,
            isPrimary: _showGifPreview,
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
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(color: context.colors.surfaceRecessed),
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
                _gifProgressLabel,
                style: TextStyle(
                  color: context.colors.textPrimary,
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
              backgroundColor: context.colors.surfaceRecessed,
              valueColor: AlwaysStoppedAnimation<Color>(kPrimaryColor),
              minHeight: 6.h,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShareLinkBar() {
    final shareUrl = _effectiveShareUrl;
    if (shareUrl == null || shareUrl.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: 370.w,
      padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: const Color(0xFF141A20),
        borderRadius: BorderRadius.circular(22.br),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              shareUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 15.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(width: 12.w),
          Material(
            color: context.colors.textPrimary.withValues(alpha: 0.08),
            shape: const CircleBorder(),
            child: InkWell(
              onTap: _copyShareUrl,
              customBorder: const CircleBorder(),
              child: Padding(
                padding: EdgeInsets.all(8.sp),
                child: Icon(
                  Icons.copy_rounded,
                  size: 18.sp,
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneratedGifPreview(String path) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16.br),
          child: Image.file(
            io.File(path),
            key: ValueKey<String>('share-gif-preview:$path'),
            width: 370.w,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            filterQuality: FilterQuality.high,
          ),
        ),
        Positioned(
          top: 8.h,
          right: 8.w,
          child: Material(
            color: Colors.black.withValues(alpha: 0.65),
            shape: const CircleBorder(),
            child: InkWell(
              onTap: widget.onClose,
              customBorder: const CircleBorder(),
              child: Padding(
                padding: EdgeInsets.all(8.sp),
                child: Icon(Icons.close, size: 18.sp, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
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
                          child:
                              !_showGifPreview || _generatedGifPath == null
                                  ? _ShareCard(
                                    boardSettings: widget.boardSettings,
                                    positionFen: widget.positionFen,
                                    lastMove: widget.lastMove,
                                    onClose: widget.onClose,
                                    pgn: widget.pgn,
                                    moveSans: widget.moveSans,
                                    whitePlayerName: widget.whitePlayerName,
                                    blackPlayerName: widget.blackPlayerName,
                                    whitePlayerCountry:
                                        widget.whitePlayerCountry,
                                    blackPlayerCountry:
                                        widget.blackPlayerCountry,
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
                                    isAtGameEnd: widget.isAtGameEnd,
                                    isPreview: true,
                                    showEvalBar: _showEvalBar,
                                    gameId: widget.gameId,
                                  )
                                  : _buildGeneratedGifPreview(
                                    _generatedGifPath!,
                                  ),
                        ),
                      )
                      .animate()
                      .fadeIn(duration: 300.ms)
                      .scale(begin: Offset(0.95, 0.95), duration: 300.ms),
                  SizedBox(height: 16.h),
                  if (!_showGifPreview) ...[
                    // Eval bar affects the static share-card preview only.
                    _buildEvalToggle().animate().fadeIn(
                      delay: 150.ms,
                      duration: 300.ms,
                    ),
                    SizedBox(height: 16.h),
                  ],
                  _buildShareLinkBar().animate().fadeIn(
                    delay: 180.ms,
                    duration: 300.ms,
                  ),
                  if ((_effectiveShareUrl ?? '').isNotEmpty)
                    SizedBox(height: 16.h),
                  // Action buttons or progress
                  if (_isGenerating)
                    CircularProgressIndicator(
                      color: kPrimaryColor,
                      strokeWidth: 2,
                    )
                  else if (_isGeneratingGif)
                    _buildGifProgress().animate().fadeIn(duration: 200.ms)
                  else
                    _buildActionButtons().animate().fadeIn(
                      delay: 200.ms,
                      duration: 300.ms,
                    ),
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
                child: Container(
                  color: context.colors.background,
                  padding: EdgeInsets.all(16.w),
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
                    isAtGameEnd: widget.isAtGameEnd,
                    isPreview: false,
                    showEvalBar: _showEvalBar,
                    gameId: widget.gameId,
                  ),
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
  final bool isAtGameEnd;
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
    this.isAtGameEnd = false,
    this.isPreview = false,
    this.showEvalBar = true,
    required this.gameId, // REQUIRED for correct eval caching
  });

  Widget _buildEndScoreWidget({
    required BuildContext context,
    required bool isWhitePlayer,
  }) {
    // For finished games, display end scores similar to main chess board screen
    final scoreStyle = AppTypography.textXsBold.copyWith(
      color: context.colors.textPrimary,
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
        return Text('½', style: scoreStyle, textAlign: TextAlign.center);
      case GameStatus.ongoing:
      case GameStatus.unknown:
        return SizedBox.shrink();
    }
  }

  /// Build player row matching PlayerFirstRowDetailWidget boardView style exactly
  Widget _buildPlayerRow({
    required BuildContext context,
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
      color: context.colors.textPrimary,
      fontWeight: FontWeight.w600,
      fontSize: 14.sp,
      height: 1.2,
    );

    // Rating style - matches PlayerFirstRowDetailWidget (context.colors.textPrimaryMuted)
    final ratingStyle = AppTypography.textXsMedium.copyWith(
      color: context.colors.textPrimaryMuted,
      fontWeight: FontWeight.w600,
      fontSize: 14.sp,
      height: 1.2,
    );

    final timeStyle = AppTypography.textXsMedium.copyWith(
      color: context.colors.textPrimary,
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
            child: Center(
              child: _buildEndScoreWidget(
                context: context,
                isWhitePlayer: isWhitePlayer,
              ),
            ),
          ),
          SizedBox(width: elementSpacing.w),
          if (FederationFlag.hasVisibleFlag(playerCountry)) ...[
            FederationFlag(
              federation: playerCountry,
              height: flagHeight.h,
              width: flagWidth.w,
              borderRadius: BorderRadius.circular(2.br),
            ),
            SizedBox(width: elementSpacing.w),
          ],
          // Name + Rating with smart truncation (matching PlayerFirstRowDetailWidget)
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final textPainter = TextPainter(
                  textDirection: TextDirection.ltr,
                  maxLines: 1,
                );

                String displaySurname = surname;
                String displayFirstName =
                    firstName.isNotEmpty ? ', $firstName' : '';

                if (surname.isNotEmpty) {
                  // Strategy 1: Try full surname + full first name + rating
                  textPainter.text = TextSpan(
                    children: [
                      if (title.isNotEmpty)
                        TextSpan(text: '$title ', style: titleStyle),
                      TextSpan(text: surname, style: nameStyle),
                      if (firstName.isNotEmpty)
                        TextSpan(text: ', $firstName', style: nameStyle),
                      TextSpan(text: rating, style: ratingStyle),
                    ],
                  );
                  textPainter.layout();

                  if (textPainter.width > constraints.maxWidth &&
                      firstName.isNotEmpty) {
                    // Strategy 2: Keep full surname + abbreviate first name
                    final firstNameParts = firstName.split(' ');
                    final abbreviatedFirst = firstNameParts
                        .where((part) => part.isNotEmpty)
                        .map((part) => '${part[0]}.')
                        .join(' ');
                    displayFirstName = ', $abbreviatedFirst';

                    textPainter.text = TextSpan(
                      children: [
                        if (title.isNotEmpty)
                          TextSpan(text: '$title ', style: titleStyle),
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
                      if (title.isNotEmpty)
                        TextSpan(text: '$title ', style: titleStyle),
                      if (displaySurname.isNotEmpty)
                        TextSpan(text: displaySurname, style: nameStyle),
                      if (displayFirstName.isNotEmpty)
                        TextSpan(text: displayFirstName, style: nameStyle),
                      TextSpan(text: rating, style: ratingStyle),
                    ],
                  ),
                );
              },
            ),
          ),
          if (playerClock != null) ...[
            SizedBox(width: 8.w),
            Text(playerClock, style: timeStyle),
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
        color: context.colors.background,
        borderRadius: BorderRadius.circular(16.br),
        border: Border.all(color: context.colors.divider, width: 3),
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
                  color: context.colors.textPrimary,
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
                color: context.colors.textPrimaryMuted,
                fontSize: 9.sp,
              ),
            ),
          SizedBox(height: 12.h),
          // Top player row - matching PlayerFirstRowDetailWidget exactly
          _buildPlayerRow(
            context: context,
            playerName: topPlayerName,
            playerCountry: topPlayerCountry,
            playerElo: topPlayerElo,
            playerTitle: topPlayerTitle,
            playerClock: topPlayerClock,
            isWhitePlayer: topIsWhitePlayer,
            sideBarWidth: sideBarWidth,
          ),
          SizedBox(height: 12.h),
          // Board with optional evaluation bar and game ending overlays
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

                // Calculate game ending data for overlays — only at the actual final position
                final gameEndingData = _calculateShareGameEndingData(
                  positionFen,
                  gameStatus,
                );
                final showGameEndingEffect =
                    isAtGameEnd &&
                    gameStatus != GameStatus.ongoing &&
                    gameStatus != GameStatus.unknown;

                // Prepare FEN - remove loser's king if showing fallen king overlay
                String displayFen = positionFen;
                if (showGameEndingEffect &&
                    gameEndingData?.loserKingSquare != null) {
                  final loserSide = gameEndingData!.loserSide;
                  final kingChar = loserSide == Side.white ? 'K' : 'k';
                  displayFen = _removeKingFromShareFen(
                    positionFen,
                    gameEndingData.loserKingSquare!,
                    kingChar,
                  );
                }

                // Build chessboard with square highlights
                final chessboard = StaticChessboard(
                  size: boardSize,
                  fen: displayFen,
                  orientation: boardOrientation,
                  lastMove: lastMove,
                  settings: StaticChessboardSettings.fromBoardSettings(
                    boardSettings,
                  ),
                  squareHighlights:
                      showGameEndingEffect
                          ? (gameEndingData?.squareHighlights.unlock ??
                              const <Square, SquareHighlight>{})
                          : const <Square, SquareHighlight>{},
                );

                // Build board widget with overlays if game ended
                Widget boardWidget;
                final squareSize = boardSize / 8;

                if (showGameEndingEffect &&
                    gameEndingData?.loserKingSquare != null) {
                  // Game ended with a winner - show fallen king overlay
                  final loserSquare = gameEndingData!.loserKingSquare!;
                  final loserSide = gameEndingData.loserSide!;

                  // Calculate square position on board
                  final file = loserSquare.file;
                  final rank = loserSquare.rank;

                  // Adjust for board orientation
                  final effectiveFile = isFlipped ? 7 - file : file;
                  final effectiveRank = isFlipped ? rank : 7 - rank;

                  // Get piece image from board settings
                  final pieceKind =
                      loserSide == Side.white
                          ? PieceKind.whiteKing
                          : PieceKind.blackKing;
                  final pieceImage = boardSettings.pieceAssets[pieceKind];

                  boardWidget = Stack(
                    children: [
                      chessboard,
                      // Fallen king overlay - animate for preview, static for capture
                      if (pieceImage != null)
                        _ShareFallenKingOverlay(
                          left: effectiveFile * squareSize,
                          top: effectiveRank * squareSize,
                          squareSize: squareSize,
                          pieceImage: pieceImage,
                          animate: isPreview,
                        ),
                    ],
                  );
                } else if (showGameEndingEffect &&
                    gameStatus == GameStatus.draw) {
                  // Game ended in draw - show peace icons on both kings
                  final position = Chess.fromSetup(Setup.parseFen(positionFen));
                  final board = position.board;
                  final whiteKingSquare = board.kingOf(Side.white);
                  final blackKingSquare = board.kingOf(Side.black);

                  if (whiteKingSquare != null && blackKingSquare != null) {
                    boardWidget = Stack(
                      children: [
                        chessboard,
                        // Peace icon on white king
                        _SharePeaceIcon(
                          square: whiteKingSquare,
                          squareSize: squareSize,
                          isFlipped: isFlipped,
                          delayMs: 0,
                          animate: isPreview,
                        ),
                        // Peace icon on black king (slight delay for stagger in preview)
                        _SharePeaceIcon(
                          square: blackKingSquare,
                          squareSize: squareSize,
                          isFlipped: isFlipped,
                          delayMs: isPreview ? 100 : 0,
                          animate: isPreview,
                        ),
                      ],
                    );
                  } else {
                    boardWidget = chessboard;
                  }
                } else {
                  boardWidget = chessboard;
                }

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
                      child: boardWidget,
                    ),
                  ],
                );
              },
            ),
          ),
          SizedBox(height: 12.h),
          // Bottom player row - matching PlayerFirstRowDetailWidget exactly
          _buildPlayerRow(
            context: context,
            playerName: bottomPlayerName,
            playerCountry: bottomPlayerCountry,
            playerElo: bottomPlayerElo,
            playerTitle: bottomPlayerTitle,
            playerClock: bottomPlayerClock,
            isWhitePlayer: bottomIsWhitePlayer,
            sideBarWidth: sideBarWidth,
          ),
          SizedBox(
            height: 20.h,
          ), // Extra padding to prevent bottom border cutoff in GIF
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
              child: Icon(
                Icons.close,
                size: 16.sp,
                color: context.colors.textPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Data class for game ending visual effects in share card
class _ShareGameEndingData {
  final IMap<Square, SquareHighlight> squareHighlights;
  final Square? loserKingSquare;
  final Side? loserSide;

  const _ShareGameEndingData({
    required this.squareHighlights,
    required this.loserKingSquare,
    required this.loserSide,
  });
}

/// Calculate game ending visual data for share card
_ShareGameEndingData? _calculateShareGameEndingData(
  String fen,
  GameStatus gameStatus,
) {
  // Parse position to find king squares
  final position = Chess.fromSetup(Setup.parseFen(fen));
  final board = position.board;
  final whiteKingSquare = board.kingOf(Side.white);
  final blackKingSquare = board.kingOf(Side.black);

  if (whiteKingSquare == null || blackKingSquare == null) {
    return null;
  }

  // Convert dartchess Square to chessground Square
  final whiteKingCgSquare = Square.fromName(whiteKingSquare.name);
  final blackKingCgSquare = Square.fromName(blackKingSquare.name);

  if (gameStatus == GameStatus.draw) {
    // Draw: mint green background for both kings
    return _ShareGameEndingData(
      squareHighlights: IMap({
        whiteKingCgSquare: const SquareHighlight(
          details: HighlightDetails(
            solidColor: Color(0xCCADE1CD), // Mint green with alpha
          ),
        ),
        blackKingCgSquare: const SquareHighlight(
          details: HighlightDetails(
            solidColor: Color(0xCCADE1CD), // Mint green with alpha
          ),
        ),
      }),
      loserKingSquare: null,
      loserSide: null,
    );
  } else if (gameStatus == GameStatus.whiteWins) {
    // White wins: black king is the loser
    return _ShareGameEndingData(
      squareHighlights: IMap({
        blackKingCgSquare: const SquareHighlight(
          details: HighlightDetails(
            solidColor: Color(0xCCF53236), // Red with alpha
          ),
        ),
      }),
      loserKingSquare: blackKingSquare,
      loserSide: Side.black,
    );
  } else if (gameStatus == GameStatus.blackWins) {
    // Black wins: white king is the loser
    return _ShareGameEndingData(
      squareHighlights: IMap({
        whiteKingCgSquare: const SquareHighlight(
          details: HighlightDetails(
            solidColor: Color(0xCCF53236), // Red with alpha
          ),
        ),
      }),
      loserKingSquare: whiteKingSquare,
      loserSide: Side.white,
    );
  }

  return null;
}

/// Remove a king from FEN string to hide it when showing fallen king overlay
String _removeKingFromShareFen(String fen, Square square, String kingChar) {
  final parts = fen.split(' ');
  if (parts.isEmpty) return fen;

  final ranks = parts[0].split('/');
  final rankIndex = 7 - square.rank; // FEN ranks are 8-1 (top to bottom)
  if (rankIndex < 0 || rankIndex >= ranks.length) return fen;

  // Expand the rank to individual characters
  final rank = ranks[rankIndex];
  final expanded = StringBuffer();
  for (final char in rank.split('')) {
    final digit = int.tryParse(char);
    if (digit != null) {
      expanded.write('1' * digit); // Replace numbers with 1s
    } else {
      expanded.write(char);
    }
  }

  // Remove the king at the file position
  final fileIndex = square.file;
  final chars = expanded.toString().split('');
  if (fileIndex >= 0 &&
      fileIndex < chars.length &&
      chars[fileIndex] == kingChar) {
    chars[fileIndex] = '1';
  }

  // Compress back: consecutive 1s become a single number
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

/// Fallen king overlay for share card - shows king tilted 45 degrees
/// Uses motor springs for smooth animation when displayed
class _ShareFallenKingOverlay extends StatefulWidget {
  final double left;
  final double top;
  final double squareSize;
  final ImageProvider pieceImage;
  final bool animate;

  const _ShareFallenKingOverlay({
    required this.left,
    required this.top,
    required this.squareSize,
    required this.pieceImage,
    this.animate = true,
  });

  @override
  State<_ShareFallenKingOverlay> createState() =>
      _ShareFallenKingOverlayState();
}

class _ShareFallenKingOverlayState extends State<_ShareFallenKingOverlay> {
  bool _animate = false;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      // Trigger animation after first frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _animate = true);
        }
      });
    } else {
      // Start already animated for static captures
      _animate = true;
    }
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
          child:
              widget.animate
                  ? SingleMotionBuilder(
                    motion: const CupertinoMotion.bouncy(),
                    value:
                        _animate
                            ? -math.pi / 4
                            : 0.0, // -45 degrees when animated
                    builder: (context, rotation, child) {
                      return Transform.rotate(
                        angle: rotation,
                        alignment: Alignment.center,
                        child: child,
                      );
                    },
                    child: Image(image: widget.pieceImage, fit: BoxFit.contain),
                  )
                  : Transform.rotate(
                    angle: -math.pi / 4, // -45 degrees (static)
                    alignment: Alignment.center,
                    child: Image(image: widget.pieceImage, fit: BoxFit.contain),
                  ),
        ),
      ),
    );
  }
}

/// Peace icon overlay for draw games in share card
/// Shows dove emoji in top-right corner of king's square
class _SharePeaceIcon extends StatefulWidget {
  final Square square;
  final double squareSize;
  final bool isFlipped;
  final int delayMs;
  final bool animate;

  const _SharePeaceIcon({
    required this.square,
    required this.squareSize,
    required this.isFlipped,
    this.delayMs = 0,
    this.animate = true,
  });

  @override
  State<_SharePeaceIcon> createState() => _SharePeaceIconState();
}

class _SharePeaceIconState extends State<_SharePeaceIcon> {
  bool _animate = false;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      // Trigger animation after delay for stagger effect
      Future.delayed(Duration(milliseconds: widget.delayMs), () {
        if (mounted) {
          setState(() => _animate = true);
        }
      });
    } else {
      // Start already animated for static captures
      _animate = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.square.file;
    final rank = widget.square.rank;

    // Adjust for board orientation
    final effectiveFile = widget.isFlipped ? 7 - file : file;
    final effectiveRank = widget.isFlipped ? rank : 7 - rank;

    // Smaller icon size for subtle appearance
    final containerSize = widget.squareSize * 0.28;

    return Positioned(
      // Position at top-right corner of the king's square
      left:
          effectiveFile * widget.squareSize +
          widget.squareSize -
          containerSize -
          1,
      top: effectiveRank * widget.squareSize + 1,
      child:
          widget.animate
              ? SingleMotionBuilder(
                motion: const CupertinoMotion.bouncy(),
                value: _animate ? 1.0 : 0.0,
                builder: (context, scale, child) {
                  return Transform.scale(
                    scale: scale,
                    alignment: Alignment.topRight,
                    child: child,
                  );
                },
                child: _buildIcon(containerSize),
              )
              : _buildIcon(containerSize),
    );
  }

  Widget _buildIcon(double containerSize) {
    return Container(
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
          colorFilter: const ColorFilter.mode(Colors.black, BlendMode.srcIn),
          child: Text('🕊️', style: TextStyle(fontSize: containerSize * 0.6)),
        ),
      ),
    );
  }
}
