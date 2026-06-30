import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Countrymen games keeps provider alive while board route is open', () {
    final source =
        File(
          'lib/screens/countrymen/tabs/countrymen_games_tab.dart',
        ).readAsStringSync();

    final providerWatch = source.indexOf(
      'final state = ref.watch(countrymenCombinedGamesProvider);',
    );
    final modeGuard = source.indexOf(
      'selectedMode != CountrymenScreenMode.games',
    );
    final hiddenRouteGuard = source.indexOf('if (!_isActiveOnScreen)');

    expect(modeGuard, isNonNegative);
    expect(providerWatch, isNonNegative);
    expect(hiddenRouteGuard, isNonNegative);
    expect(modeGuard, lessThan(providerWatch));
    expect(providerWatch, lessThan(hiddenRouteGuard));
  });

  test(
    'Countrymen games snapshots and restores scroll offset across board route',
    () {
      final source =
          File(
            'lib/screens/countrymen/tabs/countrymen_games_tab.dart',
          ).readAsStringSync();

      expect(source, contains('double? _pendingScrollOffsetRestore;'));
      expect(source, contains('_rememberScrollOffsetBeforeHiding();'));
      expect(source, contains('_restoreScrollOffsetAfterReturn();'));
      expect(source, contains('_scrollController.jumpTo(clampedOffset);'));
    },
  );
}
