import 'package:chessever2/screens/inbox/inbox_provider.dart';
import 'package:chessever2/chat/botvinnik_icon.dart';
import 'package:chessever2/chat/botvinnik_provider.dart';
import 'package:chessever2/chat/chat_api.dart';
import 'package:chessever2/chat/chat_screen.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/widgets/glass_surface.dart';
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:chessever2/widgets/press_spring.dart';
import 'package:chessever2/widgets/search_mode/search_count_badge.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Floating launcher that opens a fresh Botvinnik conversation.
///
/// One of the page's floating buttons ([InkFabStack]), cut from the same
/// frosted glass ([GlassSurface]) at the same [InkFabSize] discs, with the
/// same press ([PressSpring] at 0.9) and count badge ([SearchCountBadge]).
/// Its outline is a speech bubble: a circle with its lower-left corner drawn
/// in tight, the corner the logo's own bubble points from, so the silhouette
/// says "ask" before the mark inside it is read. The mark keeps the logo's
/// own colours, which are the bot's face.
///
/// No entrance: it is there with its page, like every floating button.
class BotvinnikChatButton extends ConsumerWidget {
  const BotvinnikChatButton({
    this.heroTag,
    this.screenContext,
    this.iconOnly = false,
    this.size = InkFabSize.regular,
    this.onPressed,
    super.key,
  });

  /// What the launcher announces and shows on long press.
  static const label = 'Ask Botvinnik';

  /// Ignored. The launcher no longer flies between routes (nothing matched
  /// its hero); kept so existing callers compile.
  final String? heroTag;
  final ChatScreenContext? screenContext;

  /// Kept for existing callers. The launcher is always a mark-only bubble.
  final bool iconOnly;

  /// Regular when it is the page's main (bottom) button, small when it sits
  /// above another one in the stack.
  final InkFabSize size;

  /// Replaces the default action (open a new Botvinnik chat for
  /// [screenContext]). Hosts that route the chat themselves, and tests, pass
  /// it; everyone else leaves it null.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(botvinnikEnabledProvider).valueOrNull ?? true;
    if (!ChatApi.buildEnabled || !enabled) {
      return const SizedBox.shrink();
    }
    return _BotvinnikLauncher(
      size: size,
      unreadCount: ref.watch(inboxUnreadCountProvider),
      onPressed:
          onPressed ??
          () => ChatScreen.show(
            context,
            screenContext: screenContext,
            createNewConversationOnOpen: true,
          ),
    );
  }
}

class _BotvinnikLauncher extends StatefulWidget {
  const _BotvinnikLauncher({
    required this.size,
    required this.onPressed,
    required this.unreadCount,
  });

  final InkFabSize size;
  final int unreadCount;
  final VoidCallback onPressed;

  @override
  State<_BotvinnikLauncher> createState() => _BotvinnikLauncherState();
}

class _BotvinnikLauncherState extends State<_BotvinnikLauncher> {
  bool _focused = false;

  void _activate() {
    HapticFeedbackService.buttonPress();
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final disc = widget.size.disc;

    // The mark's weight sits slightly low (a wide bubble under a cut-out
    // crown), so it rides a hair above geometric centre to look centred.
    final mark = Transform.translate(
      offset: Offset(0, -disc * 0.018),
      child: BotvinnikMark(size: disc * 0.73),
    );

    // The app's press, as on every floating button ([InkFab]): down under
    // the finger, back with a little pop, the glass brightening while held.
    final button = SizedBox.square(
      dimension: disc,
      child: PressSpring(
        pressedScale: 0.9,
        child: mark,
        builder: (context, press, child) {
          final scale = 1 - 0.1 * press;
          return Transform.scale(
            scale: (scale - 1).abs() < 0.001 ? 1.0 : scale,
            child: _LauncherSurface(
              side: disc,
              press: press.clamp(0.0, 1.0),
              focused: _focused,
              child: child,
            ),
          );
        },
      ),
    );

    return Tooltip(
      message: BotvinnikChatButton.label,
      excludeFromSemantics: true,
      child: Semantics(
        container: true,
        button: true,
        label: widget.unreadCount > 0
            ? '${BotvinnikChatButton.label}, ${widget.unreadCount} unread Inbox messages'
            : BotvinnikChatButton.label,
        child: FocusableActionDetector(
          mouseCursor: SystemMouseCursors.click,
          onShowFocusHighlight: (value) {
            if (_focused != value) setState(() => _focused = value);
          },
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                _activate();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _activate,
            // The disc in a square never under the 44pt target, as every
            // floating button takes touches.
            child: SizedBox.square(
              dimension: widget.size.side,
              child: Center(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    button,
                    // The one count style ([SearchCountBadge]), the one the
                    // floating search beside it wears, stepping back with
                    // the glass ([GlassFade]) as the search opens instead
                    // of staying solid and popping off.
                    if (widget.unreadCount > 0)
                      Positioned(
                        top: -2,
                        right: -2,
                        child: ExcludeSemantics(
                          child: GlassFade.content(
                            context,
                            SearchCountBadge(
                              key: const ValueKey('botvinnik-unread-badge'),
                              count: widget.unreadCount,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Round on three corners, drawn in tight on the lower left: the tail.
BorderRadius _bubbleRadius(double side) {
  final round = Radius.circular(side / 2);
  return BorderRadius.only(
    topLeft: round,
    topRight: round,
    bottomRight: round,
    bottomLeft: Radius.circular(side * 4 / 56),
  );
}

class _LauncherSurface extends StatelessWidget {
  const _LauncherSurface({
    required this.side,
    required this.press,
    required this.focused,
    required this.child,
  });

  final double side;
  final double press;
  final bool focused;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = _bubbleRadius(side);
    // The same frosted glass as every floating button, in the bubble's own
    // outline.
    final glass = GlassSurface(
      borderRadius: radius,
      lift: press,
      child: SizedBox.square(
        dimension: side,
        child: Center(child: child),
      ),
    );
    if (!focused) return glass;
    return CustomPaint(
      foregroundPainter: _FocusRingPainter(
        radius: radius,
        // The ring sits outside the silhouette, on the page, so it takes the
        // page's accent ink in light (pale teal on mint is 1.35:1).
        color: context.isLightTheme
            ? context.colors.accentText
            : BotvinnikMark.teal,
      ),
      child: glass,
    );
  }
}

/// Keyboard focus: a solid ring set just outside the bubble's silhouette.
class _FocusRingPainter extends CustomPainter {
  const _FocusRingPainter({required this.radius, required this.color});

  final BorderRadius radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color;
    canvas.drawRRect(radius.toRRect(Offset.zero & size).inflate(3), ring);
  }

  @override
  bool shouldRepaint(covariant _FocusRingPainter oldDelegate) =>
      oldDelegate.radius != radius || oldDelegate.color != color;
}
