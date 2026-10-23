class ChesseverWatchBridge {
  static void registerWith() {}
  Stream<Map<String, dynamic>> get taps => const Stream.empty();
  void start() =>
      throw UnsupportedError('Notifications require the watchOS host.');
  Future<void> dispose() async {}
}
