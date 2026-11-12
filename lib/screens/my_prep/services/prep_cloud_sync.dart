// Prep profiles in step between the reader's devices and apps.
//
// THIS FILE IS SHARED, BYTE FOR BYTE, BY THE MOBILE APP
// (`lib/screens/my_prep/services/prep_cloud_sync.dart`) AND THE DESKTOP APP
// (`lib/desktop/services/prep_cloud_sync.dart`). Change one, copy it to the
// other. It imports nothing from either app.
//
// A profile lives on the device with its games. What makes it a profile
// (its name, whether it is the reader's own, the sources its games come
// from and their download options) is also kept in `public.prep_profiles`,
// one row per profile, in the JSON shape below. Each app writes its
// profiles there and rebuilds the ones it lacks. Games are never sent: each
// device downloads them from the sources. Imported PGN files are not
// sources another device can read, so they are never part of a row.
//
// The row's `profile`:
//
//   name          String
//   kind          'mine' | 'opponent'
//   createdAtMs   int
//   fideIdentity  String?
//   accounts      [ { source: 'lichess' | 'chesscom' | 'chessever',
//                     username, externalId?, displayName?, avatarUrl?,
//                     title?, country?, fideId?, playerAliases?,
//                     preferences: { timeControls: [..], range,
//                                    fromDate, toDate } } ]
//
// An app keeps every key it does not understand when it writes a row back.
//
// How a pass decides, per profile, with three things in hand: the profile
// here, the row, and what both were when they last agreed (the base):
//
//   here == row            nothing to do
//   here == base           the row changed elsewhere: it is applied here
//   row == base            it changed here: the row is written
//   neither                both changed: the sources of both are kept
//
// A profile is compared by its [PrepCloudSync.core] only: its name, kind,
// sources and download options as this app understands them. Titles,
// photos and ratings are refreshed by each device and never start a write.
//
// A row is never removed. A deleted profile keeps its row, marked deleted,
// so the other devices remove it instead of writing it back.

import 'dart:async';
import 'dart:convert';

typedef PrepJson = Map<String, dynamic>;

/// One row of `prep_profiles`.
class PrepCloudRow {
  const PrepCloudRow({
    required this.id,
    required this.profile,
    this.deleted = false,
  });

  final String id;
  final PrepJson profile;
  final bool deleted;
}

/// The reader's rows on the server.
abstract class PrepCloudRemote {
  /// Every row of the signed-in reader. Null when they cannot be read
  /// (signed out, offline, a server without the table).
  Future<List<PrepCloudRow>?> fetch();

  /// Writes row [id]. False when it could not be written now.
  Future<bool> write(String id, PrepJson profile, {required bool deleted});
}

/// The profiles on this device, as the app keeps them.
abstract class PrepCloudDevice {
  /// Every profile of the signed-in reader on this device, by its id here,
  /// in the row's shape, each with the sources another device can download
  /// (possibly none). Null while they are not loaded: nothing may be
  /// concluded from a list that is not there.
  Map<String, PrepJson>? profiles();

  /// A source's download options as this app understands them. Two values
  /// this app cannot tell apart must give the same text.
  String preferencesCore(Object? preferences);

  /// A profile's kind as this app understands it.
  String kindCore(Object? kind);

  /// Adds the profile [profile] under [id], without its games. False when
  /// it was not added.
  Future<bool> create(String id, PrepJson profile);

  /// Makes profile [id] match [profile]: sources added and removed, their
  /// download options, its name and kind. What cannot be done is left out.
  Future<void> apply(String id, PrepJson profile);

  /// Removes profile [id], deleted on another device. False when it stays
  /// (it holds imported files here).
  Future<bool> remove(String id);
}

/// What this device remembers between passes, for one reader.
class PrepCloudState {
  PrepCloudState({
    Map<String, String>? rowOf,
    Map<String, String>? base,
    Set<String>? deletes,
  }) : rowOf = rowOf ?? {},
       base = base ?? {},
       deletes = deletes ?? {};

  /// The row each profile here is kept in, by the profile's id here. The
  /// two differ when the reader added the same player on two devices before
  /// they synced: both then share the first row.
  final Map<String, String> rowOf;

  /// Each profile's [PrepCloudSync.core] when it last agreed with its row.
  final Map<String, String> base;

  /// Rows of profiles deleted here that the server has not been told.
  final Set<String> deletes;

  PrepJson toJson() => {
    'rowOf': rowOf,
    'base': base,
    'deletes': deletes.toList(),
  };

  static PrepCloudState fromJson(Object? raw) {
    if (raw is! Map) return PrepCloudState();
    Map<String, String> strings(Object? value) => {
      if (value is Map)
        for (final entry in value.entries)
          if (entry.value is String)
            entry.key.toString(): entry.value as String,
    };
    final deletes = raw['deletes'];
    return PrepCloudState(
      rowOf: strings(raw['rowOf']),
      base: strings(raw['base']),
      deletes: {if (deletes is List) ...deletes.whereType<String>()},
    );
  }
}

/// A source's identity in a row, the same on every device: online names
/// and database ids compare without case.
String prepCloudAccountKey(Object? account) {
  if (account is! Map) return '';
  final source = account['source']?.toString() ?? '';
  final username = account['username']?.toString().trim() ?? '';
  final external = account['externalId']?.toString().trim() ?? '';
  final id = source == 'chessever' && external.isNotEmpty ? external : username;
  return source.isEmpty || id.isEmpty ? '' : '$source:${id.toLowerCase()}';
}

/// The sources of [profile] that have an identity.
List<PrepJson> prepCloudAccounts(PrepJson? profile) {
  final raw = profile?['accounts'];
  return [
    if (raw is List)
      for (final account in raw)
        if (account is Map && prepCloudAccountKey(account).isNotEmpty)
          Map<String, dynamic>.from(account),
  ];
}

class PrepCloudSync {
  PrepCloudSync({
    required this.remote,
    required this.device,
    required this.state,
    required this.save,
  });

  final PrepCloudRemote remote;
  final PrepCloudDevice device;
  final PrepCloudState state;

  /// Keeps [state] for the next launch.
  final Future<void> Function(PrepCloudState state) save;

  Future<void>? _running;
  bool _again = false;

  /// What [profile] is, as this app compares it.
  String core(PrepJson profile) {
    final accounts = [
      for (final account in prepCloudAccounts(profile))
        [
          prepCloudAccountKey(account),
          device.preferencesCore(account['preferences']),
        ],
    ]..sort((a, b) => a.first.compareTo(b.first));
    return jsonEncode([
      profile['name']?.toString().trim() ?? '',
      device.kindCore(profile['kind']),
      accounts,
    ]);
  }

  /// Whether a pass has anything to write: a profile here differs from its
  /// base, has no row yet, or a deletion is waiting. Needs no network.
  bool get dirty {
    if (state.deletes.isNotEmpty) return true;
    final profiles = device.profiles();
    if (profiles == null) return false;
    for (final entry in profiles.entries) {
      final row = state.rowOf[entry.key];
      if (row == null) {
        if (prepCloudAccounts(entry.value).isNotEmpty) return true;
      } else if (state.base[entry.key] != core(entry.value)) {
        return true;
      }
    }
    return false;
  }

  /// The reader deleted profile [id] here. Its row is marked deleted by the
  /// next pass, so the other devices remove it too.
  Future<void> forget(String id) async {
    final row = state.rowOf.remove(id);
    state.base.remove(id);
    if (row == null) return;
    state.deletes.add(row);
    await save(state);
  }

  /// Brings this device and the server into step. One pass runs at a time;
  /// a call during one runs another when it ends.
  Future<void> pass() {
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    final done = () async {
      try {
        do {
          _again = false;
          await _pass();
        } while (_again);
      } finally {
        _running = null;
      }
    }();
    _running = done;
    return done;
  }

  Future<void> _pass() async {
    if (device.profiles() == null) return;
    final rows = await remote.fetch();
    if (rows == null) return;
    final before = device.profiles();
    if (before == null) return;
    final byId = {for (final row in rows) row.id: row};

    // Deletions the server has not heard.
    for (final id in state.deletes.toList()) {
      final profile = byId[id]?.profile ?? const <String, dynamic>{};
      if (await remote.write(id, profile, deleted: true)) {
        state.deletes.remove(id);
        byId[id] = PrepCloudRow(id: id, profile: profile, deleted: true);
      }
    }

    // A profile that is no longer here without the reader having deleted it
    // (the app's data was cleared): its row is left alone and brings it
    // back below.
    for (final id in state.rowOf.keys.toList()) {
      if (!before.containsKey(id)) {
        state.rowOf.remove(id);
        state.base.remove(id);
      }
    }
    state.base.removeWhere((id, _) => !state.rowOf.containsKey(id));

    for (final entry in before.entries) {
      await _settle(entry.key, entry.value, byId);
    }

    // Rows no profile here is kept in: profiles made on another device.
    final here = device.profiles() ?? before;
    final kept = state.rowOf.values.toSet();
    final ids = byId.keys.toList()..sort();
    for (final id in ids) {
      final row = byId[id]!;
      if (row.deleted || kept.contains(id) || state.deletes.contains(id)) {
        continue;
      }
      if (prepCloudAccounts(row.profile).isEmpty || here.containsKey(id)) {
        continue;
      }
      // The same player is here already, kept in another row: two rows
      // written at the same moment. Each device keeps its own.
      if (here.values.any((profile) => _samePlayer(profile, row.profile))) {
        continue;
      }
      if (!await device.create(id, row.profile)) continue;
      final created = device.profiles()?[id];
      state.rowOf[id] = id;
      state.base[id] = core(created ?? row.profile);
      here[id] = created ?? row.profile;
    }
    await save(state);
  }

  Future<void> _settle(
    String id,
    PrepJson profile,
    Map<String, PrepCloudRow> byId,
  ) async {
    final hasSources = prepCloudAccounts(profile).isNotEmpty;
    final rowId = state.rowOf[id];
    if (rowId == null) {
      if (!hasSources) return;
      // First time: the row of the same id, or the first row of the same
      // player (added on two devices before they synced).
      final taken = state.rowOf.values.toSet();
      var row = taken.contains(id) ? null : byId[id];
      if (row == null) {
        final ids = byId.keys.toList()..sort();
        for (final other in ids) {
          final candidate = byId[other]!;
          if (candidate.deleted ||
              taken.contains(other) ||
              state.deletes.contains(other)) {
            continue;
          }
          if (_samePlayer(profile, candidate.profile)) {
            row = candidate;
            break;
          }
        }
      }
      if (row == null || row.deleted) {
        await _write(id, row?.id ?? id, profile, row?.profile, byId);
        return;
      }
      state.rowOf[id] = row.id;
      if (core(profile) == core(row.profile)) {
        state.base[id] = core(profile);
        return;
      }
      await _keepBoth(id, profile, row, byId);
      return;
    }

    final row = byId[rowId];
    final here = core(profile);
    final base = state.base[id];
    if (!hasSources) {
      // Its last source another device could download is gone.
      if (row != null && !row.deleted) {
        if (!await remote.write(rowId, row.profile, deleted: true)) return;
        byId[rowId] = PrepCloudRow(
          id: rowId,
          profile: row.profile,
          deleted: true,
        );
      }
      state.rowOf.remove(id);
      state.base.remove(id);
      return;
    }
    if (row == null) {
      await _write(id, rowId, profile, null, byId);
      return;
    }
    if (row.deleted) {
      if (base != null && here == base) {
        // Deleted on another device, unchanged here.
        state.rowOf.remove(id);
        state.base.remove(id);
        if (!await device.remove(id)) {
          state.rowOf[id] = rowId;
          state.base[id] = here;
        }
      } else {
        // Changed here since: it lives on.
        await _write(id, rowId, profile, row.profile, byId);
      }
      return;
    }
    final there = core(row.profile);
    if (there == here) {
      state.base[id] = here;
    } else if (here == base) {
      await device.apply(id, row.profile);
      final applied = device.profiles()?[id];
      state.base[id] = core(applied ?? profile);
    } else if (there == base) {
      await _write(id, rowId, profile, row.profile, byId);
    } else {
      await _keepBoth(id, profile, row, byId);
    }
  }

  /// Both sides changed, or meet for the first time: the sources of both
  /// are kept, here and in the row.
  Future<void> _keepBoth(
    String id,
    PrepJson profile,
    PrepCloudRow row,
    Map<String, PrepCloudRow> byId,
  ) async {
    final keys = {
      for (final account in prepCloudAccounts(profile))
        prepCloudAccountKey(account),
    };
    final both = <String, dynamic>{
      ...profile,
      'accounts': [
        ...prepCloudAccounts(profile),
        for (final account in prepCloudAccounts(row.profile))
          if (!keys.contains(prepCloudAccountKey(account))) account,
      ],
    };
    var now = profile;
    if (core(both) != core(profile)) {
      await device.apply(id, both);
      now = device.profiles()?[id] ?? profile;
    }
    await _write(id, row.id, now, row.profile, byId);
  }

  Future<void> _write(
    String id,
    String rowId,
    PrepJson profile,
    PrepJson? row,
    Map<String, PrepCloudRow> byId,
  ) async {
    final written = _merged(profile, row);
    if (!await remote.write(rowId, written, deleted: false)) return;
    state.rowOf[id] = rowId;
    state.base[id] = core(profile);
    byId[rowId] = PrepCloudRow(id: rowId, profile: written);
  }

  /// [profile] as it is written over [row]: every key this app does not
  /// know is kept, and so is a kind or a download option this app cannot
  /// tell from its own (another app may hold more detail in it).
  PrepJson _merged(PrepJson profile, PrepJson? row) {
    if (row == null) return profile;
    final there = {
      for (final account in prepCloudAccounts(row))
        prepCloudAccountKey(account): account,
    };
    return {
      ...row,
      ...profile,
      if (row['kind'] != null &&
          device.kindCore(row['kind']) == device.kindCore(profile['kind']))
        'kind': row['kind'],
      'accounts': [
        for (final account in prepCloudAccounts(profile))
          () {
            final other = there[prepCloudAccountKey(account)];
            if (other == null) return account;
            final same =
                device.preferencesCore(other['preferences']) ==
                device.preferencesCore(account['preferences']);
            return <String, dynamic>{
              ...other,
              ...account,
              if (same) 'preferences': other['preferences'],
            };
          }(),
      ],
    };
  }

  /// The same person: a source in common, or both the reader's own.
  bool _samePlayer(PrepJson a, PrepJson b) {
    if (device.kindCore(a['kind']) == device.kindCore('mine') &&
        device.kindCore(b['kind']) == device.kindCore('mine')) {
      return true;
    }
    final keys = {
      for (final account in prepCloudAccounts(a)) prepCloudAccountKey(account),
    };
    return prepCloudAccounts(
      b,
    ).any((account) => keys.contains(prepCloudAccountKey(account)));
  }
}
