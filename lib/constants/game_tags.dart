/// Official chess game tags for the personal library (My Likes / saved games).
///
/// These are a fixed, curated vocabulary the user can attach to liked/saved
/// games to organise their own collection. Tags are personal-library only in
/// v1 — they are NOT used to filter public surfaces (Most Liked, Miniatures).
///
/// Stored as plain strings in the `user_saved_analyses.tags` JSONB column, so
/// the label strings here ARE the persisted values. Keep them stable: renaming
/// a label orphans any games already tagged with the old value.
library;

import 'package:flutter/material.dart';

/// A single official tag with its display label and an icon for chips.
class GameTag {
  final String label;
  final IconData icon;

  const GameTag(this.label, this.icon);
}

/// The canonical, ordered list of official game tags (spec v1).
const List<GameTag> kOfficialGameTags = [
  GameTag('Wild Game', Icons.local_fire_department_rounded),
  GameTag('Beautiful Mate', Icons.auto_awesome_rounded),
  GameTag('Trap', Icons.gpp_maybe_rounded),
  GameTag('Good Defense', Icons.shield_rounded),
  GameTag('Comeback', Icons.trending_up_rounded),
  GameTag('High Technique', Icons.precision_manufacturing_rounded),
  GameTag('Positional Masterpiece', Icons.architecture_rounded),
  GameTag('Sacrifice', Icons.volunteer_activism_rounded),
  GameTag('Combination', Icons.hub_rounded),
  GameTag('Blunder', Icons.dangerous_rounded),
];

/// Just the persisted label strings, in canonical order.
const List<String> kOfficialGameTagLabels = [
  'Wild Game',
  'Beautiful Mate',
  'Trap',
  'Good Defense',
  'Comeback',
  'High Technique',
  'Positional Masterpiece',
  'Sacrifice',
  'Combination',
  'Blunder',
];

/// Resolve the icon for a tag label, falling back to a generic label icon for
/// any value not in the official set (e.g. legacy/custom tags).
IconData iconForGameTag(String label) {
  for (final tag in kOfficialGameTags) {
    if (tag.label == label) return tag.icon;
  }
  return Icons.label_rounded;
}
