import 'dart:ui' as ui;

import 'package:hooks_riverpod/hooks_riverpod.dart';

final locationRepositoryProvider = AutoDisposeProvider<LocationRepository>((
  ref,
) {
  return LocationRepository();
});

// Location Repository
class LocationRepository {
  Future<String> getCountryCode() async {
    // Use device locale for instant country detection (no network call)
    final locale = ui.PlatformDispatcher.instance.locale;
    final countryCode = locale.countryCode;

    if (countryCode != null && countryCode.isNotEmpty) {
      return countryCode;
    }

    // Fallback to US if locale has no country
    return 'US';
  }
}
