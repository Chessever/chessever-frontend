import 'package:chessever2/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Floating circular glass island wrapping the user avatar.
///
/// Replaces a flat avatar embedded in a full-width topbar row.
class GlassAvatarIsland extends StatelessWidget {
  const GlassAvatarIsland({
    super.key,
    this.onTap,
    this.size = 40,
    this.showPremiumBorder = true,
  });

  final VoidCallback? onTap;
  final double size;
  final bool showPremiumBorder;

  @override
  Widget build(BuildContext context) {
    return GlassIconButton(
      icon: UserAvatar(
        size: size * 0.72,
        showPremiumBorder: showPremiumBorder,
        onTap: null,
      ),
      onPressed: onTap,
      size: size,
      useOwnLayer: true,
      shape: GlassIconButtonShape.circle,
    );
  }
}
