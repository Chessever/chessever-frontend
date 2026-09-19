import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/group_event/model/about_tour_model.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  test(
    'only confirmed knockouts load siblings, and release them if reclassified',
    () {
      final detectedKnockout = StateProvider((ref) => false);
      final observedTours = <String>[];
      Tour tour(String id, String group) => Tour(
        id: id,
        name: id,
        slug: id,
        info: TourInfo(format: 'Swiss'),
        createdAt: DateTime.utc(2026),
        url: '',
        tier: 0,
        dates: [],
        players: [],
        groupBroadcastId: group,
      );
      final open = tour('open', 'olympiad');
      final container = ProviderContainer(
        overrides: [
          tourDetailScreenProviderOverride(
            TourDetailViewModel(
              aboutTourModel: AboutTourModel.fromTour(open),
              liveTourIds: [],
              tours: [
                for (final t in [
                  open,
                  tour('women', 'olympiad'),
                  tour('unrelated', 'other'),
                ])
                  TourModel(tour: t, roundStatus: RoundStatus.live),
              ],
            ),
          ),
          knockoutTournamentStateProvider.overrideWith((ref, id) {
            observedTours.add(id!);
            return KnockoutTournamentState(
              isKnockout: ref.watch(detectedKnockout),
              isTeamEvent: false,
              stageName: null,
              allGames: [],
            );
          }),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        relatedKnockoutStageIdsProvider('open'),
        (_, __) {},
      );
      addTearDown(subscription.close);
      expect(subscription.read(), isEmpty);
      expect(observedTours, ['open']);

      container.read(detectedKnockout.notifier).state = true;
      expect(container.read(relatedKnockoutStageIdsProvider('open')), [
        'women',
      ]);
      container.read(detectedKnockout.notifier).state = false;
      expect(container.read(relatedKnockoutStageIdsProvider('open')), isEmpty);
    },
  );
}
