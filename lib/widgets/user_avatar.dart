import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A user avatar widget that displays:
/// 1. OAuth profile picture (if available from Google/Apple sign-in)
/// 2. User initials (if no picture but name is available)
/// 3. Chess knight piece (♞) as fallback
class UserAvatar extends ConsumerWidget {
  final double size;
  final VoidCallback? onTap;
  final TextStyle? initialsStyle;

  const UserAvatar({
    super.key,
    this.size = 44,
    this.onTap,
    this.initialsStyle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    final avatarUrl = user?.avatarUrl;
    final displayName = user?.displayName;
    final initials = _getInitials(displayName);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
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
      ),
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
