import 'dart:async';

import 'package:flutter/foundation.dart';

import 'news_binding_store.dart';
import 'favorite_player_news_preference_store.dart';
import 'favorite_player_news_token_sync.dart';

class DirectPushSession {
  const DirectPushSession(this.userId, this.accessToken);
  final String userId;
  final String accessToken;
}

class FavoritePlayerNewsSyncStatus {
  const FavoritePlayerNewsSyncStatus({
    this.enabled = true,
    this.confirmed = false,
  });
  final bool enabled;
  final bool confirmed;
  String get label => labelFor(enabled);
  String labelFor(bool? desired) => confirmed && enabled == desired
      ? 'Synced on this device'
      : 'Sync pending. Saved on this device, not yet confirmed by the notification service.';
}

/// The actual foreground lifecycle controller used by DirectPushService.
/// Platform readiness and HTTP are injected so failures/auth races execute in tests.
class DirectPushRegistrationController {
  DirectPushRegistrationController({
    required this.store,
    required this.transport,
    required this.readSession,
    required this.readProof,
    required this.readRegistration,
    this.maxAttempts = 6, // Initial attempt plus the existing five retries.
    this.retryDelay = const Duration(seconds: 5),
    this.readinessTimeout = const Duration(seconds: 3),
  });

  final NewsBindingStore binding = NewsBindingStore();
  final FavoritePlayerNewsPreferenceStore store;
  final DirectPushDeviceTransport transport;
  final DirectPushSession? Function() readSession;
  final Future<Map<String, String>> Function() readProof;
  final Future<Map<String, dynamic>?> Function() readRegistration;
  final int maxAttempts;
  final Duration retryDelay;
  final Duration readinessTimeout;
  final status = ValueNotifier(const FavoritePlayerNewsSyncStatus());
  Future<void> _queue = Future.value();
  Future<void> _authBarrier = Future.value();
  Future<void>? _loading;
  Map<String, String>? _proof;
  Timer? _retry;
  bool _disposed = false;
  bool _observed = false;
  bool _authPersistenceFailed = false;
  String? _observedUser;
  int _authEpoch = 0;
  int _attempts = 0;
  bool _registrationPending = true;
  int _registrationRequest = 0;

  @visibleForTesting
  int get failedAttempts => _attempts;

  Future<void> initialize() =>
      _loading ??= _initialize().catchError((Object error) {
        _loading = null;
        throw error;
      });
  Future<void> _initialize() async {
    _proof = await readProof();
    await _observeAuth();
    await _publish();
  }

  Future<void> _observeAuth() => _observeUser(readSession()?.userId);

  /// Consume each auth event's identity, not just the SDK's latest snapshot.
  /// A rapid sign-out/sign-in to the same account still needs a detach fence.
  Future<void> authChanged(String? userId) {
    final barrier = _observeUser(userId);
    return _afterAuthChanged(barrier);
  }

  Future<void> _afterAuthChanged(Future<void> barrier) async {
    try {
      await barrier;
      await sync(register: true, resetRetries: true);
    } catch (_) {
      _retryLater();
    }
  }

  Future<void> _observeUser(String? user) {
    final same = _observed && user == _observedUser;
    if (same && !_authPersistenceFailed) return _authBarrier;
    final clearAck = _observed;
    if (!same) {
      _observed = true;
      _observedUser = user;
      _authEpoch++;
      _registrationPending = true;
      _registrationRequest++;
      _resetRetry();
    }
    _authPersistenceFailed = false;
    final epoch = _authEpoch;
    if (!_disposed) {
      status.value = FavoritePlayerNewsSyncStatus(
        enabled: status.value.enabled,
      );
    }
    // Epoch changes synchronously, before waiting for storage or an in-flight
    // request. Its old response can never acknowledge this new identity.
    _authBarrier = _authBarrier
        .catchError((Object _) {})
        .then((_) async {
          if (clearAck || (await store.load()).owner != user) {
            await binding.clear();
          }
          await store.update((state) {
            if (state.owner != null && state.owner != user) {
              state.detachPending = true;
            }
            if (clearAck || state.ackOwner != user) state.clearAck();
          });
          await _publish();
        })
        .catchError((Object error) {
          if (epoch == _authEpoch) _authPersistenceFailed = true;
          throw error;
        });
    return _authBarrier;
  }

  bool _current(DirectPushSession session, int epoch) =>
      !_disposed &&
      epoch == _authEpoch &&
      readSession()?.userId == session.userId;

  bool _confirmed(FavoritePlayerNewsRegistrationState state) =>
      !state.detachPending &&
      state.owner != null &&
      readSession()?.userId == state.owner &&
      state.ackOwner == state.owner &&
      state.ackChoice == state.choice &&
      state.ackRevision != null &&
      state.ackInstallation == _proof?['installationId'];

  Future<void> _publish() async {
    if (_disposed) return;
    final state = await store.load();
    if (!_disposed) {
      status.value = FavoritePlayerNewsSyncStatus(
        enabled: state.enabled,
        confirmed: _confirmed(state),
      );
    }
  }

  void _resetRetry() {
    _attempts = 0;
    _retry?.cancel();
    _retry = null;
  }

  /// Resume/login/readiness events explicitly restart a bounded retry cycle.
  Future<void> sync({bool register = false, bool resetRetries = false}) async {
    if (_disposed) return;
    try {
      await initialize();
      final barrier = _observeAuth();
      if (register) {
        _registrationPending = true;
        _registrationRequest++;
      }
      if (resetRetries) _resetRetry();
      await barrier;
      final next = _queue.catchError((Object _) {}).then((_) => _run());
      _queue = next;
      await next;
    } catch (_) {
      // Storage/proof failures are pending too, never background unhandled
      // errors and never permission to reset the persisted revision fence.
      _retryLater();
    }
  }

  Future<void> preferenceChanged() async {
    await initialize();
    _resetRetry();
    await _publish();
    await sync();
    if (!status.value.confirmed) {
      throw StateError('Saved on this device. News alert sync is pending.');
    }
  }

  void _retryLater() {
    if (_disposed || ++_attempts >= maxAttempts) return;
    _retry?.cancel();
    _retry = Timer(retryDelay, () {
      _retry = null;
      unawaited(sync());
    });
  }

  Future<FavoritePlayerNewsRegistrationState> _nextRevision({String? owner}) =>
      store.update((state) {
        if (state.revision >= 9007199254740991) {
          throw StateError('Notification lifecycle revision exhausted');
        }
        state.revision++;
        if (owner != null) state.owner = owner;
      });

  Future<bool> _ackCategory(
    Map<String, dynamic> ack,
    FavoritePlayerNewsRegistrationState attempt,
    DirectPushSession session,
    int epoch,
  ) async {
    if (!validNewsDeviceAck(
      ack,
      installationId: _proof!['installationId']!,
      revision: attempt.revision,
      enabled: attempt.enabled,
    )) {
      throw const FormatException('Unconfirmed News device protocol');
    }
    var accepted = false;
    await store.update((state) {
      if (_current(session, epoch) &&
          !state.detachPending &&
          state.owner == session.userId &&
          state.choice == attempt.choice &&
          state.revision == attempt.revision) {
        state.ackOwner = session.userId;
        state.ackChoice = attempt.choice;
        state.ackRevision = attempt.revision;
        state.ackInstallation = _proof!['installationId'];
        accepted = true;
      }
    });
    return accepted;
  }

  Future<bool> _detachAttempt() async {
    await binding.clear();
    final attempt = await _nextRevision();
    final ack = await transport.post('/v1/devices/logout', {
      ..._proof!,
      'registrationRevision': attempt.revision,
    });
    if (!validNewsDeviceAck(
      ack,
      installationId: _proof!['installationId']!,
      revision: attempt.revision,
      detached: true,
    )) {
      throw const FormatException('Unconfirmed installation detach');
    }
    var detached = false;
    await store.update((state) {
      if (state.revision == attempt.revision && state.detachPending) {
        state.owner = null;
        state.detachPending = false;
        state.clearAck();
        detached = true;
      }
    });
    return detached;
  }

  Future<void> _beginBinding(
    Map<String, dynamic> registration,
    DirectPushSession session,
    int epoch,
  ) async {
    final attempt = await _nextRevision(owner: session.userId);
    if (!_current(session, epoch) ||
        !attempt.enabled ||
        attempt.detachPending) {
      return;
    }
    await store.update((state) => state.clearAck());
    final intent = <String, dynamic>{
      ...registration,
      'installationId': _proof!['installationId'],
      'userId': session.userId,
      'choice': attempt.choice,
      'registrationRevision': attempt.revision,
      'requestId': NewsBindingStore.requestId(),
      'expiresAt': DateTime.now()
          .add(const Duration(minutes: 5))
          .toIso8601String(),
    };
    // Persist BEFORE issue; mark issuance implicit in this durable intent so an
    // ambiguous HTTP response/restart never blindly resends the challenge.
    await binding.save(intent);
    if (!_current(session, epoch)) {
      await binding.clear();
      return;
    }
    await transport.post('/v1/devices/news-challenge', {
      ...registration,
      ..._proof!,
      'requestId': intent['requestId'],
      'registrationRevision': attempt.revision,
      'favoritePlayerNews': true,
    }, accessToken: session.accessToken);
    if (_current(session, epoch)) await _continueBinding(session, epoch);
  }

  /// True means an existing intent owns reconciliation, including waiting. Do
  /// not allocate fresh revisions on each retry and invalidate our own nonce.
  Future<bool> _continueBinding(DirectPushSession session, int epoch) async {
    // Fence before ANY asynchronous readiness/storage read: a token refresh
    // queued while that read is pending must not be consumed by an old snapshot.
    final registrationRequest = _registrationRequest;
    final active = await binding.intent();
    if (active == null) return false;
    final state = await store.load();
    final registration = await readRegistration().timeout(
      readinessTimeout,
      onTimeout: () => null,
    );
    if (!_current(session, epoch)) return true;
    if (_registrationRequest != registrationRequest) {
      await binding.clear();
      _registrationPending = true;
      return false;
    }
    if (state.detachPending ||
        !state.enabled ||
        state.owner != session.userId ||
        active['userId'] != session.userId ||
        active['installationId'] != _proof!['installationId'] ||
        active['choice'] != state.choice ||
        active['registrationRevision'] != state.revision ||
        !DateTime.parse(
          active['expiresAt'] as String,
        ).isAfter(DateTime.now()) ||
        (registration != null &&
            (registration['token'] != active['token'] ||
                registration['platform'] != active['platform'] ||
                registration['optedIn'] != active['optedIn']))) {
      await binding.clear();
      _registrationPending = true;
      return false;
    }
    // Current token/permission readiness must be re-read before confirmation.
    if (registration == null) return true;
    final callback = await binding.callback(active);
    if (callback == null) return true;
    final latest = await store.load();
    final latestIntent = await binding.intent();
    if (!_current(session, epoch)) return true;
    if (_registrationRequest != registrationRequest) {
      await binding.clear();
      _registrationPending = true;
      return false;
    }
    if (latest.detachPending ||
        !latest.enabled ||
        latest.choice != state.choice ||
        latest.revision != state.revision ||
        latestIntent?['requestId'] != active['requestId']) {
      return true;
    }
    final ack = await transport.post('/v1/devices/news-confirm', {
      ..._proof!,
      'token': active['token'],
      'platform': active['platform'],
      'requestId': active['requestId'],
      'challengeId': callback['challengeId'],
      'registrationRevision': active['registrationRevision'],
      'audience': NewsBindingStore.audience,
      'nonce': callback['nonce'],
    }, accessToken: session.accessToken);
    if (await _ackCategory(ack, state, session, epoch)) {
      await binding.clear();
      if (_registrationRequest == registrationRequest) {
        _registrationPending = false;
      }
      _resetRetry();
    }
    return true;
  }

  Future<void> _run() async {
    if (_disposed || _attempts >= maxAttempts) return;
    try {
      await _observeAuth();
      var state = await store.load();
      if (state.detachPending) {
        if (!await _detachAttempt()) {
          _retryLater();
          return;
        }
        _registrationPending = true;
        _registrationRequest++;
      }
      final session = readSession();
      final epoch = _authEpoch;
      if (session == null || _disposed) return;
      state = await store.load();
      if (await _continueBinding(session, epoch)) return;
      var categoryConfirmed = _confirmed(state);
      Object? preferenceFailure;
      if (!categoryConfirmed) {
        final attempt = await _nextRevision(owner: session.userId);
        if (!_current(session, epoch) || attempt.detachPending) return;
        try {
          final ack = await transport.post('/v1/devices/preferences', {
            ..._proof!,
            'registrationRevision': attempt.revision,
            'favoritePlayerNews': attempt.enabled,
          }, accessToken: session.accessToken);
          categoryConfirmed = await _ackCategory(ack, attempt, session, epoch);
        } catch (error) {
          preferenceFailure = error;
          // An invalid JWT cannot be retried as registration. A missing matching
          // installation may return 403; the normal registration reconciles it
          // using the SAME JWT and installation proof, never a weaker authority.
          if (error is DirectPushDeviceException && error.statusCode == 401) {
            rethrow;
          }
        }
        await _publish();
      }
      if (!_current(session, epoch)) return;
      if (_registrationPending) {
        final registrationRequest = _registrationRequest;
        // A stuck platform token call must not hold the installation request
        // queue forever and prevent a subsequent category-only opt-out.
        final registration = await readRegistration().timeout(
          readinessTimeout,
          onTimeout: () => null,
        );
        if (!_current(session, epoch)) return;
        if (registration == null) {
          _retryLater();
          return;
        }
        final attempt = await _nextRevision(owner: session.userId);
        if (!_current(session, epoch) || attempt.detachPending) return;
        Future<Map<String, dynamic>> register(Map<String, dynamic> data) =>
            transport.post('/v1/devices', {
              ...data,
              ..._proof!,
              'registrationRevision': attempt.revision,
              'favoritePlayerNews': attempt.enabled,
            }, accessToken: session.accessToken);
        Map<String, dynamic> ack;
        try {
          ack = await register(registration);
        } on DirectPushDeviceException catch (error) {
          if (error.statusCode != 400 ||
              !registration.containsKey('timezone')) {
            rethrow;
          }
          // Preserve the old timezone compatibility fallback, but allocate and
          // persist a NEW revision for this separate network attempt.
          if (!_current(session, epoch)) return;
          final fallback = await _nextRevision(owner: session.userId);
          if (!_current(session, epoch) || fallback.detachPending) return;
          ack = await transport.post('/v1/devices', {
            ...Map<String, dynamic>.from(registration)..remove('timezone'),
            ..._proof!,
            'registrationRevision': fallback.revision,
            'favoritePlayerNews': fallback.enabled,
          }, accessToken: session.accessToken);
          if (ack['newsBindingRequired'] == true && fallback.enabled) {
            await _beginBinding(
              Map<String, dynamic>.from(registration)..remove('timezone'),
              session,
              epoch,
            );
            return;
          }
          if (await _ackCategory(ack, fallback, session, epoch)) {
            if (_registrationRequest == registrationRequest) {
              _registrationPending = false;
            }
            _resetRetry();
          }
          return;
        }
        if (ack['newsBindingRequired'] == true && attempt.enabled) {
          await _beginBinding(registration, session, epoch);
          return;
        }
        if (await _ackCategory(ack, attempt, session, epoch)) {
          if (_registrationRequest == registrationRequest) {
            _registrationPending = false;
          }
          _resetRetry();
        }
      } else if (categoryConfirmed) {
        _resetRetry();
      } else if (preferenceFailure != null) {
        _retryLater();
      }
    } catch (_) {
      // Failure bodies/proofs/tokens are intentionally never logged.
      _retryLater();
    } finally {
      await _observeAuth();
      await _publish();
      // A session can expire while a request is in flight without the SDK
      // emitting another auth event. Persisting the barrier is not enough:
      // reconcile it (and any superseding choice) even without a second caller.
      final pending = await store.load();
      if (!_disposed &&
          _attempts < maxAttempts &&
          !(_retry?.isActive ?? false) &&
          (pending.detachPending ||
              (readSession() != null && !_confirmed(pending)))) {
        _retryLater();
      }
    }
  }

  /// Proof-only, durable and serialized with registration/category requests.
  /// No session is needed, so expiry/revocation cannot bypass this barrier.
  Future<bool> detach() async {
    if (_disposed) return false;
    await initialize();
    _authEpoch++;
    _resetRetry();
    await store.update((state) {
      state.detachPending = true;
      state.clearAck();
    });
    await _publish();
    final next = _queue.catchError((Object _) {}).then((_) async {
      try {
        return await _detachAttempt();
      } catch (_) {
        _retryLater();
        return false;
      } finally {
        await _publish();
      }
    });
    _queue = next.then<void>((_) {});
    return next;
  }

  void dispose() {
    _disposed = true;
    _retry?.cancel();
    status.dispose();
  }
}
