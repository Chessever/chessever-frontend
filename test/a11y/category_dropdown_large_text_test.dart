import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/group_event/model/about_tour_model.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/category_dropdown.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_app_bar_widget.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_repo_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _MemoryStore implements TourSelectionStore {
  final Map<String, String> values = {};
  @override
  Future<String?> getString(String key) async => values[key];
  @override
  Future<void> remove(String key) async => values.remove(key);
  @override
  Future<void> setString(String key, String value) async =>
      values[key] = value;
}

Tour _tour(String id, String name) => Tour.virtual(
  id: id,
  name: name,
  slug: id,
  dates: [DateTime.utc(2026, 11, 7), DateTime.utc(2026, 11, 14)],
  players: const [],
);

void main() {
  const groupName = 'IV OPEN INTERNACIONAL DE AJEDREZ CAP NEGRET';
  final t65 = _tour('vSUNaTSs', '$groupName | 65+');
  final t50 = _tour('9xj1Ehti', '$groupName | 50+');

  final broadcast = GroupBroadcast.fromJson({
    'id': 'iv_open_internacional_de_ajedrez_cap_negret',
    'created_at': '2026-11-05T19:50:50.000Z',
    'name': groupName,
    'search': const <String>[],
  });

  for (final (scale, w, h, bold) in [(1.0, 393.0, 852.0, false), (3.1, 393.0, 852.0, true), (1.35, 320.0, 568.0, true), (3.1, 320.0, 568.0, true), (2.0, 375.0, 667.0, true), (1.0, 1024.0, 1366.0, false), (2.0, 932.0, 430.0, true), (1.0, 932.0, 430.0, false)]) {
    testWidgets('switches 65+ -> 50+ at $scale ${w}x$h bold=$bold', (tester) async {
      tester.view.physicalSize = Size(w * 3, h * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(
        overrides: [
          selectedBroadcastModelProvider.overrideWith((ref) => broadcast),
          tourSelectionStoreProvider.overrideWithValue(_MemoryStore()),
          gamesAppBarTourIdProvider.overrideWith((ref) => null),
          tourDetailScreenProviderOverride(
            TourDetailViewModel(
              aboutTourModel: AboutTourModel.fromTour(t65),
              liveTourIds: const [],
              tours: [
                TourModel(tour: t65, roundStatus: RoundStatus.ongoing),
                TourModel(tour: t50, roundStatus: RoundStatus.ongoing),
              ],
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale), boldText: bold, disableAnimations: bold),
                  child: const Scaffold(
                    body: SafeArea(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: GamesAppBarWidget(),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(CategoryDropdown));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final option = find.text('50+');
      expect(option, findsWidgets, reason: '50+ row is not rendered');
      await tester.tap(option.last, warnIfMissed: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        container.read(tourDetailScreenProvider).valueOrNull?.aboutTourModel.id,
        t50.id,
        reason: 'selection did not move to 50+',
      );
      // drain marquee timers
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 30));
    });
  }
}
