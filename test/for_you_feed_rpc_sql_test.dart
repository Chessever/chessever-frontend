import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('For You feed RPC SQL', () {
    test('latest get_for_you_group_broadcasts omits future round starts', () {
      final migration = _latestMigrationDefining(
        'create or replace function public.get_for_you_group_broadcasts',
      );
      final sql = migration.readAsStringSync();

      expect(sql, contains("and r.starts_at >= now() - interval '1 day'"));
      expect(sql, contains('and r.starts_at <= now()'));
      expect(
        sql,
        isNot(contains("r.starts_at <= now() + interval '3 days'")),
        reason: 'For You must not surface events whose rounds start later.',
      );
    });

    test('latest get_for_you_top_games ranks round recency before rating', () {
      final migration = _latestMigrationDefining(
        'create or replace function public.get_for_you_top_games',
      );
      final sql = migration.readAsStringSync();

      final eventRankingStart = sql.indexOf('partition by cg.event_id');
      expect(eventRankingStart, isNonNegative);

      final eventRankingSql = sql.substring(eventRankingStart);
      final sourceRoundTimeOrder = eventRankingSql.indexOf(
        'cg.source_round_time desc nulls last',
      );
      final categoryEloOrder = eventRankingSql.indexOf(
        'cg.category_avg_elo desc nulls last',
      );

      expect(sourceRoundTimeOrder, isNonNegative);
      expect(categoryEloOrder, isNonNegative);
      expect(
        sourceRoundTimeOrder,
        lessThan(categoryEloOrder),
        reason:
            'For You card previews should show the freshest completed section '
            'before falling back to stronger/older rating categories.',
      );
    });

    test(
      'latest get_for_you_top_games ranks live games by ascending board first',
      () {
        final migration = _latestMigrationDefining(
          'create or replace function public.get_for_you_top_games',
        );
        final sql = migration.readAsStringSync();

        expect(
          sql,
          contains("lower(btrim(coalesce(g.status, ''))) in ('*', 'ongoing')"),
          reason: 'The RPC should recognize both persisted ongoing values.',
        );

        final eventRankingStart = sql.indexOf('partition by cg.event_id');
        expect(eventRankingStart, isNonNegative);

        final eventRankingSql = sql.substring(eventRankingStart);
        final liveGameOrder = eventRankingSql.indexOf('cg.is_live_game desc');
        final boardNumberOrder = eventRankingSql.indexOf(
          'cg.board_nr asc nulls last',
        );
        final sourcePriorityOrder = eventRankingSql.indexOf(
          'cg.source_priority asc',
        );
        final sourceRoundTimeOrder = eventRankingSql.indexOf(
          'cg.source_round_time desc nulls last',
        );
        final categoryEloOrder = eventRankingSql.indexOf(
          'cg.category_avg_elo desc nulls last',
        );

        expect(liveGameOrder, isNonNegative);
        expect(boardNumberOrder, greaterThan(liveGameOrder));
        expect(sourcePriorityOrder, greaterThan(boardNumberOrder));
        expect(sourceRoundTimeOrder, greaterThan(sourcePriorityOrder));
        expect(categoryEloOrder, greaterThan(sourceRoundTimeOrder));
      },
    );

    test(
      'latest get_for_you_top_games deduplicates logical boards before limiting',
      () {
        final migration = _latestMigrationDefining(
          'create or replace function public.get_for_you_top_games',
        );
        final sql = migration.readAsStringSync();

        final identityStart = sql.indexOf('identified_games as (');
        final duplicateRankingStart = sql.indexOf(
          'duplicate_ranked_games as (',
        );
        final uniqueGamesStart = sql.indexOf('deduplicated_games as (');
        final eventRankingStart = sql.indexOf('\n  ranked_games as (');

        expect(identityStart, isNonNegative);
        expect(duplicateRankingStart, greaterThan(identityStart));
        expect(uniqueGamesStart, greaterThan(duplicateRankingStart));
        expect(eventRankingStart, greaterThan(uniqueGamesStart));

        final duplicateRankingSql = sql.substring(
          duplicateRankingStart,
          uniqueGamesStart,
        );
        expect(duplicateRankingSql, contains('ig.event_id'));
        expect(duplicateRankingSql, contains('ig.logical_round_key'));
        expect(duplicateRankingSql, contains('ig.logical_round_time'));
        expect(duplicateRankingSql, contains('ig.white_key'));
        expect(duplicateRankingSql, contains('ig.black_key'));
        expect(duplicateRankingSql, contains('ig.logical_game_discriminator'));

        final identitySql = sql.substring(identityStart, duplicateRankingStart);
        expect(identitySql, contains('pgn-round:'));
        expect(identitySql, contains('from \'(?m)^[[]Round "([^"]+)"[]]\''));
        expect(identitySql, contains("then 'fen:' || cg.fen"));
        expect(identitySql, contains("else 'game-id:' || cg.id"));

        final eventRankingSql = sql.substring(eventRankingStart);
        expect(eventRankingSql, contains('from deduplicated_games cg'));
      },
    );
  });
}

File _latestMigrationDefining(String needle) {
  final migrations =
      Directory('supabase/migrations')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.sql'))
          .where((file) => file.readAsStringSync().contains(needle))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  if (migrations.isEmpty) {
    fail('No migration defines $needle');
  }

  return migrations.last;
}
