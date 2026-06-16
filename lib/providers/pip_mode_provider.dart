/// Which games may pop out into Picture-in-Picture.
///
/// Persisted in board settings (`user_engine_settings.pip_mode`, synced) and
/// gated at the eligibility check + settings UI. Enum order is the stored
/// integer: off=0, live=1 (default). (A legacy "all"=2 value is mapped down to
/// live by [fromIndex]; the option was removed.)
enum PipMode { off, live }

extension PipModeInfo on PipMode {
  String get label => switch (this) {
    PipMode.off => 'Off',
    PipMode.live => 'Live',
  };

  static PipMode fromIndex(int? index) {
    if (index == null || index < 0) {
      return PipMode.live; // default: enabled for live games when supported
    }
    // Legacy "all" (2) collapses to live now that the option is gone.
    if (index >= PipMode.values.length) return PipMode.live;
    return PipMode.values[index];
  }
}
