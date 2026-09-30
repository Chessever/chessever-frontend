import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:chessever2/screens/streaks/widgets/player_streak_avatar.dart';
import 'package:chessever2/screens/streaks/widgets/player_streak_format.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_button.dart';
import 'package:flutter/material.dart';

/// The bar over the card: back on the left; Add to My Space and Open profile
/// on the right. Bare icons, no plates, 44pt targets.
class PlayerStreakTopBar extends StatelessWidget {
  const PlayerStreakTopBar({
    super.key,
    required this.inSpace,
    this.onToggleSpace,
    this.onOpenProfile,
  });

  final bool inSpace;

  /// Null hides the action (nothing to pin yet).
  final VoidCallback? onToggleSpace;
  final VoidCallback? onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final ink = context.colors.iconPrimary;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 8.w),
        child: SizedBox(
          height: 44.w,
          child: Row(
            children: [
              PlayerBarButton(
                label: 'Back',
                icon: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 20.w,
                  color: ink,
                ),
                onTap: () => Navigator.of(context).maybePop(),
              ),
              const Spacer(),
              if (onToggleSpace != null)
                PlayerBarButton(
                  key: const ValueKey('streak-player-space'),
                  label: inSpace ? 'Remove from My Space' : 'Add to My Space',
                  icon: Icon(
                    inSpace
                        ? Icons.dashboard_customize
                        : Icons.dashboard_customize_outlined,
                    size: 22.w,
                    color: ink,
                  ),
                  onTap: onToggleSpace!,
                ),
              if (onOpenProfile != null)
                PlayerBarButton(
                  key: const ValueKey('streak-player-profile'),
                  label: 'Open profile',
                  icon: Icon(
                    Icons.person_outline_rounded,
                    size: 24.w,
                    color: ink,
                  ),
                  onTap: onOpenProfile!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A 44pt bare icon target that presses in, with its label for screen readers
/// and a long-press tooltip.
class PlayerBarButton extends StatelessWidget {
  const PlayerBarButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final Widget icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: TappableScale(
          scaleDown: 0.97,
          onTap: onTap,
          child: SizedBox.square(
            dimension: 44.w,
            child: Center(child: icon),
          ),
        ),
      ),
    );
  }
}

/// Avatar, display name and `GM · 2733 · China · 33 y` (the rating follows the
/// selected class). Tapping the photo or name opens the full profile.
class PlayerStreakIdentity extends StatelessWidget {
  const PlayerStreakIdentity({
    super.key,
    required this.player,
    required this.timeClass,
    this.onOpenProfile,
  });

  final PlayerStreaks player;
  final StreakTimeClass timeClass;
  final VoidCallback? onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final meta = streakPlayerMeta(player, timeClass);
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PlayerStreakAvatar(
          fideId: player.fideId,
          name: player.name,
          size: 72.w,
          title: player.title,
          fed: player.fed,
        ),
        SizedBox(height: 12.w),
        Text(
          player.displayName,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: streakText(
            context,
            size: 22,
            line: 28,
            weight: FontWeight.w700,
          ),
        ),
        if (meta.isNotEmpty)
          Text.rich(
            streakFigures(meta),
            key: const ValueKey('streak-player-meta'),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: streakText(
              context,
              size: 13,
              line: 18,
              color: context.colors.textPrimaryMuted,
            ),
          ),
      ],
    );
    if (onOpenProfile == null) return body;
    return Semantics(
      button: true,
      hint: 'Opens the full profile',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onOpenProfile,
        child: body,
      ),
    );
  }
}
