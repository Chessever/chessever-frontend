import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The Feed player's own marks, drawn once in the design and tinted here.
/// Every glyph is authored in white so [FeedGlyph] can recolour it with a
/// single `srcIn` filter.
abstract final class FeedGlyphs {
  static const soundOn =
      '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
      '<path d="M4 9.5h3.2L12 5.6v12.8l-4.8-3.9H4v-5Z" stroke="#FFFFFF" '
      'stroke-width="1.7" stroke-linejoin="round"/>'
      '<path d="M15.5 9.2c.8.8 1.2 1.8 1.2 2.8s-.4 2-1.2 2.8M18 6.8c1.4 1.4 '
      '2.2 3.2 2.2 5.2s-.8 3.8-2.2 5.2" stroke="#FFFFFF" stroke-width="1.7" '
      'stroke-linecap="round"/></svg>';

  static const soundOff =
      '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
      '<path d="M4 9.5h3.2L12 5.6v12.8l-4.8-3.9H4v-5Z" stroke="#FFFFFF" '
      'stroke-width="1.7" stroke-linejoin="round"/>'
      '<path d="M16 9.5l5 5M21 9.5l-5 5" stroke="#FFFFFF" stroke-width="1.7" '
      'stroke-linecap="round"/></svg>';

  /// Play triangle shown while the viewer has paused the clip.
  static const play =
      '<svg viewBox="0 0 26 30" fill="none" xmlns="http://www.w3.org/2000/svg">'
      '<path d="M4 3.2v23.6c0 1 1.1 1.6 1.9 1.1l18.2-11.8c.8-.5.8-1.7 0-2.2'
      'L5.9 2.1C5.1 1.6 4 2.2 4 3.2Z" fill="#FFFFFF"/></svg>';

  static const _heartPath =
      'M12 20.4l-1.45-1.32C5.4 14.41 2 11.33 2 7.55 2 4.47 4.42 2.05 7.5 '
      '2.05c1.74 0 3.41.81 4.5 2.09 1.09-1.28 2.76-2.09 4.5-2.09 3.08 0 5.5 '
      '2.42 5.5 5.5 0 3.78-3.4 6.86-8.55 11.54L12 20.4z';

  static const heartFilled =
      '<svg viewBox="0 0 24 22" fill="none" xmlns="http://www.w3.org/2000/svg">'
      '<path d="$_heartPath" fill="#FFFFFF"/></svg>';

  static const heartOutline =
      '<svg viewBox="0 0 24 22" fill="none" xmlns="http://www.w3.org/2000/svg">'
      '<path d="$_heartPath" stroke="#FFFFFF" stroke-width="1.7" '
      'stroke-linejoin="round"/></svg>';

  static const mySpaceAdd =
      '<svg viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">'
      '<rect x="1.8" y="1.8" width="16.4" height="16.4" rx="3.2" '
      'stroke="#FFFFFF" stroke-width="1.6"/>'
      '<path d="M10 6v8M6 10h8" stroke="#FFFFFF" stroke-width="1.6" '
      'stroke-linecap="round"/></svg>';

  /// Same square, with the plus resolved into a tick once the game is saved.
  static const mySpaceAdded =
      '<svg viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">'
      '<rect x="1.8" y="1.8" width="16.4" height="16.4" rx="3.2" '
      'stroke="#FFFFFF" stroke-width="1.6"/>'
      '<path d="M6.2 10.3l2.6 2.6 5-5.4" stroke="#FFFFFF" stroke-width="1.6" '
      'stroke-linecap="round" stroke-linejoin="round"/></svg>';

  static const share =
      '<svg viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">'
      '<path d="M10 12.5V2.5M6.2 6 10 2.2 13.8 6" stroke="#FFFFFF" '
      'stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>'
      '<path d="M5 9H4.2A1.7 1.7 0 0 0 2.5 10.7v5.1c0 .94.76 1.7 1.7 1.7h11.6'
      'c.94 0 1.7-.76 1.7-1.7v-5.1c0-.94-.76-1.7-1.7-1.7H15" stroke="#FFFFFF" '
      'stroke-width="1.6" stroke-linecap="round"/></svg>';

  static const analyze =
      '<svg viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">'
      '<rect x="2" y="2" width="16" height="16" rx="2.5" stroke="#FFFFFF" '
      'stroke-width="1.6"/>'
      '<path d="M2 10h16M10 2v16" stroke="#FFFFFF" stroke-width="1.2"/>'
      '<rect x="2.8" y="2.8" width="6.4" height="6.4" fill="#FFFFFF" '
      'fill-opacity="0.45"/>'
      '<rect x="10.8" y="10.8" width="6.4" height="6.4" fill="#FFFFFF" '
      'fill-opacity="0.45"/></svg>';

  /// Two rounded bars, the pause counterpart of [play] at step size.
  static const pause =
      '<svg viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">'
      '<rect x="5" y="4" width="3.4" height="12" rx="1.3" fill="#FFFFFF"/>'
      '<rect x="11.6" y="4" width="3.4" height="12" rx="1.3" fill="#FFFFFF"/>'
      '</svg>';

  /// [play] at step size, optically centred in a 20-unit box.
  static const playSmall =
      '<svg viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">'
      '<path d="M6.4 4.4v11.2c0 .8.9 1.3 1.6.8l8.3-5.6c.6-.4.6-1.2 0-1.6'
      'L8 3.6C7.3 3.1 6.4 3.6 6.4 4.4Z" fill="#FFFFFF"/></svg>';

  /// Step one move back: the play triangle turned round against a rounded
  /// bar, so stepping reads as the same family as play and 2x.
  static const stepBack =
      '<svg viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">'
      '<rect x="3" y="4" width="2.4" height="12" rx="1.2" fill="#FFFFFF"/>'
      '<path d="M16.5 4.9v10.2c0 .8-.9 1.3-1.6.8L7.6 11c-.7-.5-.7-1.5 0-2'
      'l7.3-4.9c.7-.5 1.6 0 1.6.8Z" fill="#FFFFFF"/></svg>';

  /// Step one move forward.
  static const stepForward =
      '<svg viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">'
      '<rect x="14.6" y="4" width="2.4" height="12" rx="1.2" fill="#FFFFFF"/>'
      '<path d="M3.5 4.9v10.2c0 .8.9 1.3 1.6.8L12.4 11c.7-.5.7-1.5 0-2'
      'L5.1 4.1c-.7-.5-1.6 0-1.6.8Z" fill="#FFFFFF"/></svg>';

  /// A small open chevron pointing down, beside a value that opens a sheet.
  static const chevronDown =
      '<svg viewBox="0 0 12 12" fill="none" xmlns="http://www.w3.org/2000/svg">'
      '<path d="M2.5 4.5 6 8l3.5-3.5" stroke="#FFFFFF" stroke-width="1.6" '
      'stroke-linecap="round" stroke-linejoin="round"/></svg>';

  /// The tick of the chosen row in a sheet, drawn to match [mySpaceAdded].
  static const tick =
      '<svg viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">'
      '<path d="M4.5 10.4l3.6 3.6 7.4-8" stroke="#FFFFFF" stroke-width="1.8" '
      'stroke-linecap="round" stroke-linejoin="round"/></svg>';

  /// Puzzle hint: the ring the hint draws round the piece to move, with the
  /// piece's dot inside it.
  static const hint =
      '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
      '<circle cx="12" cy="12" r="7.6" stroke="#FFFFFF" stroke-width="1.7"/>'
      '<circle cx="12" cy="12" r="2.4" fill="#FFFFFF"/></svg>';

  /// Puzzle retry: one turn back round to the start.
  static const retry =
      '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
      '<path d="M5.2 12a6.8 6.8 0 1 0 2-4.8" stroke="#FFFFFF" '
      'stroke-width="1.7" stroke-linecap="round"/>'
      '<path d="M6.6 3.9v3.6h3.6" stroke="#FFFFFF" stroke-width="1.7" '
      'stroke-linecap="round" stroke-linejoin="round"/></svg>';

  /// Puzzle solution: the answer plays out, drawn as the outline of [play].
  static const solution =
      '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
      '<path d="M7.8 5.4v13.2c0 .8.9 1.3 1.6.8l9.6-6.6c.6-.4.6-1.2 0-1.6'
      'L9.4 4.6c-.7-.5-1.6 0-1.6.8Z" stroke="#FFFFFF" stroke-width="1.7" '
      'stroke-linejoin="round"/></svg>';

  /// The next post, below: the way the feed moves.
  static const next =
      '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
      '<path d="M12 4.8v13.6M6.4 13l5.6 5.6 5.6-5.6" stroke="#FFFFFF" '
      'stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/>'
      '</svg>';

  /// Double chevron beside the "2×" status.
  static const fast =
      '<svg viewBox="0 0 18 12" fill="none" xmlns="http://www.w3.org/2000/svg">'
      '<path d="M1.5 1.2 7.5 6l-6 4.8V1.2ZM9.5 1.2 15.5 6l-6 4.8V1.2Z" '
      'fill="#FFFFFF"/></svg>';
}

/// Renders one of [FeedGlyphs] at [width]×[height], tinted [color].
class FeedGlyph extends StatelessWidget {
  const FeedGlyph(
    this.svg, {
    required this.width,
    required this.height,
    required this.color,
    super.key,
  });

  final String svg;
  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      svg,
      width: width,
      height: height,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}
