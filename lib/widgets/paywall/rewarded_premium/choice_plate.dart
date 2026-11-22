import 'dart:async';

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/widgets/paywall/rewarded_premium/premium_marks.dart';
import 'package:chessever2/widgets/popup_glass.dart';
import 'package:chessever2/widgets/press_spring.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

// The Premium popups' parts, one construction for every popup of the
// flow: the Unlock Premium chooser (rewarded_access_ui.dart) and the
// rewarded-interstitial intro (rewarded_interstitial_intro.dart). A choice
// is a ChoicePlate wearing a ChoiceGlyph; the way out is a
// ChoiceDismissButton; their type is premiumPopupType.

/// The popups' type: the app's Inter, named, so it never falls back to the
/// platform's face. A null [color] takes the control's.
TextStyle premiumPopupType(
  double size,
  double height,
  FontWeight weight,
  Color? color,
) => TextStyle(
  fontFamily: 'InterDisplay',
  fontSize: size,
  height: height,
  fontWeight: weight,
  color: color,
);

/// What a choice is cut from: its plate and inks, and the edge the popups'
/// glass gives a solid chip (a rim lit along the top lip, a sheen under it,
/// one tight shadow cast down; see [SolidGlassDecoration]).
@immutable
class ChoicePlateTone {
  const ChoicePlateTone({
    required this.fill,
    required this.ink,
    required this.glyph,
    required this.rimTop,
    required this.rimBottom,
    required this.sheen,
    required this.shadow,
  });

  /// Upgrade, in both themes: a deep step of the brand cyan (the teal the
  /// premium ring turns through), white type on it at 5.6:1 and the mark in
  /// a pale brand cyan at 4.1:1. The plate stands off dark glass at 3.4:1
  /// and off paper at 5.3:1. Its lip is lit and its shadow is its own
  /// colour on paper.
  factory ChoicePlateTone.upgrade({required bool light}) => ChoicePlateTone(
    fill: _premiumPlate,
    ink: Colors.white,
    glyph: const Color(0xFFA5E6FA),
    rimTop: Colors.white.withValues(alpha: light ? 0.42 : 0.28),
    rimBottom: Colors.white.withValues(alpha: 0),
    sheen: Colors.white.withValues(alpha: 0.06),
    shadow: BoxShadow(
      color: light
          ? _premiumPlate.withValues(alpha: 0.32)
          : Colors.black.withValues(alpha: 0.45),
      blurRadius: 8,
      offset: const Offset(0, 3),
    ),
  );

  /// Watch ad: the same plate a quiet step off the card (white on paper, a
  /// lifted charcoal on dark glass), inked like the page, with the glass
  /// chip's own edge.
  factory ChoicePlateTone.watch(AppColors colors, {required bool light}) =>
      light
      ? ChoicePlateTone(
          fill: Colors.white,
          ink: colors.textPrimary,
          glyph: colors.textPrimary,
          rimTop: Colors.white,
          rimBottom: colors.textPrimary.withValues(alpha: 0.10),
          sheen: Colors.white.withValues(alpha: 0),
          shadow: BoxShadow(
            color: colors.textPrimary.withValues(alpha: 0.14),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        )
      : ChoicePlateTone(
          fill: const Color(0xFF26262A),
          ink: colors.textPrimary,
          glyph: colors.textPrimary,
          rimTop: Colors.white.withValues(alpha: 0.15),
          rimBottom: Colors.white.withValues(alpha: 0.04),
          sheen: Colors.white.withValues(alpha: 0.02),
          shadow: BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        );

  static const Color _premiumPlate = Color(0xFF0B7090);

  final Color fill;
  final Color ink;
  final Color glyph;
  final Color rimTop;
  final Color rimBottom;
  final Color sheen;
  final BoxShadow shadow;

  // Built afresh every frame of a press: equal tones never repaint a plate.
  @override
  bool operator ==(Object other) =>
      other is ChoicePlateTone &&
      other.fill == fill &&
      other.ink == ink &&
      other.glyph == glyph &&
      other.rimTop == rimTop &&
      other.rimBottom == rimBottom &&
      other.sheen == sheen &&
      other.shadow == shadow;

  @override
  int get hashCode =>
      Object.hash(fill, ink, glyph, rimTop, rimBottom, sheen, shadow);
}

/// One of a popup's choices: a 56 pt plate with its glyph and label
/// centred on it, pressed with the app's [PressSpring] (it gives under the
/// finger and springs back; nothing moves on hover).
///
/// [busy] holds the plate at full strength while its action runs; [dimmed]
/// quiets the other one meanwhile. For a beat after the tap the plate keeps
/// its mark and [label]; only an action still running after it, with
/// nothing opened over the popup, swaps them for a spinner and [busyLabel].
/// A checkout that opens at once never flashes a spinner, and none spins
/// unseen under the checkout. A choice that answers at once (it closes its
/// popup) is never busy and needs no [busyLabel].
///
/// With [pressMovesGlyph] the press reaches the glyph too: Upgrade's mark
/// closes its squares in under the finger and, as the tap lands, bursts
/// them apart and back together.
class ChoicePlate extends StatefulWidget {
  const ChoicePlate({
    super.key,
    required this.label,
    this.busyLabel,
    required this.glyph,
    required this.tone,
    required this.onTap,
    this.busy = false,
    this.dimmed = false,
    this.pressMovesGlyph = false,
  });

  final String label;
  final String? busyLabel;
  final ChoiceGlyph glyph;
  final ChoicePlateTone tone;
  final VoidCallback? onTap;
  final bool busy;
  final bool dimmed;
  final bool pressMovesGlyph;

  static const BorderRadius radius = BorderRadius.all(Radius.circular(14));

  /// How long a running choice keeps its mark: past the release and the
  /// mark's burst (settled by about half a second).
  static const Duration beat = Duration(milliseconds: 600);

  static const _dim = CupertinoMotion.smooth(
    duration: Duration(milliseconds: 240),
    snapToEnd: true,
  );

  /// Where a glyph sits against its resting label, measured on Inter Bold
  /// 16: [gap] from the glyph's ink to the label's box puts 9 pt between
  /// the two inks (U and R stand 1 pt into their boxes, W 0.33 pt), and
  /// [lead] before the glyph matches the room the label's last letter
  /// leaves at the end of its box (Upgrade's e 0.67 pt, d and n 1.17), so
  /// the pair centres on the plate by what is drawn.
  static ({double gap, double lead}) fit(ChoiceGlyph glyph) => switch (glyph) {
    ChoiceGlyph.premium => (gap: 8, lead: 0.67),
    ChoiceGlyph.play => (gap: 8.67, lead: 1.17),
    ChoiceGlyph.retry => (gap: 8, lead: 1.17),
  };

  @override
  State<ChoicePlate> createState() => _ChoicePlateState();
}

class _ChoicePlateState extends State<ChoicePlate> {
  Timer? _beat;
  bool _waited = false;

  /// Taps that landed, each one a burst of the mark.
  int _bursts = 0;

  @override
  void initState() {
    super.initState();
    if (widget.busy) _startBeat();
  }

  @override
  void didUpdateWidget(ChoicePlate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.busy == oldWidget.busy) return;
    _beat?.cancel();
    _waited = false;
    if (widget.busy) _startBeat();
  }

  void _startBeat() {
    _beat = Timer(ChoicePlate.beat, () {
      if (mounted) setState(() => _waited = true);
    });
  }

  @override
  void dispose() {
    _beat?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tap = widget.onTap;
    final tone = widget.tone;
    final glyph = widget.glyph;
    final still = MediaQuery.disableAnimationsOf(context);
    final waiting =
        widget.busy && _waited && (ModalRoute.isCurrentOf(context) ?? true);
    final fit = ChoicePlate.fit(glyph);
    Widget plate(double press) => CustomPaint(
      painter: _PlatePainter(tone),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: tap == null
              ? null
              : () {
                  unawaited(HapticFeedbackService.buttonPress());
                  if (widget.pressMovesGlyph) setState(() => _bursts++);
                  tap();
                },
          customBorder: const RoundedRectangleBorder(
            borderRadius: ChoicePlate.radius,
          ),
          splashFactory: NoSplash.splashFactory,
          // The press is the spring's. A keyboard focus or a pointer over
          // it shifts the plate's tone; nothing else.
          overlayColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.focused)
                ? tone.ink.withValues(alpha: 0.14)
                : states.contains(WidgetState.hovered)
                ? tone.ink.withValues(alpha: 0.06)
                : Colors.transparent,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (fit.lead > 0) SizedBox(width: fit.lead),
                  // The glyph's own ink box, so the label's gap and the
                  // pair's centring are measured from what is drawn. The
                  // spinner takes the same place at the glyph's height.
                  SizedBox(
                    width: glyph.size.width,
                    height: 20,
                    child: waiting
                        ? OverflowBox(
                            minWidth: 16,
                            maxWidth: 16,
                            minHeight: 16,
                            maxHeight: 16,
                            child: RepaintBoundary(
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: tone.ink,
                              ),
                            ),
                          )
                        : Center(
                            child: ChoiceGlyphIcon(
                              glyph,
                              color: tone.glyph,
                              press: widget.pressMovesGlyph ? press : 0,
                              burst: _bursts,
                            ),
                          ),
                  ),
                  SizedBox(width: fit.gap),
                  Flexible(
                    child: Text(
                      waiting ? widget.busyLabel ?? widget.label : widget.label,
                      textAlign: TextAlign.center,
                      style: premiumPopupType(
                        16,
                        1.25,
                        FontWeight.w700,
                        tone.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: tap != null,
      child: SingleMotionBuilder(
        motion: ChoicePlate._dim,
        value: widget.dimmed ? 0.4 : 1.0,
        active: !still,
        builder: (context, strength, child) =>
            Opacity(opacity: strength.clamp(0.0, 1.0), child: child),
        child: PressSpring(
          pressedScale: 0.97,
          builder: (context, press, _) {
            // A plate that cannot be tapped does not give; the one whose
            // action just started finishes its release.
            final p = tap != null || widget.busy ? press : 0.0;
            final scale = 1 - 0.03 * p;
            return Transform.scale(
              scale: (scale - 1).abs() < 0.001 ? 1.0 : scale,
              child: plate(p),
            );
          },
          child: const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// A choice's plate in its [ChoicePlateTone]: the shadow (only outside the
/// plate, so it never darkens it from beneath), the fill, the sheen under
/// the top lip and the rim, lit along the top and quiet by the middle.
class _PlatePainter extends CustomPainter {
  const _PlatePainter(this.tone);

  final ChoicePlateTone tone;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = ChoicePlate.radius.toRRect(rect);
    final shadow = tone.shadow;
    final reach = shadow.blurRadius * 2 + shadow.offset.distance + 4;
    canvas
      ..save()
      ..clipPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(rect.inflate(reach))
          ..addRRect(shape),
      )
      ..drawRRect(shape.shift(shadow.offset), shadow.toPaint())
      ..restore()
      ..drawRRect(shape, Paint()..color = tone.fill);
    final sheen = Rect.fromLTWH(0, 0, size.width, size.height / 2);
    canvas
      ..save()
      ..clipRRect(shape)
      ..drawRect(
        sheen,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [tone.sheen, tone.sheen.withValues(alpha: 0)],
          ).createShader(sheen),
      )
      ..restore()
      ..drawRRect(
        shape.deflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [tone.rimTop, tone.rimBottom],
            stops: const [0, 0.6],
          ).createShader(rect),
      );
  }

  @override
  bool shouldRepaint(_PlatePainter oldDelegate) => oldDelegate.tone != tone;
}

/// A popup's quiet way out under its choices (Not now, Go back, Skip): the
/// card's secondary ink, no plate, a 44 pt target, disabled at half
/// strength while a choice runs.
class ChoiceDismissButton extends StatelessWidget {
  const ChoiceDismissButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: colors.textSecondary,
        disabledForegroundColor: colors.textSecondary.withValues(alpha: 0.5),
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(
        label,
        style: premiumPopupType(15, 1.3, FontWeight.w500, null),
      ),
    );
  }
}
