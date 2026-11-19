import 'package:chessever2/widgets/game_filter/rating_tier_filter.dart'
    show RatingTier;
import 'package:dartchess/dartchess.dart' show Role, Square;
import 'package:flutter/foundation.dart';

/// One level a smart event can be built on: an open-ended floor on the
/// game's average rating (both players' ratings, halved), never a band.
/// Product decision (2026-06-11): every tier means that level and above.
@immutable
class SmartEventTier {
  const SmartEventTier({
    required this.name,
    required this.code,
    required this.title,
    required this.floor,
    required this.piece,
    required this.home,
  });

  /// The tier as requests, the title dropdown and saved names spell it:
  /// "Super GM", "GM".
  final String name;

  /// The short form for a narrow slot (the builder's level track): "SGM".
  final String code;

  /// The title spelled out: "Super Grandmaster".
  final String title;

  /// The lowest game average the tier takes.
  final int floor;

  /// The tier on the smart event's plate: the title ladder as the piece
  /// ladder, Super GM the king down to CM the knight.
  final Role piece;

  /// Where [piece] stands on the plate: its home square, White's side.
  final Square home;

  /// "Super Grandmaster · 2700+", the dropdown's row.
  String get longLabel => '$title · $floor+';

  /// The tier as the filter dialog's Level chips draw one.
  RatingTier get ratingTier =>
      RatingTier(label: name, subtitle: '+$floor', minRating: floor);
}

/// Every smart event tier, strongest first: the one table the request, the
/// smart event screen, its filter dialog, the builder and the plates read.
///
/// Super GM (2700+) was checked against production before it shipped
/// (2026-11-19): 45 of the last 60 days held 2700+ games, 508 in all, with
/// gaps of three days at most. The screen opens on the last day that has
/// games, so a quiet day never shows an empty list.
const List<SmartEventTier> kSmartEventTiers = [
  SmartEventTier(
    name: 'Super GM',
    code: 'SGM',
    title: 'Super Grandmaster',
    floor: 2700,
    piece: Role.king,
    home: Square.e1,
  ),
  SmartEventTier(
    name: 'GM',
    code: 'GM',
    title: 'Grandmaster',
    floor: 2500,
    piece: Role.queen,
    home: Square.d1,
  ),
  SmartEventTier(
    name: 'IM',
    code: 'IM',
    title: 'International Master',
    floor: 2400,
    piece: Role.rook,
    home: Square.a1,
  ),
  SmartEventTier(
    name: 'FM',
    code: 'FM',
    title: 'FIDE Master',
    floor: 2300,
    piece: Role.bishop,
    home: Square.c1,
  ),
  SmartEventTier(
    name: 'CM',
    code: 'CM',
    title: 'Candidate Master',
    floor: 2200,
    piece: Role.knight,
    home: Square.g1,
  ),
];

/// The tier spelled [name] ("Super GM"), or null ("All", or not a tier).
SmartEventTier? smartTierNamed(String name) {
  for (final tier in kSmartEventTiers) {
    if (tier.name == name) return tier;
  }
  return null;
}

/// The tier whose floor is exactly [floor], or null.
SmartEventTier? smartTierForFloor(int floor) {
  for (final tier in kSmartEventTiers) {
    if (tier.floor == floor) return tier;
  }
  return null;
}

/// The strongest tier [rating] reaches (2650 is GM), or null under the
/// lowest floor.
SmartEventTier? smartTierAtOrBelow(int rating) {
  for (final tier in kSmartEventTiers) {
    if (rating >= tier.floor) return tier;
  }
  return null;
}

/// The floor of the tier spelled [name]; 0 for "All" or no tier.
int smartTierFloor(String name) => smartTierNamed(name)?.floor ?? 0;

/// The tiers as the filter dialog's Level chips, strongest first.
final List<RatingTier> kSmartEventRatingTiers = List.unmodifiable([
  for (final tier in kSmartEventTiers) tier.ratingTier,
]);
