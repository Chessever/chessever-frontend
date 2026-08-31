import 'dart:math' as math;

import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';

enum TournamentDetailLayout { regular, individualKnockout, team }

const regularTournamentDetailModes = <TournamentDetailScreenMode>[
  TournamentDetailScreenMode.about,
  TournamentDetailScreenMode.games,
  TournamentDetailScreenMode.standings,
];

const knockoutTournamentDetailModes = <TournamentDetailScreenMode>[
  TournamentDetailScreenMode.about,
  TournamentDetailScreenMode.games,
  TournamentDetailScreenMode.bracket,
];

const teamTournamentDetailModes = <TournamentDetailScreenMode>[
  TournamentDetailScreenMode.about,
  TournamentDetailScreenMode.games,
  TournamentDetailScreenMode.standings,
  TournamentDetailScreenMode.players,
];

List<TournamentDetailScreenMode> tournamentDetailModesFor(
  TournamentDetailLayout layout,
) => switch (layout) {
  TournamentDetailLayout.regular => regularTournamentDetailModes,
  TournamentDetailLayout.individualKnockout => knockoutTournamentDetailModes,
  TournamentDetailLayout.team => teamTournamentDetailModes,
};

TournamentDetailLayout tournamentDetailLayoutForDetection({
  required bool isTeam,
  required bool isKnockout,
}) {
  if (isTeam) return TournamentDetailLayout.team;
  if (isKnockout) return TournamentDetailLayout.individualKnockout;
  return TournamentDetailLayout.regular;
}

/// Layout used before the selected tour's metadata has resolved.
///
/// Keeping an explicitly requested Bracket or Players mode in its compatible
/// four-tab layout prevents a deep-link selection from being discarded during
/// the first loading frame.
TournamentDetailLayout provisionalTournamentDetailLayoutForMode(
  TournamentDetailScreenMode mode,
) => switch (mode) {
  TournamentDetailScreenMode.bracket =>
    TournamentDetailLayout.individualKnockout,
  TournamentDetailScreenMode.players => TournamentDetailLayout.team,
  TournamentDetailScreenMode.about ||
  TournamentDetailScreenMode.games ||
  TournamentDetailScreenMode.standings => TournamentDetailLayout.regular,
};

int tournamentDetailPageForMode(
  List<TournamentDetailScreenMode> visibleModes,
  TournamentDetailScreenMode mode, {
  TournamentDetailScreenMode fallback = TournamentDetailScreenMode.games,
}) {
  final index = visibleModes.indexOf(mode);
  if (index >= 0) return index;

  final fallbackIndex = visibleModes.indexOf(fallback);
  return fallbackIndex >= 0 ? fallbackIndex : 0;
}

TournamentDetailScreenMode tournamentDetailModeForPage(
  List<TournamentDetailScreenMode> visibleModes,
  int page, {
  TournamentDetailScreenMode fallback = TournamentDetailScreenMode.games,
}) {
  if (page >= 0 && page < visibleModes.length) return visibleModes[page];
  return visibleModes.contains(fallback)
      ? fallback
      : visibleModes.firstOrNull ?? fallback;
}

TournamentDetailScreenMode normalizeTournamentDetailMode(
  List<TournamentDetailScreenMode> visibleModes,
  TournamentDetailScreenMode mode, {
  TournamentDetailScreenMode fallback = TournamentDetailScreenMode.games,
}) =>
    visibleModes.contains(mode)
        ? mode
        : tournamentDetailModeForPage(visibleModes, -1, fallback: fallback);

bool tournamentDetailModeHasSearch(TournamentDetailScreenMode mode) =>
    switch (mode) {
      TournamentDetailScreenMode.games ||
      TournamentDetailScreenMode.standings ||
      TournamentDetailScreenMode.players => true,
      TournamentDetailScreenMode.about ||
      TournamentDetailScreenMode.bracket => false,
    };

/// Search visibility while the PageView is between two pages.
///
/// This makes the pinned search field follow both swipe and tab animations,
/// including the fade out between Games and Bracket.
double tournamentDetailSearchVisibility(
  List<TournamentDetailScreenMode> visibleModes,
  double page,
) {
  if (visibleModes.isEmpty || !page.isFinite) return 0;

  final boundedPage = page.clamp(0.0, visibleModes.length - 1.0);
  final lowerPage = boundedPage.floor();
  final upperPage = boundedPage.ceil();
  final progress = boundedPage - lowerPage;
  final lowerVisibility =
      tournamentDetailModeHasSearch(visibleModes[lowerPage]) ? 1.0 : 0.0;
  final upperVisibility =
      tournamentDetailModeHasSearch(visibleModes[upperPage]) ? 1.0 : 0.0;
  return lowerVisibility +
      (upperVisibility - lowerVisibility) * math.min(progress, 1.0);
}

TournamentDetailScreenMode? tournamentDetailModeFromTabQuery(String? value) {
  switch (value?.trim().toLowerCase()) {
    case 'about':
      return TournamentDetailScreenMode.about;
    case 'games':
      return TournamentDetailScreenMode.games;
    case 'bracket':
      return TournamentDetailScreenMode.bracket;
    case 'standings':
      return TournamentDetailScreenMode.standings;
    case 'players':
      return TournamentDetailScreenMode.players;
    default:
      return null;
  }
}

String tournamentDetailTabQueryForMode(TournamentDetailScreenMode mode) =>
    switch (mode) {
      TournamentDetailScreenMode.about => 'about',
      TournamentDetailScreenMode.games => 'games',
      TournamentDetailScreenMode.bracket => 'bracket',
      TournamentDetailScreenMode.standings => 'standings',
      TournamentDetailScreenMode.players => 'players',
    };

/// Remembers the structural layout independently for each selected tour.
///
/// Detection may briefly return its default while providers reload. Once a
/// tour has positively resolved as team or individual knockout, its layout is
/// therefore never downgraded by a transient loading emission. A different
/// tour ID is resolved independently instead of inheriting the previous
/// category's layout.
class TournamentDetailLayoutTracker {
  final Map<String, TournamentDetailLayout> _layoutsByTour = {};

  String? _activeTourId;

  String? get activeTourId => _activeTourId;

  TournamentDetailLayout resolve({
    required String? tourId,
    bool isTeam = false,
    bool isKnockout = false,
    bool isDetectionPending = false,
    TournamentDetailLayout unresolvedLayout = TournamentDetailLayout.regular,
  }) {
    final normalizedTourId = tourId?.trim();
    if (normalizedTourId != null && normalizedTourId.isNotEmpty) {
      _activeTourId = normalizedTourId;
      final detected = tournamentDetailLayoutForDetection(
        isTeam: isTeam,
        isKnockout: isKnockout,
      );
      final remembered = _layoutsByTour[normalizedTourId];

      if (!isDetectionPending) {
        final shouldRemember =
            remembered == null ||
            (detected == TournamentDetailLayout.team &&
                remembered != TournamentDetailLayout.team) ||
            (remembered == TournamentDetailLayout.regular &&
                detected == TournamentDetailLayout.individualKnockout);
        if (shouldRemember) {
          _layoutsByTour[normalizedTourId] = detected;
        }
      }

      if (remembered == null && isDetectionPending) {
        return unresolvedLayout;
      }
    }

    final activeTourId = _activeTourId;
    if (activeTourId == null) return TournamentDetailLayout.regular;
    return _layoutsByTour[activeTourId] ?? TournamentDetailLayout.regular;
  }
}
