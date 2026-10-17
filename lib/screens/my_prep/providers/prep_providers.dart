import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/services/prep_analysis.dart';
import 'package:chessever2/screens/my_prep/services/prep_index.dart';
import 'package:chessever2/screens/my_prep/services/prep_repository.dart';
import 'package:chessever2/screens/my_prep/services/prep_watch.dart';
import 'package:chessever2/services/game_tree/game_tree_registry.dart';
import 'package:chessever2/services/game_tree/game_tree_service.dart';
import 'package:chessever2/services/game_tree/game_tree_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// How often the reader's own accounts are brought up to date: three times
/// a day, against the server's daily refresh for everyone else.
const Duration kPrepMineRefreshEvery = Duration(hours: 8);

/// How stale an opponent's or favorite's games may be before opening it
/// checks for new ones.
const Duration kPrepOthersRefreshEvery = Duration(hours: 24);

/// The first wait after a failed download. Each further failure in a row
/// waits four times longer, up to [kPrepRetryMax]: 2 min, 8 min, 32 min,
/// about 2 h, about 8.5 h, then a day.
const Duration kPrepRetryFirst = Duration(minutes: 2);

/// The longest wait between background tries. A failure that asking again
/// cannot fix (a missing account, a too-large selection) waits this long at
/// once, so it still recovers by itself once the cause goes away.
const Duration kPrepRetryMax = Duration(hours: 24);

/// How often the open app looks for refreshes that have come due. The look
/// itself is local; only a due account reaches the server.
const Duration kPrepFreshnessTick = Duration(minutes: 2);

/// How long a background refresh waits after [failures] downloads failed in
/// a row (1 for the first). [roll] in [0, 1) spreads it by ±20%, so phones
/// that failed together during an outage do not all come back together.
/// The server's [retryAfter] is a floor.
Duration prepRetryDelay(
  int failures, {
  bool permanent = false,
  Duration? retryAfter,
  double? roll,
}) {
  final steps = (failures < 1 ? 1 : failures) - 1;
  final base = permanent
      ? kPrepRetryMax
      : Duration(
          milliseconds: math
              .min(
                kPrepRetryFirst.inMilliseconds *
                    math.pow(4, math.min(steps, 8)),
                kPrepRetryMax.inMilliseconds.toDouble(),
              )
              .round(),
        );
  final spread = 0.8 + 0.4 * (roll ?? math.Random().nextDouble());
  final delay = Duration(
    milliseconds: math.min(
      (base.inMilliseconds * spread).round(),
      kPrepRetryMax.inMilliseconds,
    ),
  );
  return retryAfter != null && retryAfter > delay ? retryAfter : delay;
}

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

  /// Server writes for stars, one at a time and in order.
  Future<void> _watchWriting = Future.value();

  /// Profiles whose star came off (or which were removed) while the server
  /// could not be told. Saved with the profiles and retried at the next
  /// launch, so an unstarred player never keeps notifying.
  final Set<String> _unwatchPending = {};

  @visibleForTesting
  Future<void> debugDrainWrites() => _writing;

  @visibleForTesting
  Future<void> debugDrainWatches() async {
    await _watchWriting;
    await _writing;
  }

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
      if (json is Map && json['unwatch'] is List) {
        _unwatchPending.addAll((json['unwatch'] as List).whereType<String>());
      }
      state = AsyncValue.data([
        if (json is Map && json['profiles'] is List)
          for (final raw in json['profiles'] as List)
            ?PrepProfile.fromJson(raw),
      ]);
      _reconcileWatches();
    } catch (error, stack) {
      debugPrint('[MyPrep] profiles failed to load: $error');
      state = AsyncValue.error(error, stack);
    }
  }

  void _set(List<PrepProfile> profiles) {
    final before = _profiles;
    state = AsyncValue.data(List.unmodifiable(profiles));
    _mirrorWatches(before, profiles);
    _persist(profiles);
  }

  void _persist(List<PrepProfile> profiles) {
    final unwatch = _unwatchPending.toList();
    // Serialized so an older snapshot can never land after a newer one.
    _writing = _writing.then((_) async {
      try {
        final file = await _file();
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(
          jsonEncode({
            'version': 1,
            'profiles': [for (final p in profiles) p.toJson()],
            if (unwatch.isNotEmpty) 'unwatch': unwatch,
          }),
          flush: true,
        );
        await temp.rename(file.path);
      } catch (error) {
        debugPrint('[MyPrep] profiles failed to save: $error');
      }
    });
  }

  // ---------------------------------------------------------------- stars

  /// Stars or unstars [profileId]. The server's copy follows on its own.
  void setWatching(String profileId, bool watching) =>
      edit(profileId, (p) => p.copyWith(watching: watching));

  /// A push arrived for [profileId]. If this device no longer stars it (or
  /// no longer has it), the server is told again, so the pushes stop.
  void settleWatch(String profileId) {
    final profile = byId(profileId);
    if (profile == null || prepWatchSignature(profile) == null) {
      _queueUnwatch(profileId);
    }
  }

  /// Tells the server about every star that changed between [before] and
  /// [after]: a new or edited starred profile is written again, one that
  /// lost its star, its online accounts or its place is cleared.
  void _mirrorWatches(List<PrepProfile> before, List<PrepProfile> after) {
    final was = <String, String>{
      for (final p in before)
        if (prepWatchSignature(p) case final signature?) p.id: signature,
    };
    final watched = <String>{};
    for (final p in after) {
      final signature = prepWatchSignature(p);
      if (signature == null) continue;
      watched.add(p.id);
      if (signature != was[p.id]) _queueWatch(p.id);
    }
    for (final id in was.keys) {
      if (!watched.contains(id)) _queueUnwatch(id);
    }
  }

  /// Once per launch: retries the unstars that did not reach the server and
  /// writes every star again, which also carries today's UTC offset.
  void _reconcileWatches() {
    for (final id in _unwatchPending.toList()) {
      _queueUnwatch(id);
    }
    for (final p in _profiles) {
      if (prepWatchSignature(p) != null) _queueWatch(p.id);
    }
  }

  void _queueWatch(String profileId) {
    if (_unwatchPending.remove(profileId)) _persist(_profiles);
    _watchWriting = _watchWriting.then((_) async {
      if (!mounted) return;
      // The newest copy: it may have changed while earlier writes ran.
      final profile = byId(profileId);
      if (profile == null || prepWatchSignature(profile) == null) return;
      // A failure is retried by the next launch's reconcile.
      await _ref.read(prepWatchRemoteProvider).watch(profile);
    });
  }

  void _queueUnwatch(String profileId) {
    if (_unwatchPending.add(profileId)) _persist(_profiles);
    _watchWriting = _watchWriting.then((_) async {
      if (!mounted) return;
      final profile = byId(profileId);
      if (profile != null && prepWatchSignature(profile) != null) {
        // Starred again since: the watch queued with it wins.
        if (_unwatchPending.remove(profileId)) _persist(_profiles);
        return;
      }
      final done = await _ref.read(prepWatchRemoteProvider).unwatch(profileId);
      if (done && mounted && _unwatchPending.remove(profileId)) {
        _persist(_profiles);
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

  /// Background refreshes waiting their turn, as (profile id, account key).
  /// They run one at a time, so a launch with many stale accounts sends
  /// one download after another instead of all of them at once.
  final List<(String, String)> _queue = [];
  bool _draining = false;

  Future<void> cancelAndWait(PrepAccount account) async {
    cancel(account);
    await _running[account.key]?.future;
  }

  bool isSyncing(PrepAccount account) => state.containsKey(account.key);

  /// Downloads new games for one account. Returns the error text, or null.
  ///
  /// Every failure pushes the account's next background try out along
  /// [prepRetryDelay]; a success resets it. A [background] refresh was not
  /// asked for by the reader, so its failure is never shown on the account:
  /// the games already downloaded stay as they were.
  Future<String?> syncAccount(
    String profileId,
    PrepAccount account, {
    bool force = false,
    bool reinstall = false,
    bool background = false,
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
            syncedScope: live.preferences == account.preferences
                ? synced.syncedScope
                : 'stale',
            gameCount: synced.gameCount,
            clearError: true,
            clearRetry: true,
          ),
        );
      });
      return null;
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) return null;
      final code = error.response?.statusCode;
      return _fail(
        profileId,
        account,
        'Could not download games. Try again.',
        background: background,
        // A refused request stays refused; a timeout, a dropped connection
        // or a server error may pass.
        permanent:
            code != null &&
            code >= 400 &&
            code < 500 &&
            code != 408 &&
            code != 429,
        retryAfter: code == 429
            ? prepRetryAfter(error.response?.headers)
            : null,
      );
    } on PrepException catch (error) {
      return _fail(
        profileId,
        account,
        error.message,
        background: background,
        permanent: error.permanent,
        retryAfter: error.retryAfter,
      );
    } catch (error) {
      debugPrint('[MyPrep] sync failed: $error');
      return _fail(
        profileId,
        account,
        'Could not download games. Try again.',
        background: background,
      );
    } finally {
      if (mounted) state = {...state}..remove(account.key);
      _running.remove(account.key);
      done.complete();
    }
  }

  String _fail(
    String profileId,
    PrepAccount account,
    String message, {
    required bool background,
    bool permanent = false,
    Duration? retryAfter,
  }) {
    if (background) debugPrint('[MyPrep] background refresh failed: $message');
    final now = DateTime.now().millisecondsSinceEpoch;
    _ref.read(prepProfilesProvider.notifier).edit(profileId, (p) {
      // Detached while it ran: nothing to record.
      final live = p.accounts.where((a) => a.key == account.key).firstOrNull;
      if (live == null) return p;
      final failures = live.failedAttempts + 1;
      return p.replaceAccount(
        live.copyWith(
          error: background ? null : message,
          failedAttempts: failures,
          retryAtMs:
              now +
              prepRetryDelay(
                failures,
                permanent: permanent,
                retryAfter: retryAfter,
              ).inMilliseconds,
        ),
      );
    });
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

  /// Brings stale profiles up to date in the background: the reader's own
  /// accounts every [kPrepMineRefreshEvery], the rest daily. They download
  /// one at a time. A failed one waits out its [PrepAccount.retryAtMs]
  /// first; an account still carrying an earlier failure is tried as well,
  /// so a success clears it.
  void refreshStale(Iterable<PrepProfile> profiles) {
    final now = DateTime.now();
    for (final profile in profiles) {
      for (final account in profile.accounts) {
        final entry = (profile.id, account.key);
        if (!_due(profile, account, now) ||
            isSyncing(account) ||
            _queue.contains(entry)) {
          continue;
        }
        _queue.add(entry);
      }
    }
    unawaited(_drain());
  }

  /// Whether a background refresh should fetch [account] at [now].
  static bool _due(PrepProfile profile, PrepAccount account, DateTime now) {
    if (account.source == PrepSource.manual) return false;
    final last = account.lastSyncAtMs;
    // Connecting fetches metadata only. The first download is explicit,
    // as on desktop; freshness applies once the reader has downloaded.
    if (last == null) return false;
    final at = now.millisecondsSinceEpoch;
    if (account.retryAtMs case final retryAt? when at < retryAt) return false;
    final every = profile.kind == PrepKind.mine
        ? kPrepMineRefreshEvery
        : kPrepOthersRefreshEvery;
    return at - last >= every.inMilliseconds ||
        account.syncedScope != account.downloadScope(now);
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (mounted && _queue.isNotEmpty) {
        final (profileId, key) = _queue.removeAt(0);
        final profile = _ref
            .read(prepProfilesProvider.notifier)
            .byId(profileId);
        final account = profile?.accounts
            .where((a) => a.key == key)
            .firstOrNull;
        // Looked at again: since it was queued it may have been refreshed
        // by the reader, detached, or failed.
        if (profile == null ||
            account == null ||
            !_due(profile, account, DateTime.now())) {
          continue;
        }
        await syncAccount(profileId, account, background: true);
      }
    } finally {
      _draining = false;
    }
  }

  void cancel(PrepAccount account) {
    state[account.key]?.cancel?.cancel('Canceled by the reader');
  }
}

// ------------------------------------------------------------------ freshness

/// Keeps prepared players' games current while the app runs, as desktop
/// does: a little after launch, whenever the app comes back to the
/// foreground, and every [kPrepFreshnessTick] while it stays open, stale
/// accounts fetch only their new games (yours every [kPrepMineRefreshEvery],
/// opponents every [kPrepOthersRefreshEvery]). The tick is what lets a
/// failed refresh recover on its own once its wait is over. Watch it from
/// the home shell.
final prepKeepFreshProvider = Provider<void>((ref) {
  var launched = false;
  void check() {
    // Never from the background: the system would cut the download off.
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    final profiles = ref.read(prepProfilesProvider).valueOrNull;
    if (profiles == null || profiles.isEmpty) return;
    ref
        .read(prepSyncProvider.notifier)
        .refreshStale(profiles.where((p) => p.kind != PrepKind.favorite));
  }

  Timer? tick;
  // Not on the first frame: launch has enough to do already.
  final launch = Timer(const Duration(seconds: 10), () {
    launched = true;
    check();
    tick = Timer.periodic(kPrepFreshnessTick, (_) => check());
  });
  final lifecycle = AppLifecycleListener(
    onResume: () {
      if (launched) check();
    },
  );
  ref.onDispose(() {
    launch.cancel();
    tick?.cancel();
    lifecycle.dispose();
  });
});

// ------------------------------------------------------------------ analysis

/// What a profile's analysis depends on: its accounts' stored games.
String _analysisKey(PrepProfile profile) => [
  profile.aliases.toList()..sort(),
  profile.fideId,
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
          shared: store.sharedGames,
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
