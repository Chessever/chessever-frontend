/// Which games may post a Live Activity (iOS) / live notification (Android).
///
/// Persisted in board settings (`user_engine_settings.live_activity_mode`,
/// synced). Enum order is the stored integer: off=0 (default), live=1, all=2.
/// "live" posts only while the game is ongoing; "all" also keeps a static
/// snapshot widget for completed games. Mirrors [PipMode].
enum LiveActivityMode { off, live, all }

extension LiveActivityModeInfo on LiveActivityMode {
  String get label => switch (this) {
    LiveActivityMode.off => 'Off',
    LiveActivityMode.live => 'Live',
    LiveActivityMode.all => 'All',
  };

  static LiveActivityMode fromIndex(int? index) {
    if (index == null || index < 0 || index >= LiveActivityMode.values.length) {
      return LiveActivityMode.off; // default: off (opt-in only)
    }
    return LiveActivityMode.values[index];
  }
}
