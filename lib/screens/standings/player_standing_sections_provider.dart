import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final selectedPlayerStandingSectionProvider = StateProvider.autoDispose
    .family<String?, String>((ref, tourId) => null);

OfficialPlayerSection? selectedOfficialPlayerSection(
  List<OfficialPlayerSection> sections,
  String? selectedId,
) {
  if (sections.isEmpty) return null;
  for (final section in sections) {
    if (section.id == selectedId) return section;
  }
  return sections.first;
}

List<GamesTourModel> scopeOfficialSectionGames(
  OfficialPlayerSection section,
  List<GamesTourModel> games,
) {
  bool contains(PlayerCard card) => section.players.any((player) {
    if (card.fideId != null && player.fideId != null) {
      return card.fideId == player.fideId;
    }
    String normalize(String name) =>
        name.toLowerCase().replaceAll(RegExp(r'[,\.\s]+'), ' ').trim();
    return normalize(card.name) == normalize(player.name);
  });
  return games
      .where((game) => contains(game.whitePlayer) && contains(game.blackPlayer))
      .toList();
}
