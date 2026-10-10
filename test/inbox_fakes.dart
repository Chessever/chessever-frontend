// Labeled local fixtures/doubles. These never contact a hosted backend.
import 'dart:async';
import 'dart:convert';

import 'package:chessever2/screens/inbox/inbox_message.dart';
import 'package:chessever2/screens/inbox/inbox_repository.dart';

const inboxOwnerA = '10000000-0000-4000-8000-000000000001';
const inboxOwnerB = '10000000-0000-4000-8000-000000000002';
const inboxIdA = '20000000-0000-4000-8000-000000000001';
const inboxIdB = '20000000-0000-4000-8000-000000000002';
final inboxReadTime = DateTime.utc(2026, 9, 30, 12);

InboxMessage inboxFixture(String id, {DateTime? readAt}) => InboxMessage(
  id: id,
  title: id == inboxIdA
      ? 'Fixture: study a position'
      : 'Fixture: organize games',
  body:
      'LOCAL TEST FIXTURE ONLY.\n\nUse Board to explore a chess position. '
      '<script>alert(1)</script> [link](javascript:alert(1))',
  publishedAt: DateTime.utc(2026, 9, 30),
  readAt: readAt,
);

class FakeInboxSource implements InboxSource {
  @override
  bool hasSession(String ownerId) => true;
  final rows = <String, List<InboxMessage>>{
    inboxOwnerA: [inboxFixture(inboxIdA), inboxFixture(inboxIdB)],
    inboxOwnerB: [inboxFixture(inboxIdB)],
  };
  final fetches = <String>[];
  final marks = <(String, String)>[];
  bool failFetch = false;
  bool failMark = false;
  Future<List<InboxMessage>> Function(String)? fetchOverride;
  Future<DateTime> Function(String, String)? markOverride;

  @override
  Future<List<InboxMessage>> fetch(String ownerId) async {
    fetches.add(ownerId);
    if (failFetch) throw StateError('LOCAL FIXTURE fetch failure');
    if (fetchOverride != null) return fetchOverride!(ownerId);
    return List.of(rows[ownerId] ?? []);
  }

  @override
  Future<DateTime> markRead(String ownerId, String messageId) async {
    marks.add((ownerId, messageId));
    if (failMark) throw StateError('LOCAL FIXTURE mark failure');
    if (markOverride != null) return markOverride!(ownerId, messageId);
    rows[ownerId] = (rows[ownerId] ?? [])
        .map((m) => m.id == messageId ? m.withReadAt(inboxReadTime) : m)
        .toList();
    return inboxReadTime;
  }
}

class FakeInboxCache implements InboxCache {
  final encoded = <String, String>{};
  bool failLoad = false;
  bool failSave = false;
  Completer<void>? loadGate;

  @override
  Future<List<InboxMessage>?> load(String ownerId) async {
    if (loadGate != null) await loadGate!.future;
    if (failLoad) throw StateError('LOCAL FIXTURE cache failure');
    final value = encoded[ownerId];
    if (value == null) return null;
    return (jsonDecode(value) as List)
        .map((m) => InboxMessage.fromJson(Map<String, dynamic>.from(m as Map)))
        .toList();
  }

  @override
  Future<void> save(String ownerId, List<InboxMessage> messages) async {
    if (failSave) throw StateError('LOCAL FIXTURE cache write failure');
    encoded[ownerId] = jsonEncode(messages.map((m) => m.toJson()).toList());
  }
}
