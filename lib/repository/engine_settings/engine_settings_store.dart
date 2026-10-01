import 'dart:async';
import 'dart:convert';

import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Include the flavor/project even though native flavors have separate sandboxes.
typedef EngineSettingsScope = ({String environment, String? userId});

const engineSettingsDefaults = <String, dynamic>{
  'showEngineGauge': true,
  'showEngineGaugeOnBoard': true,
  'showEngineGaugeInGrid': true,
  'showDepthOverlay': true,
  'showPvArrows': true,
  'showEngineAnalysis': true,
  'searchTimeIndex': 0,
  'engineLinesView': 1,
  'principalVariationIndex': 4,
  'maxArrowsOnBoard': 2,
};

const _cloudColumns = <String, String>{
  'showEngineGauge': 'show_engine_gauge',
  'showDepthOverlay': 'show_depth_overlay',
  'showPvArrows': 'show_pv_arrows',
  'showEngineAnalysis': 'show_engine_analysis',
  'searchTimeIndex': 'search_time_index',
  'engineLinesView': 'engine_lines_view_index',
  'principalVariationIndex': 'principal_variation_index',
  'maxArrowsOnBoard': 'max_arrows_on_board',
};

/// Decode each field independently; a missing/new/malformed field must not
/// discard a valid thinking time. Invalid indices fall back, not to infinity.
Map<String, dynamic> validEngineSettingsFields(Map<String, dynamic> input) {
  final result = <String, dynamic>{};
  for (final key in engineSettingsDefaults.keys) {
    final value = input[key];
    if (engineSettingsDefaults[key] is bool) {
      if (value is bool) result[key] = value;
    } else {
      final max = switch (key) {
        'searchTimeIndex' => 5,
        'engineLinesView' => 1,
        _ => 4,
      };
      if (value is int && value >= 0 && value <= max) result[key] = value;
    }
  }
  return result;
}

abstract interface class EngineSettingsCache {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

class SqliteEngineSettingsCache implements EngineSettingsCache {
  @override
  Future<String?> read(String key) => AppDatabase.instance.getString(key);

  @override
  Future<void> write(String key, String value) =>
      AppDatabase.instance.setString(key, value);

  @override
  Future<void> remove(String key) => AppDatabase.instance.remove(key);
}

class EngineSettingsRemote {
  const EngineSettingsRemote(this.fields, {this.updatedAt});

  final Map<String, dynamic> fields;
  final DateTime? updatedAt;
}

abstract interface class EngineSettingsBackend {
  Future<EngineSettingsRemote?> fetch(String userId);
  Future<EngineSettingsRemote> save(
    String userId,
    Map<String, dynamic> changedFields,
    DateTime updatedAt,
  );
}

class SupabaseEngineSettingsBackend implements EngineSettingsBackend {
  SupabaseEngineSettingsBackend(this.client);

  final SupabaseClient client;

  void _checkAccount(String userId) {
    if (client.auth.currentUser?.id != userId) {
      throw StateError('Engine settings account changed');
    }
  }

  EngineSettingsRemote _decode(Map<String, dynamic> row) {
    return EngineSettingsRemote(
      validEngineSettingsFields({
        for (final entry in _cloudColumns.entries) entry.key: row[entry.value],
      }),
      updatedAt: DateTime.tryParse(row['updated_at']?.toString() ?? ''),
    );
  }

  @override
  Future<EngineSettingsRemote?> fetch(String userId) async {
    _checkAccount(userId);
    final row = await client
        .from('user_engine_settings')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    _checkAccount(userId);
    return row == null ? null : _decode(row);
  }

  @override
  Future<EngineSettingsRemote> save(
    String userId,
    Map<String, dynamic> changedFields,
    DateTime updatedAt,
  ) async {
    _checkAccount(userId);
    // Partial upsert: never overwrite unrelated cross-device/board settings
    // from a local full snapshot. Surface flags are never cloud columns.
    final row = await client
        .from('user_engine_settings')
        .upsert(
          {
            'user_id': userId,
            for (final entry in changedFields.entries)
              if (_cloudColumns.containsKey(entry.key))
                _cloudColumns[entry.key]!: entry.value,
            'updated_at': updatedAt.toUtc().toIso8601String(),
          },
          onConflict: 'user_id',
          defaultToNull: false,
        )
        .select()
        .single();
    _checkAccount(userId);
    return _decode(row);
  }
}

/// Durable outbox + snapshot in ONE SQLite value. Local commits and cloud
/// requests have separate serial lanes: a stalled network never blocks a local
/// selection, and an old acknowledgement cannot clear a newer field revision.
/// Keep one store per scope across provider rebuilds to preserve request order.
class EngineSettingsStore {
  EngineSettingsStore({
    required this.scope,
    required this.cache,
    required this.backend,
    this.importLegacySurfaces = false,
  });

  final EngineSettingsScope scope;
  final EngineSettingsCache cache;
  final EngineSettingsBackend backend;
  final bool importLegacySurfaces;
  static const legacyKey = 'cached_engine_settings';

  String get cacheKey =>
      'engine_settings_v2:${jsonEncode([scope.environment, scope.userId])}';

  Map<String, dynamic> _values = {...engineSettingsDefaults};
  Map<String, int> _pending = {};
  int _revision = 0;
  int _clearEpoch = 0;
  DateTime? _remoteVersion;
  bool _loaded = false;
  Future<void> _localTail = Future.value();
  Future<void> _syncTail = Future.value();

  Map<String, dynamic> get values => Map.unmodifiable(_values);

  Future<T> _local<T>(Future<T> Function() action) {
    final next = _localTail.then((_) => action());
    // Keep the lane usable after a disk error; callers still receive the error.
    _localTail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Map<String, dynamic> _decode(String? raw) {
    try {
      final decoded = jsonDecode(raw ?? 'null');
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _load() async {
    if (_loaded) return;
    final record = _decode(await cache.read(cacheKey));
    if (record['schema'] == 2 && record['values'] is Map<String, dynamic>) {
      _values = {
        ...engineSettingsDefaults,
        ...validEngineSettingsFields(record['values'] as Map<String, dynamic>),
      };
      final revisions = record['pending'];
      if (revisions is Map<String, dynamic>) {
        for (final entry in revisions.entries) {
          final revision = entry.value;
          if (_cloudColumns.containsKey(entry.key) &&
              revision is int &&
              revision > 0 &&
              validEngineSettingsFields(
                record['values'],
              ).containsKey(entry.key)) {
            _pending[entry.key] = revision;
            if (revision > _revision) _revision = revision;
          }
        }
      }
      final revision = record['revision'];
      if (revision is int && revision > _revision) _revision = revision;
      _remoteVersion = DateTime.tryParse(
        record['remoteVersion']?.toString() ?? '',
      );
    } else if (importLegacySurfaces) {
      // The old global snapshot has NO owner and survives sign-out. It cannot
      // safely seed ANY account's synced fields (including a logged-out guest).
      // Only explicitly device-local surface choices can be carried forward.
      final legacy = validEngineSettingsFields(
        _decode(await cache.read(legacyKey)),
      );
      for (final key in ['showEngineGaugeOnBoard', 'showEngineGaugeInGrid']) {
        if (legacy.containsKey(key)) _values[key] = legacy[key];
      }
    }
    _loaded = true;
  }

  Future<Map<String, dynamic>> loadLocal() => _local(() async {
    await _load();
    return values;
  });

  Future<void> _write(
    Map<String, dynamic> values,
    Map<String, int> pending,
    int revision,
    DateTime? remoteVersion,
  ) async {
    await cache.write(
      cacheKey,
      jsonEncode({
        'schema': 2,
        'values': values,
        'pending': pending,
        'revision': revision,
        'remoteVersion': remoteVersion?.toUtc().toIso8601String(),
      }),
    );
    _values = values;
    _pending = pending;
    _revision = revision;
    _remoteVersion = remoteVersion;
  }

  Future<Map<String, dynamic>> change(Map<String, dynamic> patch) =>
      _local(() async {
        await _load();
        final valid = validEngineSettingsFields(patch);
        final revision = _revision + 1;
        final pending = {..._pending};
        if (scope.userId != null) {
          for (final key in valid.keys.where(_cloudColumns.containsKey)) {
            pending[key] = revision;
          }
        }
        await _write({..._values, ...valid}, pending, revision, _remoteVersion);
        return values;
      });

  bool _isFresh(EngineSettingsRemote remote) =>
      _remoteVersion == null ||
      (remote.updatedAt != null &&
          !remote.updatedAt!.isBefore(_remoteVersion!));

  Future<void> _merge(
    EngineSettingsRemote remote, {
    required int epoch,
    Map<String, int>? ack,
  }) => _local(() async {
    if (epoch != _clearEpoch) return;
    await _load();
    final pending = {..._pending};
    if (ack != null) {
      for (final entry in ack.entries) {
        // A 2xx is not an acknowledgement if a server constraint/trigger
        // changed the value. In particular, the legacy 5s trigger must
        // not silently erase a durable 20s choice on this device.
        if (pending[entry.key] == entry.value &&
            remote.fields[entry.key] == _values[entry.key]) {
          pending.remove(entry.key);
        }
      }
    }
    final values = {..._values};
    final fresh = _isFresh(remote);
    if (fresh) {
      for (final entry in validEngineSettingsFields(remote.fields).entries) {
        if (_cloudColumns.containsKey(entry.key) &&
            !pending.containsKey(entry.key)) {
          values[entry.key] = entry.value;
        }
      }
    }
    await _write(
      values,
      pending,
      _revision,
      fresh ? remote.updatedAt ?? _remoteVersion : _remoteVersion,
    );
  });

  /// Bounded retry on startup, explicit refresh, or a subsequent mutation.
  /// Failure retains the outbox on disk; there is no unhandled detached save.
  Future<void> sync() {
    final next = _syncTail.then((_) async {
      final userId = scope.userId;
      if (userId == null) return;
      final epoch = _clearEpoch;
      try {
        final remote = await backend.fetch(userId);
        if (remote != null) await _merge(remote, epoch: epoch);
        final snapshot = await _local(() async {
          await _load();
          return (
            pending: {..._pending},
            fields: {for (final key in _pending.keys) key: _values[key]},
            version: _remoteVersion,
          );
        });
        if (epoch != _clearEpoch || snapshot.pending.isEmpty) return;
        var version = DateTime.now().toUtc();
        if (snapshot.version != null && !version.isAfter(snapshot.version!)) {
          version = snapshot.version!.add(const Duration(microseconds: 1));
        }
        final saved = await backend.save(userId, snapshot.fields, version);
        await _merge(saved, epoch: epoch, ack: snapshot.pending);
      } catch (_) {
        // Do not log account IDs, backend response bodies, or settings values.
        debugPrint('[EngineSettings] Sync deferred; local outbox retained');
      }
    });
    _syncTail = next;
    return next;
  }

  Future<void> clear() => _local(() async {
    await cache.remove(cacheKey);
    ++_clearEpoch;
    _values = {...engineSettingsDefaults};
    _pending = {};
    _remoteVersion = null;
    // Never reuse a revision that an in-flight acknowledgement could carry.
    _loaded = true;
  });
}
