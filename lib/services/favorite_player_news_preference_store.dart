import 'news_binding_store.dart';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Installation-local only. Never restored from an account preference table.
class FavoritePlayerNewsPreferenceStore {
  static const key = 'news_about_favorite_players_v1';
  static const stateKey = 'direct_push_news_lifecycle_v1';
  static const defaultValue = true;
  static Future<void>? _writes;

  Future<FavoritePlayerNewsRegistrationState> load() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(stateKey);
    if (encoded != null) {
      // Corrupt durable lifecycle state must not reset its monotonic fence.
      return FavoritePlayerNewsRegistrationState.fromJson(
        Map<String, dynamic>.from(jsonDecode(encoded) as Map),
      );
    }
    return FavoritePlayerNewsRegistrationState(
      enabled: prefs.getBool(key) ?? defaultValue,
      owner: prefs.getString('direct_push_owner'),
      detachPending: prefs.getBool('direct_push_detach_pending') ?? false,
    );
  }

  Future<bool> read() async => (await load()).enabled;

  /// All foreground writers share this short local queue, not the network queue.
  /// Thus a newer choice/auth barrier can be saved while an HTTP call is in flight.
  Future<FavoritePlayerNewsRegistrationState> update(
    void Function(FavoritePlayerNewsRegistrationState) change,
  ) {
    Future<FavoritePlayerNewsRegistrationState> perform() async {
      final state = await load();
      change(state);
      final saved = await (await SharedPreferences.getInstance()).setString(
        stateKey,
        jsonEncode(state.toJson()),
      );
      if (!saved) throw StateError('Notification sync state was not saved');
      return state;
    }

    final previous = _writes;
    final next = previous == null
        ? perform()
        : previous.catchError((Object _) {}).then((_) => perform());
    final barrier = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _writes = barrier;
    return next.whenComplete(() {
      // Release a drained queue rather than retaining a completed Future's
      // originating async zone across independent consumers/lifecycles.
      if (identical(_writes, barrier)) _writes = null;
    });
  }

  Future<void> write(bool enabled) async {
    await NewsBindingStore().clear();
    await update((state) {
      state.enabled = enabled;
      state.choice++;
      state.clearAck();
    });
  }
}

class FavoritePlayerNewsRegistrationState {
  FavoritePlayerNewsRegistrationState({
    this.enabled = true,
    this.choice = 0,
    this.revision = 0,
    this.owner,
    this.detachPending = false,
    this.ackOwner,
    this.ackChoice,
    this.ackRevision,
    this.ackInstallation,
  });

  bool enabled;
  int choice;
  int revision;
  String? owner;
  bool detachPending;
  String? ackOwner;
  int? ackChoice;
  int? ackRevision;
  String? ackInstallation;

  void clearAck() {
    ackOwner = null;
    ackChoice = null;
    ackRevision = null;
    ackInstallation = null;
  }

  factory FavoritePlayerNewsRegistrationState.fromJson(
    Map<String, dynamic> data,
  ) {
    final revision = data['revision'];
    final choice = data['choice'];
    if (revision is! int ||
        revision < 0 ||
        revision > 9007199254740991 ||
        choice is! int ||
        choice < 0 ||
        data['enabled'] is! bool ||
        data['detachPending'] is! bool) {
      throw const FormatException('Invalid persisted notification lifecycle');
    }
    return FavoritePlayerNewsRegistrationState(
      enabled: data['enabled'] as bool,
      choice: choice,
      revision: revision,
      owner: data['owner'] as String?,
      detachPending: data['detachPending'] as bool,
      ackOwner: data['ackOwner'] as String?,
      ackChoice: data['ackChoice'] as int?,
      ackRevision: data['ackRevision'] as int?,
      ackInstallation: data['ackInstallation'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'choice': choice,
    'revision': revision,
    'owner': owner,
    'detachPending': detachPending,
    'ackOwner': ackOwner,
    'ackChoice': ackChoice,
    'ackRevision': ackRevision,
    'ackInstallation': ackInstallation,
  };
}
