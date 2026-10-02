import 'dart:convert';
import 'dart:math';

/// A capability for this process only. Never persist it or put it in analytics.
class RewardedSession {
  RewardedSession({Duration Function()? elapsed})
    : _elapsed = elapsed ?? (() => _clock.elapsed);

  static final Stopwatch _clock = Stopwatch()..start();
  static final RewardedSession instance = RewardedSession();
  final Duration Function() _elapsed;
  String? _userId;
  String _token = _newToken();
  Duration? _deadline;

  String get token => _token;
  bool get active => remaining > Duration.zero;
  Duration get remaining {
    final deadline = _deadline;
    if (deadline == null) return Duration.zero;
    final value = deadline - _elapsed();
    return value.isNegative ? Duration.zero : value;
  }

  void bindUser(String? userId) {
    if (_userId == userId) return;
    _userId = userId;
    reset();
  }

  void reset() {
    _deadline = null;
    _token = _newToken();
  }

  void grant({required DateTime expiresAt, required DateTime serverNow}) {
    final duration = expiresAt.difference(serverNow);
    if (duration <= Duration.zero || duration > const Duration(minutes: 10)) {
      throw StateError('Invalid rewarded access duration');
    }
    _deadline = _elapsed() + duration;
  }

  Map<String, String> get headers =>
      active ? {'x-rewarded-session': _token} : const {};

  static String _newToken() {
    final random = Random.secure();
    return base64UrlEncode(
      List.generate(32, (_) => random.nextInt(256)),
    ).replaceAll('=', '');
  }
}
