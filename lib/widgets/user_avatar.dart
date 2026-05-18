import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A user avatar widget that displays:
/// 1. OAuth profile picture (if available from Google/Apple sign-in)
/// 2. User initials (if no picture but name is available)
/// 3. Chess knight piece (♞) as fallback
///
/// When the user has a premium subscription, an animated golden gradient
/// border is displayed around the avatar.
class UserAvatar extends HookConsumerWidget {
  final double size;
  final VoidCallback? onTap;
  final TextStyle? initialsStyle;

  /// If true, shows premium border when user is subscribed.
  /// Set to false to hide the border in certain contexts.
  final bool showPremiumBorder;

  const UserAvatar({
    super.key,
    this.size = 44,
    this.onTap,
    this.initialsStyle,
    this.showPremiumBorder = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final subscriptionState = ref.watch(subscriptionProvider);
    final isPremium = subscriptionState.isSubscribed;

    final avatarUrl = user?.avatarUrl;
    final displayName = user?.displayName;
    final initials = _getInitials(displayName);

    // Animation controller for the rotating gradient border
    final animationController = useAnimationController(
      duration: const Duration(seconds: 3),
    );

    useEffect(() {
      if (isPremium && showPremiumBorder) {
        animationController.repeat();
      } else {
        animationController.stop();
        animationController.reset();
      }
      return null;
    }, [isPremium, showPremiumBorder]);

    final avatarWidget = AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: size.w,
      height: size.w,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: avatarUrl == null ? kProfileInitialsGradient : null,
        color: avatarUrl != null ? context.colors.surfaceRecessed : null,
        boxShadow: [
          BoxShadow(
            color: kPrimaryColor.withAlpha(7),
            blurRadius: 4.br,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(child: _buildAvatarContent(context, avatarUrl, initials)),
    );

    // Wrap with premium border if subscribed
    if (isPremium && showPremiumBorder) {
      return GestureDetector(
        onTap: onTap,
        child: AnimatedBuilder(
          animation: animationController,
          builder: (context, child) {
            return CustomPaint(
              painter: _PremiumBorderPainter(
                progress: animationController.value,
                borderWidth: 2.5,
              ),
              child: Padding(padding: EdgeInsets.all(7.sp), child: child),
            );
          },
          child: avatarWidget,
        ),
      );
    }

    return GestureDetector(onTap: onTap, child: avatarWidget);
  }

  Widget _buildAvatarContent(
    BuildContext context,
    String? avatarUrl,
    String initials,
  ) {
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      final cacheSize =
          (size.w * MediaQuery.devicePixelRatioOf(context)).toInt();
      return CachedNetworkImage(
        imageUrl: avatarUrl,
        fit: BoxFit.cover,
        width: size.w,
        height: size.w,
        memCacheWidth: cacheSize,
        placeholder: (context, url) => _buildFallback(context, initials),
        errorWidget: (context, url, error) => _buildFallback(context, initials),
      );
    }

    return _buildFallback(context, initials);
  }

  Widget _buildFallback(BuildContext context, String initials) {
    final content = initials.isNotEmpty ? initials : '♞';
    final effectiveStyle =
        initialsStyle ??
        (size >= 44
            ? AppTypography.textMdBold
            : TextStyle(
              color: context.colors.surface,
              fontWeight: FontWeight.bold,
              fontSize: (size * 0.35).f,
            ));

    return Container(
      decoration: BoxDecoration(gradient: kProfileInitialsGradient),
      child: Center(
        child: Text(
          content,
          style: effectiveStyle.copyWith(color: context.colors.surface),
        ),
      ),
    );
  }

  String _getInitials(String? displayName) {
    if (displayName == null || displayName.isEmpty) return '';

    final parts = displayName.trim().split(' ');
    if (parts.isEmpty) return '';
    if (parts.length == 1) {
      return parts.first.isNotEmpty ? parts.first[0].toUpperCase() : '';
    }

    final first = parts.first.isNotEmpty ? parts.first[0] : '';
    final last = parts.last.isNotEmpty ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }
}

/// Custom painter for the animated premium gradient border.
/// Creates a smooth rotating gradient using app brand colors.
class _PremiumBorderPainter extends CustomPainter {
  final double progress;
  final double borderWidth;

  _PremiumBorderPainter({required this.progress, this.borderWidth = 3.0});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Inset the ring from the widget edge so the glow fits within bounds.
    // Glow extends beyond the ring by: (glowStroke - borderWidth) / 2 + blurSigma
    const glowExtraStroke = 2.0;
    const blurSigma = 2.0;
    final glowMargin = glowExtraStroke / 2 + blurSigma;
    final radius = (size.width / 2) - borderWidth / 2 - glowMargin;

    // Save canvas state and rotate around center for smooth continuous animation
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(progress * 2 * math.pi);
    canvas.translate(-center.dx, -center.dy);

    // Create gradient with app brand colors (cyan/teal tones)
    // Using fixed angles so rotation is handled by canvas transform
    const sweepGradient = SweepGradient(
      colors: [
        Color(0xFF0FB4E5), // Primary cyan
        Color(0xFF17AAD6), // Dark blue
        Color(0xFF08647F), // Deep teal
        Color(0xFF0FB4E5), // Primary cyan
        Color(0xFF68D3FF), // Light cyan (calendar active color)
        Color(0xFF0FB4E5), // Primary cyan (loop back seamlessly)
      ],
      stops: [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
    );

    final paint =
        Paint()
          ..shader = sweepGradient.createShader(
            Rect.fromCircle(center: center, radius: radius),
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth
          ..strokeCap = StrokeCap.round;

    // Draw the border
    canvas.drawCircle(center, radius, paint);

    // Add a subtle glow effect
    final glowPaint =
        Paint()
          ..shader = sweepGradient.createShader(
            Rect.fromCircle(center: center, radius: radius),
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth + glowExtraStroke
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, blurSigma);

    canvas.drawCircle(center, radius, glowPaint);

    // Restore canvas state
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PremiumBorderPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
