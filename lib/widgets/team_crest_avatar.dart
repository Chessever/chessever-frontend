import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:chessever2/widgets/team_country_code.dart';
import 'package:flutter/material.dart';

/// Team avatar: country flag when [teamName] resolves to a known country,
/// otherwise a deterministic monogram crest.
///
/// Clubs rarely have logos and often share a federation flag within a league,
/// so non-country teams keep the crest. National / olympiad-style squads
/// (`USA`, `Norway`, `India`) show the flag in the same size/radius slot.
class TeamCrestAvatar extends StatelessWidget {
  final String teamName;
  final double size;
  final double borderRadius;

  const TeamCrestAvatar({
    super.key,
    required this.teamName,
    required this.size,
    required this.borderRadius,
  });

  /// Up to two leading letters from the first significant words (quotes and
  /// punctuation stripped).
  static String monogramFor(String name) {
    final words =
        name
            .replaceAll(RegExp("[\"'`.,()\\[\\]{}\\-_/]"), ' ')
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .toList();
    if (words.isEmpty) {
      return name.isNotEmpty
          ? name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase()
          : '?';
    }
    if (words.length == 1) {
      final w = words.first;
      return w.substring(0, w.length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${words[0][0]}${words[1][0]}'.toUpperCase();
  }

  /// Stable 0–360 hue from a team name (FNV-1a style rolling hash).
  static double hueFor(String name) {
    var hash = 2166136261;
    for (final unit in name.trim().toUpperCase().codeUnits) {
      hash = (hash ^ unit) * 16777619;
      hash &= 0xFFFFFFFF;
    }
    return (hash % 360).toDouble();
  }

  /// The team's primary accent color, for cohesive tinting elsewhere (e.g. the
  /// score-card hero). Matches the crest's dominant gradient stop.
  static Color colorFor(String name) =>
      HSLColor.fromAHSL(1, hueFor(name), 0.52, 0.46).toColor();

  /// Whether [teamName] should render as a flag rather than a crest.
  static bool showsFlagFor(String teamName) =>
      resolveTeamCountryCode(teamName) != null;

  @override
  Widget build(BuildContext context) {
    final countryCode = resolveTeamCountryCode(teamName);
    if (countryCode != null) {
      return SizedBox(
        width: size,
        height: size,
        child: FederationFlag(
          federation: countryCode,
          width: size,
          height: size,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      );
    }
    return _CrestMonogram(
      teamName: teamName,
      size: size,
      borderRadius: borderRadius,
    );
  }
}

class _CrestMonogram extends StatelessWidget {
  const _CrestMonogram({
    required this.teamName,
    required this.size,
    required this.borderRadius,
  });

  final String teamName;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final hue = TeamCrestAvatar.hueFor(teamName);
    final top = HSLColor.fromAHSL(1, hue, 0.52, 0.42).toColor();
    final bottom = HSLColor.fromAHSL(1, (hue + 24) % 360, 0.58, 0.28).toColor();

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [top, bottom],
        ),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
          width: 1,
        ),
      ),
      child: Text(
        TeamCrestAvatar.monogramFor(teamName),
        style: AppTypography.textMdBold.copyWith(
          color: Colors.white.withValues(alpha: 0.95),
          fontSize: size * 0.34,
          height: 1,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
