/// Which games may pop out into Picture-in-Picture.
///
/// Persisted in board settings (`user_engine_settings.pip_mode`, synced) and
/// interpreted by the runtime eligibility check. Enum order is the stored
/// integer: off=0 (default), live=1, all=2. "all" is a legacy value and is now
/// treated the same as live-only.
enum PipMode { off, live, all }

extension PipModeInfo on PipMode {
  String get label => switch (this) {
    PipMode.off => 'Off',
    PipMode.live => 'Live',
    PipMode.all => 'All',
  };

  static PipMode fromIndex(int? index) {
    if (index == null || index < 0 || index >= PipMode.values.length) {
      return PipMode.off; // default: off (opt-in only)
    }
    return PipMode.values[index];
  }
}
