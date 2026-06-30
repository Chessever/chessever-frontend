import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeGroupBroadcastRepository extends GroupBroadcastRepository {
  @override
  Future<GroupBroadcast> getGroupBroadcastById(String id) async {
    await Future<void>.delayed(Duration.zero);
    return GroupBroadcast(
      id: id,
      createdAt: DateTime.utc(2026),
      name: 'FIDE World Cup 2025',
      search: const ['FIDE World Cup 2025'],
      dateStart: DateTime.utc(2025, 11),
      dateEnd: DateTime.utc(2025, 11, 26),
      timeControl: 'standard',
    );
  }
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

  testWidgets('search result opens tournament detail on the Games tab', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          groupBroadcastRepositoryProvider.overrideWithValue(
            _FakeGroupBroadcastRepository(),
          ),
        ],
        child: MaterialApp(
          routes: {
            '/':
                (context) => Consumer(
                  builder: (context, ref, _) {
                    return TextButton(
                      onPressed: () {
                        ref
                            .read(tournamentNavigationProvider)
                            .openTournament(
                              context: context,
                              id: 'fide_world_cup_2025',
                              category: GroupEventCategory.search,
                            );
                      },
                      child: const Text('open'),
                    );
                  },
                ),
            '/tournament_detail_screen':
                (context) => Consumer(
                  builder: (context, ref, _) {
                    final selected = ref.watch(selectedBroadcastModelProvider);
                    final mode = ref.watch(selectedTourModeProvider);
                    return Text('${selected?.id ?? 'missing'}:${mode.name}');
                  },
                ),
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('fide_world_cup_2025:games'), findsOneWidget);
  });
}
