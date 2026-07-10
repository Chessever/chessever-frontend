import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _migrationPath =
    'supabase/migrations/20260710150000_my_space_layouts.sql';

const _collectionTypes = {
  'my_likes',
  'saved_events',
  'databases',
  'saved_studies',
  'favorite_players',
  'library_recents',
  'miniatures',
  'study_discovery',
};

const _pinnedTypes = {
  'pinned_event',
  'pinned_database',
  'pinned_folder',
  'pinned_study',
  'pinned_study_chapter',
  'pinned_player',
  'pinned_game',
};

const _v1Types = {'continue', ..._collectionTypes, ..._pinnedTypes};

void main() {
  late String sql;
  late String normalized;

  setUpAll(() {
    sql = File(_migrationPath).readAsStringSync().toLowerCase();
    normalized = sql.replaceAll(RegExp(r'\s+'), ' ').trim();
  });

  test('creates only the bounded one-row-per-user layout store', () {
    _expectSqlPattern(
      sql,
      r'create\s+table\s+public\.user_my_space_layouts\s*\(',
    );
    _expectSqlPattern(
      sql,
      r'user_id\s+uuid\s+primary\s+key\s+references\s+'
      r'auth\.users\s*\(\s*id\s*\)\s+on\s+delete\s+cascade',
    );
    _expectSqlPattern(sql, r'schema_version\s+integer\s+not\s+null');
    _expectSqlPattern(sql, r'check\s*\(\s*schema_version\s*>\s*0\s*\)');
    _expectSqlPattern(sql, r'revision\s+bigint\s+not\s+null');
    _expectSqlPattern(sql, r'check\s*\(\s*revision\s*>\s*0\s*\)');
    _expectSqlPattern(sql, r'shelves\s+jsonb\s+not\s+null');
    _expectSqlPattern(sql, r"jsonb_typeof\s*\(\s*shelves\s*\)\s*=\s*'array'");
    _expectSqlPattern(sql, r'jsonb_array_length\s*\(\s*shelves\s*\)\s*<=\s*24');
    _expectSqlPattern(
      sql,
      r'octet_length\s*\(\s*shelves::text\s*\)\s*<=\s*32768',
    );
    _expectSqlPattern(sql, r'created_at\s+timestamptz\s+not\s+null\s+default');
    _expectSqlPattern(sql, r'updated_at\s+timestamptz\s+not\s+null\s+default');

    expect(
      RegExp(
        r'create\s+table\s+(?:public\.)?[a-z0-9_]*progress',
        caseSensitive: false,
      ).hasMatch(sql),
      isFalse,
      reason: 'Study progress is outside this migration slice.',
    );
    expect(sql, isNot(contains('study_progress')));
  });

  test('allows authenticated owner reads but no direct client writes', () {
    _expectSqlPattern(
      sql,
      r'alter\s+table\s+public\.user_my_space_layouts\s+'
      r'enable\s+row\s+level\s+security',
    );

    final policies =
        RegExp(
          r'create\s+policy\b.*?;',
          caseSensitive: false,
          dotAll: true,
        ).allMatches(sql).map((match) => _normalize(match.group(0)!)).toList();

    expect(policies, hasLength(1));
    final selectPolicy = policies.single;
    expect(selectPolicy, contains('for select'));
    expect(selectPolicy, contains('to authenticated'));
    expect(
      RegExp(
        r'using\s*\(\s*user_id\s*=\s*\(\s*select\s+auth\.uid\(\)\s*\)\s*\)',
      ).hasMatch(selectPolicy),
      isTrue,
    );
    expect(selectPolicy, isNot(contains('premium')));
    expect(
      RegExp(r'for\s+(?:insert|update|delete|all)\b').hasMatch(selectPolicy),
      isFalse,
    );

    _expectSqlPattern(
      sql,
      r'revoke\s+all\s+on\s+table\s+'
      r'public\.user_my_space_layouts\s+from\s+'
      r'public\s*,\s*anon\s*,\s*authenticated',
    );
    _expectSqlPattern(
      sql,
      r'grant\s+select\s+on\s+table\s+'
      r'public\.user_my_space_layouts\s+to\s+authenticated',
    );
    expect(
      RegExp(
        r'^\s*grant\s+[^;]*\b(?:all|insert|update|delete)\b[^;]*\bon\s+'
        r'(?:table\s+)?public\.user_my_space_layouts',
        caseSensitive: false,
        multiLine: true,
      ).hasMatch(sql),
      isFalse,
      reason: 'Clients must mutate only through the save RPC.',
    );
    expect(
      RegExp(
        r'grant\s+select\s+on\s+(?:table\s+)?'
        r'public\.user_my_space_layouts\s+to\s+(?:public|anon)\b',
        caseSensitive: false,
      ).hasMatch(sql),
      isFalse,
      reason: 'Anonymous roles must not read layout rows.',
    );
  });

  test('hardens the RPC and checks server-derived premium authority', () {
    _expectSqlPattern(
      sql,
      r'create\s+or\s+replace\s+function\s+'
      r'public\.save_my_space_layout\s*\(\s*'
      r'p_layout\s+jsonb\s*,\s*p_expected_revision\s+bigint\s*\)',
    );
    _expectSqlPattern(
      sql,
      r'returns\s+public\.user_my_space_layouts\s+'
      r'language\s+plpgsql\s+security\s+definer\s+'
      r"set\s+search_path\s*=\s*''",
    );
    _expectSqlPattern(
      sql,
      r'v_user_id\s+uuid\s*:=\s*\(\s*select\s+auth\.uid\(\)\s*\)',
    );
    _expectSqlPattern(
      sql,
      r'from\s+public\.user_premium_view\s+as\s+premium\s+'
      r'where\s+premium\.user_id\s*=\s*v_user_id\s+'
      r'and\s+premium\.is_premium\s+is\s+true',
    );

    expect(
      normalized,
      contains(
        "errcode = '28000', message = 'my_space_layout_unauthenticated'",
      ),
    );
    expect(
      normalized,
      contains(
        "errcode = '42501', message = 'my_space_layout_premium_required'",
      ),
    );

    _expectSqlPattern(
      sql,
      r'revoke\s+all\s+on\s+function\s+'
      r'public\.save_my_space_layout\s*\(\s*jsonb\s*,\s*bigint\s*\)\s+'
      r'from\s+public\s*,\s*anon\s*,\s*authenticated',
    );
    _expectSqlPattern(
      sql,
      r'grant\s+execute\s+on\s+function\s+'
      r'public\.save_my_space_layout\s*\(\s*jsonb\s*,\s*bigint\s*\)\s+'
      r'to\s+authenticated',
    );

    final executeGrants =
        RegExp(
          r'grant\s+execute\s+on\s+function\s+'
          r'public\.save_my_space_layout\s*\(\s*jsonb\s*,\s*bigint\s*\).*?;',
          caseSensitive: false,
          dotAll: true,
        ).allMatches(sql).map((match) => _normalize(match.group(0)!)).toList();
    expect(executeGrants, hasLength(1));
    expect(executeGrants.single, contains('to authenticated'));
    expect(executeGrants.single, isNot(contains('to anon')));
    expect(executeGrants.single, isNot(contains('to public')));
  });

  test('validates the complete schema-v1 document and exact type set', () {
    expect(normalized, contains('from pg_catalog.jsonb_object_keys(p_layout)'));
    expect(normalized, contains('if v_key_count <> 2'));
    expect(normalized, contains("p_layout ? 'schema_version'"));
    expect(normalized, contains("p_layout ? 'shelves'"));
    expect(normalized, contains("(p_layout ->> 'schema_version') <> '1'"));
    _expectSqlPattern(
      sql,
      r'octet_length\s*\(\s*p_layout::text\s*\)\s*>\s*32768',
    );
    _expectSqlPattern(
      sql,
      r'jsonb_array_length\s*\(\s*v_shelves\s*\)\s*>\s*24',
    );

    expect(
      normalized,
      contains('from pg_catalog.jsonb_object_keys(v_descriptor)'),
    );
    expect(normalized, contains('if v_key_count <> 5'));
    for (final key in ['id', 'type', 'targetid', 'size', 'visible']) {
      expect(normalized, contains("v_descriptor ? '$key'"));
    }
    expect(
      normalized,
      contains(
        "jsonb_typeof(v_descriptor -> 'visible') is distinct from 'boolean'",
      ),
    );
    expect(normalized, contains('char_length(v_id) > 128'));
    expect(normalized, contains("v_id ~ '^[[:space:]]'"));
    expect(normalized, contains("v_id ~ '[[:space:]]\$'"));
    expect(normalized, contains("v_descriptor -> 'targetid' <> 'null'::jsonb"));
    expect(
      normalized,
      contains(
        "jsonb_typeof(v_descriptor -> 'targetid') is distinct from 'string'",
      ),
    );
    expect(normalized, contains('char_length(v_target_id) > 512'));

    final allowedTypes = RegExp(
      r'if\s+v_type\s+not\s+in\s*\((.*?)\)\s*then',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(sql);
    expect(allowedTypes, isNotNull);
    expect(_stringLiterals(allowedTypes!.group(1)!), unorderedEquals(_v1Types));
  });

  test('matches Dart size, target, singleton, and uniqueness rules', () {
    final sizeMatrix = RegExp(
      r"if\s+not\s*\(\s*"
      r"\(v_type\s*=\s*'continue'\s+and\s+v_size\s+in\s*\(([^)]*)\)\)\s*"
      r"or\s*\(\s*v_type\s+in\s*\((.*?)\)\s*"
      r"and\s+v_size\s+in\s*\(([^)]*)\)\s*\)\s*"
      r"or\s*\(\s*v_type\s+in\s*\((.*?)\)\s*"
      r"and\s+v_size\s+in\s*\(([^)]*)\)\s*\)\s*"
      r"\)\s*then",
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(sql);

    expect(sizeMatrix, isNotNull);
    expect(
      _stringLiterals(sizeMatrix!.group(1)!),
      unorderedEquals({'standard', 'featured'}),
    );
    expect(
      _stringLiterals(sizeMatrix.group(2)!),
      unorderedEquals(_collectionTypes),
    );
    expect(
      _stringLiterals(sizeMatrix.group(3)!),
      unorderedEquals({'compact', 'standard'}),
    );
    expect(
      _stringLiterals(sizeMatrix.group(4)!),
      unorderedEquals(_pinnedTypes),
    );
    expect(
      _stringLiterals(sizeMatrix.group(5)!),
      unorderedEquals({'standard', 'featured'}),
    );

    expect(
      normalized,
      contains("group by descriptor.value ->> 'id' having count(*) > 1"),
    );
    expect(
      normalized,
      contains("group by descriptor.value ->> 'type' having count(*) > 1"),
    );
    expect(
      normalized,
      contains(
        "group by descriptor.value ->> 'type', "
        "descriptor.value ->> 'targetid' having count(*) > 1",
      ),
    );
    expect(sql, contains('my_space_layout_duplicate_id'));
    expect(sql, contains('my_space_layout_duplicate_dynamic_type'));
    expect(sql, contains('my_space_layout_duplicate_pinned_target'));

    final dynamicSingletonTypes = RegExp(
      r"where\s+descriptor\.value\s*->>\s*'type'\s+in\s*\(([^)]*)\)\s*"
      r"group\s+by\s+descriptor\.value\s*->>\s*'type'\s*"
      r'having\s+count\s*\(\s*\*\s*\)\s*>\s*1',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(sql);
    expect(dynamicSingletonTypes, isNotNull);
    expect(
      _stringLiterals(dynamicSingletonTypes!.group(1)!),
      unorderedEquals({'continue', ..._collectionTypes}),
    );

    final uniquePinnedTargets = RegExp(
      r"where\s+descriptor\.value\s*->>\s*'type'\s+in\s*\(([^)]*)\)\s*"
      r"group\s+by\s+descriptor\.value\s*->>\s*'type'\s*,\s*"
      r"descriptor\.value\s*->>\s*'targetid'\s*"
      r'having\s+count\s*\(\s*\*\s*\)\s*>\s*1',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(sql);
    expect(uniquePinnedTargets, isNotNull);
    expect(
      _stringLiterals(uniquePinnedTargets!.group(1)!),
      unorderedEquals(_pinnedTypes),
    );
  });

  test('uses atomic optimistic concurrency and monotonic reset saves', () {
    expect(normalized, contains('if p_expected_revision = 0 then'));
    _expectSqlPattern(
      sql,
      r'values\s*\(\s*v_user_id\s*,\s*1\s*,\s*1\s*,\s*'
      r'v_shelves\s*,\s*v_now\s*,\s*v_now\s*\)',
    );
    _expectSqlPattern(sql, r'on\s+conflict\s*\(\s*user_id\s*\)\s+do\s+nothing');
    _expectSqlPattern(sql, r'revision\s*=\s*layout\.revision\s*\+\s*1');
    _expectSqlPattern(
      sql,
      r'where\s+layout\.user_id\s*=\s*v_user_id\s+'
      r'and\s+layout\.revision\s*=\s*p_expected_revision',
    );
    expect(
      normalized,
      contains(
        "errcode = '40001', message = 'my_space_layout_revision_conflict'",
      ),
    );

    final functionBody = RegExp(
      r'as\s+\$function\$(.*?)\$function\$\s*;',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(sql);
    expect(functionBody, isNotNull);
    expect(
      RegExp(
        r'delete\s+from\s+public\.user_my_space_layouts',
        caseSensitive: false,
      ).hasMatch(functionBody!.group(1)!),
      isFalse,
    );
    expect(
      normalized,
      contains(
        'reset-to-default saves the curated default through this same rpc '
        'with the current expected revision; it never deletes the row, so '
        'revision remains monotonic',
      ),
    );
  });
}

void _expectSqlPattern(String sql, String pattern) {
  expect(
    RegExp(pattern, caseSensitive: false, dotAll: true).hasMatch(sql),
    isTrue,
    reason: 'Expected SQL pattern: $pattern',
  );
}

String _normalize(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
}

Set<String> _stringLiterals(String value) {
  return RegExp(
    r"'([^']+)'",
  ).allMatches(value).map((match) => match.group(1)!).toSet();
}
