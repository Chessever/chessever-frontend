import 'package:chessever2/theme/app_theme.dart';
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
      return _fallback();
    }

    // Countries that show white/blank flags due to sanctions or restrictions.
    if (_restrictedFideCodes.contains(normalized)) {
      return _fideLogo();
    }

    // Handle UK subdivisions (England, Scotland, Wales) with their own flags.
    if (_ukSubdivisions.containsKey(normalized)) {
      return _ukSubdivisionFlag(normalized);
    }

    // Also check for country names like "England", "Scotland", "Wales".
    final lowerRaw = raw.toLowerCase();
    if (lowerRaw == 'england') return _ukSubdivisionFlag('ENG');
    if (lowerRaw == 'scotland') return _ukSubdivisionFlag('SCO');
    if (lowerRaw == 'wales') return _ukSubdivisionFlag('WLS');

    String? iso2;
    if (normalized.length == 2) {
      iso2 = normalized;
    } else if (normalized.length == 3) {
      iso2 = CountryUtils.toIso2Code(normalized);
    } else {
      iso2 = CountryUtils.getCountryCode(raw);
    }

    if (iso2 == null || iso2.length != 2) {
      return _fallback();
    }

    final child = CountryFlag.fromCountryCode(
      iso2,
      width: width,
      height: height,
    );

    final radius = borderRadius ?? BorderRadius.circular(3);
    return ClipRRect(borderRadius: radius, child: child);
  }

  Widget _ukSubdivisionFlag(String fideCode) {
    final country = _ukSubdivisions[fideCode];
    if (country == null) return _fallback();

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

  Widget _fideLogo() {
    final w = width;
    final h = height;
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(3),
      child: Image.asset(
        PngAsset.fideLogo,
        width: w,
        height: h,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(),
      ),
    );
  }

  Widget _fallback() {
    final size = (height ?? width ?? 16).clamp(10, 24).toDouble();
    return Icon(
      Icons.flag_rounded,
      size: size,
      color: kWhiteColor.withValues(alpha: 0.35),
    );
  }
}

