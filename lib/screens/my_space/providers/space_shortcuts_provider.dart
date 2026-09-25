import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:chessever2/config/feature_flags.dart';
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/screens/my_space/defaults/space_defaults.dart';
import 'package:chessever2/screens/my_space/defaults/space_seed_gate.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The user's My Space shortcuts, newest first within each section.
///
/// Source of truth is `public.user_space_shortcuts` (one row per user, kind
/// and target). The list is cached in SQLite so My Space paints instantly on
/// launch, and a Realtime channel keeps every signed-in device in step.
/// Guests keep a device-local list under the empty user id; nothing is lost
/// if the table is not reachable, the notifier simply stays local.
final spaceShortcutsProvider =
    AsyncNotifierProvider<SpaceShortcutsNotifier, List<SpaceShortcut>>(
      SpaceShortcutsNotifier.new,
    );

/// Whether a target is already in My Space. Drives the long-press menu label
/// ("Add to My Space" vs "Remove from My Space").
///
/// Auto-disposed: callers watch a fresh key per search row or per Smart Event
/// filter combination, and a keep-alive family would hold every one of them
/// for the session, each re-scanning the list on every add or remove.
final spaceShortcutExistsProvider = Provider.autoDispose.family<bool, String>((
  ref,
  key,
) {
  final list = ref.watch(spaceShortcutsProvider).valueOrNull ?? const [];
  return list.any((s) => s.key == key);
});

/// Shortcuts grouped by section, in display order.
final spaceShortcutsBySectionProvider =
    Provider<Map<SpaceSection, List<SpaceShortcut>>>((ref) {
      final list = ref.watch(spaceShortcutsProvider).valueOrNull ?? const [];
      final out = <SpaceSection, List<SpaceShortcut>>{};
      for (final s in list) {
        (out[s.section] ??= <SpaceShortcut>[]).add(s);
      }
      return out;
    });

class SpaceShortcutsNotifier extends AsyncNotifier<List<SpaceShortcut>> {
  static const _table = 'user_space_shortcuts';
  static const _cacheKey = 'my_space_shortcuts_v1';

  SupabaseClient get _db => Supabase.instance.client;

  String? _userId;
  RealtimeChannel? _channel;
  Timer? _refetchDebounce;

  /// Set once the table answers "does not exist" so we stop hammering it and
  /// keep working from the local list until the next launch.
  bool _remoteUnavailable = false;

  /// Keys whose upsert is on the wire right now (an [add], an Undo or a
  /// retry), so a retry never races the first attempt for the same row.
  final Set<String> _syncing = {};

  /// Times the server refused a retried row this session. A row it keeps
  /// refusing (as opposed to a dropped connection) is left alone after
  /// [_maxSyncRejections] tries and tried again on the next launch.
  final Map<String, int> _syncRejections = {};
  static const _maxSyncRejections = 3;

  /// The user whose unsynced pins are being pushed, while a pass runs.
  String? _syncPassFor;

  /// Seeding runs one pass at a time; [_seedSettledFor] is the account (or
  /// '' for a guest) whose defaults are settled for this session.
  bool _seedRunning = false;
  String? _seedSettledFor;

  /// The retired default openings are taken back one pass at a time.
  /// [_trimSettledFor] is the account (or '' for a guest) whose trim is done
  /// for this session; [_trimAttemptedFor] the one whose rows were already
  /// removed once this session, so a delete the server did not take waits
  /// for the next launch instead of looping.
  bool _trimRunning = false;
  String? _trimSettledFor;
  String? _trimAttemptedFor;

  @override
  Future<List<SpaceShortcut>> build() async {
    // Only the id: a write to the account's metadata (the seed flag) must
    // never rebuild the store.
    _userId = ref.watch(currentUserProvider.select((u) => u?.id));
    ref.onDispose(_teardown);

    final uid = _userId;
    final cached = await _readCache();
    if (uid != null) {
      unawaited(_refresh());
      _subscribe();
    } else {
      // A guest's defaults live on this device alone.
      unawaited(
        Future<void>(() async {
          await _maybeSeed(null);
          await _maybeTrimDefaults(null);
        }),
      );
    }
    return cached;
  }

  // ---------------------------------------------------------------- reads

  /// Replaces the list with the server's. True once the server has answered,
  /// which is also the moment an account can safely be given its defaults.
  Future<bool> _refresh() async {
    final uid = _userId;
    if (uid == null || _remoteUnavailable) return false;
    try {
      final rows = await _db
          .from(_table)
          .select()
          .eq('user_id', uid)
          .order('sort_index', ascending: false)
          .order('created_at', ascending: false);
      final list = <SpaceShortcut>[];
      for (final row in rows as List) {
        final s = SpaceShortcut.fromJson(Map<String, dynamic>.from(row as Map));
        if (s != null) list.add(s);
      }
      if (_userId != uid) return false;
      final merged = _mergePendingLocals(_reconcile(list));
      state = AsyncData(merged);
      unawaited(_writeCache(merged));
      // Any `local:` row left after the merge is one the server lacks.
      unawaited(_syncUnsyncedLocals(uid));
      unawaited(
        _maybeSeed(
          uid,
          serverKnown: true,
        ).whenComplete(() => _maybeTrimDefaults(uid, serverKnown: true)),
      );
      return true;
    } on PostgrestException catch (e) {
      if (_isMissingTable(e)) {
        _remoteUnavailable = true;
        debugPrint('[MySpace] table missing, staying local: ${e.message}');
        // No server to agree with: the defaults stay on this device.
        unawaited(_maybeSeed(uid).whenComplete(() => _maybeTrimDefaults(uid)));
      } else {
        debugPrint('[MySpace] refresh failed: ${e.message}');
      }
    } catch (e) {
      debugPrint('[MySpace] refresh failed: $e');
    }
    return false;
  }

  /// Server rows with this device's in-flight sort writes laid over them, and
  /// the existing instance kept wherever nothing changed, so a refetch does not
  /// rebuild tiles whose shortcut is the same.
  List<SpaceShortcut> _reconcile(List<SpaceShortcut> remote) {
    final current = {
      for (final s in state.valueOrNull ?? const <SpaceShortcut>[]) s.key: s,
    };
    return [
      for (final fetched in remote)
        () {
          final pending = _pendingSortFor(fetched.key);
          final row =
              pending == null || (fetched.sortIndex - pending).abs() < 1e-9
              ? fetched
              : fetched.copyWith(sortIndex: pending);
          final local = current[row.key];
          return local != null &&
                  local.id == row.id &&
                  spaceShortcutsMatch(local, row)
              ? local
              : row;
        }(),
    ];
  }

  /// Local drafts that the server has not echoed back yet survive a refresh.
  List<SpaceShortcut> _mergePendingLocals(List<SpaceShortcut> remote) {
    final current = state.valueOrNull ?? const <SpaceShortcut>[];
    final remoteKeys = remote.map((s) => s.key).toSet();
    final pending = current.where(
      (s) => s.isLocal && !remoteKeys.contains(s.key),
    );
    return _sorted([...pending, ...remote]);
  }

  void _subscribe() {
    final uid = _userId;
    if (uid == null || _channel != null) return;
    try {
      _channel = _db
          .channel('space-shortcuts:$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: _table,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: uid,
            ),
            callback: _onRealtime,
          )
          .subscribe((status, _) {
            // The channel rejoins once the connection is back; that is
            // the moment to push pins added while it was down.
            if (status != RealtimeSubscribeStatus.subscribed) return;
            try {
              _retryUnsyncedSoon();
            } catch (e) {
              debugPrint('[MySpace] rejoin retry skipped: $e');
            }
          });
    } catch (e) {
      debugPrint('[MySpace] realtime subscribe failed: $e');
    }
  }

  /// Every write this device makes comes straight back over the channel. An
  /// echo that only repeats what the list already shows is dropped: a full
  /// refetch would rebuild every tile's board and avatar for nothing, and an
  /// older echo racing a newer write would snap a moved tile back.
  void _onRealtime(PostgresChangePayload payload) {
    try {
      if (_isOwnEcho(payload)) return;
    } catch (e) {
      debugPrint('[MySpace] realtime payload unreadable: $e');
    }
    _scheduleRefetch();
  }

  bool _isOwnEcho(PostgresChangePayload payload) {
    final current = state.valueOrNull ?? const <SpaceShortcut>[];
    if (payload.eventType == PostgresChangeEvent.delete) {
      final old = SpaceShortcut.fromJson(payload.oldRecord);
      // Our own delete: the target is already gone here.
      return old != null && !current.any((s) => s.key == old.key);
    }
    final row = SpaceShortcut.fromJson(payload.newRecord);
    if (row == null) return false;
    final local = current.where((s) => s.key == row.key).firstOrNull;
    if (local == null) return false;
    final pending = _pendingSortFor(row.key);
    if (pending != null) {
      if ((row.sortIndex - pending).abs() < 1e-9) _pendingSort.remove(row.key);
      // A newer sort write is still in flight: this echo carries an older
      // value and must not undo it.
      return spaceShortcutsMatch(local, row.copyWith(sortIndex: pending));
    }
    return spaceShortcutsMatch(local, row);
  }

  void _scheduleRefetch() {
    _refetchDebounce?.cancel();
    _refetchDebounce = Timer(const Duration(milliseconds: 400), _refresh);
  }

  void _teardown() {
    _refetchDebounce?.cancel();
    final ch = _channel;
    _channel = null;
    if (ch != null) unawaited(_db.removeChannel(ch));
  }

  // ---------------------------------------------------------------- seed

  /// Gives a new My Space its defaults (the elite openings, GM and Classical
  /// Smart Events) once per account, or once per device for a guest. They
  /// arrive as ordinary shortcuts, after anything already pinned, so remove,
  /// reorder and Undo work on them like on any pin. Never removes anything.
  Future<void> _maybeSeed(String? uid, {bool serverKnown = false}) async {
    if (!FeatureFlags.mySpaceDefaults) return;
    if (_seedRunning || _seedSettledFor == (uid ?? '')) return;
    _seedRunning = true;
    try {
      try {
        await future;
      } catch (_) {
        return;
      }
      if (_userId != uid) return;
      final gate = ref.read(spaceSeedGateProvider);
      final local = gate.readLocal(uid);
      final signedIn = uid != null && !_remoteUnavailable;
      var remoteFlag = false;
      if (signedIn && local != SpaceSeedMark.synced) {
        remoteFlag = await gate.readRemote();
        if (_userId != uid) return;
      }
      final current = state.valueOrNull ?? const <SpaceShortcut>[];
      final step = planSpaceSeed(
        signedIn: signedIn,
        local: local,
        serverKnown: serverKnown,
        remoteFlag: remoteFlag,
        serverHasSeededRows: current.any((s) => !s.isLocal && isSpaceSeeded(s)),
      );
      switch (step) {
        case SpaceSeedStep.skip:
          // Settled for good, or waiting for the server to answer first.
          if (local == SpaceSeedMark.synced || !signedIn) {
            _seedSettledFor = uid ?? '';
          }
        case SpaceSeedStep.markOnly:
          final flagged = remoteFlag || await gate.writeRemote();
          if (flagged && _userId == uid) {
            await gate.writeLocal(uid, SpaceSeedMark.synced);
            _seedSettledFor = uid ?? '';
          }
        case SpaceSeedStep.seed:
          await _seed(uid, gate, signedIn: signedIn);
      }
    } catch (e) {
      debugPrint('[MySpace] seeding skipped: $e');
    } finally {
      _seedRunning = false;
    }
  }

  Future<void> _seed(
    String? uid,
    SpaceSeedGate gate, {
    required bool signedIn,
  }) async {
    final current = state.valueOrNull ?? const <SpaceShortcut>[];
    final plan = planSeed(current, spaceSeedDrafts());
    if (plan.isNotEmpty) {
      final next = _sorted([...current, ...plan]);
      state = AsyncData(next);
      unawaited(_writeCache(next));
    }
    await gate.writeLocal(uid, SpaceSeedMark.seeded);
    if (!signedIn || uid == null) {
      _seedSettledFor = uid ?? '';
      return;
    }
    if (plan.isNotEmpty && !await _pushSeed(uid, plan)) return;
    if (_userId != uid) return;
    if (await gate.writeRemote()) {
      await gate.writeLocal(uid, SpaceSeedMark.synced);
      _seedSettledFor = uid;
    }
  }

  /// Takes back, once per account (or per device for a guest), the retired
  /// default openings older builds seeded and the user never touched (see
  /// [planSpaceDefaultTrim]). Each goes through [remove], the same path a
  /// swipe takes, so the server row is deleted by its natural key. An account
  /// decides only from the server's rows, never a cached list; its flag is
  /// written by the refresh that confirms nothing is left to take.
  Future<void> _maybeTrimDefaults(
    String? uid, {
    bool serverKnown = false,
  }) async {
    final who = uid ?? '';
    if (_trimRunning || _trimSettledFor == who) return;
    final signedIn = uid != null && !_remoteUnavailable;
    if (signedIn && !serverKnown) return;
    _trimRunning = true;
    try {
      try {
        await future;
      } catch (_) {
        return;
      }
      if (_userId != uid) return;
      final gate = ref.read(spaceSeedGateProvider);
      if (gate.readTrimmed(uid)) {
        _trimSettledFor = who;
        return;
      }
      final plan = planSpaceDefaultTrim(
        state.valueOrNull ?? const <SpaceShortcut>[],
      );
      if (plan.isEmpty) {
        await gate.writeTrimmed(uid);
        _trimSettledFor = who;
        return;
      }
      if (_trimAttemptedFor == who) return;
      _trimAttemptedFor = who;
      for (final s in plan) {
        if (_userId != uid) return;
        await remove(s.id);
      }
      if (_userId != uid) return;
      if (uid == null || _remoteUnavailable) {
        await gate.writeTrimmed(uid);
        _trimSettledFor = who;
      } else {
        _scheduleRefetch();
      }
    } catch (e) {
      debugPrint('[MySpace] default trim skipped: $e');
    } finally {
      _trimRunning = false;
    }
  }

  /// One insert for every seeded row. A row the account already holds is left
  /// exactly as it is. On failure the rows stay local and the unsynced pass
  /// pushes them with the next refresh.
  Future<bool> _pushSeed(String uid, List<SpaceShortcut> rows) async {
    final keys = [for (final s in rows) s.key];
    _syncing.addAll(keys);
    try {
      final saved = await _db
          .from(_table)
          .upsert(
            [
              for (final s in rows) {...s.toInsert(), 'user_id': uid},
            ],
            onConflict: 'user_id,kind,target_id',
            ignoreDuplicates: true,
          )
          .select();
      for (final row in saved as List) {
        final s = SpaceShortcut.fromJson(Map<String, dynamic>.from(row as Map));
        if (s != null) _adoptSaved(uid, s);
      }
      return true;
    } on PostgrestException catch (e) {
      if (_isMissingTable(e)) _remoteUnavailable = true;
      debugPrint('[MySpace] seed write failed: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('[MySpace] seed write failed: $e');
      return false;
    } finally {
      _syncing.removeAll(keys);
      _retryUnsyncedSoon();
    }
  }

  /// The defaults still missing from [current], placed after everything
  /// already there (sort values below the lowest) and in their own order,
  /// each with its own local id. Pins made later take max + 1 and so land in
  /// front of them.
  @visibleForTesting
  static List<SpaceShortcut> planSeed(
    List<SpaceShortcut> current,
    List<SpaceShortcut> defaults,
  ) {
    final have = {for (final s in current) s.key};
    final floor = math.min(
      0.0,
      current.isEmpty ? 0.0 : current.map((s) => s.sortIndex).reduce(math.min),
    );
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final out = <SpaceShortcut>[];
    for (final d in defaults) {
      if (!have.add(d.key)) continue;
      final i = out.length;
      out.add(d.copyWith(id: 'local:seed:$i:$stamp', sortIndex: floor - 1 - i));
    }
    return out;
  }

  // ---------------------------------------------------------------- writes

  bool contains(SpaceShortcutKind kind, String targetId) {
    final key = SpaceShortcut.keyFor(kind, targetId);
    return (state.valueOrNull ?? const []).any((s) => s.key == key);
  }

  /// Adds [draft] to the front of its section. Returns false when the target
  /// is already in My Space (the caller shows "Already in My Space").
  Future<bool> add(SpaceShortcut draft) async {
    final current = state.valueOrNull ?? const <SpaceShortcut>[];
    if (current.any((s) => s.key == draft.key)) return false;

    final top = current.isEmpty
        ? 0.0
        : current.map((s) => s.sortIndex).reduce((a, b) => a > b ? a : b);
    final item = draft.copyWith(sortIndex: top + 1);
    final next = _sorted([item, ...current]);
    state = AsyncData(next);
    unawaited(_writeCache(next));

    final uid = _userId;
    if (uid == null || _remoteUnavailable) return true;
    // A failed upsert leaves the pin in place under its `local:` id; the next
    // refresh, channel rejoin or successful write pushes it again.
    _syncing.add(item.key);
    try {
      final row = await _db
          .from(_table)
          .upsert({
            ...item.toInsert(),
            'user_id': uid,
          }, onConflict: 'user_id,kind,target_id')
          .select()
          .single();
      final saved = SpaceShortcut.fromJson(Map<String, dynamic>.from(row));
      if (saved != null) _adoptSaved(uid, saved);
      _retryUnsyncedSoon();
    } on PostgrestException catch (e) {
      if (_isMissingTable(e)) {
        _remoteUnavailable = true;
      } else {
        debugPrint('[MySpace] add failed: ${e.message}');
      }
    } catch (e) {
      debugPrint('[MySpace] add failed: $e');
    } finally {
      _syncing.remove(item.key);
    }
    return true;
  }

  /// Removes a shortcut and returns it so the caller can offer Undo.
  Future<SpaceShortcut?> remove(String id) async {
    final current = state.valueOrNull ?? const <SpaceShortcut>[];
    final idx = current.indexWhere((s) => s.id == id);
    if (idx < 0) return null;
    final removed = current[idx];
    final next = [...current]..removeAt(idx);
    state = AsyncData(next);
    unawaited(_writeCache(next));

    final uid = _userId;
    if (uid != null && !_remoteUnavailable) {
      await _deleteRemote(uid, removed);
    }
    return removed;
  }

  /// Removes the shortcut for a target (used by "Remove from My Space" on the
  /// long-press menus, which only know the target).
  Future<SpaceShortcut?> removeTarget(SpaceShortcutKind kind, String targetId) {
    final key = SpaceShortcut.keyFor(kind, targetId);
    final match = (state.valueOrNull ?? const <SpaceShortcut>[]).where(
      (s) => s.key == key,
    );
    if (match.isEmpty) return Future.value(null);
    return remove(match.first.id);
  }

  /// Puts a removed shortcut back exactly where it was (snack Undo). A seeded
  /// default comes back marked kept ([spaceRestoredShortcut]): putting it
  /// back is a choice, so the one-time trim of retired defaults leaves it.
  Future<void> restore(SpaceShortcut item) async {
    final current = state.valueOrNull ?? const <SpaceShortcut>[];
    if (current.any((s) => s.key == item.key)) return;
    final back = spaceRestoredShortcut(item);
    final next = _sorted([back, ...current]);
    state = AsyncData(next);
    unawaited(_writeCache(next));
    final uid = _userId;
    if (uid == null || _remoteUnavailable) return;
    _syncing.add(back.key);
    var stored = false;
    try {
      await _db.from(_table).upsert({
        ...back.toInsert(),
        'user_id': uid,
      }, onConflict: 'user_id,kind,target_id');
      stored = true;
    } catch (e) {
      debugPrint('[MySpace] restore failed: $e');
    } finally {
      _syncing.remove(back.key);
    }
    if (stored) _retryUnsyncedSoon();
  }

  /// Moves a shortcut to the front of its row.
  Future<void> moveToFront(String id) async {
    final current = state.valueOrNull ?? const <SpaceShortcut>[];
    final idx = current.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    final top = current.map((s) => s.sortIndex).reduce((a, b) => a > b ? a : b);
    final moved = current[idx].copyWith(sortIndex: top + 1);
    final next = _sorted([...current]..[idx] = moved);
    state = AsyncData(next);
    unawaited(_writeCache(next));
    await _writeSort([moved]);
  }

  /// Moves the shortcut with [key] to [toIndex] within its own row (a drag
  /// in a rail or the "See all" grid, or a Move left / right action).
  ///
  /// The list updates at once; one row is written, by its natural key, with a
  /// sort value halfway between its new neighbours. Only when those two
  /// already share a value is the row renumbered, in a single upsert.
  Future<void> moveWithinSection(String key, int toIndex) async {
    final plan = planSectionMove(
      state.valueOrNull ?? const <SpaceShortcut>[],
      key,
      toIndex,
    );
    if (plan == null) return;
    state = AsyncData(plan.list);
    unawaited(_writeCache(plan.list));
    await _writeSort(plan.changed);
  }

  /// The list after moving [key] to [toIndex] inside its section, and the
  /// rows whose sort value changed. Null when nothing moves.
  ///
  /// Sort values run high to low along a row. A move to the front takes the
  /// global top + 1 (like [add] and [moveToFront]); to the end, the last value
  /// - 1; anywhere else, the midpoint of its new neighbours. Neighbours that
  /// collide (the column defaults to 0) renumber the section.
  @visibleForTesting
  static ({List<SpaceShortcut> list, List<SpaceShortcut> changed})?
  planSectionMove(List<SpaceShortcut> list, String key, int toIndex) {
    final item = list.where((s) => s.key == key).firstOrNull;
    if (item == null) return null;
    final row = [
      for (final s in list)
        if (s.section == item.section) s,
    ];
    final from = row.indexWhere((s) => s.key == key);
    if (row.length < 2) return null;
    final to = toIndex.clamp(0, row.length - 1);
    if (from == to) return null;

    row.removeAt(from);
    final prev = to > 0 ? row[to - 1] : null;
    final next = to < row.length ? row[to] : null;

    double? value;
    if (prev == null) {
      value = list.map((s) => s.sortIndex).reduce(math.max) + 1;
    } else if (next == null) {
      value = prev.sortIndex - 1;
    } else {
      final mid = (prev.sortIndex + next.sortIndex) / 2;
      final roomy = prev.sortIndex - next.sortIndex > 1e-6;
      if (roomy && mid < prev.sortIndex && mid > next.sortIndex) value = mid;
    }

    final changed = <SpaceShortcut>[];
    final byKey = <String, SpaceShortcut>{};
    if (value != null) {
      final moved = item.copyWith(sortIndex: value);
      changed.add(moved);
      byKey[key] = moved;
    } else {
      row.insert(to, item);
      final top =
          row.map((s) => s.sortIndex).reduce(math.max).floorToDouble() +
          row.length;
      for (var i = 0; i < row.length; i++) {
        final v = top - i;
        if (row[i].sortIndex == v) continue;
        final updated = row[i].copyWith(sortIndex: v);
        changed.add(updated);
        byKey[updated.key] = updated;
      }
    }
    return (
      list: _sorted([for (final s in list) byKey[s.key] ?? s]),
      changed: changed,
    );
  }

  /// Merges [values] into the params of the pin with [key], here and on the
  /// server: a game pin keeps the card its game was looked up as, so it is
  /// drawn from the pin next time instead of looked up again.
  Future<void> mergeParams(String key, Map<String, dynamic> values) async {
    final current = state.valueOrNull ?? const <SpaceShortcut>[];
    final idx = current.indexWhere((s) => s.key == key);
    if (idx < 0) return;
    final params = {...current[idx].params, ...values};
    if (const DeepCollectionEquality().equals(params, current[idx].params)) {
      return;
    }
    final updated = current[idx].copyWith(params: params);
    final next = [...current]..[idx] = updated;
    state = AsyncData(next);
    unawaited(_writeCache(next));
    await _patch(updated, {'params': params});
  }

  /// Records an open so "recently used" ordering and analytics stay honest.
  Future<void> markOpened(String id) async {
    final current = state.valueOrNull ?? const <SpaceShortcut>[];
    final idx = current.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    final now = DateTime.now();
    final updated = current[idx].copyWith(
      lastOpenedAt: now,
      openCount: current[idx].openCount + 1,
    );
    final next = [...current]..[idx] = updated;
    state = AsyncData(next);
    unawaited(_writeCache(next));
    await _patch(updated, {
      'last_opened_at': now.toUtc().toIso8601String(),
      'open_count': updated.openCount,
    });
  }

  /// Writes by the row's natural key, never its id: a row put back by Undo
  /// gets a new uuid on the server while this list keeps the old one.
  Future<void> _patch(SpaceShortcut s, Map<String, dynamic> values) async {
    final uid = _userId;
    if (uid == null || _remoteUnavailable || s.isLocal) return;
    try {
      await _db
          .from(_table)
          .update({
            ...values,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('user_id', uid)
          .eq('kind', s.kind.name)
          .eq('target_id', s.targetId);
    } catch (e) {
      debugPrint('[MySpace] update failed: $e');
    }
  }

  /// Sort values this device wrote and has not yet seen come back. While one
  /// is pending, an echo or a refetch still carrying the old value keeps the
  /// new one, and an add that lands after a move keeps the move.
  final Map<String, ({double value, DateTime at})> _pendingSort = {};

  static const _pendingSortTtl = Duration(seconds: 10);

  double? _pendingSortFor(String key) {
    final entry = _pendingSort[key];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.at) > _pendingSortTtl) {
      _pendingSort.remove(key);
      return null;
    }
    return entry.value;
  }

  /// Persists new sort values: one row as a single update, several (a
  /// renumbered section) as one upsert. Guests and an unreachable table keep
  /// the local list only.
  Future<void> _writeSort(List<SpaceShortcut> rows) async {
    if (rows.isEmpty) return;
    final now = DateTime.now();
    for (final s in rows) {
      _pendingSort[s.key] = (value: s.sortIndex, at: now);
    }
    final uid = _userId;
    if (uid == null || _remoteUnavailable) return;
    final stamp = now.toUtc().toIso8601String();
    try {
      if (rows.length == 1) {
        final s = rows.single;
        await _db
            .from(_table)
            .update({'sort_index': s.sortIndex, 'updated_at': stamp})
            .eq('user_id', uid)
            .eq('kind', s.kind.name)
            .eq('target_id', s.targetId);
      } else {
        await _db.from(_table).upsert([
          for (final s in rows)
            {...s.toInsert(), 'user_id': uid, 'updated_at': stamp},
        ], onConflict: 'user_id,kind,target_id');
      }
    } on PostgrestException catch (e) {
      if (_isMissingTable(e)) {
        _remoteUnavailable = true;
      } else {
        debugPrint('[MySpace] reorder failed: ${e.message}');
      }
    } catch (e) {
      debugPrint('[MySpace] reorder failed: $e');
    }
  }

  void _replaceByKey(SpaceShortcut saved) {
    // A move made while the add was still in flight wins over the value the
    // insert came back with.
    final pending = _pendingSortFor(saved.key);
    var row = saved;
    if (pending != null && (saved.sortIndex - pending).abs() > 1e-9) {
      row = saved.copyWith(sortIndex: pending);
      unawaited(_writeSort([row]));
    }
    final current = state.valueOrNull ?? const <SpaceShortcut>[];
    final next = _sorted([for (final s in current) s.key == row.key ? row : s]);
    state = AsyncData(next);
    unawaited(_writeCache(next));
  }

  /// Takes the row the server stored for a pin this device wrote. If the pin
  /// was removed while that write was in flight, the row it just created is
  /// deleted again so the next refresh does not bring it back.
  void _adoptSaved(String uid, SpaceShortcut saved) {
    if (_userId != uid) return;
    final current = state.valueOrNull ?? const <SpaceShortcut>[];
    if (current.any((s) => s.key == saved.key)) {
      _replaceByKey(saved);
    } else {
      unawaited(_deleteRemote(uid, saved));
    }
  }

  Future<void> _deleteRemote(String uid, SpaceShortcut s) async {
    try {
      await _db
          .from(_table)
          .delete()
          .eq('user_id', uid)
          .eq('kind', s.kind.name)
          .eq('target_id', s.targetId);
    } catch (e) {
      debugPrint('[MySpace] remove failed: $e');
    }
  }

  // ---------------------------------------------------------------- retry

  /// Pins that never reached the server: still on a `local:` id, not being
  /// written right now, and not refused too often this session.
  Iterable<SpaceShortcut> _unsyncedLocals() =>
      (state.valueOrNull ?? const <SpaceShortcut>[]).where(
        (s) =>
            s.isLocal &&
            !_syncing.contains(s.key) &&
            (_syncRejections[s.key] ?? 0) < _maxSyncRejections,
      );

  /// Queues a refresh when unsynced pins are waiting. The refresh confirms
  /// which of them the server really lacks before anything is written again,
  /// so a pin already stored (its reply was lost) is adopted, not rewritten.
  void _retryUnsyncedSoon() {
    if (_userId == null || _remoteUnavailable) return;
    if (_unsyncedLocals().isEmpty) return;
    _scheduleRefetch();
  }

  /// Upserts again every pin still on a `local:` id: added offline, or whose
  /// first write failed. Called straight after a refresh, when those are
  /// exactly the rows the server does not have. The upsert is idempotent on
  /// (user_id, kind, target_id), so a repeat never duplicates. A dropped
  /// connection ends the pass; the next refresh, rejoin or write resumes it.
  Future<void> _syncUnsyncedLocals(String uid) async {
    if (_syncPassFor == uid) return;
    final keys = [for (final s in _unsyncedLocals()) s.key];
    if (keys.isEmpty) return;
    _syncPassFor = uid;
    try {
      for (final key in keys) {
        if (_userId != uid || _remoteUnavailable) return;
        final item = (state.valueOrNull ?? const <SpaceShortcut>[])
            .where((s) => s.key == key)
            .firstOrNull;
        if (item == null || !item.isLocal || _syncing.contains(key)) continue;
        _syncing.add(key);
        final openedAt = item.lastOpenedAt?.toUtc().toIso8601String();
        try {
          final row = await _db
              .from(_table)
              .upsert({
                ...item.toInsert(),
                'user_id': uid,
                // Opens made while the pin was local were never written.
                if (item.openCount > 0) 'open_count': item.openCount,
                if (openedAt != null) 'last_opened_at': openedAt,
              }, onConflict: 'user_id,kind,target_id')
              .select()
              .single();
          _syncRejections.remove(key);
          final saved = SpaceShortcut.fromJson(Map<String, dynamic>.from(row));
          if (saved != null) _adoptSaved(uid, saved);
        } on PostgrestException catch (e) {
          if (_isMissingTable(e)) {
            _remoteUnavailable = true;
            return;
          }
          _syncRejections[key] = (_syncRejections[key] ?? 0) + 1;
          debugPrint('[MySpace] retry refused for $key: ${e.message}');
        } catch (e) {
          debugPrint('[MySpace] retry paused: $e');
          return;
        } finally {
          _syncing.remove(key);
        }
      }
    } finally {
      if (_syncPassFor == uid) _syncPassFor = null;
    }
  }

  // ---------------------------------------------------------------- cache

  Future<List<SpaceShortcut>> _readCache() async {
    try {
      final entry = await AppDatabase.instance.getCache(
        key: _cacheKey,
        userId: _userId,
      );
      if (entry == null) return const [];
      final raw = jsonDecode(entry.value);
      if (raw is! List) return const [];
      final list = <SpaceShortcut>[];
      for (final m in raw) {
        if (m is Map) {
          final s = SpaceShortcut.fromJson(Map<String, dynamic>.from(m));
          if (s != null) list.add(s);
        }
      }
      return _sorted(list);
    } catch (e) {
      debugPrint('[MySpace] cache read failed: $e');
      return const [];
    }
  }

  Future<void> _writeCache(List<SpaceShortcut> list) async {
    try {
      await AppDatabase.instance.setCache(
        key: _cacheKey,
        value: jsonEncode(list.map((s) => s.toJson()).toList()),
        userId: _userId,
      );
    } catch (e) {
      debugPrint('[MySpace] cache write failed: $e');
    }
  }

  static List<SpaceShortcut> _sorted(List<SpaceShortcut> list) {
    final out = [...list];
    out.sort((a, b) {
      final bySort = b.sortIndex.compareTo(a.sortIndex);
      if (bySort != 0) return bySort;
      final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
      final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
      return bt.compareTo(at);
    });
    return out;
  }

  static bool _isMissingTable(PostgrestException e) =>
      e.code == '42P01' ||
      e.code == 'PGRST205' ||
      (e.message.contains('user_space_shortcuts') &&
          e.message.contains('does not exist'));
}

/// Whether two copies of a shortcut would show and behave the same: same
/// target, copy, params, place and open history. The id is not compared; a
/// row restored by Undo keeps its old local id.
bool spaceShortcutsMatch(SpaceShortcut a, SpaceShortcut b) {
  if (a.key != b.key ||
      a.title != b.title ||
      a.subtitle != b.subtitle ||
      (a.sortIndex - b.sortIndex).abs() > 1e-9 ||
      a.openCount != b.openCount ||
      !const DeepCollectionEquality().equals(a.params, b.params)) {
    return false;
  }
  final at = a.lastOpenedAt;
  final bt = b.lastOpenedAt;
  if (at == null || bt == null) return at == bt;
  return at.difference(bt).inMilliseconds.abs() < 1000;
}
