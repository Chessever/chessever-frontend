import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/repository/supabase/round/round_repository.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/tour_detail/bracket/utils/knockout_stage_parser.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/knockout_match_detector.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const String kKnockoutStagePrefix = 'knockout-stage';

class KnockoutTournamentState {
  final bool isKnockout;

  /// True when this tour is a team event (`N-team` format or every player
  /// teamed and not an explicit `N-player` knockout). Drives the 4-tab layout.
  final bool isTeamEvent;
  final bool isDetectionPending;
  final String? stageName;
  final List<GamesTourModel> allGames;

  const KnockoutTournamentState({
    required this.isKnockout,
    required this.isTeamEvent,
    this.isDetectionPending = false,
    required this.stageName,
    required this.allGames,
  });

  const KnockoutTournamentState.empty()
    : isKnockout = false,
      isTeamEvent = false,
      isDetectionPending = false,
      stageName = null,
      allGames = const <GamesTourModel>[];
}

final knockoutTournamentStateProvider = Provider.autoDispose.family<
  KnockoutTournamentState,
  String?
>((ref, tourId) {
  if (tourId == null || tourId.isEmpty) {
    return const KnockoutTournamentState.empty();
  }

  final tourDetailAsync = ref.watch(tourDetailScreenProvider);
  final tourDetail = tourDetailAsync.valueOrNull;
  final Tour? tourMetadata = _findTourById(tourDetail, tourId);
  final formatString = tourMetadata?.info.format;
  final metadataRequest = resolveKnockoutRoundMetadataRequest(
    tourDetail: tourDetail,
    tourId: tourId,
  );
  final tourName = metadataRequest.tourName;
  final roundEvidenceAsync = ref.watch(
    knockoutRoundMetadataEvidenceProvider(metadataRequest),
  );
  final hasExplicitNonKnockoutFormat = formatRulesOutKnockout(formatString);
  final hasTourNameStageEvidence = hasTrustworthyKnockoutStageMetadata(
    rounds: const <Round>[],
    tourName: tourName,
  );
  final hasRoundMetadataEvidence =
      !hasExplicitNonKnockoutFormat &&
      (hasTourNameStageEvidence || (roundEvidenceAsync.valueOrNull ?? false));

  final gamesAsync = ref.watch(gamesTourProvider(tourId));
  final rawGames = gamesAsync.valueOrNull ?? const <Games>[];

  final models = <GamesTourModel>[];
  for (final game in rawGames) {
    try {
      models.add(GamesTourModel.fromGame(game));
    } catch (_) {
      // Ignore games that fail to parse into display models
    }
  }

  // Team brackets (e.g. "16-team Knockout") must NEVER use the player
  // knockout view: that view groups games by 1v1 player matchups, which
  // shatters a team-vs-team round (many boards) into meaningless
  // single-game "matches". Route these to the group-event (team) view.
  //
  // The discriminator is the curated FORMAT token, NOT "every player has a
  // team". Two look-alikes prove why:
  //  - A 16-team double-leg knockout has repeated pairs + "game-1/2" slugs,
  //    so the structural detector ALSO flags it as knockout — gating must
  //    cover the inferred path too, not just the format string.
  //  - Individual events like the FIDE World Cup ("206-player ... Knockout")
  //    tag every player with a club/team, so an "all players have a team"
  //    test would wrongly demote them out of the (correct) knockout view.
  // Hence: "N-team" => team event; an explicit "N-player" format always
  // stays a player knockout even when team metadata is present; a bare
  // "Knockout" with every player teamed (e.g. corporate brackets) is team.
  final teamPlayers =
      (tourMetadata?.players.isNotEmpty ?? false)
          ? tourMetadata!.players
          : (tourDetail?.aboutTourModel.players ?? const <TournamentPlayer>[]);
  final lowerFormat = (formatString ?? '').toLowerCase();
  final formatSaysTeam = lowerFormat.contains('team');
  final formatSaysPlayer = lowerFormat.contains('player');
  final allPlayersHaveTeam =
      teamPlayers.isNotEmpty && teamPlayers.every((p) => p.team != null);
  final isTeamEvent = resolveTeamEventClassification(
    teamTable: tourMetadata?.info.teamTable,
    formatSaysTeam: formatSaysTeam,
    formatSaysPlayer: formatSaysPlayer,
    allPlayersHaveTeam: allPlayersHaveTeam,
  );

  // Check format string first (fast), only analyze games if inconclusive
  final explicitKnockout =
      !isTeamEvent && _formatSuggestsKnockout(formatString);
  final inferredKnockout =
      !isTeamEvent &&
      !explicitKnockout &&
      !hasExplicitNonKnockoutFormat &&
      !hasRoundMetadataEvidence &&
      models.isNotEmpty &&
      KnockoutMatchDetector.isKnockoutMatchFormat(models);
  final isKnockout = isIndividualKnockoutFromEvidence(
    isTeamEvent: isTeamEvent,
    explicitFormat: explicitKnockout,
    explicitNonKnockoutFormat: hasExplicitNonKnockoutFormat,
    roundMetadata: hasRoundMetadataEvidence,
    inferredFromGames: inferredKnockout,
  );
  final metadataDetectionIsLoading =
      !hasTourNameStageEvidence && roundEvidenceAsync.isLoading;
  final gamesDetectionIsLoading = !gamesAsync.hasValue && !gamesAsync.hasError;
  final isDetectionPending =
      !isTeamEvent &&
      !hasExplicitNonKnockoutFormat &&
      !isKnockout &&
      (metadataDetectionIsLoading || gamesDetectionIsLoading);

  if (models.isEmpty && !isKnockout) {
    // Team detection keys off the format string, so it is known even
    // before games load — surface it so the 4-tab layout appears eagerly.
    return KnockoutTournamentState(
      isKnockout: false,
      isTeamEvent: isTeamEvent,
      isDetectionPending: isDetectionPending,
      stageName: null,
      allGames: models,
    );
  }

  if (!isKnockout) {
    return KnockoutTournamentState(
      isKnockout: false,
      isTeamEvent: isTeamEvent,
      isDetectionPending: isDetectionPending,
      stageName: null,
      allGames: models,
    );
  }

  final stageName = _resolveStageName(
    tourName: tourName,
    formatString: formatString,
  );

  return KnockoutTournamentState(
    isKnockout: true,
    isTeamEvent: false,
    isDetectionPending: false,
    stageName: stageName,
    allGames: models,
  );
});

/// Prefer Lichess's explicit `tour.teamTable` signal. The older heuristics are
/// retained only for rows ingested before the data hub preserved that field.
bool resolveTeamEventClassification({
  required bool? teamTable,
  required bool formatSaysTeam,
  required bool formatSaysPlayer,
  required bool allPlayersHaveTeam,
}) =>
    teamTable ??
    (formatSaysTeam || (!formatSaysPlayer && allPlayersHaveTeam));

typedef KnockoutRoundMetadataRequest = ({String tourId, String tourName});

KnockoutRoundMetadataRequest resolveKnockoutRoundMetadataRequest({
  required TourDetailViewModel? tourDetail,
  required String tourId,
}) => (
  tourId: tourId,
  tourName:
      _findTourById(tourDetail, tourId)?.name ??
      tourDetail?.aboutTourModel.name ??
      '',
);

final knockoutRoundMetadataEvidenceProvider = FutureProvider.autoDispose
    .family<bool, KnockoutRoundMetadataRequest>((ref, request) async {
      final rounds = await ref
          .watch(roundRepositoryProvider)
          .getRoundsByTourId(request.tourId);
      return hasTrustworthyKnockoutStageMetadata(
        rounds: rounds,
        tourName: request.tourName,
      );
    });

bool isIndividualKnockoutFromEvidence({
  required bool isTeamEvent,
  required bool explicitFormat,
  bool explicitNonKnockoutFormat = false,
  required bool roundMetadata,
  required bool inferredFromGames,
}) =>
    !isTeamEvent &&
    !explicitNonKnockoutFormat &&
    (explicitFormat || roundMetadata || inferredFromGames);

/// Conservative evidence that a feed is an elimination event before enough
/// games exist for repeated-matchup detection.
///
/// Plain `Round 3` metadata is intentionally insufficient because Swiss and
/// round-robin feeds use it too. Decimal/tiebreak legs, named elimination
/// stages, stage-bearing slugs, and stage-scoped tour names are trustworthy.
bool hasTrustworthyKnockoutStageMetadata({
  required Iterable<Round> rounds,
  required String tourName,
}) {
  final tourDescriptor = parseKnockoutTourStageDescriptor(tourName);
  final tourHasStage = tourDescriptor.stage != null;
  if (tourHasStage &&
      (tourName.contains('|') || _containsNamedEliminationStage(tourName))) {
    return true;
  }

  for (final round in rounds) {
    final name = round.name.trim();
    final slug = round.slug.trim().toLowerCase();
    final resolved = resolveLogicalKnockoutStage(
      name,
      slug,
      tourName: tourName,
    );
    if (resolved == null) continue;

    if (RegExp(r'^round\s+\d+[._]\d+', caseSensitive: false).hasMatch(name) ||
        RegExp(
          r'\b(?:tie[ -]?breaks?|rapid|blitz|armageddon)\b',
          caseSensitive: false,
        ).hasMatch(name) ||
        _containsNamedEliminationStage(name) ||
        slug.contains('--') ||
        slug.startsWith('stage-') ||
        (tourHasStage && _isGenericKnockoutLeg(name, slug))) {
      return true;
    }
  }

  return false;
}

bool _containsNamedEliminationStage(String value) => RegExp(
  r'\b(?:round\s+of\s+\d+|last\s+\d+|quarter[ -]?finals?|semi[ -]?finals?|finals?|third[ -]?place|bronze)\b',
  caseSensitive: false,
).hasMatch(value);

bool _isGenericKnockoutLeg(String name, String slug) {
  final normalizedName = name.trim().toLowerCase();
  final normalizedSlug = slug.replaceAll('_', '-');
  return RegExp(
        r'^(?:game|leg|tie[ -]?breaks?|rapid|blitz|armageddon)\b',
        caseSensitive: false,
      ).hasMatch(normalizedName) ||
      RegExp(
        r'^(?:game|leg|tie-?breaks?|rapid|blitz|armageddon)(?:-|$)',
      ).hasMatch(normalizedSlug);
}

/// True when the current tour is a team event (drives the 4-tab layout).
final isTeamEventProvider = Provider.autoDispose.family<bool, String?>((
  ref,
  tourId,
) {
  if (tourId == null || tourId.isEmpty) return false;
  return ref.watch(knockoutTournamentStateProvider(tourId)).isTeamEvent;
});

Tour? _findTourById(TourDetailViewModel? viewModel, String tourId) {
  if (viewModel == null) return null;
  for (final TourModel tourModel in viewModel.tours) {
    if (tourModel.tour.id == tourId) {
      return tourModel.tour;
    }
  }
  return null;
}

bool _formatSuggestsKnockout(String? format) {
  if (format == null || format.isEmpty) return false;
  final lower = format.toLowerCase();
  return lower.contains('knockout') ||
      lower.contains('single-elimination') ||
      lower.contains('elimination');
}

bool formatRulesOutKnockout(String? format) {
  if (format == null || format.isEmpty) return false;
  final lower = format.toLowerCase().replaceAll('_', ' ').replaceAll('-', ' ');
  return lower.contains('swiss') ||
      lower.contains('round robin') ||
      lower.contains('all play all') ||
      lower.contains('league');
}

String? _resolveStageName({
  required String tourName,
  required String? formatString,
}) {
  if (tourName.isNotEmpty) {
    final extracted = KnockoutMatchDetector.extractTournamentRoundName(
      tourName,
    );
    if (extracted.isNotEmpty) {
      return extracted;
    }
  }

  if (formatString == null || formatString.isEmpty) {
    return null;
  }

  final lower = formatString.toLowerCase();
  final stagePatterns = <RegExp>[
    RegExp(r'(quarterfinals?)'),
    RegExp(r'(semifinals?)'),
    RegExp(r'(finals?)'),
    RegExp(r'(round\s+\d+)'),
  ];

  for (final pattern in stagePatterns) {
    final match = pattern.firstMatch(lower);
    if (match != null) {
      final value = match.group(0);
      if (value != null && value.isNotEmpty) {
        return value
            .split(' ')
            .map(
              (word) =>
                  word.isEmpty
                      ? word
                      : word[0].toUpperCase() + word.substring(1),
            )
            .join(' ');
      }
    }
  }

  return null;
}
