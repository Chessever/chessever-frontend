import 'dart:async';
import 'dart:convert';

import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/stories/story_models.dart' show kStoryCap;
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// When the collection stories row sits at the top of Today (Settings ›
/// Customization › Collection stories).
enum StoryRowMode {
  /// While there is something new to the reader: stories they have not
  /// seen, for up to [kStoryRowIdleDays] days on Today without a story
  /// opened; once they have seen it all, for the rest of that day. The
  /// default.
  whenNew,

  /// Whenever there are collections, the unseen first.
  always,

  /// Never.
  off;

  /// The choice as the picker lists it.
  String get label => switch (this) {
    StoryRowMode.whenNew => "When there's something new",
    StoryRowMode.always => 'Always',
    StoryRowMode.off => 'Off',
  };

  /// The choice as the settings row names it, beside its title.
  String get shortLabel => switch (this) {
    StoryRowMode.whenNew => 'When new',
    StoryRowMode.always => 'Always',
    StoryRowMode.off => 'Off',
  };

  String get _wire => switch (this) {
    StoryRowMode.whenNew => 'new',
    StoryRowMode.always => 'always',
    StoryRowMode.off => 'off',
  };

  static StoryRowMode _parse(Object? wire) => switch (wire) {
    'always' => StoryRowMode.always,
    'off' => StoryRowMode.off,
    _ => StoryRowMode.whenNew,
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

/// How many days the row stands on Today, with nothing new arriving and no
/// story opened, before it steps away until something new comes (When
/// new). Opening a story starts the count again.
const int kStoryRowIdleDays = 3;

/// The row's current stretch on Today (device): what the catalog held when
/// it began ([since], as [storyCatalogSnapshot]), and on how many local
/// days ([days], the last one [day]) the row has stood there since with
/// nothing new and no story opened.
///
/// A reader who never opens a collection still sees the row step away: the
/// stories they pass over every day are not new to them any more.
@immutable
class StoryRowRun {
  const StoryRowRun({
    required this.since,
    required this.days,
    required this.day,
  });

  /// A stretch beginning on [today] with [catalog]: the row stood there
  /// today ([days] 1), or a story was just opened (0).
  factory StoryRowRun.start(
    List<Collection> catalog,
    String today, {
    int days = 1,
  }) => StoryRowRun(
    since: Map.unmodifiable(storyCatalogSnapshot(catalog)),
    days: days,
    day: today,
  );

  final Map<String, int> since;
  final int days;
  final String day;

  /// The stretch is over on [today]: the row stood its days, and a new day
  /// has begun since the last of them.
  bool retiredOn(String today) => days >= kStoryRowIdleDays && day != today;

  /// The row stood on Today on [today] too.
  StoryRowRun countedOn(String today) => day == today
      ? this
      : StoryRowRun(since: since, days: days + 1, day: today);

  Map<String, Object> toJson() => {
    's': _packSnapshot(since),
    'n': days,
    'd': day,
  };

  static StoryRowRun? fromJson(Object? json) {
    if (json is! Map) return null;
    final packed = json['s'];
    final days = json['n'];
    final day = json['d'];
    if (packed is! String || days is! int || day is! String) return null;
    return StoryRowRun(
      since: Map.unmodifiable(_unpackSnapshot(packed)),
      days: days,
      day: day,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StoryRowRun &&
      other.days == days &&
      other.day == day &&
      mapEquals(other.since, since);

  @override
  int get hashCode => Object.hash(days, day, since.length);
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

/// The row's state as the reader set it, and as the device saw it.
@immutable
class StoryRowPrefs {
  const StoryRowPrefs({
    this.mode = StoryRowMode.whenNew,
    this.dismissal,
    this.allSeenDay,
    this.run,
    this.owner,
    this.updatedAt = 0,
  });

  /// The reader's choice (account).
  final StoryRowMode mode;

  /// The row pulled away (account).
  final StoryRowDismissal? dismissal;

  /// The local day ([storyDayKey]) this device first found every story
  /// seen (device). Cleared as soon as something is unseen again.
  final String? allSeenDay;

  /// The row's current stretch on Today (device), When new.
  final StoryRowRun? run;

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
    String? Function()? allSeenDay,
    StoryRowRun? Function()? run,
    String? Function()? owner,
    int? updatedAt,
  }) => StoryRowPrefs(
    mode: mode ?? this.mode,
    dismissal: dismissal == null ? this.dismissal : dismissal(),
    allSeenDay: allSeenDay == null ? this.allSeenDay : allSeenDay(),
    run: run == null ? this.run : run(),
    owner: owner == null ? this.owner : owner(),
    updatedAt: updatedAt ?? this.updatedAt,
  );

  /// What the account keeps: the reader's choice and their pull-away.
  Map<String, Object?> toAccountJson() => {
    'm': mode._wire,
    'd': dismissal?.toAccountJson(),
    'u': updatedAt,
  };

  /// What the device keeps: the account's part and whose it is, the day it
  /// saw all, and the row's current stretch.
  String encodeLocal() => jsonEncode({
    ...toAccountJson(),
    'd': dismissal?.toLocalJson(),
    'a': ?allSeenDay,
    'r': ?run?.toJson(),
    'o': ?owner,
  });

  static StoryRowPrefs decodeLocal(String? raw) {
    if (raw == null || raw.isEmpty) return const StoryRowPrefs();
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return const StoryRowPrefs();
      final day = json['a'];
      final owner = json['o'];
      return fromAccountJson(json).copyWith(
        allSeenDay: () => day is String && day.isNotEmpty ? day : null,
        run: () => StoryRowRun.fromJson(json['r']),
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
      other.allSeenDay == allSeenDay &&
      other.run == run &&
      other.owner == owner &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode =>
      Object.hash(mode, dismissal, allSeenDay, run, owner, updatedAt);
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
    // A new choice starts clean: Always or When new shows the row now, with
    // a new stretch of days.
    await _change(
      state.copyWith(mode: mode, dismissal: () => null, run: () => null),
    );
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

  /// Records what this device saw of the row ([decideStoryRow]): the day
  /// it found every story seen (null: something is unseen), and the row's
  /// current stretch on Today.
  void observe({required String? allSeenDay, required StoryRowRun? run}) {
    if (state.allSeenDay == allSeenDay && state.run == run) return;
    unawaited(
      _set(state.copyWith(allSeenDay: () => allSeenDay, run: () => run)),
    );
  }

  /// The reader opened a story from the row with [catalog] in it: the row
  /// is wanted, and its count of idle days starts again.
  void opened(List<Collection> catalog) {
    if (state.mode != StoryRowMode.whenNew) return;
    final today = storyDayKey(_now());
    unawaited(
      _set(
        state.copyWith(run: () => StoryRowRun.start(catalog, today, days: 0)),
      ),
    );
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

/// How many of [c]'s games count toward something new in its stories: a
/// book's every game (its newest lead its stories), anything else's first
/// [kStoryCap] (later ones are past its stories). A collection holds new
/// stories exactly when this grows (as the seen record counts them).
int storyNewsCount(Collection c) =>
    c.kind == CollectionKind.book || c.gameCount < kStoryCap
    ? c.gameCount
    : kStoryCap;

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
    this.allSeenDay,
    this.run,
    this.adoptSnapshot,
  });

  /// The row is on Today.
  final bool shows;

  /// What arrived while the row was away (it leads the row).
  final Set<String> fresh;

  /// The row comes back after a pull-away or a stretch it stepped away
  /// from, [fresh] first.
  final bool returning;

  /// Something new arrived since the pull-away: forget it.
  final bool clearDismissal;

  /// The day every story was seen, as it should now be recorded (null:
  /// something is unseen).
  final String? allSeenDay;

  /// The row's stretch on Today, as it should now be recorded.
  final StoryRowRun? run;

  /// A pull-away made on another device, still in force: this device's own
  /// snapshot of the catalog to keep for it, from which it tells what is
  /// new from here on ([StoryRowPrefsNotifier.adoptDismissalSnapshot]).
  final Map<String, int>? adoptSnapshot;
}

/// Whether the row shows for [catalog], and what to record:
///
/// * Off: never.
/// * Pulled away: hidden until a collection is new, or one gained games
///   among its stories, since; then back, those first. On a device other
///   than the one it was pulled away on, until the catalog has grown since.
/// * When new: while something is new to the reader. A collection with a
///   story they have not seen is new for [kStoryRowIdleDays] days on Today
///   ([StoryRowRun]); past them, with nothing new arriving and no story
///   opened, the row steps away until something new comes, then returns,
///   that first. Once every story is seen, the row stays for the rest of
///   that local day ([today]).
/// * Always: whenever there are collections.
StoryRowDecision decideStoryRow({
  required StoryRowPrefs prefs,
  required List<Collection> catalog,
  required bool Function(Collection collection) isSeen,
  required String today,
}) {
  final anyUnseen = catalog.any((c) => !isSeen(c));
  final allSeenDay = anyUnseen ? null : (prefs.allSeenDay ?? today);
  final run = prefs.run;
  if (prefs.mode == StoryRowMode.off || catalog.isEmpty) {
    return StoryRowDecision(shows: false, allSeenDay: allSeenDay, run: run);
  }
  final whenNew = prefs.mode == StoryRowMode.whenNew;
  final dismissal = prefs.dismissal;
  if (dismissal != null) {
    final snapshot = dismissal.snapshot;
    final Set<String> fresh;
    if (snapshot != null) {
      fresh = storyFreshSince(snapshot, catalog);
    } else {
      // Put away on another device: the account holds only what the whole
      // catalog came to. The same catalog, or one with no more to it, is
      // nothing new, and becomes this device's own snapshot; one that grew
      // brings the row back (what grew is not known here: unseen first).
      final now = storyCatalogSnapshot(catalog);
      final same = storySnapshotFingerprint(now) == dismissal.fingerprint;
      if (same || storySnapshotGames(now) <= dismissal.games) {
        return StoryRowDecision(
          shows: false,
          allSeenDay: allSeenDay,
          run: run,
          adoptSnapshot: now,
        );
      }
      fresh = const {};
    }
    if (snapshot != null && fresh.isEmpty) {
      return StoryRowDecision(shows: false, allSeenDay: allSeenDay, run: run);
    }
    return StoryRowDecision(
      shows: true,
      fresh: fresh,
      returning: true,
      clearDismissal: true,
      allSeenDay: allSeenDay,
      run: whenNew ? StoryRowRun.start(catalog, today) : run,
    );
  }
  if (!whenNew) {
    return StoryRowDecision(shows: true, allSeenDay: allSeenDay, run: run);
  }
  // Every story seen: the row's last day is the day that happened, and no
  // stretch is counted.
  if (!anyUnseen) {
    return StoryRowDecision(shows: allSeenDay == today, allSeenDay: allSeenDay);
  }
  if (run == null) {
    return StoryRowDecision(
      shows: true,
      run: StoryRowRun.start(catalog, today),
    );
  }
  final fresh = storyFreshSince(run.since, catalog);
  if (run.retiredOn(today)) {
    if (fresh.isEmpty) return StoryRowDecision(shows: false, run: run);
    return StoryRowDecision(
      shows: true,
      fresh: fresh,
      returning: true,
      run: StoryRowRun.start(catalog, today),
    );
  }
  return StoryRowDecision(
    shows: true,
    // Something new arrived while the row stood: its days start again.
    run: fresh.isEmpty
        ? run.countedOn(today)
        : StoryRowRun.start(catalog, today),
  );
}

/// Whether the row will show, as far as the device's copy alone says: what
/// Today's first frame lays out before the catalog is read, so a row that
/// will stay hidden never shows its skeleton.
bool storyRowExpected(StoryRowPrefs prefs, String today) {
  if (prefs.mode == StoryRowMode.off) return false;
  if (prefs.dismissal != null) return false;
  if (prefs.mode == StoryRowMode.whenNew) {
    final day = prefs.allSeenDay;
    if (day != null && day != today) return false;
    if (prefs.run?.retiredOn(today) ?? false) return false;
  }
  return true;
}
