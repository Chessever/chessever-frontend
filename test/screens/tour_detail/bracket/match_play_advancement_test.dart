import 'dart:convert';
import 'dart:io';

import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/tour_detail/bracket/models/knockout_bracket.dart';
import 'package:chessever2/screens/tour_detail/bracket/utils/knockout_bracket_builder.dart';
import 'package:flutter_test/flutter_test.dart';

final fixture =
    jsonDecode(File('test/fixtures/scc_final_20261116.json').readAsStringSync())
        as Map<String, dynamic>;

KnockoutBracket build({Map<String, dynamic>? metadata, List<Games>? games}) {
  final tour = Tour(
    id: 'fqCjSUpE',
    name: 'Speed Chess Championship XI (2026–27)',
    slug: '2026-speed-chess-championship',
    info: TourInfo.fromJson({
      'format': '16-player knockout',
      'matchPlayBracket': metadata,
    }),
    createdAt: DateTime.utc(2026, 11, 3),
    url: 'https://chessever.com',
    tier: 1,
    dates: [DateTime.utc(2026, 11, 16)],
    players: const [],
  );
  return buildKnockoutBracket(
    selectedTour: tour,
    siblingTours: const [],
    roundsByTourId: {
      tour.id: [
        for (final raw in fixture['rounds'] as List)
          Round(
            id: raw['id'],
            name: raw['name'],
            slug: raw['slug'],
            tourId: tour.id,
            tourSlug: tour.slug,
            createdAt: tour.createdAt,
            url: 'https://chessever.com',
            startsAt: DateTime.tryParse(raw['starts_at'] ?? ''),
          ),
      ],
    },
    gamesByTourId: {
      tour.id:
          games ??
          [
            for (final raw in fixture['games'] as List)
              Games.fromJson({
                ...raw,
                'tour_slug': tour.slug,
                'round_slug': 'round-of-16',
              }),
          ],
    },
    now: DateTime.utc(2026, 11, 16, 22),
  );
}

Map<String, dynamic> metadata() =>
    jsonDecode(jsonEncode(fixture['matchPlayBracket']));
List<Games> sourceGames() => [
  for (final raw in fixture['games'] as List)
    Games.fromJson({
      ...raw,
      'tour_slug': '2026-speed-chess-championship',
      'round_slug': 'round-of-16',
    }),
];
KnockoutMatch naka(KnockoutBracket bracket) => bracket.stages
    .expand((s) => s.matches)
    .firstWhere(
      (m) =>
          m.games.isNotEmpty &&
          (m.participant1.fideId == 2016192 ||
              m.participant2.fideId == 2016192),
    );

void main() {
  test(
    'confirmed 12–8 result advances Nakamura to QF2 before other matches play',
    () {
      final bracket = build(metadata: fixture['matchPlayBracket']);
      final source = bracket.stages.firstWhere(
        (s) => s.sourceRoundIds.contains('60IswAYI'),
      );
      final match = source.matches.firstWhere(
        (m) =>
            m.participant1.fideId == 2016192 ||
            m.participant2.fideId == 2016192,
      );
      expect(match.winner?.fideId, 2016192);
      expect(source.isComplete, isFalse);
      final next = bracket.stages.firstWhere(
        (s) => s.sourceRoundIds.contains('qhktidXj'),
      );
      expect(next.matches, hasLength(4));
      expect(next.matches[1].participant1.fideId, 2016192);
      expect(next.matches[1].participant2.name, 'TBD');
      expect(next.matches.every((m) => m.games.isEmpty && !m.isLive), isTrue);
      expect(
        bracket.edges
            .where((e) => e.sourceMatchKey == match.key)
            .single
            .destinationMatchKey,
        next.matches[1].key,
      );
      expect(bracket.currentStageKey, source.key);
    },
  );
  test(
    'no confirmed final means no advancement during a gap between games',
    () {
      final bracket = build();
      expect(naka(bracket).winner, isNull);
      expect(
        bracket.stages
            .firstWhere((s) => s.sourceRoundIds.contains('qhktidXj'))
            .matches,
        isEmpty,
      );
    },
  );

  test(
    'new games, partial reads and result corrections invalidate a final',
    () {
      final games = sourceGames();
      for (final changed in [
        games.skip(1).toList(),
        [games.first.copyWith(status: '*'), ...games.skip(1)],
        [games.first.copyWith(status: '0-1'), ...games.skip(1)],
        [...games, games.first.copyWith(id: 'game-21', status: '*')],
      ]) {
        final bracket = build(metadata: metadata(), games: changed);
        expect(naka(bracket).winner, isNull);
        expect(
          bracket.stages
              .firstWhere((s) => s.sourceRoundIds.contains('qhktidXj'))
              .matches,
          hasLength(4),
        );
      }
    },
  );

  test(
    'wrong winners, malformed scores, wrong rounds and duplicates fail closed',
    () {
      for (final patch in [
        {'winnerFideId': '44599790'},
        {'gameCount': 19},
        {
          'scores': [8, 12],
        },
        {
          'scores': [10, 10],
        },
        {
          'scores': ['12', 8],
        },
        {'roundId': 'other'},
        {
          'fideIds': ['2016192', '2093596'],
        },
      ]) {
        final m = metadata();
        (m['results'][0] as Map).addAll(patch);
        expect(naka(build(metadata: m)).winner, isNull);
      }
      final m = metadata();
      (m['results'] as List).add({
        ...m['results'][0],
        'winnerFideId': '44599790',
      });
      expect(naka(build(metadata: m)).winner, isNull);
    },
  );

  test(
    'reversed identities work; ambiguous seeds cannot invent a destination',
    () {
      final m = metadata();
      m['results'][0]['fideIds'] = ['44599790', '2016192'];
      m['results'][0]['scores'] = [8, 12];
      expect(naka(build(metadata: m)).winner?.fideId, 2016192);
      m['seeds'][0]['fideIds'][1] = m['seeds'][0]['fideIds'][0];
      final bracket = build(metadata: m);
      expect(naka(bracket).winner?.fideId, 2016192);
      expect(
        bracket.stages
            .firstWhere((s) => s.sourceRoundIds.contains('qhktidXj'))
            .matches,
        isEmpty,
      );
    },
  );

  test('metadata survives the TourInfo cache round trip', () {
    final info = TourInfo.fromJson({'matchPlayBracket': metadata()});
    expect(TourInfo.fromJson(info.toJson()).matchPlayBracket, metadata());
    expect(
      TourInfo.fromJson({'matchPlayBracket': 'bad'}).matchPlayBracket,
      isNull,
    );
  });
  test('published quarterfinal games replace projected cards', () {
    final games = sourceGames();
    final published = Games(
      id: 'quarterfinal-game',
      roundId: 'qhktidXj',
      roundSlug: 'quarterfinals',
      tourId: 'fqCjSUpE',
      tourSlug: '2026-speed-chess-championship',
      players: [
        games.first.players!.first,
        games
            .firstWhere((g) => g.players!.first.fideId == 25092340)
            .players!
            .first,
      ],
      status: '*',
      boardNr: 1,
    );
    final bracket = build(metadata: metadata(), games: [...games, published]);
    final next = bracket.stages.firstWhere(
      (s) => s.sourceRoundIds.contains('qhktidXj'),
    );
    expect(next.matches, hasLength(4));
    final publishedMatch = next.matches.singleWhere((m) => !m.isProjected);
    expect(publishedMatch.isProjected, isFalse);
    expect(publishedMatch.sourceGameIds, ['quarterfinal-game']);
    expect(publishedMatch.participant2.fideId, 25092340);
  });
}
