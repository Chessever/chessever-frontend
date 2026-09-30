import 'package:chessever2/chat/botvinnik_icon.dart';
import 'package:chessever2/chat/botvinnik_provider.dart';
import 'package:chessever2/chat/chat_api.dart';
import 'package:chessever2/chat/chat_screen.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

/// Floating launcher that opens a fresh Botvinnik conversation.
///
/// A speech bubble cut from ink: a circle with its lower-left corner drawn in
/// tight, the same corner the logo's own bubble points from, so the silhouette
/// says "ask" before the mark inside it is read. The ink is the app's
/// floating-capsule black (see `app_snack.dart`), lifted toward the logo's
/// teal so it holds its edge on the near-black dark theme and reads as a
/// solid object on the mint light theme, where teal on paper would vanish.
class BotvinnikChatButton extends ConsumerWidget {
  const BotvinnikChatButton({
    required this.heroTag,
    this.screenContext,
    this.iconOnly = false,
    this.onPressed,
    super.key,
  });

  /// What the launcher announces and shows on long press.
  static const label = 'Ask Botvinnik';

  /// Re-arms the once-per-session entrance, so tests can watch it play.
  @visibleForTesting
  static void debugResetSessionEntrance() => _launcherSessionEntered = false;

  final String heroTag;
  final ChatScreenContext? screenContext;

  /// Kept for existing callers. The launcher is always a mark-only bubble.
  final bool iconOnly;

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
    return Hero(
      tag: heroTag,
      child: _BotvinnikLauncher(
        onPressed:
            onPressed ??
            () => ChatScreen.show(
              context,
              screenContext: screenContext,
              createNewConversationOnOpen: true,
            ),
      ),
    );
  }
}

/// The entrance plays for the first launcher of the app session only. Every
/// later screen that hosts one slides in with its route, and a button that
/// greets you on every push is noise.
bool _launcherSessionEntered = false;

class _BotvinnikLauncher extends StatefulWidget {
  const _BotvinnikLauncher({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_BotvinnikLauncher> createState() => _BotvinnikLauncherState();
}

class _BotvinnikLauncherState extends State<_BotvinnikLauncher> {
  // Press is a frequent action: short and firm. Entrance is a one-off: long
  // enough to be noticed, no bounce. Both land on exact identity.
  static const _pressMotion = CupertinoMotion.snappy(
    duration: Duration(milliseconds: 240),
    snapToEnd: true,
  );
  static const _entranceMotion = CupertinoMotion.smooth(
    duration: Duration(milliseconds: 460),
    snapToEnd: true,
  );

  late final bool _playEntrance;
  bool _pressed = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _playEntrance = !_launcherSessionEntered;
    _launcherSessionEntered = true;
  }

  void _setPressed(bool value) {
    if (_pressed != value && mounted) setState(() => _pressed = value);
  }

  void _activate() {
    HapticFeedbackService.buttonPress();
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final palette = context.isLightTheme
        ? _LauncherPalette.light
        : _LauncherPalette.dark;
    // 56dp on the 393pt design phone; bounded so a tablet's scale factor
    // can't balloon it and a compact phone keeps it well clear of 48dp.
    final side = 56.ic.clamp(52.0, 64.0);

    // The mark's weight sits slightly low (a wide bubble under a cut-out
    // crown), so it rides a hair above geometric centre to look centred.
    final mark = Transform.translate(
      offset: Offset(0, -side * 0.018),
      child: BotvinnikMark(size: side * 0.73),
    );

    Widget visual = SingleMotionBuilder(
      motion: _pressMotion,
      value: _pressed ? 1.0 : 0.0,
      active: !reduceMotion,
      child: mark,
      builder: (context, value, child) {
        final press = value.clamp(0.0, 1.0);
        final scale = reduceMotion ? 1.0 : _identitySnap(1 - 0.03 * value);
        return Transform.scale(
          scale: scale,
          child: _LauncherSurface(
            side: side,
            palette: palette,
            press: press,
            focused: _focused,
            child: child!,
          ),
        );
      },
    );

    // One gentle rise the first time a launcher appears. The button is fully
    // opaque from frame one: only its position and size settle.
    visual = SingleMotionBuilder(
      motion: _entranceMotion,
      from: _playEntrance && !reduceMotion ? 0.0 : null,
      value: 1.0,
      child: visual,
      builder: (context, value, child) {
        final t = value.clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, (1 - t) * 10),
          child: Transform.scale(
            scale: _identitySnap(0.9 + 0.1 * t),
            child: child,
          ),
        );
      },
    );

    return Tooltip(
      message: BotvinnikChatButton.label,
      excludeFromSemantics: true,
      child: Semantics(
        container: true,
        button: true,
        label: BotvinnikChatButton.label,
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
          // Raw pointer events so the press shows on touch-down, not after
          // the tap recognizer's 100ms arena wait (the tooltip's long-press
          // recognizer competes for every touch).
          child: Listener(
            onPointerDown: (_) => _setPressed(true),
            onPointerUp: (_) => _setPressed(false),
            onPointerCancel: (_) => _setPressed(false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _activate,
              child: SizedBox.square(dimension: side, child: visual),
            ),
          ),
        ),
      ),
    );
  }
}

/// Springs only approach their target; a resting scale of 0.999998 blurs the
/// mark and shaves the hit box, so the settled frame is pinned to 1.0.
double _identitySnap(double scale) => (scale - 1).abs() < 0.002 ? 1.0 : scale;

/// Colours for one theme. The surface and edge are tones of the same
/// teal-ink family as the mark, so nothing on the button is a foreign colour.
@immutable
class _LauncherPalette {
  const _LauncherPalette({
    required this.surface,
    required this.surfacePressed,
    required this.edgeTop,
    required this.edgeBottom,
    required this.shadows,
  });

  final Color surface;
  final Color surfacePressed;

  /// The 1px lip is lit from above: bright where light catches the top,
  /// dimming toward the bottom. In dark it is the silhouette, so [edgeBottom]
  /// must still clear 3:1 against the page.
  final Color edgeTop;
  final Color edgeBottom;

  /// One light source: a tight contact shadow and a short fall-off below it.
  final List<BoxShadow> shadows;

  static const _ink = Color(0xFF0B1A19);
  static const _inkLifted = Color(0xFF1B3431);

  // On the near-black dark theme the surface is lifted toward teal so the
  // body has mass of its own (1.5:1 against the background), and the lip
  // carries the silhouette. The lip is still lit from above, but its dim end
  // never drops below 3:1: the lower-left tail, the corner that says "ask",
  // sits at that dim end and holds 4.0:1 against the background and 3.5:1
  // against a card (5.9:1 at the top). The mark itself is 8.2:1 on this
  // surface.
  static final dark = _LauncherPalette(
    surface: _inkLifted,
    surfacePressed: const Color(0xFF22403C),
    edgeTop: BotvinnikMark.teal.withValues(alpha: 0.6),
    edgeBottom: BotvinnikMark.teal.withValues(alpha: 0.42),
    shadows: const [
      BoxShadow(color: Color(0x66000000), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(color: Color(0x73000000), blurRadius: 10, offset: Offset(0, 4)),
    ],
  );

  // On the mint light theme the ink itself does the separating (14.8:1
  // against the background); the lip is only a quiet highlight and the
  // shadow is tinted with the ink rather than grey.
  static final light = _LauncherPalette(
    surface: _ink,
    surfacePressed: const Color(0xFF16302D),
    edgeTop: BotvinnikMark.teal.withValues(alpha: 0.4),
    edgeBottom: BotvinnikMark.teal.withValues(alpha: 0.1),
    shadows: [
      BoxShadow(
        color: _ink.withValues(alpha: 0.24),
        blurRadius: 2,
        offset: const Offset(0, 1),
      ),
      BoxShadow(
        color: _ink.withValues(alpha: 0.22),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
    ],
  );
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
    required this.palette,
    required this.press,
    required this.focused,
    required this.child,
  });

  final double side;
  final _LauncherPalette palette;
  final double press;
  final bool focused;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = _bubbleRadius(side);
    return CustomPaint(
      foregroundPainter: _LipPainter(
        radius: radius,
        top: palette.edgeTop,
        bottom: palette.edgeBottom,
        // The ring sits outside the silhouette, on the page, so it takes the
        // page's accent ink in light (pale teal on mint is 1.35:1).
        ring: focused
            ? (context.isLightTheme
                  ? context.colors.accentText
                  : BotvinnikMark.teal)
            : null,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color.lerp(palette.surface, palette.surfacePressed, press),
          borderRadius: radius,
          boxShadow: palette.shadows,
        ),
        child: SizedBox.square(
          dimension: side,
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _LipPainter extends CustomPainter {
  const _LipPainter({
    required this.radius,
    required this.top,
    required this.bottom,
    this.ring,
  });

  final BorderRadius radius;
  final Color top;
  final Color bottom;

  /// Keyboard-focus ring colour; null when the launcher isn't focused.
  final Color? ring;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final lip = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [top, bottom],
      ).createShader(rect);
    canvas.drawRRect(radius.toRRect(rect).deflate(0.5), lip);

    final ringColor = ring;
    if (ringColor != null) {
      // Keyboard focus: a solid ring set just outside the silhouette.
      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = ringColor;
      canvas.drawRRect(radius.toRRect(rect).inflate(3), ringPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LipPainter oldDelegate) {
    return oldDelegate.radius != radius ||
        oldDelegate.top != top ||
        oldDelegate.bottom != bottom ||
        oldDelegate.ring != ring;
  }
}
