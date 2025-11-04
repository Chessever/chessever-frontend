import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/knockout_match_detector.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const String kKnockoutStagePrefix = 'knockout-stage';

class KnockoutTournamentState {
  final bool isKnockout;
  final String? stageName;
  final List<GamesTourModel> allGames;

  const KnockoutTournamentState({
    required this.isKnockout,
    required this.stageName,
    required this.allGames,
  });

  const KnockoutTournamentState.empty()
    : isKnockout = false,
      stageName = null,
      allGames = const <GamesTourModel>[];
}

final knockoutTournamentStateProvider = Provider.autoDispose
    .family<KnockoutTournamentState, String?>((ref, tourId) {
      if (tourId == null || tourId.isEmpty) {
        return const KnockoutTournamentState.empty();
      }

      final tourDetailAsync = ref.watch(tourDetailScreenProvider);
      final tourDetail = tourDetailAsync.valueOrNull;
      final Tour? tourMetadata = _findTourById(tourDetail, tourId);
      final formatString = tourMetadata?.info.format;
      final tourName = tourDetail?.aboutTourModel.name ?? '';

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

      final inferredKnockout =
          models.isNotEmpty &&
          KnockoutMatchDetector.isKnockoutMatchFormat(models);
      final explicitKnockout = _formatSuggestsKnockout(formatString);
      final isKnockout = inferredKnockout || explicitKnockout;

      if (models.isEmpty && !explicitKnockout) {
        return const KnockoutTournamentState.empty();
      }

      if (!isKnockout) {
        return KnockoutTournamentState(
          isKnockout: false,
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
        stageName: stageName,
        allGames: models,
      );
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
