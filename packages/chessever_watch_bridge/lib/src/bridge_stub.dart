class ChesseverWatchBridge {
  static void registerWith() {}
  static bool get powerConstrained => false;
  Stream<Map<String, dynamic>> get taps => const Stream.empty();
  void start() =>
      throw UnsupportedError('Notifications require the watchOS host.');
  Future<void> dispose() async {}
}
