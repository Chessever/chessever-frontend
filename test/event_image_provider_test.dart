import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:chessever2/widgets/event_card/event_image_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeTourRepository extends TourRepository {
  _FakeTourRepository(this.tours);

  final List<Tour> tours;
  int calls = 0;

  @override
  Future<List<Tour>> getTourByGroupId(String groupId) async {
    calls++;
    return tours;
  }
}

Tour _tour({required String id, String? image}) {
  return Tour.fromJson({
    'id': id,
    'name': 'Tour $id',
    'slug': id,
    'info': {
      'format': 'Swiss',
      'tc': '3+1',
      'players': '',
      'location': 'Online',
    },
    'created_at': DateTime.utc(2026, 7, 7).toIso8601String(),
    'url': 'https://example.com/$id',
    'tier': 1,
    'dates': [DateTime.utc(2026, 7, 7).toIso8601String()],
    'players': const <Map<String, dynamic>>[],
    'search': const <String>[],
    'group_broadcast_id': 'event-1',
    'avg_elo': 2700,
    'image': image,
  });
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    try {
      Supabase.instance.client;
    } catch (_) {
      await Supabase.initialize(
        url: 'http://localhost:54321',
        anonKey: 'test-anon-key',
      );
    }
  });

  test('event image provider keeps resolved broadcast images alive', () async {
    final repository = _FakeTourRepository([
      _tour(id: 'tour-1', image: 'https://example.com/titled-tuesday.png'),
    ]);
    final container = ProviderContainer(
      overrides: [tourRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final provider = eventImageProvider('event-1');
    final subscription = container.listen(provider, (_, __) {});
    final first = await container.read(provider.future);
    subscription.close();

    await Future<void>.delayed(Duration.zero);

    final second = await container.read(provider.future);

    expect(first.imageUrl, 'https://example.com/titled-tuesday.png');
    expect(second.imageUrl, first.imageUrl);
    expect(repository.calls, 1);
  });
}
