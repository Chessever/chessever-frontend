import 'dart:async';

import 'package:chessever2/screens/stories/story_row_prefs.dart';

/// The Collection stories choice kept in memory: the device's copy, the
/// server's `user_engine_settings.collection_stories` column ([server]) and
/// the account's 39.2 copy ([legacy]). Signed out (a guest) by default.
class MemoryStoryRowStore implements StoryRowPrefsStore {
  MemoryStoryRowStore({
    this.local,
    this.id,
    this.server,
    this.legacy,
    this.missingColumn = false,
    this.offline = false,
  });

  /// The device's copy.
  String? local;

  /// The signed-in reader; null when signed out or a guest.
  String? id;

  /// The server's column for [id]; null when never chosen.
  StoryRowMode? server;

  /// The account's 39.2 copy (auth user_metadata).
  Map<String, dynamic>? legacy;

  /// The server has no column yet (its migration not applied).
  bool missingColumn;

  /// Reads and writes fail as offline.
  bool offline;

  /// Holds the next server read until it completes.
  Completer<void>? readGate;

  /// Holds server writes until it completes.
  Completer<void>? writeGate;

  /// A read answers with the column as it was when the read began (a
  /// request the server served before a write committed).
  bool readsAtStart = false;

  int reads = 0;
  final List<(String, StoryRowMode)> serverWrites = [];
  final List<Map<String, Object?>> legacyWrites = [];

  final StreamController<String?> _sessions =
      StreamController<String?>.broadcast();

  /// A sign in, a sign out or an account switch.
  void signIn(String? next) {
    id = next;
    _sessions.add(next);
  }

  @override
  String? readLocal() => local;

  @override
  Future<void> writeLocal(String value) async => local = value;

  @override
  String? accountId() => id;

  @override
  Stream<String?> accountChanges() => _sessions.stream;

  @override
  Future<StoryRowServerRead> readServer(String accountId) async {
    reads++;
    final seen = server;
    final gate = readGate;
    if (gate != null) await gate.future;
    if (offline) return const StoryRowServerUnreachable();
    if (missingColumn) return const StoryRowServerMissing();
    return StoryRowServerValue(readsAtStart ? seen : server);
  }

  @override
  Future<StoryRowServerWrite> writeServer(
    String accountId,
    StoryRowMode mode,
  ) async {
    final gate = writeGate;
    if (gate != null) await gate.future;
    if (offline) return StoryRowServerWrite.failed;
    if (missingColumn) return StoryRowServerWrite.missingColumn;
    serverWrites.add((accountId, mode));
    server = mode;
    return StoryRowServerWrite.saved;
  }

  @override
  Map<String, dynamic>? readLegacyAccount() => id == null ? null : legacy;

  @override
  Future<void> writeLegacyAccount(Map<String, Object?> value) async {
    legacyWrites.add(value);
    legacy = Map<String, dynamic>.from(value);
  }
}
