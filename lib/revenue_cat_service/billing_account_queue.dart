/// Serializes billing identity changes with purchases and restores.
class BillingAccountQueue {
  BillingAccountQueue(this.currentAccount);

  final String? Function() currentAccount;
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(String? account, Future<T> Function() operation) {
    final result = _tail.then((_) async {
      void checkAccount() {
        if (currentAccount() != account) {
          throw StateError('Account changed. Please try again.');
        }
      }

      checkAccount();
      final result = await operation();
      checkAccount();
      return result;
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
