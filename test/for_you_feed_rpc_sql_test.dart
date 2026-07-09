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
