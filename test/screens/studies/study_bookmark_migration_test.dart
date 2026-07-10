import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Study bookmark migration is owner-scoped and content-free', () {
    final sql =
        File(
          'supabase/migrations/20260710193409_study_bookmark_references.sql',
        ).readAsStringSync();

    expect(
      sql,
      contains(
        'alter table public.user_study_bookmarks enable row level security',
      ),
    );
    expect(sql, contains('user_id = (select auth.uid())'));
    expect(sql, contains(r"lichess_study_id ~ '^[A-Za-z0-9]{8}$'"));
    expect(sql, contains(r"content_version ~ '^sha256:[0-9a-f]{64}$'"));
    expect(sql, contains('last_ply between 0 and 1000000'));
    expect(sql, contains("set search_path = ''"));
    expect(sql.toLowerCase(), isNot(contains('premium')));
    expect(sql.toLowerCase(), isNot(contains('pgn')));
  });
}
