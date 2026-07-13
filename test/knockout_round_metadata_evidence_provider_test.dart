import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/repository/supabase/round/round_repository.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    try {
      Supabase.instance.client;
    } catch (_) {
      await Supabase.initialize(
        url: 'https://placeholder.supabase.co',
        anonKey: 'placeholder-anon-key',
      );
    }
  });

  test(
    'cached false evidence becomes true after a decimal round publishes',
    () async {
      final repository = _MutableRoundRepository();
      final container = ProviderContainer(
        overrides: [roundRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      const request = (tourId: 'tour', tourName: 'Open Cup');
      final subscription = container.listen(
        knockoutRoundMetadataEvidenceProvider(request),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      expect(
        await container.read(
          knockoutRoundMetadataEvidenceProvider(request).future,
        ),
        isFalse,
      );

      repository.rounds = [_round('round-31', 'Round 3.1', 'round-3-1')];
      expect(
        container
            .read(knockoutRoundMetadataEvidenceProvider(request))
            .valueOrNull,
        isFalse,
      );

      container.invalidate(knockoutRoundMetadataEvidenceProvider(request));

      expect(
        await container.read(
          knockoutRoundMetadataEvidenceProvider(request).future,
        ),
        isTrue,
      );
      expect(repository.fetchCount, 2);
    },
  );
}

Round _round(String id, String name, String slug) => Round(
  id: id,
  slug: slug,
  tourId: 'tour',
  tourSlug: 'tour',
  name: name,
  createdAt: DateTime.utc(2026, 7, 11),
  startsAt: DateTime.utc(2026, 7, 11),
  url: 'https://lichess.org/broadcast/tour/$slug/$id',
);

class _MutableRoundRepository extends RoundRepository {
  List<Round> rounds = const <Round>[];
  int fetchCount = 0;

  @override
  Future<List<Round>> getRoundsByTourId(String tourId) async {
    fetchCount++;
    return List<Round>.of(rounds);
  }
}
