import 'package:flutter/painting.dart';

/// The three hues of Toby's live prediction, most likely move first. Each
/// candidate's text and its board arrow share one hue.
///
/// Chosen apart from everything else that draws on the board: the engine
/// line palette (`enginePvVariantPalette`: green, blue, orange, pink,
/// purple), the variant-step cyan (`kPrimaryColor`) and the PGN `%cal`
/// colours (green, yellow, blue, red, orange).
const Color kTobyTeal = Color(0xFF2FA39B);
const Color kTobyCoral = Color(0xFFE0796B);
const Color kTobyGold = Color(0xFFC9A23A);

const List<Color> kTobyCandidatePalette = <Color>[
  kTobyTeal,
  kTobyCoral,
  kTobyGold,
];

/// The hue of the candidate at [rank] (0 = most likely). Ranks past the
/// palette wrap around.
Color tobyCandidateHue(int rank) =>
    kTobyCandidatePalette[rank.abs() % kTobyCandidatePalette.length];
