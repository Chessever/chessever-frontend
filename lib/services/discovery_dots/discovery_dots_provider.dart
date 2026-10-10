import 'dart:async';
import 'dart:convert';

import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/services/discovery_dots/discovery_dot.dart';
import 'package:chessever2/services/firebase_app.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Remote Config key holding the published dots, edited from the admin
/// console (Nudges). The value is `{"dots":[...]}`; see [parseDiscoveryDots].
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
  const DiscoveryDotsSeenStore();

  static const _key = 'discovery_dots_seen.v1';

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

final discoveryDotsSourceProvider = Provider<DiscoveryDotsSource>(
  (ref) => FirebaseDiscoveryDotsSource(),
);

final discoveryDotsSeenStoreProvider = Provider<DiscoveryDotsSeenStore>(
  (ref) => const DiscoveryDotsSeenStore(),
);

class DiscoveryDotsState {
  const DiscoveryDotsState({this.dots = const [], this.seen = const {}})
    : _lit = null;

  DiscoveryDotsState._(this.dots, this.seen)
    : _lit = litDiscoveryAnchors(dots, seen);

  final List<DiscoveryDot> dots;
  final Map<String, int> seen;
  final Set<String>? _lit;

  /// Anchor ids that currently show a dot.
  Set<String> get lit => _lit ?? const {};
}

/// The dots published from the admin console, minus the ones this device has
/// already tapped. Empty until Firebase supplies a value, and empty forever if
/// it never does, so the feature costs nothing when nothing is published.
final discoveryDotsProvider =
    NotifierProvider<DiscoveryDotsNotifier, DiscoveryDotsState>(
      DiscoveryDotsNotifier.new,
    );

class DiscoveryDotsNotifier extends Notifier<DiscoveryDotsState> {
  StreamSubscription<String>? _updates;
  bool _disposed = false;

  @override
  DiscoveryDotsState build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      unawaited(_updates?.cancel());
    });
    unawaited(_load(ref.watch(discoveryDotsSourceProvider)));
    return DiscoveryDotsState(
      seen: ref.watch(discoveryDotsSeenStoreProvider).read(),
    );
  }

  void _apply(String raw) {
    if (_disposed) return;
    state = DiscoveryDotsState._(parseDiscoveryDots(raw), state.seen);
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

  /// Records that the user reached [anchor]. Returns the message to show when
  /// that completed a dot which carries one.
  String? acknowledge(String anchor) {
    if (!state.lit.contains(anchor)) return null;
    final result = acknowledgeDiscoveryAnchor(state.dots, anchor, state.seen);
    state = DiscoveryDotsState._(state.dots, result.seen);
    unawaited(ref.read(discoveryDotsSeenStoreProvider).write(result.seen));
    return result.message;
  }
}
