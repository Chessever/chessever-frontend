import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/pip_mode_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults PiP to live when no stored value exists', () {
    expect(PipModeInfo.fromIndex(null), PipMode.live);
    expect(const BoardSettingsNew().pipMode, PipMode.live);
  });

  test('preserves explicit off PiP setting', () {
    expect(PipModeInfo.fromIndex(0), PipMode.off);
    expect(const BoardSettingsNew(pipModeIndex: 0).pipMode, PipMode.off);
  });
}
