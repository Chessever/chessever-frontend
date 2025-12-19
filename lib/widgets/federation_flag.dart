import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/country_utils.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';

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

