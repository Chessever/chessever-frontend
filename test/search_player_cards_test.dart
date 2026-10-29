import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/widget/player_search_cards.dart';
import 'package:chessever2/widgets/search/enhanced_group_broadcast_local_storage.dart';
import 'package:chessever2/widgets/search/search_result_model.dart';
import 'package:flutter_test/flutter_test.dart';

// The cards above search results come from the results being shown. They
// used to read the Events tab's query, so Home search showed the last Events
// search's players, or none at all.
void main() {
  test('cards are the distinct players of the given results, in order', () {
    final results = _results([
      _player('Hikaru Nakamura', fideId: 2016192),
      _player('Hikaru Nakamura', fideId: 2016192),
      _player('Wesley So', fideId: 5202213),
    ]);

    expect(topSearchedPlayers(results).map((p) => p.name), [
      'Hikaru Nakamura',
      'Wesley So',
    ]);
  });

  test('same name without a FIDE id stays one card per person', () {
    final results = _results([
      _player('Ivan Petrov', memorialId: 'chessgames:1'),
      _player('Ivan Petrov', memorialId: 'chessgames:2'),
    ]);

    expect(topSearchedPlayers(results), hasLength(2));
  });

  test('at most four cards, and none for event-only results', () {
    final results = _results([
      for (var i = 0; i < 6; i++) _player('Player $i', fideId: 100 + i),
    ]);

    expect(topSearchedPlayers(results), hasLength(4));
    expect(topSearchedPlayers(EnhancedSearchResult.empty()), isEmpty);
  });
}

EnhancedSearchResult _results(List<SearchPlayer> players) {
  return EnhancedSearchResult(
    tournamentResults: const [],
    playerResults: [
      for (final player in players)
        SearchResult(
          tournament: _event,
          score: 1,
          matchedText: player.name,
          type: SearchResultType.player,
          player: player,
        ),
    ],
  );
}

SearchPlayer _player(String name, {int? fideId, String? memorialId}) {
  return SearchPlayer(
    id: '${fideId ?? memorialId ?? name}',
    name: name,
    fideId: fideId,
    memorialSourceIdentity: memorialId,
    tournamentId: _event.id,
    tournamentName: _event.title,
  );
}

final _event = GroupEventCardModel(
  id: 'tour-1',
  title: 'Sinquefield Cup 2026',
  dates: 'Aug 20, 2026',
  maxAvgElo: 2750,
  timeUntilStart: '',
  tourEventCategory: TourEventCategory.completed,
  timeControl: 'Classical',
  startDate: DateTime.utc(2026, 8, 20),
  endDate: DateTime.utc(2026, 8, 30),
);
