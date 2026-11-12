class ChesseverWatchBridge {
  static void registerWith() {}
  static bool get powerConstrained => false;
  static bool loadSound(int sound, List<int> bytes) => false;
  static void playSound(int sound) {}
  static void stopSounds() {}
  Stream<Map<String, dynamic>> get taps => const Stream.empty();
  void start() =>
      throw UnsupportedError('Notifications require the watchOS host.');
  Future<void> dispose() async {}
}
