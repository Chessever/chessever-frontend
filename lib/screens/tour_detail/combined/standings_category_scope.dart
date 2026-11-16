import 'package:chessever2/screens/tour_detail/combined/combined_games_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Marks the standings rows below it as one category's table inside the
/// Combined Standings tab, when that category is not the selected one.
///
/// Everything a standings row opens (a player's score card, a team's, a
/// team's matches) reads the selected category by default. A row of another
/// category has to name its own, or the card comes up empty. The rows are
/// the same widgets either way, so they look this scope up instead of taking
/// the category through every constructor.
class StandingsCategoryScope extends InheritedWidget {
  const StandingsCategoryScope({
    super.key,
    required this.tourId,
    required super.child,
  });

  /// The category's tour, or null for the selected category.
  final String? tourId;

  /// The category the row under [context] belongs to when it is not the
  /// selected one. Null everywhere outside Combined standings.
  static String? tourIdOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<StandingsCategoryScope>()?.tourId;

  @override
  bool updateShouldNotify(StandingsCategoryScope oldWidget) =>
      oldWidget.tourId != tourId;
}

/// What a score card opened from a standings row should load its games from:
/// null for the selected category (the card reads the tournament's own
/// providers), or [tourId]'s boards for a row of another Combined category.
///
/// The Combined lists already hold that category's boards as list models, so
/// nothing is parsed on the tap.
List<GamesTourModel>? scoreCardGamesContextForCategory(
  WidgetRef ref,
  String? tourId,
) {
  if (tourId == null || tourId.isEmpty) return null;
  final games = ref.read(combinedTourGamesProvider(tourId)).valueOrNull;
  return games == null || games.isEmpty ? null : games;
}
