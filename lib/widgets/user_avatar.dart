import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
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
      height: size.h,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: avatarUrl == null ? kProfileInitialsGradient : null,
        color: avatarUrl != null ? kGrey900 : null,
        boxShadow: [
          BoxShadow(
            color: kPrimaryColor.withAlpha(7),
            blurRadius: 4.br,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: _buildAvatarContent(avatarUrl, initials),
      ),
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
              child: Padding(
                padding: EdgeInsets.all(4.sp),
                child: child,
              ),
            );
          },
          child: avatarWidget,
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: avatarWidget,
    );
  }

  Widget _buildAvatarContent(String? avatarUrl, String initials) {
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: avatarUrl,
        fit: BoxFit.cover,
        width: size.w,
        height: size.h,
        placeholder: (context, url) => _buildFallback(initials),
        errorWidget: (context, url, error) => _buildFallback(initials),
      );
    }

    return _buildFallback(initials);
  }

  Widget _buildFallback(String initials) {
    final content = initials.isNotEmpty ? initials : '♞';
    final effectiveStyle =
        initialsStyle ??
        (size >= 44
            ? AppTypography.textMdBold
            : TextStyle(
              color: kBlack2Color,
              fontWeight: FontWeight.bold,
              fontSize: (size * 0.35).f,
            ));

    return Container(
      decoration: BoxDecoration(
        gradient: kProfileInitialsGradient,
      ),
      child: Center(
        child: Text(
          content,
          style: effectiveStyle.copyWith(
            color: kBlack2Color,
          ),
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
/// Creates a rotating golden/rainbow gradient effect.
class _PremiumBorderPainter extends CustomPainter {
  final double progress;
  final double borderWidth;

  _PremiumBorderPainter({
    required this.progress,
    this.borderWidth = 3.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - borderWidth / 2;

    // Create rotating gradient
    final sweepGradient = SweepGradient(
      startAngle: progress * 2 * math.pi,
      endAngle: (progress * 2 * math.pi) + (2 * math.pi),
      colors: const [
        Color(0xFFFFD700), // Gold
        Color(0xFFFFA500), // Orange
        Color(0xFFFF6B6B), // Coral
        Color(0xFF9370DB), // Purple
        Color(0xFF00CED1), // Cyan
        Color(0xFF00FF7F), // Spring Green
        Color(0xFFFFD700), // Gold (loop back)
      ],
      stops: const [0.0, 0.17, 0.33, 0.5, 0.67, 0.83, 1.0],
    );

    final paint = Paint()
      ..shader = sweepGradient.createShader(
        Rect.fromCircle(center: center, radius: radius),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth
      ..strokeCap = StrokeCap.round;

    // Draw the border
    canvas.drawCircle(center, radius, paint);

    // Add a subtle glow effect
    final glowPaint = Paint()
      ..shader = sweepGradient.createShader(
        Rect.fromCircle(center: center, radius: radius),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth + 2
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    canvas.drawCircle(center, radius, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _PremiumBorderPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
