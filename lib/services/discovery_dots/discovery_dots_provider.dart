import 'dart:async';
import 'dart:convert';

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/services/attention_policy.dart';
import 'package:chessever2/services/discovery_dots/discovery_dot.dart';
import 'package:chessever2/services/firebase_app.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Remote Config key holding the published dots, edited from the admin
/// console (Nudges). The value is `{"dots":[...],"targeted":[...]}`; see
/// [parseDiscoveryDots].
const discoveryDotsConfigKey = 'discovery_dots';

abstract interface class DiscoveryDotsSource {
  /// Last activated value, available without a network round trip.
  Future<String> initialize();
  Future<String> fetch();
  Stream<String> get updates;
}

class FirebaseDiscoveryDotsSource implements DiscoveryDotsSource {
  late FirebaseRemoteConfig _config;

  @override
  Future<String> initialize() async {
    await ensureFirebaseInitialized();
    _config = FirebaseRemoteConfig.instance;
    // No setDefaults here: it replaces the defaults other features installed,
    // and a missing key already reads as the empty string.
    await _config.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: kDebugMode
            ? const Duration(minutes: 1)
            : const Duration(hours: 1),
      ),
    );
    return _config.getString(discoveryDotsConfigKey);
  }

  @override
  Future<String> fetch() async {
    await _config.fetchAndActivate();
    return _config.getString(discoveryDotsConfigKey);
  }

  @override
  Stream<String> get updates => _config.onConfigUpdated
      .where((update) => update.updatedKeys.contains(discoveryDotsConfigKey))
      .asyncMap((_) async {
        await _config.activate();
        return _config.getString(discoveryDotsConfigKey);
      });
}

/// Device-local memory of which dots were tapped, and at which revision.
class DiscoveryDotsSeenStore {
  const DiscoveryDotsSeenStore() : _key = 'discovery_dots_seen.v1';

  /// The same kind of map, holding when each dot was first received; see
  /// [discoveryDotDeliveryKey].
  const DiscoveryDotsSeenStore.deliveries()
    : _key = 'discovery_dots_delivered.v1';

  final String _key;

  /// Read synchronously from the preferences loaded at startup, so a dismissed
  /// dot never paints for a frame on the next launch.
  Map<String, int> read() {
    final raw = SharedPreferencesService.instance.prefsOrNull?.getString(_key);
    if (raw == null) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const {};
      return {
        for (final entry in decoded.entries)
          if (entry.value is int) entry.key: entry.value as int,
      };
    } on FormatException {
      return const {};
    }
  }

  Future<void> write(Map<String, int> seen) async {
    try {
      final prefs = await SharedPreferencesService.instance.ensureInitialized();
      await prefs?.setString(_key, jsonEncode(seen));
    } catch (e) {
      debugPrint('[DiscoveryDots] dismissal not saved: $e');
    }
  }
}

/// Asks the server which targeted dots are meant for the signed-in person.
abstract interface class DiscoveryAudienceMatcher {
  /// [audiences] maps a dot id to its audience id; returns the dot ids that
  /// match.
  Future<Set<String>> match(Map<String, String> audiences);
}

/// The database looks up each audience and checks it against the caller's own
/// account only, with the same rules as the console's Inbox and Notifications
/// audiences.
class SupabaseDiscoveryAudienceMatcher implements DiscoveryAudienceMatcher {
  const SupabaseDiscoveryAudienceMatcher();

  @override
  Future<Set<String>> match(Map<String, String> audiences) async {
    final ids = await Supabase.instance.client
        .rpc('match_editorial_audiences', params: {'p_audiences': audiences})
        .timeout(const Duration(seconds: 10));
    return {
      if (ids is List)
        for (final id in ids)
          if (id is String) id,
    };
  }
}

final discoveryAudienceMatcherProvider = Provider<DiscoveryAudienceMatcher>(
  (ref) => const SupabaseDiscoveryAudienceMatcher(),
);

/// Whose audiences are checked: the account in use, guests included.
final discoveryAudienceViewerProvider = Provider<String?>(
  (ref) => ref.watch(currentUserProvider)?.id,
);

final discoveryDotsSourceProvider = Provider<DiscoveryDotsSource>(
  (ref) => FirebaseDiscoveryDotsSource(),
);

final discoveryDotsSeenStoreProvider = Provider<DiscoveryDotsSeenStore>(
  (ref) => const DiscoveryDotsSeenStore(),
);

final discoveryDotsDeliveryStoreProvider = Provider<DiscoveryDotsSeenStore>(
  (ref) => const DiscoveryDotsSeenStore.deliveries(),
);

class DiscoveryDotsState {
  const DiscoveryDotsState({this.dots = const [], this.seen = const {}})
    : _lit = null;

  DiscoveryDotsState._(this.dots, this.seen)
    : _lit = litDiscoveryAnchors(dots, seen);

  /// The campaign lighting now, at most one: see [nextDiscoveryDot].
  final List<DiscoveryDot> dots;
  final Map<String, int> seen;
  final Set<String>? _lit;

  /// Anchor ids that currently show a dot.
  Set<String> get lit => _lit ?? const {};
}

/// The dots published from the admin console, minus the ones this device has
/// already tapped. Empty until Firebase supplies a value, and empty forever if
/// it never does, so the feature costs nothing when nothing is published.
///
/// They follow the shared attention rules (`attention_policy.dart`): a new
/// account absorbs every dot published in its first week, and after that one
/// campaign lights at a time, the next waiting for the next launch.
final discoveryDotsProvider =
    NotifierProvider<DiscoveryDotsNotifier, DiscoveryDotsState>(
      DiscoveryDotsNotifier.new,
    );

class DiscoveryDotsNotifier extends Notifier<DiscoveryDotsState> {
  StreamSubscription<String>? _updates;
  bool _disposed = false;

  /// Every published dot, targeted ones included.
  List<DiscoveryDot> _all = const [];

  /// Targeted dot ids the server matched for [_matchedKey]; null while unknown.
  Set<String>? _matched;
  String? _matchedKey;
  int _matchRequest = 0;
  bool _watchingViewer = false;
  bool _watchingAccount = false;

  /// When this device first received each dot; see [nextDiscoveryDot].
  Map<String, int> _delivered = const {};

  /// Set once a campaign's target is reached. The next campaign waits for the
  /// next launch instead of lighting up straight after.
  bool _reachedThisSession = false;

  @override
  DiscoveryDotsState build() {
    _disposed = false;
    _all = const [];
    _matched = null;
    _matchedKey = null;
    _watchingViewer = false;
    _watchingAccount = false;
    _reachedThisSession = false;
    _delivered = ref.watch(discoveryDotsDeliveryStoreProvider).read();
    ref.onDispose(() {
      _disposed = true;
      unawaited(_updates?.cancel());
    });
    unawaited(_load(ref.watch(discoveryDotsSourceProvider)));
    return DiscoveryDotsState(
      seen: ref.watch(discoveryDotsSeenStoreProvider).read(),
    );
  }

  void _publish() {
    final visible = visibleDiscoveryDots(_all, _matched);
    var seen = state.seen;
    var lit = const <DiscoveryDot>[];
    if (visible.isNotEmpty) {
      _watchAccount();
      final createdAt = ref.read(accountCreatedAtProvider);
      final now = ref.read(attentionClockProvider)();
      if (createdAt == null) {
        // Nobody signed in yet: hold every dot rather than light one the
        // account turns out to be too new for.
      } else if (isQuietAccount(createdAt, now)) {
        seen = absorbDiscoveryDots(visible, seen);
        if (!mapEquals(seen, state.seen)) {
          unawaited(ref.read(discoveryDotsSeenStoreProvider).write(seen));
        }
      } else {
        final delivered = _deliver(visible, now);
        final next = _reachedThisSession
            ? null
            : nextDiscoveryDot(
                visible,
                seen: seen,
                delivered: delivered,
                now: now,
                shelfLife: announcementShelfLife,
              );
        if (next != null) lit = [next];
      }
    }
    state = DiscoveryDotsState._(lit, seen);
  }

  /// Only a published dot needs the account, so nothing reads it before one.
  void _watchAccount() {
    if (_watchingAccount) return;
    _watchingAccount = true;
    ref.listen<DateTime?>(accountCreatedAtProvider, (_, _) => _publish());
  }

  /// Remembers when this device first received each [visible] dot, and
  /// forgets dots no longer published.
  Map<String, int> _deliver(List<DiscoveryDot> visible, DateTime now) {
    final published = {for (final dot in _all) discoveryDotDeliveryKey(dot)};
    final next = {
      for (final entry in _delivered.entries)
        if (published.contains(entry.key)) entry.key: entry.value,
      for (final dot in visible)
        discoveryDotDeliveryKey(dot):
            _delivered[discoveryDotDeliveryKey(dot)] ??
            now.millisecondsSinceEpoch,
    };
    if (!mapEquals(next, _delivered)) {
      _delivered = next;
      unawaited(ref.read(discoveryDotsDeliveryStoreProvider).write(next));
    }
    return next;
  }

  void _apply(String raw) {
    if (_disposed) return;
    _all = parseDiscoveryDots(raw);
    _publish();
    if (!_all.any((dot) => dot.targeted)) return;
    // Only targeted dots need to know who is signed in, so nothing reads the
    // account until one is published.
    if (_watchingViewer) {
      unawaited(_match(ref.read(discoveryAudienceViewerProvider)));
      return;
    }
    _watchingViewer = true;
    ref.listen<String?>(
      discoveryAudienceViewerProvider,
      (_, viewer) => unawaited(_match(viewer)),
      fireImmediately: true,
    );
  }

  /// Asks which targeted dots are for [viewer]. Until the answer arrives, and
  /// whenever it cannot, targeted dots stay hidden.
  Future<void> _match(String? viewer) async {
    final audiences = {
      for (final dot in _all)
        if (dot.audienceId case final audienceId?) dot.id: audienceId,
    };
    final key = viewer == null ? null : '$viewer ${jsonEncode(audiences)}';
    if (key != null && key == _matchedKey) return;
    final request = ++_matchRequest;
    _matched = null;
    _matchedKey = null;
    _publish();
    if (key == null || audiences.isEmpty) return;
    try {
      final matched = await ref
          .read(discoveryAudienceMatcherProvider)
          .match(audiences);
      if (_disposed || request != _matchRequest) return;
      _matched = matched;
      _matchedKey = key;
      _publish();
    } catch (_) {
      debugPrint(
        '[DiscoveryDots] Audience check unavailable; targeted dots hidden.',
      );
    }
  }

  Future<void> _load(DiscoveryDotsSource source) async {
    try {
      final cached = await source.initialize();
      if (_disposed) return;
      _apply(cached);
      _updates = source.updates.listen(
        _apply,
        onError: (Object _) {
          debugPrint('[DiscoveryDots] Remote Config update unavailable.');
        },
      );
      try {
        _apply(await source.fetch());
      } catch (_) {
        // Keep the last activated dots on network failure.
        debugPrint('[DiscoveryDots] Remote Config fetch unavailable.');
      }
    } catch (_) {
      debugPrint('[DiscoveryDots] Remote Config unavailable; no dots shown.');
    }
  }

  /// Records that the user reached [anchor]. Returns the tooltip stack for
  /// every campaign completed at this target, in publication order.
  List<DiscoveryNudgeMessage> acknowledge(String anchor) {
    if (!state.lit.contains(anchor)) return const [];
    final result = acknowledgeDiscoveryAnchor(state.dots, anchor, state.seen);
    state = DiscoveryDotsState._(state.dots, result.seen);
    unawaited(ref.read(discoveryDotsSeenStoreProvider).write(result.seen));
    if (state.dots.any((dot) => (result.seen[dot.id] ?? 0) >= dot.rev)) {
      _reachedThisSession = true;
    }
    return result.messages;
  }
}
