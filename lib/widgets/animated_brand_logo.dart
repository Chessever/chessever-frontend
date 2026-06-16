import 'package:chessever2/utils/lottie_asset.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Animated ChessEver brand mark (the 4 cyan squares + centre king) with the
/// "ChessEver" wordmark tucked into the composition's reserved lower band.
///
/// Plays the piece-assemble once on mount — the corner squares spring in
/// (staggered), the centre cell pops, the king rises with a glow bloom, and the
/// wordmark fades up — then, when [repeatIdle] is true, loops only the idle
/// segment (gentle breath + glow pulse) so the mark never re-assembles
/// distractingly while the user lingers. Transparent background, so it
/// composites over any backdrop (the login [BlurBackground] or splash gradient).
///
/// The wordmark is a real Lottie text layer rendered with the app's Inter
/// (`InterDisplay`) font, so it lives in the same coordinate space as the mark
/// and lands in the reserved gap at any [width]/[height] under
/// [BoxFit.contain] — no separate widget, no layout math. [showWordmark]
/// toggles it; when false the text layer's opacity is forced to 0.
class AnimatedBrandLogo extends StatefulWidget {
  const AnimatedBrandLogo({
    super.key,
    required this.width,
    required this.height,
    this.repeatIdle = true,
    this.showWordmark = false,
  });

  final double width;
  final double height;

  /// When true, loops the idle segment after the assemble. When false, holds on
  /// the assembled resting frame.
  final bool repeatIdle;

  /// When true, shows the baked-in "ChessEver" wordmark under the mark.
  final bool showWordmark;

  @override
  State<AnimatedBrandLogo> createState() => _AnimatedBrandLogoState();
}

class _AnimatedBrandLogoState extends State<AnimatedBrandLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);

  // Fraction of the timeline where the assemble finishes and the idle begins.
  // Source animation is 210 frames; the piece-assemble settles by frame ~84,
  // after which only the gentle breath + glow pulse loops.
  static const double _idleStart = 84 / 210;

  // Render the wordmark text layer with the app's Inter family, regardless of
  // the font name baked into the JSON.
  static TextStyle _wordmarkStyle(LottieFontStyle font) => const TextStyle(
        fontFamily: 'InterDisplay',
        fontWeight: FontWeight.w700,
      );

  void _onLoaded(LottieComposition composition) {
    final total = composition.duration;
    _controller.duration = total;
    // Play ONLY the assemble (0 -> _idleStart) and settle exactly on the idle
    // baseline, then loop the idle from that same point.
    //
    // Previously this ran the whole timeline to the end (frame 210) and then
    // called repeat(min: _idleStart), which snaps the controller value 1.0 ->
    // _idleStart in a single frame to begin the loop. Frame 210 and frame 84
    // are pixel-identical, so the loop itself is seamless — but that one-frame
    // controller reset is what flashed the centre king to "another place".
    // Stopping the assemble at _idleStart means the loop continues from where
    // the assemble ended, with no reset and no jump. (Every assemble keyframe —
    // squares pop, king rise, glow bloom, wordmark fade — has settled by 84.)
    _controller
        .animateTo(_idleStart, duration: total * _idleStart)
        .whenComplete(() {
      if (!mounted || !widget.repeatIdle) return;
      _controller.repeat(
        min: _idleStart,
        max: 1.0,
        period: total * (1 - _idleStart),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Lottie.asset(
      LottieAsset.chesseverLogo,
      controller: _controller,
      width: widget.width,
      height: widget.height,
      fit: BoxFit.contain,
      onLoaded: _onLoaded,
      delegates: LottieDelegates(
        textStyle: _wordmarkStyle,
        // Hide the baked wordmark when not wanted by zeroing its layer opacity.
        values: widget.showWordmark
            ? null
            : [
                ValueDelegate.transformOpacity(const ['wordmark'], value: 0),
              ],
      ),
    );
  }
}
