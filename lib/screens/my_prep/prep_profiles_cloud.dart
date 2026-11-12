import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/prep_space_shortcut.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/services/prep_cloud_sync.dart';
import 'package:chessever2/screens/my_prep/services/prep_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Prep profiles in step between this app, the reader's other phones and
// the desktop app. The rules are in `services/prep_cloud_sync.dart`, shared
// with the desktop app; this file is the mobile side of it: what a profile
// here looks like as a row, and how a row is made into a profile here.
//
// Profiles and their games stay in `prep/profiles.json` exactly as before.
// What this adds is kept apart, in `prep/cloud.json`, so an older build on
// the same device reads its file as it always did.

/// How often an open app looks for changes made on another device. It also
/// looks at launch, on coming back to the foreground, and right after a
/// change made here.
const kPrepCloudEvery = Duration(minutes: 3);

/// [profile] in the shape of its row: who it is and the sources another
/// device can download, never its games. A player kept only so their games
/// stay downloaded (`PrepKind.favorite`) is not a profile the reader made
/// and has no row.
PrepJson prepCloudProfile(PrepProfile profile) => {
  'name': profile.name,
  'kind': profile.kind.name,
  'createdAtMs': profile.createdAtMs,
  'fideIdentity': ?profile.fideId,
  'favoriteId': ?profile.favoriteId,
  'accounts': prepPinRecipe(profile)?['accounts'] ?? const <Object>[],
};

/// The row identity of a source here.
String _key(PrepAccount account) => prepCloudAccountKey({
  'source': account.source.name,
  'username': account.username,
  'externalId': account.externalId,
});

/// The reader's rows, through Supabase.
class PrepCloudSupabase implements PrepCloudRemote {
  const PrepCloudSupabase(this.userId);

  final String userId;
  static const _table = 'prep_profiles';

  SupabaseClient? get _client {
    try {
      final client = Supabase.instance.client;
      return client.auth.currentUser?.id == userId ? client : null;
    } catch (_) {
      // Not initialized (tests, a very early call).
      return null;
    }
  }

  @override
  Future<List<PrepCloudRow>?> fetch() async {
    final client = _client;
    if (client == null) return null;
    try {
      final rows = await client
          .from(_table)
          .select('profile_id, profile, deleted_at')
          .eq('user_id', userId);
      return [
        for (final row in rows)
          if (row['profile_id'] case final String id when id.isNotEmpty)
            PrepCloudRow(
              id: id,
              profile: row['profile'] is Map
                  ? Map<String, dynamic>.from(row['profile'] as Map)
                  : <String, dynamic>{},
              deleted: row['deleted_at'] != null,
            ),
      ];
    } catch (error) {
      debugPrint('[MyPrep] profiles not read from the server: $error');
      return null;
    }
  }

  @override
  Future<bool> write(
    String id,
    PrepJson profile, {
    required bool deleted,
  }) async {
    final client = _client;
    if (client == null) return false;
    try {
      await client.from(_table).upsert({
        'user_id': userId,
        'profile_id': id,
        'profile': profile,
        'deleted_at': deleted ? DateTime.now().toUtc().toIso8601String() : null,
      }, onConflict: 'user_id,profile_id');
      return true;
    } catch (error) {
      debugPrint('[MyPrep] profile not written to the server: $error');
      return false;
    }
  }
}

/// The signed-in reader whose profiles sync, or null (signed out).
final prepCloudUserProvider = Provider<String?>(
  (ref) => ref.watch(currentUserProvider)?.id,
);

/// The server for [userId]. A provider so tests can stand in for it.
final prepCloudRemoteProvider = Provider.family<PrepCloudRemote, String>(
  (ref, userId) => PrepCloudSupabase(userId),
);

/// What the sync remembers on this device (`prep/cloud.json`): whose each
/// profile is, and each reader's [PrepCloudState].
class PrepCloudFile {
  PrepCloudFile._(this._file, this.owners, this._states);

  final File _file;

  /// The reader each profile belongs to. Profiles are kept per device, not
  /// per account: on a shared device, one reader's profiles never go to
  /// another's account. A profile no one owns yet goes to the reader who is
  /// signed in when it first syncs.
  final Map<String, String> owners;
  final Map<String, PrepCloudState> _states;
  Future<void> _writing = Future.value();

  static Future<PrepCloudFile> open() async {
    final file = File(
      '${(await PrepRepository.prepDirectory()).path}/cloud.json',
    );
    Object? json;
    try {
      if (await file.exists()) json = jsonDecode(await file.readAsString());
    } catch (error) {
      // Unreadable: every profile meets its row again, which keeps both.
      debugPrint('[MyPrep] sync state unreadable: $error');
    }
    final owners = json is Map ? json['owners'] : null;
    final users = json is Map ? json['users'] : null;
    return PrepCloudFile._(
      file,
      {
        if (owners is Map)
          for (final entry in owners.entries)
            if (entry.value is String)
              entry.key.toString(): entry.value as String,
      },
      {
        if (users is Map)
          for (final entry in users.entries)
            entry.key.toString(): PrepCloudState.fromJson(entry.value),
      },
    );
  }

  PrepCloudState stateOf(String userId) =>
      _states.putIfAbsent(userId, PrepCloudState.new);

  Future<void> save() {
    final json = jsonEncode({
      'version': 1,
      'owners': owners,
      'users': {
        for (final entry in _states.entries) entry.key: entry.value.toJson(),
      },
    });
    return _writing = _writing.then((_) async {
      try {
        final temp = File('${_file.path}.tmp');
        await temp.writeAsString(json, flush: true);
        await temp.rename(_file.path);
      } catch (error) {
        debugPrint('[MyPrep] sync state not saved: $error');
      }
    });
  }
}

/// The profiles on this device, for [userId].
class _Device implements PrepCloudDevice {
  _Device(this._ref, this._file, this.userId);

  final Ref _ref;
  final PrepCloudFile _file;
  final String userId;

  /// Sources rebuilt here by the last pass, whose games are still to come.
  final downloads = <(String, String)>[];

  PrepProfilesNotifier get _store => _ref.read(prepProfilesProvider.notifier);

  @override
  Map<String, PrepJson>? profiles() {
    final list = _ref.read(prepProfilesProvider).valueOrNull;
    if (list == null) return null;
    var claimed = false;
    final mine = <String, PrepJson>{};
    for (final profile in list) {
      if (profile.kind == PrepKind.favorite) continue;
      final owner = _file.owners[profile.id];
      if (owner == null) {
        _file.owners[profile.id] = userId;
        claimed = true;
      } else if (owner != userId) {
        continue;
      }
      mine[profile.id] = prepCloudProfile(profile);
    }
    if (claimed) unawaited(_file.save());
    return mine;
  }

  @override
  String preferencesCore(Object? preferences) =>
      jsonEncode(PrepDownloadPreferences.fromJson(preferences).toJson());

  @override
  String kindCore(Object? kind) =>
      kind == PrepKind.mine.name ? PrepKind.mine.name : PrepKind.opponent.name;

  PrepKind _kind(Object? kind) =>
      kind == PrepKind.mine.name ? PrepKind.mine : PrepKind.opponent;

  @override
  Future<bool> create(String id, PrepJson profile) async {
    final made = PrepProfile.fromJson({
      ...profile,
      'id': id,
      'kind': _kind(profile['kind']).name,
    });
    if (made == null || made.accounts.isEmpty) return false;
    final holder = _store.restore(made);
    if (holder == null || holder.id != id) return false;
    _file.owners[id] = userId;
    for (final account in made.accounts) {
      downloads.add((id, account.key));
    }
    // Starred on the device that made it: the star shows here too.
    _store.settleWatch(id);
    return true;
  }

  @override
  Future<void> apply(String id, PrepJson profile) async {
    final here = _store.byId(id);
    if (here == null) return;
    final wanted = {
      for (final account in prepCloudAccounts(profile))
        prepCloudAccountKey(account): account,
    };
    // Sources removed elsewhere go, with their games. Imported files are
    // never part of a row and stay.
    for (final account in here.accounts) {
      if (account.source == PrepSource.manual) continue;
      if (!wanted.containsKey(_key(account))) {
        await _store.removeAccount(id, account);
      }
    }
    final held = {
      for (final account in _store.byId(id)?.accounts ?? const <PrepAccount>[])
        _key(account): account,
    };
    for (final entry in wanted.entries) {
      final account = held[entry.key];
      if (account == null) {
        final added = PrepAccount.fromJson(entry.value);
        if (added == null || added.source == PrepSource.manual) continue;
        try {
          _store.attach(id, [added]);
          downloads.add((id, added.key));
        } on PrepException {
          // Attached to another profile here, or a second database
          // player: left out.
        }
        continue;
      }
      final options = PrepDownloadPreferences.fromJson(
        entry.value['preferences'],
      );
      if (options != account.preferences) {
        // A refresh downloads the new selection, as when the reader
        // changes it here.
        _store.edit(
          id,
          (p) => p.replaceAccount(account.copyWith(preferences: options)),
        );
      }
    }
    final now = _store.byId(id);
    if (now == null) return;
    final name = profile['name']?.toString().trim() ?? '';
    var kind = _kind(profile['kind']);
    final others = _ref.read(prepProfilesProvider).valueOrNull ?? const [];
    // One profile of the reader's own per device, and a player kept from
    // Players stays one.
    if (now.kind == PrepKind.favorite ||
        (kind == PrepKind.mine &&
            others.any((p) => p.id != id && p.kind == PrepKind.mine))) {
      kind = now.kind;
    }
    if ((name.isEmpty || name == now.name) && kind == now.kind) return;
    _store.edit(
      id,
      (p) => p.copyWith(name: name.isEmpty ? null : name, kind: kind),
    );
  }

  @override
  Future<bool> remove(String id) async {
    final here = _store.byId(id);
    if (here == null) return true;
    if (here.accounts.any((a) => a.source == PrepSource.manual)) return false;
    await _store.delete(id);
    _file.owners.remove(id);
    return true;
  }
}

/// Keeps the Prep profiles on this device and on the reader's account in
/// step (see the top of this file). Watch it from the home shell.
final prepCloudSyncProvider = Provider<void>((ref) {
  PrepCloudSync? sync;
  _Device? device;
  PrepCloudFile? file;
  var disposed = false;
  Timer? soon;

  Future<void> run() async {
    final engine = sync;
    final here = device;
    if (engine == null || here == null || disposed) return;
    await engine.pass();
    if (disposed) return;
    // The games of what was rebuilt, one source after another.
    final downloads = [...here.downloads];
    here.downloads.clear();
    final downloader = ref.read(prepSyncProvider.notifier);
    final profiles = ref.read(prepProfilesProvider.notifier);
    for (final (profileId, key) in downloads) {
      if (disposed) return;
      final account = profiles
          .byId(profileId)
          ?.accounts
          .where((a) => a.key == key)
          .firstOrNull;
      if (account == null || account.lastSyncAtMs != null) continue;
      await downloader.syncAccount(profileId, account);
    }
  }

  /// A change here is written a moment later, once it has settled.
  void changed() {
    if (!(sync?.dirty ?? false)) return;
    soon?.cancel();
    soon = Timer(const Duration(seconds: 2), () => unawaited(run()));
  }

  Future<void> start(String? userId) async {
    sync = null;
    device = null;
    if (userId == null) return;
    final PrepCloudFile opened;
    try {
      opened = file ??= await PrepCloudFile.open();
    } catch (error) {
      // No storage to remember in: nothing is synced this session.
      debugPrint('[MyPrep] sync not started: $error');
      return;
    }
    if (disposed || ref.read(prepCloudUserProvider) != userId) return;
    final here = _Device(ref, opened, userId);
    device = here;
    sync = PrepCloudSync(
      remote: ref.read(prepCloudRemoteProvider(userId)),
      device: here,
      state: opened.stateOf(userId),
      save: (_) => opened.save(),
    );
    await run();
  }

  ref.listen(prepCloudUserProvider, (_, userId) => unawaited(start(userId)));
  ref.listen(prepProfilesProvider, (before, after) {
    final was = before?.valueOrNull;
    final now = after.valueOrNull;
    if (now == null) return;
    if (was == null) {
      // Just loaded.
      unawaited(run());
      return;
    }
    // Profiles the reader deleted here: their rows are marked deleted.
    final held = {for (final p in now) p.id};
    for (final old in was) {
      if (held.contains(old.id)) continue;
      file?.owners.remove(old.id);
      unawaited(sync?.forget(old.id));
    }
    changed();
  });
  final tick = Timer.periodic(kPrepCloudEvery, (_) {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    unawaited(run());
  });
  final lifecycle = AppLifecycleListener(onResume: () => unawaited(run()));
  ref.onDispose(() {
    disposed = true;
    soon?.cancel();
    tick.cancel();
    lifecycle.dispose();
  });
  unawaited(start(ref.read(prepCloudUserProvider)));
});
