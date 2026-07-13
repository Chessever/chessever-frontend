import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// The user avatar seated in a single thin liquid-glass rim — the glass IS the
/// frame, so there is only one border.
///
/// Premium is shown with one small, STATIC badge in the corner (a glass-tinted
/// crown), not a second animated ring around the avatar — a spinning gradient
/// border competing with the glass rim was distracting and read as clutter.
class GlassAvatarIsland extends ConsumerWidget {
  const GlassAvatarIsland({super.key, this.onTap, this.size = 44});

  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPremium = ref.watch(subscriptionProvider).isSubscribed;
    final badgeSize = size * 0.36;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GlassIconButton(
            // Inset padding = the glass rim; the avatar fills the rest of the
            // disc. showPremiumBorder:false — the glass is the only border.
            icon: Padding(
              padding: EdgeInsets.all(size * 0.06),
              child: UserAvatar(
                size: size * 0.88,
                showPremiumBorder: false,
                onTap: null,
              ),
            ),
            onPressed: onTap,
            size: size,
            useOwnLayer: true,
            shape: GlassIconButtonShape.circle,
          ),
          if (isPremium)
            Positioned(
              right: -1,
              bottom: -1,
              child: _PremiumBadge(size: badgeSize, ringColor: context.colors.background),
            ),
        ],
      ),
    );
  }
}

/// A small static premium mark — a warm gold disc with a crown, ringed by the
/// page background so it reads cleanly against the avatar.
class _PremiumBadge extends StatelessWidget {
  const _PremiumBadge({required this.size, required this.ringColor});

  final double size;
  final Color ringColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFD86B), Color(0xFFF5A623)],
        ),
        border: Border.all(color: ringColor, width: size * 0.12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF5A623).withValues(alpha: 0.45),
            blurRadius: size * 0.35,
          ),
        ],
      ),
      child: Icon(
        Icons.workspace_premium_rounded,
        size: size * 0.62,
        color: const Color(0xFF5A3A00),
      ),
    );
  }
}
