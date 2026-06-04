/// Which games may pop out into Picture-in-Picture.
///
/// Persisted in board settings (`user_engine_settings.pip_mode`, synced) and
/// premium-gated at the eligibility check + settings UI. Enum order is the
/// stored integer: off=0, completed=1, live=2 (default), both=3.
enum PipMode { off, completed, live, both }

extension PipModeInfo on PipMode {
  String get label => switch (this) {
    PipMode.off => 'Off',
    PipMode.completed => 'Completed',
    PipMode.live => 'Live',
    PipMode.both => 'Both',
  };

  static PipMode fromIndex(int? index) {
    if (index == null || index < 0 || index >= PipMode.values.length) {
      return PipMode.off; // default: off (opt-in only)
    }
    return PipMode.values[index];
  }
}
