import 'package:chessever2/screens/tour_detail/combined/combined_round_sections.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_flattened_layout.dart';

/// Like web CombinedHall, one time bucket contains separate source grids.
/// The generated header never replaces a game's real tour or round identity.
class CombinedRoundBucket {
  const CombinedRoundBucket({required this.round, required this.sources});
  final GamesAppBarModel round;
  final List<GamesTourSourceSection> sources;

  List<GamesTourModel> get games => [
    for (final source in sources) ...source.games,
  ];
}

List<CombinedRoundBucket> buildCombinedRoundBuckets(
  List<CombinedRoundSection> sections, {
  required String eventId,
}) {
  final buckets = <String, List<CombinedRoundSection>>{};
  for (final section in sections) {
    final start = section.startsAt?.toUtc().microsecondsSinceEpoch;
    // An unknown, undated round must not merge with unrelated undated rounds.
    final key = start == null ? 'round:${section.round.id}' : 'start:$start';
    (buckets[key] ??= []).add(section);
  }
  return [
    for (final entry in buckets.entries)
      CombinedRoundBucket(
        round: GamesAppBarModel(
          id: 'combined:$eventId:${entry.key}',
          name:
              entry.value.every(
                (source) => source.round.name == entry.value.first.round.name,
              )
              ? entry.value.first.round.name
              : 'Games',
          startsAt: entry.value.first.startsAt,
          roundStatus: entry.value.first.round.roundStatus,
          sourceRoundIds: [for (final source in entry.value) source.round.id],
        ),
        sources: [
          for (final source in entry.value)
            GamesTourSourceSection(
              roundId: source.round.id,
              label: source.category.label,
              games: source.games,
            ),
        ],
      ),
  ];
}
