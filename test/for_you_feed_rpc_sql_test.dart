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

    test(
      'latest get_for_you_top_games selects one tour before ranking boards',
      () {
        final migration = _latestMigrationDefining(
          'create or replace function public.get_for_you_top_games',
        );
        final sql = migration.readAsStringSync();

        expect(
          sql,
          contains('selected_round_sources as ('),
          reason: 'Each event must resolve one tour and round before boards.',
        );
        expect(
          sql,
          contains('join public.tours t on t.id = rs.selected_tour_id'),
        );
        expect(
          sql,
          contains('join public.rounds r on r.id = rs.source_round_id'),
        );
        expect(
          sql,
          isNot(contains('t.avg_elo is not distinct from rs.category_avg_elo')),
          reason: 'Average Elo is priority metadata, not category identity.',
        );
        expect(
          sql,
          contains('partition by rs.event_id, rs.selected_tour_id'),
          reason:
              'All ranked boards for an event must belong to its selected tour.',
        );
      },
    );

    test(
      'latest get_for_you_top_games picks live category by Elo before recency',
      () {
        final migration = _latestMigrationDefining(
          'create or replace function public.get_for_you_top_games',
        );
        final sql = migration.readAsStringSync();

        final liveSourcesStart = sql.indexOf('live_round_sources as (');
        final fallbackSourcesStart = sql.indexOf('fallback_round_sources as (');
        expect(liveSourcesStart, isNonNegative);
        expect(fallbackSourcesStart, greaterThan(liveSourcesStart));

        final liveSourcesSql = sql.substring(
          liveSourcesStart,
          fallbackSourcesStart,
        );
        final categoryEloOrder = liveSourcesSql.indexOf(
          'er.category_avg_elo desc nulls last',
        );
        final sourceRoundTimeOrder = liveSourcesSql.indexOf(
          'er.source_round_time desc nulls last',
        );

        expect(categoryEloOrder, isNonNegative);
        expect(sourceRoundTimeOrder, greaterThan(categoryEloOrder));
      },
    );

    test(
      'latest get_for_you_top_games backfills by round inside selected tour',
      () {
        final migration = _latestMigrationDefining(
          'create or replace function public.get_for_you_top_games',
        );
        final sql = migration.readAsStringSync();

        expect(
          sql,
          contains('selected_tour_rounds as ('),
          reason: 'Backfill rounds must remain scoped to the selected tour.',
        );

        final eventRankingStart = sql.indexOf('partition by cg.event_id');
        expect(eventRankingStart, isNonNegative);

        final eventRankingSql = sql.substring(eventRankingStart);
        final roundRankOrder = eventRankingSql.indexOf('cg.round_rank asc');
        final boardRankOrder = eventRankingSql.indexOf('cg.board_rank asc');

        expect(roundRankOrder, isNonNegative);
        expect(boardRankOrder, greaterThan(roundRankOrder));
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
