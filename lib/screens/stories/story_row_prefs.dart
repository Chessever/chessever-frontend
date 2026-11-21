import 'dart:async';
import 'dart:convert';

import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
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
}

/// The reader pulled the row away: when, and what the catalog held then,
/// so the row returns once something new comes.
///
/// The account keeps only the catalog's [fingerprint] and its [games] (a
/// few bytes, whatever the catalog's size: the account's metadata rides in
/// every request's token). The [snapshot] of each collection, which says
/// exactly what is new, stays on the device that has it; another device
/// takes its own from the catalog it finds ([decideStoryRow]).
@immutable
class StoryRowDismissal {
  const StoryRowDismissal({
    required this.at,
    required this.fingerprint,
    required this.games,
    this.snapshot,
  });

  /// A pull-away at [at] with [snapshot] ([storyCatalogSnapshot]).
  factory StoryRowDismissal.of(DateTime at, Map<String, int> snapshot) =>
      StoryRowDismissal(
        at: at,
        fingerprint: storySnapshotFingerprint(snapshot),
        games: storySnapshotGames(snapshot),
        snapshot: Map.unmodifiable(snapshot),
      );

  final DateTime at;

  /// [storySnapshotFingerprint] of the catalog when the row was put away.
  final String fingerprint;

  /// [storySnapshotGames] of the catalog then.
  final int games;

  /// What each collection held then, keyed by [storySlugKey] (device only);
  /// null on a device that has not seen the catalog since the pull-away.
  final Map<String, int>? snapshot;

  /// The same pull-away, [snapshot] taken on this device.
  StoryRowDismissal withSnapshot(Map<String, int> snapshot) =>
      StoryRowDismissal(
        at: at,
        fingerprint: fingerprint,
        games: games,
        snapshot: Map.unmodifiable(snapshot),
      );

  /// Whether [other] is this pull-away (made at the same moment, of the
  /// same catalog), whichever copy holds the snapshot.
  bool sameAs(StoryRowDismissal? other) =>
      other != null &&
      other.at == at &&
      other.fingerprint == fingerprint &&
      other.games == games;

  /// What the account keeps.
  Map<String, Object> toAccountJson() => {
    't': at.millisecondsSinceEpoch,
    'f': fingerprint,
    'g': games,
  };

  /// What the device keeps: the account's part and the snapshot.
  Map<String, Object> toLocalJson() => {
    ...toAccountJson(),
    if (snapshot case final snapshot?) 's': _packSnapshot(snapshot),
  };

  static StoryRowDismissal? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = json['t'];
    if (at is! int) return null;
    final packed = json['s'];
    final snapshot = packed is String ? _unpackSnapshot(packed) : null;
    final fingerprint = json['f'];
    final games = json['g'];
    if (fingerprint is String && games is int) {
      return StoryRowDismissal(
        at: DateTime.fromMillisecondsSinceEpoch(at),
        fingerprint: fingerprint,
        games: games,
        snapshot: snapshot == null ? null : Map.unmodifiable(snapshot),
      );
    }
    if (snapshot == null) return null;
    return StoryRowDismissal.of(
      DateTime.fromMillisecondsSinceEpoch(at),
      snapshot,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StoryRowDismissal &&
      sameAs(other) &&
      mapEquals(other.snapshot, snapshot);

  @override
  int get hashCode => Object.hash(at, fingerprint, games);
}

/// [snapshot] packed as `key:count,key:count`.
String _packSnapshot(Map<String, int> snapshot) => [
  for (final MapEntry(:key, :value) in snapshot.entries) '$key:$value',
].join(',');

/// A snapshot packed as `key:count,key:count`.
Map<String, int> _unpackSnapshot(String packed) {
  final snapshot = <String, int>{};
  for (final entry in packed.split(',')) {
    final colon = entry.lastIndexOf(':');
    if (colon <= 0) continue;
    final count = int.tryParse(entry.substring(colon + 1));
    if (count != null) snapshot[entry.substring(0, colon)] = count;
  }
  return snapshot;
}

/// The row's state as the reader set it.
@immutable
class StoryRowPrefs {
  const StoryRowPrefs({
    this.mode = StoryRowMode.on,
    this.dismissal,
    this.owner,
    this.updatedAt = 0,
  });

  /// The reader's choice (account).
  final StoryRowMode mode;

  /// The row pulled away (account).
  final StoryRowDismissal? dismissal;

  /// The account [mode] and [dismissal] belong to (device): the signed-in
  /// reader's id when they were set or last synced, null when set signed
  /// out. Another account signing in on this device never inherits them.
  final String? owner;

  /// When [mode] or [dismissal] last changed, in ms: the newer of the
  /// device's copy and the account's wins.
  final int updatedAt;

  StoryRowPrefs copyWith({
    StoryRowMode? mode,
    StoryRowDismissal? Function()? dismissal,
    String? Function()? owner,
    int? updatedAt,
  }) => StoryRowPrefs(
    mode: mode ?? this.mode,
    dismissal: dismissal == null ? this.dismissal : dismissal(),
    owner: owner == null ? this.owner : owner(),
    updatedAt: updatedAt ?? this.updatedAt,
  );

  /// What the account keeps: the reader's choice and their pull-away.
  Map<String, Object?> toAccountJson() => {
    'm': mode._wire,
    'd': dismissal?.toAccountJson(),
    'u': updatedAt,
  };

  /// What the device keeps: the account's part and whose it is. 39.1.0's
  /// device fields (the day it saw all, the row's stretch of days) are
  /// read past and dropped.
  String encodeLocal() => jsonEncode({
    ...toAccountJson(),
    'd': dismissal?.toLocalJson(),
    'o': ?owner,
  });

  static StoryRowPrefs decodeLocal(String? raw) {
    if (raw == null || raw.isEmpty) return const StoryRowPrefs();
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return const StoryRowPrefs();
      final owner = json['o'];
      return fromAccountJson(json).copyWith(
        owner: () => owner is String && owner.isNotEmpty ? owner : null,
      );
    } catch (_) {
      return const StoryRowPrefs();
    }
  }

  static StoryRowPrefs fromAccountJson(Map<dynamic, dynamic> json) {
    final updated = json['u'];
    return StoryRowPrefs(
      mode: StoryRowMode._parse(json['m']),
      dismissal: StoryRowDismissal.fromJson(json['d']),
      updatedAt: updated is int ? updated : 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StoryRowPrefs &&
      other.mode == mode &&
      other.dismissal == dismissal &&
      other.owner == owner &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(mode, dismissal, owner, updatedAt);
}

/// Where [StoryRowPrefs] live: a device copy read at once (Today's first
/// frame knows whether the row is there), and the account's copy in the
/// signed-in reader's auth `user_metadata`, so the choice and a pull-away
/// follow them to every device.
abstract class StoryRowPrefsStore {
  /// The device's copy, synchronously; null when there is none.
  String? readLocal();
  Future<void> writeLocal(String value);

  /// The account's copy: null when no one is signed in (or the account
  /// cannot be read), empty when the account has none yet.
  Future<Map<String, dynamic>?> readAccount();

  /// The signed-in reader's id; null when no one is.
  String? accountId();
  Future<void> writeAccount(Map<String, Object?> value);

  /// Fires whenever the signed-in account or its session changes (a sign
  /// in, a token refresh carrying another device's change).
  Stream<void> accountChanges();
}

/// The app's store: SharedPreferences on the device (read synchronously,
/// as Settings › Start screen is), and auth `user_metadata` on the account,
/// as My Space's seeded flag and the linked chess accounts are kept.
class AppStoryRowPrefsStore implements StoryRowPrefsStore {
  const AppStoryRowPrefsStore();

  static const String localKey = 'today_story_row_v1';
  static const String accountKey = 'today_stories_v1';

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

  static GoTrueClient? get _auth {
    try {
      return Supabase.instance.client.auth;
    } catch (_) {
      // Not initialised (tests, a failed start): the device copy only.
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>?> readAccount() async {
    final user = _auth?.currentUser;
    if (user == null) return null;
    final value = user.userMetadata?[accountKey];
    return value is Map ? Map<String, dynamic>.from(value) : const {};
  }

  @override
  String? accountId() => _auth?.currentUser?.id;

  @override
  Future<void> writeAccount(Map<String, Object?> value) async {
    final auth = _auth;
    if (auth?.currentUser == null) return;
    try {
      await auth!
          .updateUser(UserAttributes(data: {accountKey: value}))
          .timeout(const Duration(seconds: 6));
    } catch (e) {
      // The device copy stands; the next change, or the next session,
      // carries it to the account.
      debugPrint('[Stories] row choice not saved on the account: $e');
    }
  }

  @override
  Stream<void> accountChanges() =>
      _auth?.onAuthStateChange.map((_) {}) ?? const Stream.empty();
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
    : super(StoryRowPrefs.decodeLocal(_store.readLocal())) {
    _accountSub = _store.accountChanges().listen((_) => unawaited(pull()));
    unawaited(pull());
  }

  final StoryRowPrefsStore _store;
  final DateTime Function() _now;
  StreamSubscription<void>? _accountSub;

  @override
  void dispose() {
    _accountSub?.cancel();
    super.dispose();
  }

  /// Brings the device's copy and the account's in step: the newer one
  /// wins, and a choice made signed out reaches the account on sign in. A
  /// copy that belongs to another account ([StoryRowPrefs.owner]) is never
  /// carried over: the account signing in keeps its own choice (or the
  /// default).
  Future<void> pull() async {
    final Map<String, dynamic>? account;
    final String? id;
    try {
      account = await _store.readAccount();
      id = _store.accountId();
    } catch (_) {
      return;
    }
    if (!mounted || account == null) return;
    final remote = StoryRowPrefs.fromAccountJson(account);
    // The account's pull-away carries no snapshot: this device keeps its
    // own of the same pull-away.
    final local = state.dismissal;
    final remoteDismissal = remote.dismissal;
    StoryRowPrefs adopt() => state.copyWith(
      mode: remote.mode,
      dismissal: () =>
          remoteDismissal != null &&
              remoteDismissal.sameAs(local) &&
              local?.snapshot != null
          ? remoteDismissal.withSnapshot(local!.snapshot!)
          : remoteDismissal,
      updatedAt: remote.updatedAt,
      owner: () => id,
    );
    final owner = state.owner;
    if (owner != null && owner != id) {
      await _set(adopt());
    } else if (remote.updatedAt > state.updatedAt) {
      await _set(adopt());
    } else {
      if (owner != id) await _set(state.copyWith(owner: () => id));
      if (state.updatedAt > remote.updatedAt) {
        unawaited(_store.writeAccount(state.toAccountJson()));
      }
    }
  }

  /// The reader's choice in Settings.
  Future<void> setMode(StoryRowMode mode) async {
    if (mode == state.mode) return;
    // A new choice starts clean: On shows the row now.
    await _change(state.copyWith(mode: mode, dismissal: () => null));
  }

  /// The reader pulled the row away with [catalog] in it. Returns what was
  /// there before, for Undo.
  StoryRowDismissal? dismiss(List<Collection> catalog) {
    final before = state.dismissal;
    unawaited(
      _change(
        state.copyWith(
          dismissal: () =>
              StoryRowDismissal.of(_now(), storyCatalogSnapshot(catalog)),
        ),
      ),
    );
    return before;
  }

  /// Undo of [dismiss]: the pull-away as it was before.
  Future<void> restore(StoryRowDismissal? before) =>
      _change(state.copyWith(dismissal: () => before));

  /// This device's own snapshot of a pull-away made on another device
  /// ([decideStoryRow]): kept here only, the account's copy unchanged.
  void adoptDismissalSnapshot(
    StoryRowDismissal dismissal,
    Map<String, int> snapshot,
  ) {
    final current = state.dismissal;
    if (current == null ||
        !current.sameAs(dismissal) ||
        current.snapshot != null) {
      return;
    }
    unawaited(
      _set(state.copyWith(dismissal: () => current.withSnapshot(snapshot))),
    );
  }

  /// Something new arrived since the pull-away: the row is back.
  Future<void> clearDismissal() async {
    if (state.dismissal == null) return;
    await _change(state.copyWith(dismissal: () => null));
  }

  Future<void> _change(StoryRowPrefs next) async {
    // Always later than the copy it replaces, even on a clock that stepped
    // back: the newer copy is the one that wins everywhere. Stamped with
    // the account it was made under.
    final now = _now().millisecondsSinceEpoch;
    final stamped = next.copyWith(
      updatedAt: now > state.updatedAt ? now : state.updatedAt + 1,
      owner: () => _store.accountId(),
    );
    await _set(stamped);
    unawaited(_store.writeAccount(stamped.toAccountJson()));
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

/// A short key for [slug] in a pull-away's snapshot (FNV-1a, base 36), so
/// the account's copy stays small whatever the catalog's size.
String storySlugKey(String slug) {
  var hash = 0x811c9dc5;
  for (final unit in utf8.encode(slug)) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(36);
}

/// How many of [c]'s games count toward something new: every one, since a
/// collection's latest game always leads its stories. A collection holds
/// something new for a pull-away exactly when this grows.
int storyNewsCount(Collection c) => c.gameCount;

/// [storyNewsCount] per collection of [catalog], keyed by [storySlugKey].
Map<String, int> storyCatalogSnapshot(List<Collection> catalog) => {
  for (final c in catalog) storySlugKey(c.slug): storyNewsCount(c),
};

/// One short key for the whole of [snapshot] (FNV-1a over its entries in
/// key order, base 36): equal snapshots, equal keys.
String storySnapshotFingerprint(Map<String, int> snapshot) {
  final keys = snapshot.keys.toList()..sort();
  return storySlugKey([for (final k in keys) '$k:${snapshot[k]}'].join(','));
}

/// The games [snapshot] counts in all: it grows when something new comes.
int storySnapshotGames(Map<String, int> snapshot) =>
    snapshot.values.fold(0, (sum, count) => sum + count);

/// The collections of [catalog] that are new since [snapshot], or hold new
/// games among their stories, by slug.
Set<String> storyFreshSince(
  Map<String, int> snapshot,
  List<Collection> catalog,
) {
  final fresh = <String>{};
  for (final c in catalog) {
    final before = snapshot[storySlugKey(c.slug)];
    if (before == null || storyNewsCount(c) > before) fresh.add(c.slug);
  }
  return fresh;
}

/// What the row does with the catalog as it is now.
@immutable
class StoryRowDecision {
  const StoryRowDecision({
    required this.shows,
    this.fresh = const {},
    this.returning = false,
    this.clearDismissal = false,
    this.adoptSnapshot,
  });

  /// The row is on Today.
  final bool shows;

  /// What arrived while the row was away (it leads the row).
  final Set<String> fresh;

  /// The row comes back after a pull-away, [fresh] first.
  final bool returning;

  /// Something new arrived since the pull-away: forget it.
  final bool clearDismissal;

  /// A pull-away made on another device, still in force: this device's own
  /// snapshot of the catalog to keep for it, from which it tells what is
  /// new from here on ([StoryRowPrefsNotifier.adoptDismissalSnapshot]).
  final Map<String, int>? adoptSnapshot;
}

/// Whether the row shows for [catalog], and what to record:
///
/// * Off: never.
/// * Pulled away: hidden until a collection is new, or one gained games,
///   since; then back, those first. On a device other than the one it was
///   pulled away on, until the catalog has grown since.
/// * On: always, while there are collections. Everything seen never takes
///   the row away: its circles go quiet, and a circle with something new
///   leads it.
StoryRowDecision decideStoryRow({
  required StoryRowPrefs prefs,
  required List<Collection> catalog,
}) {
  if (prefs.mode == StoryRowMode.off || catalog.isEmpty) {
    return const StoryRowDecision(shows: false);
  }
  final dismissal = prefs.dismissal;
  if (dismissal == null) return const StoryRowDecision(shows: true);
  final snapshot = dismissal.snapshot;
  final Set<String> fresh;
  if (snapshot != null) {
    fresh = storyFreshSince(snapshot, catalog);
    if (fresh.isEmpty) return const StoryRowDecision(shows: false);
  } else {
    // Put away on another device: the account holds only what the whole
    // catalog came to. The same catalog, or one with no more to it, is
    // nothing new, and becomes this device's own snapshot; one that grew
    // brings the row back (what grew is not known here: unseen first).
    final now = storyCatalogSnapshot(catalog);
    final same = storySnapshotFingerprint(now) == dismissal.fingerprint;
    if (same || storySnapshotGames(now) <= dismissal.games) {
      return StoryRowDecision(shows: false, adoptSnapshot: now);
    }
    fresh = const {};
  }
  return StoryRowDecision(
    shows: true,
    fresh: fresh,
    returning: true,
    clearDismissal: true,
  );
}

/// Whether the row will show, as far as the device's copy alone says: what
/// Today's first frame lays out before the catalog is read, so a row that
/// will stay hidden never shows its skeleton.
bool storyRowExpected(StoryRowPrefs prefs) =>
    prefs.mode != StoryRowMode.off && prefs.dismissal == null;
