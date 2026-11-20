import 'dart:math' as math;

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/widgets/glass_surface.dart';
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:chessever2/widgets/live_glyph.dart';
import 'package:chessever2/widgets/press_spring.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

/// What turning Live first on does to the list it floats over, so the
/// button can say it aloud.
enum LiveFirstMode {
  /// The live ones lead and every other one stays listed (an event's Games,
  /// Favorites, Countrymen, Today, Events).
  reorder,

  /// Only the live ones are listed; the others are hidden until it is
  /// turned off. No list does this today.
  liveOnly,
}

/// Live first, floating: one of the page's round glass buttons ([InkFab]'s
/// disc, glass, press and glyph scale), wearing the live mark ([LiveGlyph]),
/// a solid dot broadcasting.
///
/// Off, the arcs sit in the glass's ink and the dot in the app's live colour
/// (`accentText`, the colour of every LIVE label). On, the glass takes the
/// brand's tonal blue as every floating toggle does and the whole mark wears
/// it. Between the two the colours cross on a spring and the arcs push out
/// once, the signal leaving the dot; with reduced motion it snaps. Nothing
/// moves at rest.
///
/// No count is drawn. The live count and what a tap does are read aloud and
/// shown as the tooltip ("Show the 11 live games first"; on, "Live games
/// shown first", with how to get the usual order back).
///
/// The same full-size disc as the page's main button (the search, or
/// Today's filter) it floats above (PM, 2026-11-20). It answers touches over
/// at least 44pt.
class LiveFirstCapsule extends StatelessWidget {
  const LiveFirstCapsule({
    super.key,
    required this.on,
    required this.onTap,
    this.liveCount,
    this.subject = 'games',
    this.size = InkFabSize.regular,
    this.mode = LiveFirstMode.reorder,
  });

  /// Whether live items are shown first right now.
  final bool on;

  /// Flips Live first. The button plays the toggle haptic itself.
  final VoidCallback onTap;

  /// How many are live, when the page knows. Only read aloud and in the
  /// tooltip; null (or 0) leaves the number out.
  final int? liveCount;

  /// What comes first, plural: "games" or "events". Only read aloud.
  final String subject;

  /// Which floating button it is: regular (the default), the size of the
  /// page's main button.
  final InkFabSize size;

  /// What on does to the list: reorder it (the default) or hide what is not
  /// live. Sets what is read aloud.
  final LiveFirstMode mode;

  /// The on/off change: quick, with a hair of bounce.
  static const CupertinoMotion motion = CupertinoMotion.snappy(
    duration: Duration(milliseconds: 380),
    snapToEnd: true,
  );

  /// How strongly the glass takes the brand's tonal blue while on: the
  /// floating buttons' own "on" tint ([InkFab]).
  static const double onTintAlpha = 0.16;

  /// The key of the mark while off, and while on: what tests find to tell
  /// the drawn state.
  static const Key offGlyphKey = ValueKey<String>('live_first_capsule_off');
  static const Key onGlyphKey = ValueKey<String>('live_first_capsule_on');

  /// What a screen reader announces, and the tooltip: off, what a tap does;
  /// on, what is in force.
  static String semanticsLabelFor({
    required bool on,
    int? liveCount,
    String subject = 'games',
    LiveFirstMode mode = LiveFirstMode.reorder,
  }) {
    final count = liveCount;
    final known = count != null && count > 0;
    switch (mode) {
      case LiveFirstMode.reorder:
        if (on) return 'Live $subject shown first';
        if (!known) return 'Show live $subject first';
        if (count == 1) return 'Show the live ${_singular(subject)} first';
        return 'Show the $count live $subject first';
      case LiveFirstMode.liveOnly:
        if (on) return 'Only live $subject shown';
        if (!known) return 'Show only live $subject';
        if (count == 1) return 'Show only the live ${_singular(subject)}';
        return 'Show only the $count live $subject';
    }
  }

  /// The hint read after the label while on, where the label says what is,
  /// not what a tap does: back to the usual order where nothing was hidden,
  /// back to every one where the rest was. Off, the label is the action.
  static String? semanticsHintFor({
    required bool on,
    String subject = 'games',
    LiveFirstMode mode = LiveFirstMode.reorder,
  }) {
    if (!on) return null;
    return switch (mode) {
      LiveFirstMode.reorder => 'Double tap to restore the usual order',
      LiveFirstMode.liveOnly => 'Double tap to show all $subject',
    };
  }

  static String _singular(String subject) =>
      subject.length > 1 && subject.endsWith('s')
      ? subject.substring(0, subject.length - 1)
      : subject;

  void _activate() {
    HapticFeedbackService.toggle();
    onTap();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final disc = size.disc;
    final glass = GlassStyle.of(context);
    final live = context.colors.accentText;

    // The app's press, as on every floating button ([InkFab]): down under
    // the finger, back with a little pop, the glass brightening while held.
    // The on/off spring runs outside it, so a press never restarts it.
    final button = SizedBox.square(
      dimension: disc,
      child: SingleMotionBuilder(
        motion: motion,
        value: on ? 1.0 : 0.0,
        active: !reduce,
        builder: (context, raw, _) {
          final t = raw.clamp(0.0, 1.0);
          final glyph = LiveGlyph(
            key: on ? onGlyphKey : offGlyphKey,
            size: disc * InkFab.glyphFraction,
            dotColor: live,
            waveColor: Color.lerp(glass.ink, live, t)!,
            // Once out and back over the change, whichever way it goes.
            spread: math.sin(math.pi * t),
          );
          return PressSpring(
            pressedScale: 0.9,
            child: Center(child: glyph),
            builder: (context, press, child) {
              final scale = 1 - 0.1 * press;
              return Transform.scale(
                scale: (scale - 1).abs() < 0.001 ? 1.0 : scale,
                child: GlassSurface(
                  tint: t > 0 ? live.withValues(alpha: onTintAlpha * t) : null,
                  lift: press.clamp(0.0, 1.0),
                  child: child,
                ),
              );
            },
          );
        },
      ),
    );

    final label = semanticsLabelFor(
      on: on,
      liveCount: liveCount,
      subject: subject,
      mode: mode,
    );
    // The node outermost, so the button is the one node a reader (and a
    // test) finds; the tooltip shows the same words and is not read twice.
    return Semantics(
      container: true,
      button: true,
      toggled: on,
      enabled: true,
      label: label,
      hint: semanticsHintFor(on: on, subject: subject, mode: mode),
      onTap: _activate,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _activate,
          child: SizedBox.square(
            dimension: size.side,
            child: Center(child: button),
          ),
        ),
      ),
    );
  }
}
