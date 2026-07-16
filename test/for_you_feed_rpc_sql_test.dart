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

    test('latest get_for_you_top_games locks one tour and round', () {
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
        contains('join public.tours t on t.id = srs.selected_tour_id'),
      );
      expect(
        sql,
        contains('join public.rounds r on r.id = srs.source_round_id'),
      );
      expect(
        sql,
        isNot(contains('t.avg_elo is not distinct from srs.category_avg_elo')),
        reason: 'Average Elo is priority metadata, not category identity.',
      );
      expect(
        sql,
        contains('partition by srs.event_id'),
        reason:
            'All ranked boards for an event must belong to its selected tour.',
      );
    });

    test(
      'latest get_for_you_top_games picks a today round by Elo before recency',
      () {
        final migration = _latestMigrationDefining(
          'create or replace function public.get_for_you_top_games',
        );
        final sql = migration.readAsStringSync();

        final todaySourcesStart = sql.indexOf('today_round_sources as (');
        final fallbackSourcesStart = sql.indexOf('fallback_round_sources as (');
        expect(todaySourcesStart, isNonNegative);
        expect(fallbackSourcesStart, greaterThan(todaySourcesStart));

        final todaySourcesSql = sql.substring(
          todaySourcesStart,
          fallbackSourcesStart,
        );
        expect(
          todaySourcesSql,
          contains('where er.has_today'),
          reason: 'The locked round itself must contain a played game today.',
        );
        final categoryEloOrder = todaySourcesSql.indexOf(
          'er.category_avg_elo desc nulls last',
        );
        final sourceRoundTimeOrder = todaySourcesSql.indexOf(
          'er.source_round_time desc nulls last',
        );

        expect(categoryEloOrder, isNonNegative);
        expect(sourceRoundTimeOrder, greaterThan(categoryEloOrder));
      },
    );

    test(
      'latest get_for_you_top_games fallback picks Elo before latest round',
      () {
        final migration = _latestMigrationDefining(
          'create or replace function public.get_for_you_top_games',
        );
        final sql = migration.readAsStringSync();

        final fallbackSourcesStart = sql.indexOf('fallback_round_sources as (');
        final selectedSourcesStart = sql.indexOf('selected_round_sources as (');
        expect(fallbackSourcesStart, isNonNegative);
        expect(selectedSourcesStart, greaterThan(fallbackSourcesStart));

        final fallbackSourcesSql = sql.substring(
          fallbackSourcesStart,
          selectedSourcesStart,
        );
        final categoryEloOrder = fallbackSourcesSql.indexOf(
          'er.category_avg_elo desc nulls last',
        );
        final sourceRoundTimeOrder = fallbackSourcesSql.indexOf(
          'er.source_round_time desc nulls last',
        );

        expect(categoryEloOrder, isNonNegative);
        expect(sourceRoundTimeOrder, greaterThan(categoryEloOrder));
      },
    );

    test(
      'latest get_for_you_top_games never backfills after locking a round',
      () {
        final migration = _latestMigrationDefining(
          'create or replace function public.get_for_you_top_games',
        );
        final sql = migration.readAsStringSync();

        expect(sql, isNot(contains('selected_tour_rounds as (')));
        expect(sql, isNot(contains('round_rank')));
        expect(sql, contains('g.board_nr asc nulls last'));
        expect(sql, contains('top_games.board_rank <= p.board_count'));
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
