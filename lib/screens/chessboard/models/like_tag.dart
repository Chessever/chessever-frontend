import 'package:flutter/material.dart';

/// A single classification a user can attach to a liked game.
///
/// Tags are the public-facing taxonomy for liked games: later, liked games
/// surface in shared/library views filtered by these tags. The list is a
/// closed vocabulary (ten curated tags) so the taxonomy stays browsable and
/// the picker stays legible — a free-text field would fragment the data and
/// make cross-user filtering meaningless.
///
/// [color] is the chip / dropdown-row accent and the dot on the save-sheet
/// chip. The palette is deliberately a *designed set*, not a rainbow: every
/// hue sits in a similar lightness/chroma band so the ten read as one coherent
/// set, and each hue carries a little of the tag's meaning (gold crown for a
/// mate, venom green for a trap, crimson for a sacrifice, a muddy bronze for a
/// blunder). Labels render in near-white over the tinted fill, which clears
/// 4.5:1 against every colour below.
///
/// [icon] is a glyph that *explains* the tag at a glance in the post-like
/// dropdown: a cyclone for chaos, a crown for a beautiful mate, a spider for a
/// venom trap, a shield for defence, a rocket for a comeback, and so on.
@immutable
class LikeTag {
  const LikeTag(this.label, this.color, this.icon);

  /// The exact string persisted into `SavedAnalysis.tags` (and the Supabase
  /// `user_saved_analyses.tags TEXT[]` column). Stored verbatim — do not
  /// lower-case or slugify, the filter vocabulary keys off this literal.
  final String label;

  /// Chip / dropdown-row accent.
  final Color color;

  /// Glyph shown beside the label in the tag dropdown — a quick visual cue for
  /// what the tag means.
  final IconData icon;
}

/// The canonical, ordered tag vocabulary. Keep the order stable so a remembered
/// initial tag lists always render consistently.
const List<LikeTag> kLikeTags = <LikeTag>[
  // hot pink — chaos · a spinning storm
  LikeTag('Wild Game', Color(0xFFFF4D9D), Icons.cyclone_rounded),
  // gold — the crown · checkmate beauty
  LikeTag('Beautiful Mate', Color(0xFFF2B84B), Icons.workspace_premium_rounded),
  // venom green — the snare · a lurking spider
  LikeTag('Trap', Color(0xFF7BD66A), Icons.pest_control_rounded),
  // steel blue — the shield
  LikeTag('Good Defense', Color(0xFF4F9BE0), Icons.shield_rounded),
  // ember orange — rising · a launch
  LikeTag('Comeback', Color(0xFFFF8A3D), Icons.rocket_launch_rounded),
  // teal — precision · the draftsman's compass
  LikeTag('High Technique', Color(0xFF2FD4C4), Icons.architecture_rounded),
  // royal purple — mastery · the board's structure
  LikeTag('Positional Masterpiece', Color(0xFFA77BF0), Icons.grid_on_rounded),
  // crimson — blood · giving material away
  LikeTag('Sacrifice', Color(0xFFFF5A5A), Icons.volunteer_activism_rounded),
  // indigo — intricate · linked tactics
  LikeTag('Combination', Color(0xFF6C7BF0), Icons.hub_rounded),
  // bronze — the mistake · a fallen face
  LikeTag('Blunder', Color(0xFFB5814E), Icons.sentiment_dissatisfied_rounded),
];

/// Lookup by persisted label. Returns `null` for an unknown / legacy tag so
/// callers can decide whether to drop it or render it neutrally.
LikeTag? likeTagByLabel(String label) {
  for (final t in kLikeTags) {
    if (t.label == label) return t;
  }
  return null;
}

/// Normalizes user-selected tag labels before UI display or persistence.
///
/// The vocabulary may evolve, so this intentionally preserves unknown legacy
/// labels while enforcing trim and dedupe.
List<String> normalizeLikeTagLabels(Iterable<String> labels) {
  final seen = <String>{};
  final normalized = <String>[];
  for (final raw in labels) {
    final label = raw.trim();
    if (label.isEmpty || !seen.add(label)) continue;
    normalized.add(label);
  }
  return List<String>.unmodifiable(normalized);
}
