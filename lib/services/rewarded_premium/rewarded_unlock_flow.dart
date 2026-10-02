import 'package:chessever2/services/rewarded_premium/rewarded_session.dart';

typedef RewardedRequest =
    Future<Map<String, dynamic>> Function(
      String action,
      String token, {
      String? attempt,
    });

/// Owns pending rewards separately from any screen. Retrying a network error
/// or delayed SSV confirmation cannot consume another ad.
class RewardedUnlockFlow {
  RewardedUnlockFlow(
    this.session, {
    this.pollCount = 12,
    this.pollDelay = const Duration(seconds: 2),
  });
  final RewardedSession session;
  final int pollCount;
  final Duration pollDelay;
  String? _attempt;
  bool _busy = false;
  int _generation = 0;
  bool get pending => _attempt != null;
  bool get busy => _busy;

  void clear() {
    _generation++;
    _attempt = null;
  }

  Future<bool> unlock({
    required Future<void> Function() prepareAds,
    required Future<bool> Function(String attempt) showAd,
    required RewardedRequest request,
    required void Function() onPending,
  }) async {
    if (_busy) return false;
    if (session.active) return true;
    _busy = true;
    final generation = _generation;
    final token = session.token;
    bool current() => generation == _generation && token == session.token;
    try {
      if (_attempt == null) {
        await prepareAds();
        if (!current()) return false;
        final prepared = await request('prepare', token);
        if (!current()) return false;
        final attempt = prepared['attempt_id'] as String;
        final earned = await showAd(attempt);
        if (!current() || !earned) return false;
        _attempt = attempt;
        onPending();
      }
      for (var poll = 0; poll < pollCount; poll++) {
        final elapsed = Stopwatch()..start();
        final result = await request('activate', token, attempt: _attempt);
        elapsed.stop();
        if (!current()) return false;
        if (result['status'] == 'active') {
          // Conservatively subtract the whole round trip: never over-grant
          // beyond the server's deadline due to response latency.
          final expires = DateTime.parse(result['expires_at'] as String);
          final serverNow = DateTime.parse(result['server_now'] as String);
          final adjustedNow = serverNow.add(elapsed.elapsed);
          if (!expires.isAfter(adjustedNow)) {
            _attempt = null;
            return false;
          }
          session.grant(expiresAt: expires, serverNow: adjustedNow);
          _attempt = null;
          return true;
        }
        if (result['status'] == 'expired') {
          _attempt = null;
          throw StateError('This reward has expired. Please watch a new ad.');
        }
        if (result['status'] != 'pending') {
          throw StateError('Invalid reward response');
        }
        if (poll + 1 < pollCount) await Future<void>.delayed(pollDelay);
      }
      return false;
    } finally {
      _busy = false;
    }
  }
}
