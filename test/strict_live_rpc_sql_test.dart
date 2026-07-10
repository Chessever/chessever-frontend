import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('strict-live RPC returns only compact event ids with invoker ACLs', () {
    final sql =
        File(
          'supabase/migrations/20260710012016_strict_live_ids_rpc.sql',
        ).readAsStringSync().toLowerCase();
    final normalized = sql.replaceAll(RegExp(r'\s+'), ' ');

    expect(sql, contains('security invoker'));
    expect(sql, contains("set search_path = ''"));
    expect(sql, contains('max(g.last_move_time)'));
    expect(sql, contains('returns table (group_broadcast_id text)'));
    expect(
      normalized,
      contains(
        'revoke all on function public.get_strict_live_group_broadcast_ids'
        '(text[], integer) from public, anon',
      ),
    );
    expect(
      normalized,
      contains(
        'grant execute on function public.get_strict_live_group_broadcast_ids'
        '(text[], integer) to authenticated',
      ),
    );
    expect(sql, isNot(contains('select *')));
  });
}
