import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/screens/home/home_screen.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/widgets/liquid_glass/glass_avatar_island.dart';
import 'package:chessever2/widgets/liquid_glass/glass_motion.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

/// Top-left branding for the home tabs: the user's glass avatar island beside
/// their first name — or the "ChessEver" wordmark when no name is available.
/// Tapping the avatar opens the left drawer.
///
/// The name never shows a hard `…` ellipsis: any overflow is masked with a soft
/// right-edge fade so it dissolves cleanly instead of chopping mid-word. When
/// [collapsed] is true (the mode tabs have separated into wider icon chips on
/// scroll-down) the name yields its room on purpose — it fades out and its width
/// animates to zero so the chips get space, instead of the two fighting over the
/// row and the name getting truncated to "Ber…".
class GlassProfileHeader extends ConsumerWidget {
  const GlassProfileHeader({super.key, this.onAvatarTap, this.collapsed = false});

  final VoidCallback? onAvatarTap;
  final bool collapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final display = user?.displayName?.trim();
    final firstName =
        (display != null && display.isNotEmpty) ? display.split(' ').first : null;
    final label = firstName ?? 'ChessEver';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassAvatarIsland(
          onTap:
              onAvatarTap ??
              () => homeScaffoldKey.currentState?.openDrawer(),
        ),
        // The avatar always stays put; only the name collapses/reveals.
        Flexible(
          child: SingleMotionBuilder(
            motion: collapsed ? GlassMotion.collapse : GlassMotion.widen,
            value: collapsed ? 0.0 : 1.0,
            builder: (context, raw, _) {
              final t = raw.clamp(0.0, 1.0);
              if (t <= 0.001) return const SizedBox.shrink();
              return ClipRect(
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: t,
                  child: Opacity(
                    opacity: t,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: _FadingName(label: label),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The name, rendered full when it fits and — only when it genuinely overflows
/// the available width — with a soft right-edge fade instead of a hard `…`.
///
/// The fade is measured, not unconditional: an earlier version masked the last
/// slice of the text always, so even a short name that fit looked chopped. Here
/// we measure the text against the incoming width and only fade the tail (a
/// fixed ~24px) when it truly can't fit.
class _FadingName extends StatelessWidget {
  const _FadingName({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.textMdBold.copyWith(
      color: context.colors.textPrimary,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final painter = TextPainter(
          text: TextSpan(text: label, style: style),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout();

        final text = Text(
          label,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
          style: style,
        );

        // Fits (or unbounded) → no fade, show it all.
        if (!maxWidth.isFinite || painter.width <= maxWidth) return text;

        // Overflows → fade only the last ~24px, not a fixed fraction.
        final fadeFrac = (24 / maxWidth).clamp(0.0, 1.0);
        return ShaderMask(
          shaderCallback: (rect) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              stops: [0.0, 1 - fadeFrac, 1.0],
              colors: const [Colors.white, Colors.white, Colors.transparent],
            ).createShader(rect);
          },
          blendMode: BlendMode.dstIn,
          child: text,
        );
      },
    );
  }
}
