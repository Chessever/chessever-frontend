import 'package:chessever2/utils/country_utils.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter_country_flags/flutter_country_flags.dart' as fcf;

class FederationFlag extends StatelessWidget {
  const FederationFlag({
    super.key,
    required this.federation,
    this.width,
    this.height,
    this.borderRadius,
  });

  /// Federation value from APIs.
  /// Can be ISO2 ("US"), FIDE alpha-3 ("USA"), or a country name ("Norway").
  final String? federation;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  static const Set<String> _restrictedFideCodes = {'RUS', 'BLR', 'FID'};

  /// Restricted country names (from Gamebase API which returns full names).
  static const Set<String> _restrictedCountryNames = {'russia', 'belarus'};

  /// UK constituent countries that need special flag handling.
  /// Maps FIDE codes to flutter_country_flags Country enum.
  static const Map<String, fcf.Country> _ukSubdivisions = {
    'ENG': fcf.Country.england,
    'SCO': fcf.Country.scotland,
    'WLS': fcf.Country.wales,
  };

  @override
  Widget build(BuildContext context) {
    final raw = (federation ?? '').trim();
    final normalized = raw.toUpperCase();

    if (raw.isEmpty) {
      return _fallback(context);
    }

    final lowerRaw = raw.toLowerCase();

    // Countries that show FIDE logo due to sanctions or restrictions.
    // Check both 3-letter FIDE codes and full country names from Gamebase API.
    if (_restrictedFideCodes.contains(normalized) ||
        _restrictedCountryNames.contains(lowerRaw)) {
      return _fideLogo(context);
    }

    // Handle UK subdivisions (England, Scotland, Wales) with their own flags.
    if (_ukSubdivisions.containsKey(normalized)) {
      return _ukSubdivisionFlag(context, normalized);
    }
    if (lowerRaw == 'england') return _ukSubdivisionFlag(context, 'ENG');
    if (lowerRaw == 'scotland') return _ukSubdivisionFlag(context, 'SCO');
    if (lowerRaw == 'wales') return _ukSubdivisionFlag(context, 'WLS');

    String? iso2;
    if (normalized.length == 2) {
      iso2 = normalized;
    } else if (normalized.length == 3) {
      iso2 = CountryUtils.toIso2Code(normalized);
    } else {
      // Country name (e.g. "Norway", "Austria") — use manual mapping first
      // (more reliable), then fall back to country_picker's name lookup.
      final manual = CountryUtils.countryNameToIso2(raw);
      iso2 = manual.isNotEmpty ? manual : CountryUtils.getCountryCode(raw);
    }

    if (iso2 == null || iso2.length != 2) {
      return _fallback(context);
    }

    final child = CountryFlag.fromCountryCode(
      iso2,
      width: width,
      height: height,
    );

    final radius = borderRadius ?? BorderRadius.circular(3);
    return ClipRRect(borderRadius: radius, child: child);
  }

  Widget _ukSubdivisionFlag(BuildContext context, String fideCode) {
    final country = _ukSubdivisions[fideCode];
    if (country == null) return _fallback(context);

    final radius = borderRadius ?? BorderRadius.circular(3);
    return ClipRRect(
      borderRadius: radius,
      child: fcf.FlutterCountryFlags(
        country: country,
        width: width,
        height: height,
      ),
    );
  }

  Widget _fideLogo(BuildContext context) {
    final w = width;
    final h = height;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final cacheW = w != null ? (w * pixelRatio).toInt() : null;
    final cacheH = h != null ? (h * pixelRatio).toInt() : null;

    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(3),
      child: Image.asset(
        PngAsset.fideLogo,
        width: w,
        height: h,
        fit: BoxFit.cover,
        cacheWidth: cacheW,
        cacheHeight: cacheH,
        errorBuilder: (_, __, ___) => SizedBox(width: w, height: h),
      ),
    );
  }

  Widget _fallback(BuildContext context) {
    return _fideLogo(context);
  }
}
