import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/my_prep/library/prep_cloud_sync.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/services/prep_analysis.dart';
import 'package:chessever2/screens/my_prep/services/prep_index.dart';
import 'package:chessever2/screens/my_prep/services/prep_repository.dart';
import 'package:chessever2/services/game_tree/game_tree_registry.dart';
import 'package:chessever2/services/game_tree/game_tree_service.dart';
import 'package:chessever2/services/game_tree/game_tree_store.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// How often the reader's own accounts are brought up to date: three times
/// a day, against the server's daily refresh for everyone else.
const Duration kPrepMineRefreshEvery = Duration(hours: 8);

/// How stale an opponent's or favorite's games may be before opening it
/// checks for new ones.
const Duration kPrepOthersRefreshEvery = Duration(hours: 24);

final prepRepositoryProvider = Provider<PrepRepository>(
  (ref) => PrepRepository(ref.read(gamebaseRepositoryProvider)),
);

// ------------------------------------------------------------------ store

/// Every Prep profile on this device, persisted as one JSON file next to
/// the downloaded games.
final prepProfilesProvider =
    StateNotifierProvider<PrepProfilesNotifier, AsyncValue<List<PrepProfile>>>(
      (ref) => PrepProfilesNotifier(ref),
    );

final prepProfileProvider = Provider.autoDispose.family<PrepProfile?, String>((
  ref,
  id,
) {
  final profiles = ref.watch(prepProfilesProvider).valueOrNull;
  for (final p in profiles ?? const <PrepProfile>[]) {
    if (p.id == id) return p;
  }
  return null;
});

final prepProfilesOfKindProvider = Provider.autoDispose
    .family<List<PrepProfile>?, PrepKind>((ref, kind) {
      final profiles = ref.watch(prepProfilesProvider).valueOrNull;
      if (profiles == null) return null;
      return [
        for (final p in profiles)
          if (p.kind == kind) p,
      ];
    });

class PrepProfilesNotifier extends StateNotifier<AsyncValue<List<PrepProfile>>> {
  PrepProfilesNotifier(this._ref) : super(const AsyncValue.loading()) {
    unawaited(_load());
  }

  final Ref _ref;
  Future<void> _writing = Future.value();

  List<PrepProfile> get _profiles => state.valueOrNull ?? const [];

  Future<File> _file() async =>
      File('${(await PrepRepository.prepDirectory()).path}/profiles.json');

  Future<void> _load() async {
    try {
      final file = await _file();
      if (!await file.exists()) {
        state = const AsyncValue.data([]);
        return;
      }
      final json = jsonDecode(await file.readAsString());
      state = AsyncValue.data([
        if (json is Map && json['profiles'] is List)
          for (final raw in json['profiles'] as List) ?PrepProfile.fromJson(raw),
      ]);
    } catch (error, stack) {
      debugPrint('[MyPrep] profiles failed to load: $error');
      state = AsyncValue.error(error, stack);
    }
  }

  void _set(List<PrepProfile> profiles) {
    state = AsyncValue.data(List.unmodifiable(profiles));
    // Serialized so an older snapshot can never land after a newer one.
    _writing = _writing.then((_) async {
      try {
        final file = await _file();
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(
          jsonEncode({
            'version': 1,
            'profiles': [for (final p in profiles) p.toJson()],
          }),
          flush: true,
        );
        await temp.rename(file.path);
      } catch (error) {
        debugPrint('[MyPrep] profiles failed to save: $error');
      }
    });
  }

  PrepProfile? byId(String id) {
    for (final p in _profiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// The profile already holding [account], if any (one account belongs to
  /// one profile, so its stored games are never shared).
  PrepProfile? owning(PrepSource source, String username) {
    final key = '${source.name}:${username.toLowerCase()}';
    for (final p in _profiles) {
      if (p.accounts.any((a) => a.key == key)) return p;
    }
    return null;
  }

  PrepProfile create({
    required PrepKind kind,
    required String name,
    required List<PrepAccount> accounts,
    String? favoriteId,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final profile = PrepProfile(
      id: '${kind.name}-$now-${_profiles.length}',
      kind: kind,
      name: name.trim(),
      createdAtMs: now,
      accounts: accounts,
      favoriteId: favoriteId,
    );
    _set([profile, ..._profiles]);
    return profile;
  }

  void update(PrepProfile profile) {
    _set([for (final p in _profiles) p.id == profile.id ? profile : p]);
  }

  /// Applies [change] to the newest stored copy of [profileId], so a sync
  /// finishing late cannot undo an edit made while it ran.
  void edit(String profileId, PrepProfile Function(PrepProfile) change) {
    final current = byId(profileId);
    if (current != null) update(change(current));
  }

  Future<void> delete(String profileId) async {
    final profile = byId(profileId);
    if (profile == null) return;
    _set([for (final p in _profiles) if (p.id != profileId) p]);
    await PrepIndex.forget(profileId, accounts: profile.accounts);
    final repo = _ref.read(prepRepositoryProvider);
    for (final account in profile.accounts) {
      await repo.deleteGames(account);
    }
  }

  Future<void> removeAccount(String profileId, PrepAccount account) async {
    edit(
      profileId,
      (p) => p.copyWith(
        accounts: [for (final a in p.accounts) if (a.key != account.key) a],
      ),
    );
    // The profile's own index notices the missing source and rebuilds.
    await PrepIndex.forget(profileId, accounts: [account], profileToo: false);
    await _ref.read(prepRepositoryProvider).deleteGames(account);
  }
}

// ------------------------------------------------------------------ sync

/// What one account's download is doing right now.
@immutable
class PrepSyncStatus {
  const PrepSyncStatus({required this.message, this.cancel});
  final String message;
  final CancelToken? cancel;
}

/// Running downloads by account key.
final prepSyncProvider =
    StateNotifierProvider<PrepSyncController, Map<String, PrepSyncStatus>>(
      (ref) => PrepSyncController(ref),
    );

class PrepSyncController extends StateNotifier<Map<String, PrepSyncStatus>> {
  PrepSyncController(this._ref) : super(const {});

  final Ref _ref;

  bool isSyncing(PrepAccount account) => state.containsKey(account.key);

  /// Downloads new games for one account. Returns the error text, or null.
  Future<String?> syncAccount(
    String profileId,
    PrepAccount account, {
    bool force = false,
  }) async {
    if (isSyncing(account)) return null;
    final profiles = _ref.read(prepProfilesProvider.notifier);
    final profile = profiles.byId(profileId);
    if (profile == null) return null;
    final cancel = CancelToken();
    void report(String message) {
      if (!mounted) return;
      state = {...state, account.key: PrepSyncStatus(message: message, cancel: cancel)};
    }

    report('Checking ${account.source.label}…');
    try {
      final synced = await _ref
          .read(prepRepositoryProvider)
          .sync(
            account,
            forceRefresh: force,
            frequent: profile.kind == PrepKind.mine,
            onProgress: report,
            cancelToken: cancel,
          );
      profiles.edit(profileId, (p) {
        final live = p.accounts.where((a) => a.key == account.key).firstOrNull;
        if (live == null) return p;
        // Keep any download options changed while this ran; the next sync
        // notices the new scope and replaces the games.
        return p.replaceAccount(
          live.copyWith(
            lastSyncAtMs: synced.lastSyncAtMs,
            syncedScope: live.preferences == account.preferences
                ? synced.syncedScope
                : 'stale',
            gameCount: synced.gameCount,
            clearError: true,
          ),
        );
      });
      // A player saved to the cloud takes the new games there too.
      _ref.read(prepCloudSyncProvider.notifier).syncAfterDownload(profileId);
      return null;
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) return null;
      return _fail(profileId, account, 'Could not download games. Try again.');
    } on PrepException catch (error) {
      return _fail(profileId, account, error.message);
    } catch (error) {
      debugPrint('[MyPrep] sync failed: $error');
      return _fail(profileId, account, 'Could not download games. Try again.');
    } finally {
      if (mounted) state = {...state}..remove(account.key);
    }
  }

  String _fail(String profileId, PrepAccount account, String message) {
    _ref
        .read(prepProfilesProvider.notifier)
        .edit(
          profileId,
          (p) => p.replaceAccount(
            (p.accounts.where((a) => a.key == account.key).firstOrNull ??
                    account)
                .copyWith(error: message),
          ),
        );
    return message;
  }

  /// Syncs every account of a profile, one after another (the server
  /// serializes provider downloads anyway). Returns the first error.
  Future<String?> syncProfile(String profileId, {bool force = false}) async {
    final profile = _ref.read(prepProfilesProvider.notifier).byId(profileId);
    if (profile == null) return null;
    String? firstError;
    for (final account in profile.accounts) {
      final error = await syncAccount(profileId, account, force: force);
      firstError ??= error;
    }
    return firstError;
  }

  /// Brings stale profiles of [kinds] up to date in the background: the
  /// reader's own accounts every [kPrepMineRefreshEvery], the rest daily.
  void refreshStale(Iterable<PrepProfile> profiles) {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final profile in profiles) {
      final every = profile.kind == PrepKind.mine
          ? kPrepMineRefreshEvery
          : kPrepOthersRefreshEvery;
      for (final account in profile.accounts) {
        final last = account.lastSyncAtMs;
        final stale =
            last == null ||
            now - last >= every.inMilliseconds ||
            account.syncedScope != account.preferences.scopeKey(DateTime.now());
        if (stale && account.error == null) {
          unawaited(syncAccount(profile.id, account));
        }
      }
    }
  }

  void cancel(PrepAccount account) {
    state[account.key]?.cancel?.cancel('Canceled by the reader');
  }
}

// ------------------------------------------------------------------ freshness

/// Keeps prepared players' games current while the app runs, as desktop
/// does: a little after launch, and whenever the app comes back to the
/// foreground, stale accounts fetch only their new games (yours every
/// [kPrepMineRefreshEvery], opponents every [kPrepOthersRefreshEvery]).
/// Watch it from the home shell; it does nothing without Premium.
final prepKeepFreshProvider = Provider<void>((ref) {
  var launched = false;
  void check() {
    final profiles = ref.read(prepProfilesProvider).valueOrNull;
    if (profiles == null || profiles.isEmpty) return;
    if (!ref.read(premiumAccessProvider)) return;
    ref
        .read(prepSyncProvider.notifier)
        .refreshStale(profiles.where((p) => p.kind != PrepKind.favorite));
  }

  // Not on the first frame: launch has enough to do already.
  final timer = Timer(const Duration(seconds: 10), () {
    launched = true;
    check();
  });
  final lifecycle = AppLifecycleListener(
    onResume: () {
      if (launched) check();
    },
  );
  ref.onDispose(() {
    timer.cancel();
    lifecycle.dispose();
  });
});

// ------------------------------------------------------------------ analysis

/// What a profile's analysis depends on: its accounts' stored games.
String _analysisKey(PrepProfile profile) => [
  for (final a in profile.accounts) '${a.key}@${a.lastSyncAtMs}#${a.gameCount}',
].join(',');

/// The games list, stats and opening tree for one profile, refreshed
/// whenever one of its accounts finishes a sync.
///
/// The heavy part lives in the profile's SQLite index: the first open of a
/// large account indexes it once, in the background, and every later sync
/// adds only its new games. The games list read from the index is light
/// (no PGN, no moves); PGNs are read from their files when a card shows.
final prepAnalysisProvider = FutureProvider.autoDispose
    .family<PrepAnalysis, String>((ref, profileId) async {
      final key = ref.watch(
        prepProfileProvider(profileId).select(
          (p) => p == null ? null : _analysisKey(p),
        ),
      );
      final profile = ref.read(prepProfileProvider(profileId));
      if (profile == null || key == null) return PrepAnalysis.empty(profileId);
      final status = ref.read(gameTreeStatusProvider.notifier);
      final repo = ref.read(prepRepositoryProvider);
      GameTreeStore store;
      try {
        store = await PrepIndex.ensureProfile(
          repo,
          profile,
          onProgress: (fraction) => status.set(
            profileId,
            GameTreeStatus(phase: GameTreePhase.indexing, fraction: fraction),
          ),
        );
      } on GameTreeCanceled {
        // Stopped from the tree button: show what is indexed so far; the
        // next open picks up where it stopped.
        final partial = GameTreeRegistry.storeFor(profileId);
        if (partial == null) rethrow;
        store = partial;
      } finally {
        status.clear(profileId);
      }
      final rows = await store.loadGames();
      final analysis = PrepAnalysis(
        profileId: profileId,
        store: store,
        games: List.unmodifiable([
          for (var i = 0; i < rows.length; i++) PrepGame.fromIndex(rows[i], i),
        ]),
      );
      // Kept while the profile is open and briefly after, so stepping into
      // the explorer and back does not re-read the games list.
      final link = ref.keepAlive();
      final timer = Timer(const Duration(minutes: 3), link.close);
      ref.onDispose(timer.cancel);
      return analysis;
    });
