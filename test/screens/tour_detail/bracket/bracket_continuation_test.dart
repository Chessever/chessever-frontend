import 'package:chessever2/screens/tour_detail/bracket/widgets/bracket_graph_layout.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:flutter_test/flutter_test.dart';
import 'match_play_advancement_test.dart' as f;

void main() {
  test(
    'official seeds show every future round before any final is confirmed',
    () {
      final metadata = f.metadata()..['results'] = [];
      final bracket = f.build(metadata: metadata);
      final byRound = {
        for (final stage in bracket.stages) stage.sourceRoundIds.single: stage,
      };
      expect(byRound['qhktidXj']!.matches, hasLength(4));
      expect(byRound['thbREnFa']!.matches, hasLength(2));
      expect(byRound['BljVh3AO']!.matches, hasLength(1));
      expect(byRound['9CtXnTQu']!.matches, hasLength(1));
      expect(
        bracket.edges,
        isEmpty,
        reason: 'planned routes do not prove a winner',
      );
    },
  );

  test(
    'final follows semifinals and third place is a separate lower branch',
    () {
      final bracket = f.build(metadata: f.metadata());
      final byRound = {
        for (final stage in bracket.stages) stage.sourceRoundIds.single: stage,
      };
      final layout = buildBracketGraphLayout(bracket);
      final semi = layout.stageHeaderRects[byRound['thbREnFa']!.key]!;
      final finalHeader = layout.stageHeaderRects[byRound['BljVh3AO']!.key]!;
      final third = layout.stageHeaderRects[byRound['9CtXnTQu']!.key]!;
      expect(finalHeader.left, semi.left + BracketGraphMetrics.stageStride);
      expect(third.left, finalHeader.left);
      expect(
        third.top,
        greaterThan(
          layout.matchRects[byRound['BljVh3AO']!.matches.single.key]!.bottom,
        ),
      );
    },
  );

  test('qualifying a winner does not move reserved quarterfinal slots', () {
    final metadata = f.metadata()..['results'] = [];
    final before = f.build(metadata: metadata);
    final after = f.build(metadata: f.metadata());
    final beforeLayout = buildBracketGraphLayout(before);
    final afterLayout = buildBracketGraphLayout(after);
    final future = after.stages.where(
      (s) => !s.sourceRoundIds.contains('60IswAYI'),
    );
    for (final stage in future) {
      for (final match in stage.matches) {
        expect(
          afterLayout.matchRects[match.key],
          beforeLayout.matchRects[match.key],
        );
      }
    }
  });

  test('the full tree has fourteen winner routes and two loser branches', () {
    final bracket = f.build(metadata: f.metadata());
    final layout = buildBracketGraphLayout(bracket);
    expect(layout.connections, hasLength(16));
    expect(layout.connections.where((c) => c.isConfirmed), hasLength(1));
    expect(layout.connections.where((c) => c.feedsLosers), hasLength(2));
    expect(bracket.edges, hasLength(1));
  });

  test(
    'published final participants prove semifinal losers for third place',
    () {
      final games = f.sourceGames();
      final players = {
        for (final g in games)
          for (final p in g.players!) p.fideId: p,
      };
      Games game(
        String id,
        String round,
        int white,
        int black,
        String status,
      ) => Games(
        id: id,
        roundId: round,
        roundSlug: round,
        tourId: 'fqCjSUpE',
        tourSlug: '2026-speed-chess-championship',
        players: [players[white]!, players[black]!],
        status: status,
        boardNr: 1,
      );
      final bracket = f.build(
        metadata: f.metadata(),
        games: [
          ...games,
          game('semi-1', 'thbREnFa', 2016192, 1503014, '0-1'),
          game('semi-2', 'thbREnFa', 2020009, 5202213, '1-0'),
          game('final', 'BljVh3AO', 1503014, 2020009, '*'),
        ],
      );
      final third = bracket.stages
          .firstWhere((s) => s.sourceRoundIds.contains('9CtXnTQu'))
          .matches
          .single;
      expect(
        {third.participant1.fideId, third.participant2.fideId},
        {2016192, 5202213},
      );
      expect(third.isProjected, isTrue);
      expect(third.feedsLosers, isTrue);
      final quarters = bracket.stages.firstWhere(
        (s) => s.sourceRoundIds.contains('qhktidXj'),
      );
      expect(quarters.matches, hasLength(4));
    },
  );
}
