class PushTokenSyncRetryState {
  PushTokenSyncRetryState({this.maxAttempts = 3}) : assert(maxAttempts > 0);

  final int maxAttempts;

  String? _syncedSignature;
  String? _activeSignature;
  int _failedAttempts = 0;

  bool shouldSync(String signature) {
    if (_syncedSignature == signature) return false;
    _activate(signature);
    return _failedAttempts < maxAttempts;
  }

  Duration? recordFailure(String signature) {
    _activate(signature);
    _failedAttempts += 1;
    if (_failedAttempts >= maxAttempts) return null;
    return _failedAttempts == 1
        ? const Duration(seconds: 2)
        : const Duration(seconds: 5);
  }

  void recordSuccess(String signature) {
    _activeSignature = signature;
    _syncedSignature = signature;
    _failedAttempts = 0;
  }

  void _activate(String signature) {
    if (_activeSignature == signature) return;
    _activeSignature = signature;
    _failedAttempts = 0;
  }
}
