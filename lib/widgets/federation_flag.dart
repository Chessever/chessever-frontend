import 'package:chessever2/utils/country_utils.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:country_flags/country_flags.dart';
import 'package:country_picker/country_picker.dart';
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

  /// True when [federation] resolves to a visible country or FIDE flag.
  ///
  /// Use this before adding surrounding spacing so missing/unknown values do not
  /// leave an empty flag slot.
  static bool hasVisibleFlag(String? federation) {
    final raw = (federation ?? '').trim();
    final normalized = raw.toUpperCase();

    if (raw.isEmpty) return false;
    final lowerRaw = raw.toLowerCase();
    if (_unknownSentinels.contains(lowerRaw)) return false;
    if (normalized == 'FID' || normalized == 'FIDE') return true;
    if (_ukSubdivisions.containsKey(normalized)) return true;
    if (lowerRaw == 'england' ||
        lowerRaw == 'scotland' ||
        lowerRaw == 'wales') {
      return true;
    }

    final iso2 = _resolveIso2(raw, normalized);

    return iso2 != null && iso2.length == 2;
  }

  // country_picker's CountryService builds ~250 Country objects in its
  // constructor. A flag sits in every game card and standings row, and
  // hasVisibleFlag plus build each looked the country up, so one instance and a
  // memo per federation string replace a table rebuild on every card build.
  static final CountryService _countries = CountryService();
  static final Map<String, String?> _iso2ByFederation = {};

  /// ISO2 for a trimmed federation value that is not one of the special cases
  /// handled by the callers (unknown sentinels, FIDE, UK subdivisions).
  static String? _resolveIso2(String raw, String normalized) {
    if (_iso2ByFederation.containsKey(raw)) return _iso2ByFederation[raw];

    String? iso2;
    if (normalized.length == 2) {
      iso2 = _countries.findByCode(normalized)?.countryCode;
    } else if (normalized.length == 3) {
      final mapped = CountryUtils.toIso2Code(normalized);
      iso2 = _countries.findByCode(mapped)?.countryCode;
    } else {
      // Country name (e.g. "Norway", "Austria") — use manual mapping first
      // (more reliable), then fall back to country_picker's name lookup.
      final manual = CountryUtils.countryNameToIso2(raw);
      iso2 = manual.isNotEmpty ? manual : CountryUtils.getCountryCode(raw);
    }

    // Federation values are a small closed set; the cap only guards against
    // unexpected free text from an API.
    if (_iso2ByFederation.length >= 2048) _iso2ByFederation.clear();
    return _iso2ByFederation[raw] = iso2;
  }

  @override
  Widget build(BuildContext context) {
    final raw = (federation ?? '').trim();
    final normalized = raw.toUpperCase();

    if (raw.isEmpty) {
      return _noFlag();
    }

    final lowerRaw = raw.toLowerCase();

    if (_unknownSentinels.contains(lowerRaw)) {
      return _noFlag();
    }

    // FID/FIDE = sanctioned/neutral players (e.g. RU/BY). Show the FIDE
    // logo so the slot isn't blank when no backfill resolved a real country.
    if (normalized == 'FID' || normalized == 'FIDE') {
      return _fideLogoFlag();
    }

    // Handle UK subdivisions (England, Scotland, Wales) with their own flags.
    if (_ukSubdivisions.containsKey(normalized)) {
      return _ukSubdivisionFlag(context, normalized);
    }
    if (lowerRaw == 'england') return _ukSubdivisionFlag(context, 'ENG');
    if (lowerRaw == 'scotland') return _ukSubdivisionFlag(context, 'SCO');
    if (lowerRaw == 'wales') return _ukSubdivisionFlag(context, 'WLS');

    final iso2 = _resolveIso2(raw, normalized);

    if (iso2 == null || iso2.length != 2) {
      return _noFlag();
    }

    return _iso2Flag(context, iso2);
  }

  Widget _iso2Flag(BuildContext context, String iso2) {
    final radius = borderRadius ?? BorderRadius.circular(3);
    return ClipRRect(
      borderRadius: radius,
      child:
          iso2 == _kosovoIso2
              ? CountryFlag.fromCountryCode(
                iso2,
                theme: ImageTheme(width: width, height: height),
              )
              : fcf.FlutterCountryFlags(
                country: iso2,
                width: width,
                height: height,
                fit: BoxFit.cover,
                borderRadius: 0,
              ),
    );
  }

  /// `flutter_country_flags` bundles `xk.png` but its code resolver never
  /// reaches the asset: neither its `Country` enum nor its ISO code table
  /// lists XK, so it paints the grey fallback tile instead. `country_flags`
  /// renders Kosovo correctly and is already used for event flags.
  static const _kosovoIso2 = 'XK';

  Widget _ukSubdivisionFlag(BuildContext context, String fideCode) {
    final country = _ukSubdivisions[fideCode];
    if (country == null) return _noFlag();

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

  /// Unknown/missing federation should not render a generic flag-like symbol.
  /// Cards and player rows should only show a flag when we know the country.
  Widget _noFlag() => const SizedBox.shrink();

  Widget _fideLogoFlag() {
    final radius = borderRadius ?? BorderRadius.circular(3);
    return ClipRRect(
      borderRadius: radius,
      child: Image.asset(
        PngAsset.fideLogo,
        width: width,
        height: height,
        fit: BoxFit.cover,
      ),
    );
  }
}
