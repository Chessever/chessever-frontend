import 'dart:io';

import 'package:hooks_riverpod/hooks_riverpod.dart';

final keyboardTotalHeightProvider =
    StateNotifierProvider<KeyboardTotalHeightNotifier, double>(
      (ref) => KeyboardTotalHeightNotifier(),
    );

class KeyboardTotalHeightNotifier extends StateNotifier<double> {
  KeyboardTotalHeightNotifier() : super(Platform.isIOS ? 336.0 : 286.0);

  void update(double height) {
    if (height <= 0) return;
    // Ignore tiny fluctuations that can cause layout jitter
    if ((height - state).abs() < 0.5) return;
    if (height > state) {
      state = height;
    }
  }
}
