import 'package:chessever2/screens/my_space/widgets/pixel_art.dart';
import 'package:flutter/widgets.dart';

/// The pixel streak flame: a 9 x 12 block flame whose blocks flicker in a
/// wave rising from the base. It burns faster as the streak grows and throws
/// sparks from 10 wins (two) and 20 wins (three); under five wins the
/// flame has no mid tone.
///
/// [size] is the height; the width follows the flame's 9:14 frame. Sparks may
/// rise slightly above the box, as in the design.
///
/// [tone] picks the palette; left null it follows the theme, which keeps the
/// dark theme exactly as designed and inks the flame for paper in light. A
/// flame drawn on a plate that stays dark in the light theme passes
/// [PixelTone.dark].
class PixelFlame extends StatelessWidget {
  const PixelFlame({
    super.key,
    required this.streak,
    this.size = 30,
    this.tone,
  });

  final int streak;
  final double size;
  final PixelTone? tone;

  @override
  Widget build(BuildContext context) {
    final box = Size((size * 9 / 14).roundToDouble(), size);
    final art = PixelArt.flame(streak, tone: tone ?? PixelTone.of(context));
    return ExcludeSemantics(
      child: SizedBox.fromSize(
        size: box,
        child: PixelArtView(scene: PixelScene.flame(art, box)),
      ),
    );
  }
}
