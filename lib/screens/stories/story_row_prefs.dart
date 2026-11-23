import 'dart:async';
import 'dart:convert';

import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Whether the collection stories row sits at the top of Today (Settings ›
/// Customization › Collection stories).
enum StoryRowMode {
  /// The row is there, its circles quiet once watched, a circle with
  /// something new leading. The default.
  on,

  /// Never.
  off;

  /// The choice as the picker lists it.
  String get label => switch (this) {
    StoryRowMode.on => 'On',
    StoryRowMode.off => 'Off',
  };

  /// The choice as the settings row names it, beside its title.
  String get shortLabel => label;

  /// The choice as it is written: on the device, in the account's old copy
  /// and in `user_engine_settings.collection_stories`.
  String get _wire => switch (this) {
    StoryRowMode.on => 'on',
    StoryRowMode.off => 'off',
  };

  /// 39.1.0 and older offered "When there's something new" (`new`, the
  /// default) and "Always" (`always`): both are On now. Builds before
  /// 39.2.0 read `on` as their default, When new.
  static StoryRowMode _parse(Object? wire) => switch (wire) {
    'off' => StoryRowMode.off,
    _ => StoryRowMode.on,
  };

  /// The server's column: null when the reader never chose there.
  static StoryRowMode? _fromServer(Object? wire) => switch (wire) {
    'on' => StoryRowMode.on,
    'off' => StoryRowMode.off,
    _ => null,
  };
}

/// The row's state as the reader set it: one choice, On or Off, whichever
/// way it was made (Settings › Customization › Collection stories, or a
/// pull past either end of the row, which turns it Off).
@immutable
class StoryRowPrefs {
  const StoryRowPrefs({
    this.mode = StoryRowMode.on,
    this.owner,
    this.updatedAt = 0,
    this.pending = false,
  });

  /// The reader's choice (account).
  final StoryRowMode mode;

  /// The account [mode] belongs to (device): the signed-in reader's id when
  /// it was set or last loaded, null when set signed out or as a guest.
  /// Another account signing in on this device never inherits it.
  final String? owner;

  /// When [mode] last changed on this device, in ms; 0 when the reader
  /// never chose. Carrying a choice to the server for the first time takes
  /// the newer of the device's and the account's old copy.
  final int updatedAt;

  /// [mode] was changed signed in and has not reached the server yet (a
  /// write that failed offline): the next load writes it instead of reading
  /// the server's older value back over it.
  final bool pending;

  StoryRowPrefs copyWith({
    StoryRowMode? mode,
    String? Function()? owner,
    int? updatedAt,
    bool? pending,
  }) => StoryRowPrefs(
    mode: mode ?? this.mode,
    owner: owner == null ? this.owner : owner(),
    updatedAt: updatedAt ?? this.updatedAt,
    pending: pending ?? this.pending,
  );

  /// The choice and when it was made, as 39.2 kept it on the account (auth
  /// `user_metadata`). Written there only while the server has no column
  /// for it yet ([AppStoryRowPrefsStore.column]).
  Map<String, Object?> toAccountJson() => {'m': mode._wire, 'u': updatedAt};

  /// What the device keeps: the choice, whose it is, and whether it still
  /// has to reach the server. 39.1.0's device fields (the day it saw all,
  /// the row's stretch of days) and 39.2's pull-away are read past and
  /// dropped.
  String encodeLocal() =>
      jsonEncode({...toAccountJson(), 'o': ?owner, if (pending) 'p': true});

  static StoryRowPrefs decodeLocal(String? raw) {
    if (raw == null || raw.isEmpty) return const StoryRowPrefs();
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return const StoryRowPrefs();
      final owner = json['o'];
      return fromAccountJson(json).copyWith(
        owner: () => owner is String && owner.isNotEmpty ? owner : null,
        pending: json['p'] == true,
      );
    } catch (_) {
      return const StoryRowPrefs();
    }
  }

  /// Reads a copy written by any build. 39.2 kept a pull-away beside the
  /// choice (`d`: the row hidden "until something new" while the choice
  /// still said On); the reader put the row away, so it reads as Off, the
  /// one thing a pull means now, and Settings says so.
  static StoryRowPrefs fromAccountJson(Map<dynamic, dynamic> json) {
    final updated = json['u'];
    return StoryRowPrefs(
      mode: _pulledAway(json['d'])
          ? StoryRowMode.off
          : StoryRowMode._parse(json['m']),
      updatedAt: updated is int ? updated : 0,
    );
  }

  /// Whether [json] (the account's old copy) holds a choice at all.
  static bool _holdsChoice(Map<dynamic, dynamic> json) =>
      json.containsKey('m') || _pulledAway(json['d']);

  /// A 39.2 pull-away: `{"t": <ms>, ...}`.
  static bool _pulledAway(Object? dismissal) =>
      dismissal is Map && dismissal['t'] is int;

  @override
  bool operator ==(Object other) =>
      other is StoryRowPrefs &&
      other.mode == mode &&
      other.owner == owner &&
      other.updatedAt == updatedAt &&
      other.pending == pending;

  @override
  int get hashCode => Object.hash(mode, owner, updatedAt, pending);
}

/// What the server holds for the signed-in reader's choice.
sealed class StoryRowServerRead {
  const StoryRowServerRead();
}

/// `user_engine_settings.collection_stories`: [mode], or null when the
/// reader never chose there (no settings row yet, or the column empty).
final class StoryRowServerValue extends StoryRowServerRead {
  const StoryRowServerValue(this.mode);

  final StoryRowMode? mode;
}

/// The server has no column for the choice yet (its migration is not
/// applied): the choice rides on the account's old copy, as in 39.2.
final class StoryRowServerMissing extends StoryRowServerRead {
  const StoryRowServerMissing();
}

/// The server could not be read (offline, a timeout): the device's copy
/// stands until the next load.
final class StoryRowServerUnreachable extends StoryRowServerRead {
  const StoryRowServerUnreachable();
}

/// How a write of the choice to the server went.
enum StoryRowServerWrite {
  saved,

  /// The column is not there yet ([StoryRowServerMissing]).
  missingColumn,

  /// Offline, a timeout, a refusal: the device keeps the change pending.
  failed,
}

/// Where [StoryRowPrefs] live. For a signed-in reader the server's settings
/// row is the choice (`user_engine_settings.collection_stories`, beside the
/// board, engine and Countrymen settings), read at launch, at sign-in and
/// on an account switch, and written on every change. The device keeps a
/// copy read synchronously, so Today's first frame knows whether the row
/// is there, and it is the whole choice for a guest or a reader signed out.
abstract class StoryRowPrefsStore {
  /// The device's copy, synchronously; null when there is none.
  String? readLocal();
  Future<void> writeLocal(String value);

  /// The signed-in reader's id; null when no one is, or the reader is a
  /// guest (an anonymous session), whose choice stays on the device.
  String? accountId();

  /// [accountId] whenever the session changes: a sign in, a sign out, an
  /// account switch, a guest's account made permanent.
  Stream<String?> accountChanges();

  /// The server's copy of [accountId]'s choice.
  Future<StoryRowServerRead> readServer(String accountId);

  /// Writes [mode] as [accountId]'s choice on the server.
  Future<StoryRowServerWrite> writeServer(String accountId, StoryRowMode mode);

  /// The copy 39.1 and 39.2 kept on the signed-in account (auth
  /// `user_metadata`), null when there is none. Read to carry it to the
  /// server the first time it has no choice, and while the server has no
  /// column for it.
  Map<String, dynamic>? readLegacyAccount();

  /// Writes the account's old copy: only while the server has no column for
  /// the choice, so a build that ships before the migration keeps 39.2's
  /// behaviour.
  Future<void> writeLegacyAccount(Map<String, Object?> value);
}

/// The app's store: SharedPreferences on the device (read synchronously,
/// as Settings › Start screen is), the reader's `user_engine_settings` row
/// on the server, as the board, engine and Countrymen settings are kept.
class AppStoryRowPrefsStore implements StoryRowPrefsStore {
  const AppStoryRowPrefsStore({this._client});

  final SupabaseClient? _client;

  static const String localKey = 'today_story_row_v1';

  /// The per-user settings table and its column for the choice.
  static const String table = 'user_engine_settings';
  static const String column = 'collection_stories';

  /// Where 39.1 and 39.2 kept the choice on the account.
  static const String legacyAccountKey = 'today_stories_v1';

  static const Duration _timeout = Duration(seconds: 8);

  /// Whether [error] says the server has no `collection_stories` column
  /// yet: PostgREST answers 42703 (undefined column) to a read and PGRST204
  /// (not in its schema cache) to a write. Never shown to the reader.
  ///
  /// The code is also read from the raw body in the message: some paths of
  /// the client (`maybeSingle`) rethrow PostgREST's error as the HTTP status
  /// with the body as its message.
  static bool isMissingColumn(Object error) {
    if (error is! PostgrestException) return false;
    if (_missingColumnCodes.contains(error.code)) return true;
    try {
      final body = jsonDecode(error.message);
      return body is Map && _missingColumnCodes.contains(body['code']);
    } catch (_) {
      return false;
    }
  }

  static const Set<String> _missingColumnCodes = {'42703', 'PGRST204'};

  SupabaseClient? get _supabase {
    if (_client != null) return _client;
    try {
      return Supabase.instance.client;
    } catch (_) {
      // Not initialised (tests, a failed start): the device copy only.
      return null;
    }
  }

  static String? _accountOf(User? user) =>
      user == null || user.isAnonymous ? null : user.id;

  @override
  String? readLocal() =>
      SharedPreferencesService.instance.prefsOrNull?.getString(localKey);

  @override
  Future<void> writeLocal(String value) async {
    try {
      final prefs =
          SharedPreferencesService.instance.prefsOrNull ??
          await SharedPreferencesService.instance.ensureInitialized();
      await prefs?.setString(localKey, value);
    } catch (e) {
      debugPrint('[Stories] row choice not saved on the device: $e');
    }
  }

  @override
  String? accountId() => _accountOf(_supabase?.auth.currentUser);

  @override
  Stream<String?> accountChanges() =>
      _supabase?.auth.onAuthStateChange.map(
        (auth) => _accountOf(auth.session?.user),
      ) ??
      const Stream.empty();

  @override
  Future<StoryRowServerRead> readServer(String accountId) async {
    final client = _supabase;
    if (client == null) return const StoryRowServerUnreachable();
    try {
      // One row per reader (user_id is unique); none until a first
      // settings write.
      final rows = await client
          .from(table)
          .select(column)
          .eq('user_id', accountId)
          .limit(1)
          .timeout(_timeout);
      return StoryRowServerValue(
        rows.isEmpty ? null : StoryRowMode._fromServer(rows.first[column]),
      );
    } catch (e) {
      if (isMissingColumn(e)) return const StoryRowServerMissing();
      debugPrint('[Stories] row choice not read from the server: $e');
      return const StoryRowServerUnreachable();
    }
  }

  @override
  Future<StoryRowServerWrite> writeServer(
    String accountId,
    StoryRowMode mode,
  ) async {
    final client = _supabase;
    if (client == null) return StoryRowServerWrite.failed;
    try {
      // Names its columns alone, as the Countrymen setting does: the board
      // and engine settings in the same row stay as they are.
      await client
          .from(table)
          .upsert({
            'user_id': accountId,
            column: mode._wire,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }, onConflict: 'user_id')
          .timeout(_timeout);
      return StoryRowServerWrite.saved;
    } catch (e) {
      if (isMissingColumn(e)) return StoryRowServerWrite.missingColumn;
      debugPrint('[Stories] row choice not saved on the server: $e');
      return StoryRowServerWrite.failed;
    }
  }

  @override
  Map<String, dynamic>? readLegacyAccount() {
    final value = _supabase?.auth.currentUser?.userMetadata?[legacyAccountKey];
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  @override
  Future<void> writeLegacyAccount(Map<String, Object?> value) async {
    final auth = _supabase?.auth;
    if (auth?.currentUser == null) return;
    try {
      await auth!
          .updateUser(UserAttributes(data: {legacyAccountKey: value}))
          .timeout(_timeout);
    } catch (e) {
      // The device copy stands; the next change, or the next load, carries
      // it to the account.
      debugPrint('[Stories] row choice not saved on the account: $e');
    }
  }
}

final storyRowPrefsStoreProvider = Provider<StoryRowPrefsStore>(
  (ref) => const AppStoryRowPrefsStore(),
);

/// The clock the row's day is read from (tests pass their own).
final storyClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The row's preferences and lifecycle state.
final storyRowPrefsProvider =
    StateNotifierProvider<StoryRowPrefsNotifier, StoryRowPrefs>(
      (ref) => StoryRowPrefsNotifier(
        ref.watch(storyRowPrefsStoreProvider),
        ref.watch(storyClockProvider),
      ),
    );

class StoryRowPrefsNotifier extends StateNotifier<StoryRowPrefs> {
  StoryRowPrefsNotifier(this._store, this._now)
    : _account = _store.accountId(),
      super(_firstFrame(_store)) {
    _accountSub = _store.accountChanges().listen((id) {
      if (id == _account) return;
      _account = id;
      unawaited(pull());
    });
    unawaited(pull());
  }

  final StoryRowPrefsStore _store;
  final DateTime Function() _now;
  StreamSubscription<String?>? _accountSub;

  /// The reader the last session change named.
  String? _account;

  /// Counts the reader's changes: a load that started before one never
  /// reads the server's older value back over it.
  int _changes = 0;

  /// The load in flight, and whose; Today's row and the session ask for
  /// one at launch, and they share it.
  Future<void>? _loading;
  String? _loadingFor;

  /// Server writes, in the order they were made; [_writes] names the last,
  /// [_writesDone] counts the ones finished (saved, refused or failed).
  Future<void> _writeQueue = Future<void>.value();
  int _writes = 0;
  int _writesDone = 0;

  /// The device's copy, unless it is another account's: then the default
  /// until this account's own choice is read.
  static StoryRowPrefs _firstFrame(StoryRowPrefsStore store) {
    final local = StoryRowPrefs.decodeLocal(store.readLocal());
    final id = store.accountId();
    final owner = local.owner;
    if (id != null && owner != null && owner != id) {
      return StoryRowPrefs(owner: id);
    }
    return local;
  }

  @override
  void dispose() {
    _accountSub?.cancel();
    super.dispose();
  }

  /// Every write of the choice so far has finished (tests).
  @visibleForTesting
  Future<void> get settled => _writeQueue;

  /// Loads the signed-in reader's choice from the server, the source of
  /// truth: at launch, at sign-in, on an account switch, and when Today's
  /// row comes up. A guest or a reader signed out keeps the device's copy.
  ///
  /// The first load that finds no choice on the server carries the one the
  /// reader already had there once: the account's 39.2 copy, or this
  /// device's own (made under this account, or signed out), the newer of
  /// the two. A choice that belongs to another account is never carried.
  Future<void> pull() {
    final id = _store.accountId();
    final loading = _loading;
    if (loading != null && _loadingFor == id) return loading;
    _loadingFor = id;
    late final Future<void> run;
    run = _load(id)
        .catchError((Object e) {
          // Never a message for this: the device's copy stands.
          debugPrint('[Stories] row choice not loaded: $e');
        })
        .whenComplete(() {
          if (identical(_loading, run)) _loading = null;
        });
    _loading = run;
    return run;
  }

  Future<void> _load(String? id) async {
    if (id == null) return;
    final changes = _changes;
    // A write queued or in flight when the read starts can land before the
    // read is answered, and the answer would then be the value it replaced:
    // such a read is dropped (the write carries the reader's latest word;
    // another device's change is read at the next load).
    final writes = _writes;
    final writing = _writesDone < _writes;
    StoryRowServerRead read;
    try {
      read = await _store.readServer(id);
    } catch (_) {
      read = const StoryRowServerUnreachable();
    }
    // Another reader since, or a change made meanwhile (it is the reader's
    // latest word, and it is on its way to the server): this read is stale.
    if (!mounted ||
        _store.accountId() != id ||
        changes != _changes ||
        writing ||
        writes != _writes) {
      return;
    }
    switch (read) {
      case StoryRowServerUnreachable():
        if (!_owns(id)) await _set(StoryRowPrefs(owner: id));
      case StoryRowServerMissing():
        await _loadLegacy(id);
      case StoryRowServerValue(mode: final StoryRowMode server):
        if (state.pending && state.owner == id && state.mode != server) {
          // This device's last change never reached the server: it is the
          // reader's latest word, so it goes there now.
          unawaited(_write(id, state.mode));
          return;
        }
        await _set(
          state.copyWith(mode: server, owner: () => id, pending: false),
        );
      case StoryRowServerValue(mode: null):
        final carried = _carried(id);
        if (carried == null) {
          if (!_owns(id)) await _set(StoryRowPrefs(owner: id));
          return;
        }
        await _set(carried.copyWith(owner: () => id, pending: true));
        unawaited(_write(id, carried.mode));
    }
  }

  /// Whether the device's copy may stand for [id]: it was made under that
  /// account, or signed out.
  bool _owns(String id) => state.owner == null || state.owner == id;

  /// The choice the reader made before the server kept it: the account's
  /// 39.2 copy or this device's, the newer; null when there is none.
  StoryRowPrefs? _carried(String id) {
    final legacy = _store.readLegacyAccount();
    final account = legacy != null && StoryRowPrefs._holdsChoice(legacy)
        ? StoryRowPrefs.fromAccountJson(legacy)
        : null;
    final device = _owns(id) && state.updatedAt > 0 ? state : null;
    if (account == null) return device;
    if (device == null) return account;
    return device.updatedAt > account.updatedAt ? device : account;
  }

  /// No column on the server yet: 39.2's way, the account's copy and the
  /// device's in step, the newer winning. A copy that belongs to another
  /// account ([StoryRowPrefs.owner]) is never carried over.
  Future<void> _loadLegacy(String id) async {
    final remote = StoryRowPrefs.fromAccountJson(
      _store.readLegacyAccount() ?? const {},
    );
    StoryRowPrefs adopt() => state.copyWith(
      mode: remote.mode,
      updatedAt: remote.updatedAt,
      owner: () => id,
      pending: false,
    );
    if (!_owns(id) || remote.updatedAt > state.updatedAt) {
      await _set(adopt());
      return;
    }
    await _set(state.copyWith(owner: () => id, pending: false));
    if (state.updatedAt > remote.updatedAt) {
      unawaited(_store.writeLegacyAccount(state.toAccountJson()));
    }
  }

  /// The reader's choice, from Settings or from the row itself (a pull past
  /// either end turns it Off, its Undo On again). Today and Settings both
  /// watch this one state, so each shows the other's change at once. Signed
  /// in, it is written to the server.
  Future<void> setMode(StoryRowMode mode) async {
    if (mode == state.mode) return;
    _changes++;
    final id = _store.accountId();
    // Always later than the copy it replaces, even on a clock that stepped
    // back. Stamped with the account it was made under.
    final now = _now().millisecondsSinceEpoch;
    await _set(
      state.copyWith(
        mode: mode,
        updatedAt: now > state.updatedAt ? now : state.updatedAt + 1,
        owner: () => id,
        pending: id != null,
      ),
    );
    if (id != null) unawaited(_write(id, mode));
  }

  /// Writes [mode] as [id]'s choice, after the writes before it, so quick
  /// changes reach the server in the order they were made.
  Future<void> _write(String id, StoryRowMode mode) {
    final seq = ++_writes;
    final write = _writeQueue.then((_) async {
      try {
        await _writeNow(id, mode, seq);
      } finally {
        _writesDone++;
      }
    });
    _writeQueue = write.catchError((Object _) {});
    return _writeQueue;
  }

  Future<void> _writeNow(String id, StoryRowMode mode, int seq) async {
    // A queued write never lands on the next account.
    if (!mounted || _store.accountId() != id) return;
    StoryRowServerWrite result;
    try {
      result = await _store.writeServer(id, mode);
    } catch (_) {
      result = StoryRowServerWrite.failed;
    }
    // A later change has its own write queued: it settles the copy.
    if (!mounted || seq != _writes || state.owner != id) return;
    switch (result) {
      case StoryRowServerWrite.saved:
        await _set(state.copyWith(pending: false));
      case StoryRowServerWrite.missingColumn:
        await _set(state.copyWith(pending: false));
        await _store.writeLegacyAccount(state.toAccountJson());
      case StoryRowServerWrite.failed:
        // Stays pending: the next load writes it.
        break;
    }
  }

  Future<void> _set(StoryRowPrefs next) async {
    if (!mounted || next == state) return;
    state = next;
    await _store.writeLocal(next.encodeLocal());
  }
}

/// [local]'s calendar day, as the row's day rule reads it.
String storyDayKey(DateTime local) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}

/// Whether the row will show, as far as the device's copy says: what
/// Today's first frame lays out before the catalog is read, so a row that
/// is Off never shows its skeleton.
bool storyRowExpected(StoryRowPrefs prefs) => prefs.mode != StoryRowMode.off;
