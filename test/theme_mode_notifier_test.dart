import 'package:chessever2/theme/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ThemeModeNotifier setTheme and toggleTheme drive real state', () {
    final notifier = ThemeModeNotifier();
    // Default is dark (before async restore settles in tests).
    expect(notifier.state, ThemeMode.dark);

    notifier.setTheme(ThemeMode.light);
    expect(notifier.state, ThemeMode.light);

    notifier.toggleTheme();
    expect(notifier.state, ThemeMode.dark);

    notifier.toggleTheme();
    expect(notifier.state, ThemeMode.light);

    // No-op when same mode.
    notifier.setTheme(ThemeMode.light);
    expect(notifier.state, ThemeMode.light);
  });
}
