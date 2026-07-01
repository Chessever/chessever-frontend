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
