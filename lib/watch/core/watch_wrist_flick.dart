/// Recognises a deliberate wrist flick from gyroscope samples.
///
/// A flick is a sharp roll about the forearm (the watch's x axis) that snaps
/// back: a spike past [_start] rad/s on that axis, clearly larger than the
/// other two axes, followed within [_window] by an opposite spike past
/// [_back]. Raising the wrist to read is slow and one-way, and walking sway
/// stays well under the start threshold, so neither triggers it.
///
/// [add] returns +1 for an outward-first flick (next board), -1 for an
/// inward-first flick (previous board) and 0 otherwise. After a flick the
/// detector ignores input for [_cooldown] so the return swing and hand
/// settling cannot fire a second step.
class WatchWristFlick {
  static const _start = 6.0;
  static const _back = 4.0;
  static const _dominance = 1.8;
  static const _window = Duration(milliseconds: 350);
  static const _cooldown = Duration(milliseconds: 900);

  int _armedSign = 0;
  Duration _armedAt = Duration.zero;
  Duration _quietUntil = Duration.zero;

  int add(double x, double y, double z, Duration at) {
    if (at < _quietUntil) return 0;
    if (_armedSign != 0 && at - _armedAt > _window) _armedSign = 0;

    final roll = x.abs();
    final dominant = roll > _dominance * y.abs() && roll > _dominance * z.abs();

    if (_armedSign == 0) {
      if (dominant && roll >= _start) {
        _armedSign = x.sign.toInt();
        _armedAt = at;
      }
      return 0;
    }

    if (dominant && x.sign.toInt() == -_armedSign && roll >= _back) {
      final direction = _armedSign;
      _armedSign = 0;
      _quietUntil = at + _cooldown;
      return direction;
    }
    return 0;
  }

  void reset() {
    _armedSign = 0;
    _quietUntil = Duration.zero;
  }
}
