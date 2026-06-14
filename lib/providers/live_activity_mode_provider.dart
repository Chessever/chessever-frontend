/// Which games may post a Live Activity (iOS) / live notification (Android).
///
/// Persisted in board settings (`user_engine_settings.live_activity_mode`,
/// synced). Enum order is the stored integer: off=0, live=1 (default when no
/// preference is stored). "live" posts only while the game is ongoing. A legacy
/// "all"=2 value is mapped down to live by [fromIndex]; the option was removed.
/// Mirrors [PipMode].
enum LiveActivityMode { off, live }

extension LiveActivityModeInfo on LiveActivityMode {
  String get label => switch (this) {
    LiveActivityMode.off => 'Off',
    LiveActivityMode.live => 'Live',
  };

  static LiveActivityMode fromIndex(int? index) {
    if (index == null) {
      return LiveActivityMode.live;
    }
    if (index < 0) {
      return LiveActivityMode.off;
    }
    // Legacy "all" (2) collapses to live now that the option is gone.
    if (index >= LiveActivityMode.values.length) return LiveActivityMode.live;
    return LiveActivityMode.values[index];
  }
}
