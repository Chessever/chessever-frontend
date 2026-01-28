import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// A beautiful player avatar widget that displays a player's photo or
/// falls back to stylized initials with a chess-themed gradient background.
///
/// Features:
/// - Graceful image loading with smooth transitions
/// - Beautiful gradient fallback with initials
/// - Subtle chess-piece watermark for visual interest
/// - Consistent styling across the app
/// - Automatic detection of black/placeholder images
class PlayerInitialsAvatar extends StatelessWidget {
  /// The URL of the player's photo (can be null)
  final String? photoUrl;

  /// The player's initials to display when no photo is available
  final String initials;

  /// The size of the avatar (width and height)
  final double size;

  /// Border radius for the avatar container
  final double? borderRadius;

  /// Optional title badge (e.g., "GM", "IM") shown at the bottom
  final String? title;

  /// Whether to use circular shape instead of rounded rectangle
  final bool isCircular;

  const PlayerInitialsAvatar({
    super.key,
    this.photoUrl,
    required this.initials,
    required this.size,
    this.borderRadius,
    this.title,
    this.isCircular = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveBorderRadius = borderRadius ?? (isCircular ? size / 2 : 12.br);
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;

    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(effectiveBorderRadius),
          child: hasPhoto
              ? _ValidatedNetworkImage(
                  imageUrl: photoUrl!,
                  size: size,
                  initials: initials,
                )
              : _InitialsPlaceholder(
                  initials: initials,
                  size: size,
                ),
        ),
        if (title != null && title!.isNotEmpty)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 3.w, vertical: 1.5.h),
              decoration: BoxDecoration(
                color: getTitleBadgeColor(title!),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(effectiveBorderRadius - 2),
                  bottomRight: Radius.circular(effectiveBorderRadius - 2),
                ),
              ),
              child: Text(
                title!,
                textAlign: TextAlign.center,
                style: AppTypography.textXsMedium.copyWith(
                  color: Colors.white,
                  fontSize: 9.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A network image widget that validates the loaded image isn't a placeholder/black image.
/// Uses ColorFiltered to detect mostly-black images and falls back to initials.
class _ValidatedNetworkImage extends StatefulWidget {
  final String imageUrl;
  final double size;
  final String initials;

  const _ValidatedNetworkImage({
    required this.imageUrl,
    required this.size,
    required this.initials,
  });

  @override
  State<_ValidatedNetworkImage> createState() => _ValidatedNetworkImageState();
}

class _ValidatedNetworkImageState extends State<_ValidatedNetworkImage> {
  bool _imageValidated = false;
  bool _showFallback = false;

  @override
  Widget build(BuildContext context) {
    // If we've determined the image is invalid, show fallback immediately
    if (_showFallback) {
      return _InitialsPlaceholder(
        initials: widget.initials,
        size: widget.size,
      );
    }

    return CachedNetworkImage(
      imageUrl: widget.imageUrl,
      width: widget.size,
      height: widget.size,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 200),
      fadeOutDuration: const Duration(milliseconds: 200),
      placeholder: (context, url) => _InitialsPlaceholder(
        initials: widget.initials,
        size: widget.size,
      ),
      errorWidget: (context, url, error) => _InitialsPlaceholder(
        initials: widget.initials,
        size: widget.size,
      ),
      imageBuilder: (context, imageProvider) {
        // Validate the image once loaded
        if (!_imageValidated) {
          _validateImage(imageProvider);
        }

        return Image(
          image: imageProvider,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            // If frame is null, image isn't loaded yet
            if (frame == null) {
              return _InitialsPlaceholder(
                initials: widget.initials,
                size: widget.size,
              );
            }
            return child;
          },
          errorBuilder: (context, error, stackTrace) {
            return _InitialsPlaceholder(
              initials: widget.initials,
              size: widget.size,
            );
          },
        );
      },
    );
  }

  Future<void> _validateImage(ImageProvider imageProvider) async {
    _imageValidated = true;

    try {
      final ImageStream stream = imageProvider.resolve(ImageConfiguration.empty);
      stream.addListener(ImageStreamListener(
        (ImageInfo info, bool synchronousCall) async {
          final image = info.image;
          final width = image.width;
          final height = image.height;

          // Very small images are placeholders
          if (width < 10 || height < 10) {
            _setFallback();
            return;
          }

          // Check if image is mostly black/dark by sampling pixels
          try {
            final byteData = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            if (byteData != null && _isImageMostlyBlack(byteData, width, height)) {
              _setFallback();
            }
          } catch (e) {
            // If pixel sampling fails, keep the image
          }
        },
        onError: (exception, stackTrace) {
          _setFallback();
        },
      ));
    } catch (e) {
      // If we can't validate, keep showing the image
    }
  }

  void _setFallback() {
    if (mounted) {
      setState(() {
        _showFallback = true;
      });
    }
  }

  /// Samples pixels from the image to determine if it's mostly black.
  /// Returns true if the image appears to be a black placeholder.
  bool _isImageMostlyBlack(ByteData byteData, int width, int height) {
    final bytes = byteData.buffer.asUint8List();
    final totalPixels = width * height;

    // Sample up to 100 pixels evenly distributed across the image
    final sampleCount = totalPixels < 100 ? totalPixels : 100;
    final step = totalPixels ~/ sampleCount;

    int darkPixelCount = 0;
    const darkThreshold = 30; // RGB values below this are considered "dark"

    for (int i = 0; i < sampleCount; i++) {
      final pixelIndex = (i * step) * 4; // 4 bytes per pixel (RGBA)
      if (pixelIndex + 2 < bytes.length) {
        final r = bytes[pixelIndex];
        final g = bytes[pixelIndex + 1];
        final b = bytes[pixelIndex + 2];

        // Check if pixel is dark
        if (r < darkThreshold && g < darkThreshold && b < darkThreshold) {
          darkPixelCount++;
        }
      }
    }

    // If more than 90% of sampled pixels are dark, it's a black placeholder
    return darkPixelCount / sampleCount > 0.90;
  }
}

/// Clean initials placeholder using the app's theme gradient.
class _InitialsPlaceholder extends StatelessWidget {
  final String initials;
  final double size;

  const _InitialsPlaceholder({
    required this.initials,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final fontSize = size * 0.38;
    final effectiveInitials = initials.isNotEmpty ? initials.toUpperCase() : '?';

    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        // Use the app's profile initials gradient for consistency
        gradient: kProfileInitialsGradient,
      ),
      child: Center(
        child: Text(
          effectiveInitials,
          style: TextStyle(
            fontFamily: 'InterDisplay',
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }
}

/// A simpler version of the initials avatar for list items.
/// Uses a cleaner design optimized for smaller sizes.
class PlayerInitialsAvatarCompact extends StatelessWidget {
  final String? photoUrl;
  final String initials;
  final double size;
  final double? borderRadius;

  const PlayerInitialsAvatarCompact({
    super.key,
    this.photoUrl,
    required this.initials,
    required this.size,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveBorderRadius = borderRadius ?? 8.br;
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(effectiveBorderRadius),
      child: hasPhoto
          ? _ValidatedNetworkImageCompact(
              imageUrl: photoUrl!,
              size: size,
              initials: initials,
            )
          : _CompactInitialsPlaceholder(
              initials: initials,
              size: size,
            ),
    );
  }
}

/// Validated network image for compact avatar - detects placeholder/black images.
class _ValidatedNetworkImageCompact extends StatefulWidget {
  final String imageUrl;
  final double size;
  final String initials;

  const _ValidatedNetworkImageCompact({
    required this.imageUrl,
    required this.size,
    required this.initials,
  });

  @override
  State<_ValidatedNetworkImageCompact> createState() =>
      _ValidatedNetworkImageCompactState();
}

class _ValidatedNetworkImageCompactState
    extends State<_ValidatedNetworkImageCompact> {
  bool _imageValidated = false;
  bool _showFallback = false;

  @override
  Widget build(BuildContext context) {
    if (_showFallback) {
      return _CompactInitialsPlaceholder(
        initials: widget.initials,
        size: widget.size,
      );
    }

    return CachedNetworkImage(
      imageUrl: widget.imageUrl,
      width: widget.size,
      height: widget.size,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 150),
      fadeOutDuration: const Duration(milliseconds: 150),
      placeholder: (context, url) => _CompactInitialsPlaceholder(
        initials: widget.initials,
        size: widget.size,
      ),
      errorWidget: (context, url, error) => _CompactInitialsPlaceholder(
        initials: widget.initials,
        size: widget.size,
      ),
      imageBuilder: (context, imageProvider) {
        if (!_imageValidated) {
          _validateImage(imageProvider);
        }

        return Image(
          image: imageProvider,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (frame == null) {
              return _CompactInitialsPlaceholder(
                initials: widget.initials,
                size: widget.size,
              );
            }
            return child;
          },
          errorBuilder: (context, error, stackTrace) {
            return _CompactInitialsPlaceholder(
              initials: widget.initials,
              size: widget.size,
            );
          },
        );
      },
    );
  }

  Future<void> _validateImage(ImageProvider imageProvider) async {
    _imageValidated = true;

    try {
      final ImageStream stream =
          imageProvider.resolve(ImageConfiguration.empty);
      stream.addListener(ImageStreamListener(
        (ImageInfo info, bool synchronousCall) async {
          final image = info.image;
          final width = image.width;
          final height = image.height;

          // Very small images are placeholders
          if (width < 10 || height < 10) {
            _setFallback();
            return;
          }

          // Check if image is mostly black
          try {
            final byteData = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            if (byteData != null && _isImageMostlyBlack(byteData, width, height)) {
              _setFallback();
            }
          } catch (e) {
            // If pixel sampling fails, keep the image
          }
        },
        onError: (exception, stackTrace) {
          _setFallback();
        },
      ));
    } catch (e) {
      // If we can't validate, keep showing the image
    }
  }

  void _setFallback() {
    if (mounted) {
      setState(() {
        _showFallback = true;
      });
    }
  }

  /// Samples pixels to detect mostly-black placeholder images.
  bool _isImageMostlyBlack(ByteData byteData, int width, int height) {
    final bytes = byteData.buffer.asUint8List();
    final totalPixels = width * height;
    final sampleCount = totalPixels < 100 ? totalPixels : 100;
    final step = totalPixels ~/ sampleCount;

    int darkPixelCount = 0;
    const darkThreshold = 30;

    for (int i = 0; i < sampleCount; i++) {
      final pixelIndex = (i * step) * 4;
      if (pixelIndex + 2 < bytes.length) {
        final r = bytes[pixelIndex];
        final g = bytes[pixelIndex + 1];
        final b = bytes[pixelIndex + 2];

        if (r < darkThreshold && g < darkThreshold && b < darkThreshold) {
          darkPixelCount++;
        }
      }
    }

    return darkPixelCount / sampleCount > 0.90;
  }
}

/// A cleaner initials placeholder for compact/list contexts.
class _CompactInitialsPlaceholder extends StatelessWidget {
  final String initials;
  final double size;

  const _CompactInitialsPlaceholder({
    required this.initials,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final fontSize = size * 0.38;
    final effectiveInitials = initials.isNotEmpty ? initials.toUpperCase() : '?';

    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        // Use the app's profile initials gradient for consistency
        gradient: kProfileInitialsGradient,
      ),
      child: Center(
        child: Text(
          effectiveInitials,
          style: TextStyle(
            fontFamily: 'InterDisplay',
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

/// Helper function to extract initials from a player name.
/// Handles common chess player name formats like "Lastname, Firstname".
String getPlayerInitials(String name) {
  if (name.isEmpty) return '?';

  // Handle "Lastname, Firstname" format
  if (name.contains(',')) {
    final parts = name.split(',');
    if (parts.length >= 2) {
      final lastName = parts[0].trim();
      final firstName = parts[1].trim();
      if (firstName.isNotEmpty && lastName.isNotEmpty) {
        return '${firstName[0]}${lastName[0]}'.toUpperCase();
      }
    }
  }

  // Handle "Firstname Lastname" format
  final words = name.trim().split(' ').where((w) => w.isNotEmpty).toList();
  if (words.length >= 2) {
    return '${words.first[0]}${words.last[0]}'.toUpperCase();
  }

  // Single word - take first two characters
  if (words.isNotEmpty) {
    final word = words.first;
    return word.length >= 2
        ? word.substring(0, 2).toUpperCase()
        : word.toUpperCase();
  }

  return '?';
}

/// Returns the appropriate badge color for a chess title.
/// Consistent across the app for all title badge displays.
Color getTitleBadgeColor(String title) {
  switch (title.toUpperCase()) {
    case 'GM':
      return const Color(0xFF22C55E); // Green - Grandmaster
    case 'IM':
      return const Color(0xFFEAB308); // Yellow/Gold - International Master
    case 'FM':
      return const Color(0xFFCD7F32); // Bronze - FIDE Master
    case 'CM':
      return const Color(0xFF8B5CF6); // Purple - Candidate Master
    case 'NM':
      return const Color(0xFF6366F1); // Indigo - National Master
    case 'WGM':
      return const Color(0xFFEC4899); // Pink - Woman Grandmaster
    case 'WIM':
      return const Color(0xFFF59E0B); // Amber - Woman International Master
    case 'WFM':
      return const Color(0xFF14B8A6); // Teal - Woman FIDE Master
    case 'WCM':
      return const Color(0xFFA855F7); // Light Purple - Woman Candidate Master
    case 'WNM':
      return const Color(0xFF8B5CF6); // Purple - Woman National Master
    default:
      return const Color(0xFF71717A); // Gray - Unknown/Other
  }
}
