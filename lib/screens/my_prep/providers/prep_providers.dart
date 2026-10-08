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

final prepRepositoryProvider = Provider<PrepRepository>((ref) {
  final repo = PrepRepository(ref.read(gamebaseRepositoryProvider));
  ref.onDispose(repo.dispose);
  return repo;
});

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

class PrepProfilesNotifier
    extends StateNotifier<AsyncValue<List<PrepProfile>>> {
  PrepProfilesNotifier(this._ref) : super(const AsyncValue.loading()) {
    unawaited(_load());
  }

  final Ref _ref;
  Future<void> _writing = Future.value();

  @visibleForTesting
  Future<void> debugDrainWrites() => _writing;

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
          for (final raw in json['profiles'] as List)
            ?PrepProfile.fromJson(raw),
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
    final key = '${source.name}:${username.trim().toLowerCase()}';
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
    if (!state.hasValue) {
      throw const PrepException('Wait for your saved profiles to load.');
    }
    for (final account in accounts) {
      if (owning(account.source, account.externalId ?? account.username) !=
          null) {
        throw const PrepException(
          'This source is already attached to another profile.',
        );
      }
    }
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

  /// Attachment invariants live here as well as in the picker: async lookups
  /// and multiple routes must never share one source file between profiles.
  void attach(String profileId, Iterable<PrepAccount> accounts) {
    final current = byId(profileId);
    if (current == null) throw const PrepException('This profile was removed.');
    final incoming = accounts.toList();
    final known = {for (final account in current.accounts) account.key};
    var hasDatabase = current.databaseAccount != null;
    for (final account in incoming) {
      if (!known.add(account.key)) {
        throw const PrepException('This source is already attached.');
      }
      final owner = owning(
        account.source,
        account.externalId ?? account.username,
      );
      if (owner != null && owner.id != profileId) {
        throw PrepException('This source is already in ${owner.name}.');
      }
      if (account.source == PrepSource.chessever) {
        if (hasDatabase) {
          throw const PrepException(
            'Detach the current ChessEver source first.',
          );
        }
        if (current.fideId != null && current.fideId != account.fideId) {
          throw PrepException(
            'This profile belongs to FIDE ${current.fideId}. Choose that player.',
          );
        }
        hasDatabase = true;
      }
    }
    update(current.copyWith(accounts: [...current.accounts, ...incoming]));
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
    _ref.read(prepCloudSyncProvider.notifier).cancel(profileId);
    _set([
      for (final p in _profiles)
        if (p.id != profileId) p,
    ]);
    for (final account in profile.accounts) {
      await _ref.read(prepSyncProvider.notifier).cancelAndWait(account);
      await GameTreeService.cancel(PrepIndex.accountScope(account));
    }
    await GameTreeService.cancel(profileId);
    await PrepIndex.forget(profileId, accounts: profile.accounts);
    final repo = _ref.read(prepRepositoryProvider);
    for (final account in profile.accounts) {
      await repo.deleteGames(account);
    }
  }

  Future<void> removeAccount(String profileId, PrepAccount account) async {
    _ref.read(prepCloudSyncProvider.notifier).cancel(profileId);
    await _ref.read(prepSyncProvider.notifier).cancelAndWait(account);
    await GameTreeService.cancel(PrepIndex.accountScope(account));
    await GameTreeService.cancel(profileId);
    edit(
      profileId,
      (p) => p.copyWith(
        accounts: [
          for (final a in p.accounts)
            if (a.key != account.key) a,
        ],
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

  final Map<String, Completer<void>> _running = {};

  Future<void> cancelAndWait(PrepAccount account) async {
    cancel(account);
    await _running[account.key]?.future;
  }

  bool isSyncing(PrepAccount account) => state.containsKey(account.key);

  /// Downloads new games for one account. Returns the error text, or null.
  Future<String?> syncAccount(
    String profileId,
    PrepAccount account, {
    bool force = false,
    bool reinstall = false,
  }) async {
    if (isSyncing(account)) return null;
    final profiles = _ref.read(prepProfilesProvider.notifier);
    final profile = profiles.byId(profileId);
    if (profile == null || !profile.accounts.any((a) => a.key == account.key)) {
      return null;
    }
    if (account.source == PrepSource.manual) return null;
    final done = Completer<void>();
    _running[account.key] = done;
    final cancel = CancelToken();
    void report(String message) {
      if (!mounted) return;
      state = {
        ...state,
        account.key: PrepSyncStatus(message: message, cancel: cancel),
      };
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
            reinstall: reinstall,
          );
      profiles.edit(profileId, (p) {
        final live = p.accounts.where((a) => a.key == account.key).firstOrNull;
        if (live == null) return p;
        // Keep any download options changed while this ran; the next sync
        // notices the new scope and replaces the games.
        return p.replaceAccount(
          live.copyWith(
            lastSyncAtMs: synced.lastSyncAtMs,
            syncedScope:
                account.source == PrepSource.chessever ||
                    live.preferences == account.preferences
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
      _running.remove(account.key);
      done.complete();
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
        if (account.source == PrepSource.manual) continue;
        final last = account.lastSyncAtMs;
        final stale =
            last == null ||
            now - last >= every.inMilliseconds ||
            (account.source.online &&
                account.syncedScope !=
                    account.preferences.scopeKey(DateTime.now()));
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
  profile.aliases.toList()..sort(),
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
      return ref.watch(
        prepSourceAnalysisProvider((
          profileId: profileId,
          accountKey: null,
        )).future,
      );
    });

/// A source selection reads its own index, rather than filtering Combined.
/// Combined may deduplicate a game also present in an imported PGN; that game
/// must still appear when the reader selects the original source itself.
final prepSourceAnalysisProvider = FutureProvider.autoDispose
    .family<PrepAnalysis, ({String profileId, String? accountKey})>((
      ref,
      selection,
    ) async {
      final profileId = selection.profileId;
      final key = ref.watch(
        prepProfileProvider(
          profileId,
        ).select((p) => p == null ? null : _analysisKey(p)),
      );
      final profile = ref.read(prepProfileProvider(profileId));
      if (profile == null || key == null) return PrepAnalysis.empty(profileId);
      final account = profile.accounts
          .where((a) => a.key == selection.accountKey)
          .firstOrNull;
      if (selection.accountKey != null && account == null) {
        return PrepAnalysis.empty(profileId);
      }
      final scope = account == null
          ? profileId
          : PrepIndex.accountScope(account);
      final status = ref.read(gameTreeStatusProvider.notifier);
      final repo = ref.read(prepRepositoryProvider);
      // Register lifecycle callbacks before the first await. A reader can
      // leave during indexing; that must not register callbacks on a dead Ref.
      final link = ref.keepAlive();
      Timer? cacheTimer;
      var disposed = false;
      ref.onDispose(() {
        disposed = true;
        cacheTimer?.cancel();
      });
      try {
        GameTreeStore store;
        try {
          void progress(double fraction) => status.set(
            scope,
            GameTreeStatus(phase: GameTreePhase.indexing, fraction: fraction),
          );
          store = account == null
              ? await PrepIndex.ensureProfile(
                  repo,
                  profile,
                  onProgress: progress,
                )
              : await PrepIndex.ensureAccount(
                  repo,
                  profile,
                  account,
                  onProgress: progress,
                );
        } on GameTreeCanceled {
          // Stopped from the tree button: show what is indexed so far; the
          // next open picks up where it stopped.
          final partial = GameTreeRegistry.storeFor(scope);
          if (partial == null) rethrow;
          store = partial;
        } finally {
          status.clear(scope);
        }
        final rows = await store.loadGames();
        final analysis = PrepAnalysis(
          profileId: scope,
          store: store,
          games: List.unmodifiable([
            for (var i = 0; i < rows.length; i++)
              PrepGame.fromIndex(rows[i], i),
          ]),
        );
        if (!disposed) {
          cacheTimer = Timer(const Duration(minutes: 3), link.close);
        }
        return analysis;
      } catch (_) {
        link.close();
        rethrow;
      }
    });
