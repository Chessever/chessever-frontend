import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A guarded, idempotent single-row write, NOT a cross-table transaction.
/// Only the supplied natural key is touched. A concurrent change fails closed.
/// Including the attempted write in a caller's undo journal also covers a
/// response lost after the server committed it.
Future<void> writeConfirmedSavedRow({
  required SupabaseClient client,
  required String userId,
  required String table,
  required List<String> keyColumns,
  required Map<String, dynamic>? before,
  required Map<String, dynamic>? after,
}) async {
  final key = before ?? after!;
  Future<Map<String, dynamic>?> read(Map<String, dynamic> identity) async {
    var query = client.from(table).select().eq('user_id', userId);
    for (final column in keyColumns) {
      query = query.eq(column, identity[column] as Object);
    }
    return await query.maybeSingle();
  }

  bool matches(Map<String, dynamic>? row, Map<String, dynamic>? expected) {
    if (row == null || expected == null) return row == expected;
    return expected.entries.every((e) {
      if (e.key.endsWith('_at') && e.value is String && row[e.key] is String) {
        return DateTime.tryParse(row[e.key] as String) ==
            DateTime.tryParse(e.value as String);
      }
      return const DeepCollectionEquality().equals(row[e.key], e.value);
    });
  }

  final current = await read(key);
  // Retry or compensation after a lost reply: never repeat a committed write.
  if (after == null && current == null) return;
  if (after != null && matches(await read(after), after)) {
    if (before == null ||
        keyColumns.every((k) => before[k] == after[k]) ||
        current == null) {
      return;
    }
  }
  if (!matches(current, before)) throw const SavedRowConflict();

  if (before == null) {
    await client.from(table).insert({...after!, 'user_id': userId});
  } else {
    // Compare all business fields read for this row. In particular, deleting
    // a merged source must not remove a subscription another client changed.
    var query = after == null
        ? client.from(table).delete()
        : client.from(table).update(after);
    query = query.eq('user_id', userId);
    for (final entry in before.entries) {
      if (entry.value == null) {
        query = query.isFilter(entry.key, null);
      } else {
        query = query.eq(
          entry.key,
          entry.value is Map || entry.value is List
              ? jsonEncode(entry.value)
              : entry.value as Object,
        );
      }
    }
    final changed = await query.select();
    if ((changed as List).length != 1) throw const SavedRowConflict();
  }
  if (!matches(await read(after ?? key), after)) {
    throw const SavedRowConflict();
  }
  if (before != null &&
      after != null &&
      keyColumns.any((k) => before[k] != after[k]) &&
      await read(before) != null) {
    throw const SavedRowConflict();
  }
}

class SavedRowConflict implements Exception {
  const SavedRowConflict();
  @override
  String toString() => 'Saved item changed elsewhere. Refresh and try again.';
}
