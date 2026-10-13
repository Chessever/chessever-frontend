import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/standings/player_standing_sections_provider.dart';
import 'package:chessever2/screens/standings/player_standing_section_select.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

Map<String, dynamic> snapshot() => {
  'source': 'chess-results',
  'sourceUrl': 'https://chess-results.com/tnr100.aspx',
  'fetchedAt': '2026-10-13T12:00:00Z',
  'sections': [
    for (final id in ['100', '101'])
      {
        'id': id,
        'name': id == '100' ? 'Open U19' : 'Open U17',
        'sourceUrl': 'https://chess-results.com/tnr$id.aspx',
        'players': [
          {
            'name': 'Player $id',
            'fideId': int.parse(id),
            'rank': 1,
            'score': 3.5,
            'played': 4,
          },
          {'name': 'Second $id', 'rank': 1, 'score': 3.5, 'played': 4},
        ],
      },
  ],
};

void main() {
  test(
    'official section snapshots preserve shared ranks and cache roundtrip',
    () {
      final info = TourInfo(
        standings: 'https://chess-results.com/tnr100.aspx',
        officialPlayerStandingsSections: snapshot(),
      );
      final parsed = TourInfo.fromJson(info.toJson());
      expect(parsed.playerStandingSections.map((s) => s.name), [
        'Open U19',
        'Open U17',
      ]);
      expect(parsed.playerStandingSections.first.players.map((p) => p.rank), [
        1,
        1,
      ]);
      expect(parsed.playerStandingSections.first.players.first.score, 3.5);
      expect(
        selectedOfficialPlayerSection(
          parsed.playerStandingSections,
          '101',
        )!.name,
        'Open U17',
      );
      expect(
        selectedOfficialPlayerSection(
          parsed.playerStandingSections,
          'removed',
        )!.id,
        '100',
      );
    },
  );

  test('a relink or any malformed table rejects the complete snapshot', () {
    expect(
      OfficialPlayerSection.parse(
        snapshot(),
        'https://chess-results.com/tnr999.aspx',
      ),
      isEmpty,
    );
    for (final field in ['rank', 'played', 'score']) {
      final data = snapshot();
      (((data['sections'] as List).last as Map)['players'] as List)
              .first[field] =
          -1;
      expect(
        OfficialPlayerSection.parse(
          data,
          'https://chess-results.com/tnr100.aspx',
        ),
        isEmpty,
      );
    }
    final data = snapshot();
    ((data['sections'] as List).first as Map)['sourceUrl'] =
        'https://example.com/tnr100.aspx';
    expect(
      OfficialPlayerSection.parse(
        data,
        'https://chess-results.com/tnr100.aspx',
      ),
      isEmpty,
    );
  });

  test('section scorecards exclude other sections and cross-section games', () {
    final section = OfficialPlayerSection.parse(
      snapshot(),
      'https://chess-results.com/tnr100.aspx',
    ).first;
    PlayerCard card(String name, int? id) => PlayerCard(
      name: name,
      fideId: id,
      federation: '',
      title: '',
      rating: 0,
      countryCode: '',
      team: null,
    );
    GamesTourModel game(String id, PlayerCard white, PlayerCard black) =>
        GamesTourModel(
          gameId: id,
          whitePlayer: white,
          blackPlayer: black,
          whiteTimeDisplay: '',
          blackTimeDisplay: '',
          whiteClockCentiseconds: 0,
          blackClockCentiseconds: 0,
          gameStatus: GameStatus.draw,
          tourId: 'tour',
          roundId: 'round',
        );
    final games = [
      game('in', card('Player 100', 100), card('Second 100', null)),
      game('other', card('Player 101', 101), card('Second 101', null)),
      game('mixed', card('Player 100', 100), card('Player 101', 101)),
    ];
    expect(
      scopeOfficialSectionGames(section, games).map((game) => game.gameId),
      ['in'],
    );
  });

  testWidgets('selecting an official section changes only that tournament', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final sections = OfficialPlayerSection.parse(
      snapshot(),
      'https://chess-results.com/tnr100.aspx',
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: PlayerStandingSectionSelect(
              tourId: 'tour',
              sections: sections,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open U19').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open U17').last);
    await tester.pumpAndSettle();
    expect(
      container.read(selectedPlayerStandingSectionProvider('tour')),
      '101',
    );
    expect(
      container.read(selectedPlayerStandingSectionProvider('another-tour')),
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
}
