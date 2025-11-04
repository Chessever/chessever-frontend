import 'package:chessever2/repository/supabase/game/games.dart';
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

final knockoutTournamentStateProvider = Provider.autoDispose.family<
  KnockoutTournamentState,
  String?
>((ref, tourId) {
  if (tourId == null || tourId.isEmpty) {
    return const KnockoutTournamentState.empty();
  }

  final gamesAsync = ref.watch(gamesTourProvider(tourId));
  final rawGames = gamesAsync.valueOrNull ?? const <Games>[];

  if (rawGames.isEmpty) {
    return const KnockoutTournamentState.empty();
  }

  final models = <GamesTourModel>[];
  for (final game in rawGames) {
    try {
      models.add(GamesTourModel.fromGame(game));
    } catch (_) {
      // Ignore games that fail to parse into display models
    }
  }

  if (models.isEmpty) {
    return const KnockoutTournamentState.empty();
  }

  final isKnockout = KnockoutMatchDetector.isKnockoutMatchFormat(models);
  if (!isKnockout) {
    return KnockoutTournamentState(
      isKnockout: false,
      stageName: null,
      allGames: models,
    );
  }

  final tourName =
      ref.read(tourDetailScreenProvider).value?.aboutTourModel.name ?? '';
  final stageName =
      tourName.isNotEmpty
          ? KnockoutMatchDetector.extractTournamentRoundName(tourName)
          : null;

  return KnockoutTournamentState(
    isKnockout: true,
    stageName: stageName,
    allGames: models,
  );
});
