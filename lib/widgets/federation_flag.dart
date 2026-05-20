import 'package:chessever2/utils/country_utils.dart';
import 'package:chessever2/utils/png_asset.dart';
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

  /// UK constituent countries that need special flag handling.
  /// Maps FIDE codes to flutter_country_flags Country enum.
  static const Map<String, fcf.Country> _ukSubdivisions = {
    'ENG': fcf.Country.england,
    'SCO': fcf.Country.scotland,
    'WLS': fcf.Country.wales,
  };

  /// Federation values from the Gamebase API that mean "no real federation
  /// resolved" — TWIC fills this in for historical / unrated / unknown players.
  /// Treat them as an unknown placeholder, not as a FIDE-stateless tag.
  static const Set<String> _unknownSentinels = {
    'unknown',
    'none',
    'unrated',
    'n/a',
    'na',
    '?',
    '-',
  };

  @override
  Widget build(BuildContext context) {
    final raw = (federation ?? '').trim();
    final normalized = raw.toUpperCase();

    if (raw.isEmpty) {
      return _unknownPlaceholder(context);
    }

    final lowerRaw = raw.toLowerCase();

    if (_unknownSentinels.contains(lowerRaw)) {
      return _unknownPlaceholder(context);
    }

    // Lichess returns the literal "FIDE" for stateless / sanctioned players;
    // when no real federation can be resolved, render the FIDE logo.
    if (normalized == 'FID' || normalized == 'FIDE') {
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
      return _unknownPlaceholder(context);
    }

    return _iso2Flag(context, iso2);
  }

  Widget _iso2Flag(BuildContext context, String iso2) {
    final radius = borderRadius ?? BorderRadius.circular(3);
    return ClipRRect(
      borderRadius: radius,
      child: fcf.FlutterCountryFlags(
        country: iso2,
        width: width,
        height: height,
        fit: BoxFit.cover,
        borderRadius: 0,
      ),
    );
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
    return _unknownPlaceholder(context);
  }

  /// Renders a neutral globe placeholder when no real federation can be
  /// resolved (e.g. TWIC `fed: "Unknown"` or a country name that isn't in any
  /// of our mapping tables). Previously this returned the FIDE webp logo,
  /// which is mostly-white and looked like a blank rectangle at flag sizes.
  Widget _unknownPlaceholder(BuildContext context) {
    final w = width;
    final h = height;
    final iconSize = (h ?? w ?? 16) * 0.85;
    final brightness = Theme.of(context).brightness;
    // High-contrast surface so the globe placeholder is clearly visible
    // against the card body, regardless of the active theme.
    final bg = brightness == Brightness.light
        ? const Color(0xFF6B7280)
        : const Color(0xFF374151);
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(3),
      child: Container(
        width: w,
        height: h,
        alignment: Alignment.center,
        color: bg,
        child: Icon(
          Icons.public_rounded,
          size: iconSize,
          color: Colors.white,
        ),
      ),
    );
  }
}
