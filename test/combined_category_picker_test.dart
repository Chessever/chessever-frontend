import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/group_event/model/about_tour_model.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_category.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/category_dropdown.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_app_bar_widget.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_repo_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
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
  Future<void> setString(String key, String value) async => values[key] = value;
}

const _groupName = 'Total Chess World Championship Tour';
const _groupId = 'total_chess_world_championship_tour';

Tour _tour(String id, String section) => Tour.virtual(
  id: id,
  name: '$_groupName | $section',
  slug: id,
  dates: [DateTime.utc(2026, 11, 7), DateTime.utc(2026, 11, 14)],
  players: const [],
);

final _groupA = _tour('tour-a', 'Group A');
final _groupB = _tour('tour-b', 'Group B');
final _mirror = _tour('tour-combined', 'Combined');

final _broadcast = GroupBroadcast.fromJson({
  'id': _groupId,
  'created_at': '2026-11-05T19:50:50.000Z',
  'name': _groupName,
  'search': const <String>[],
});

/// The synthetic row reads "Combined   all N"; an organizer's own Combined
/// section is a plain category row without the count.
Finder _combinedRow(int count) =>
    find.textContaining('all $count', findRichText: true);

Future<ProviderContainer> _pumpPicker(
  WidgetTester tester, {
  required List<Tour> tours,
  bool entitled = true,
  TournamentDetailScreenMode mode = TournamentDetailScreenMode.games,
}) async {
  tester.view.physicalSize = const Size(393 * 3, 852 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      selectedBroadcastModelProvider.overrideWith((ref) => _broadcast),
      selectedTourModeProvider.overrideWith((ref) => mode),
      tourSelectionStoreProvider.overrideWithValue(_MemoryStore()),
      gamesAppBarTourIdProvider.overrideWith((ref) => null),
      premiumAccessProvider.overrideWithValue(entitled),
      tourDetailScreenProviderOverride(
        TourDetailViewModel(
          aboutTourModel: AboutTourModel.fromTour(tours.first),
          liveTourIds: const [],
          tours: [
            for (final tour in tours)
              TourModel(tour: tour, roundStatus: RoundStatus.ongoing),
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
            return const Scaffold(
              body: SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: GamesAppBarWidget(),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  return container;
}

Future<void> _openPicker(WidgetTester tester) async {
  await tester.tap(find.byType(CategoryDropdown));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _settlePicker(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Closes a picker left open by a test that only read its rows.
Future<void> _closePicker(WidgetTester tester) async {
  // The open picker's backdrop covers the chip and closes it just the same.
  await tester.tap(find.byType(CategoryDropdown), warnIfMissed: false);
  await _settlePicker(tester);
}

/// Marquee and shimmer tickers outlive the assertions; let them drain.
Future<void> _drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 30));
}

void main() {
  test('only a merged category other than the selected one is "other"', () {
    ProviderContainer container({required bool combined}) {
      final container = ProviderContainer(
        overrides: [
          combinedCategorySelectedProvider.overrideWithValue(combined),
          combinedCategoriesProvider.overrideWithValue(
            CombinedCategories.fromTours([
              for (final tour in [_groupA, _groupB])
                TourModel(tour: tour, roundStatus: RoundStatus.ongoing),
            ]),
          ),
          tourDetailScreenProviderOverride(
            TourDetailViewModel(
              aboutTourModel: AboutTourModel.fromTour(_groupA),
              liveTourIds: const [],
              tours: [
                for (final tour in [_groupA, _groupB, _mirror])
                  TourModel(tour: tour, roundStatus: RoundStatus.ongoing),
              ],
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    final combined = container(combined: true);
    // Group B is merged in but is not the category selected underneath.
    expect(combined.read(combinedOtherCategoryProvider('tour-b')), isTrue);
    // The selected category, the organizer mirror and a stranger are not.
    expect(combined.read(combinedOtherCategoryProvider('tour-a')), isFalse);
    expect(
      combined.read(combinedOtherCategoryProvider('tour-combined')),
      isFalse,
    );
    expect(combined.read(combinedOtherCategoryProvider('elsewhere')), isFalse);
    expect(combined.read(combinedOtherCategoryProvider('')), isFalse);

    // Outside Combined nothing changes for anyone.
    expect(
      container(combined: false).read(combinedOtherCategoryProvider('tour-b')),
      isFalse,
    );
  });

  testWidgets('the picker offers Combined above the categories it merges', (
    tester,
  ) async {
    final container = await _pumpPicker(tester, tours: [_groupA, _groupB]);
    await _openPicker(tester);

    expect(_combinedRow(2), findsOneWidget);
    final combinedTop = tester.getTopLeft(_combinedRow(2)).dy;
    expect(combinedTop, lessThan(tester.getTopLeft(find.text('Group B')).dy));
    // Combined never shows a Premium lock.
    expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);

    await tester.tap(_combinedRow(2));
    await _settlePicker(tester);

    expect(container.read(combinedCategorySelectedProvider), isTrue);
    // The chip names what the Games tab now shows.
    expect(find.text(kCombinedCategoryLabel), findsOneWidget);
    // The category underneath is untouched, for About and Standings.
    expect(
      container.read(tourDetailScreenProvider).valueOrNull?.aboutTourModel.id,
      _groupA.id,
    );
    await _drain(tester);
  });

  testWidgets('picking a real category on Games leaves Combined', (
    tester,
  ) async {
    final container = await _pumpPicker(tester, tours: [_groupA, _groupB]);
    await container
        .read(combinedCategoryPrefsProvider.notifier)
        .setSelected(_groupId, true);
    await tester.pump();
    expect(container.read(combinedCategorySelectedProvider), isTrue);

    await _openPicker(tester);
    await tester.tap(find.text('Group B').last);
    await _settlePicker(tester);

    expect(container.read(combinedCategorySelectedProvider), isFalse);
    expect(
      container.read(tourDetailScreenProvider).valueOrNull?.aboutTourModel.id,
      _groupB.id,
    );
    await _drain(tester);
  });

  testWidgets('without Premium Combined opens without a lock', (
    tester,
  ) async {
    final container = await _pumpPicker(
      tester,
      tours: [_groupA, _groupB],
      entitled: false,
    );
    await _openPicker(tester);

    expect(_combinedRow(2), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);

    await tester.tap(_combinedRow(2));
    await _settlePicker(tester);

    expect(container.read(combinedCategorySelectedProvider), isTrue);
    expect(find.text(kCombinedCategoryLabel), findsOneWidget);
    await _drain(tester);
  });

  testWidgets('an organizer Combined section is not merged or duplicated', (
    tester,
  ) async {
    // One real group beside its mirror: nothing to combine, so the picker
    // lists the two real rows and no synthetic one.
    final container = await _pumpPicker(tester, tours: [_groupA, _mirror]);
    await _openPicker(tester);

    expect(container.read(combinedCategoriesProvider).canCombine, isFalse);
    expect(_combinedRow(1), findsNothing);
    expect(_combinedRow(2), findsNothing);
    await _closePicker(tester);
    await _drain(tester);
  });

  testWidgets('two real groups merge without the organizer mirror', (
    tester,
  ) async {
    final container = await _pumpPicker(
      tester,
      tours: [_groupA, _groupB, _mirror],
    );
    await _openPicker(tester);

    // "all 2", not 3: the mirror would list every board twice.
    expect(_combinedRow(2), findsOneWidget);
    expect(container.read(combinedCategoriesProvider).tourIds, [
      _groupA.id,
      _groupB.id,
    ]);
    await _closePicker(tester);
    await _drain(tester);
  });

  testWidgets('About and Standings keep naming the real category', (
    tester,
  ) async {
    final container = await _pumpPicker(
      tester,
      tours: [_groupA, _groupB],
      mode: TournamentDetailScreenMode.standings,
    );
    await container
        .read(combinedCategoryPrefsProvider.notifier)
        .setSelected(_groupId, true);
    await tester.pump();

    expect(container.read(combinedCategorySelectedProvider), isTrue);
    // Games is combined, but this chip belongs to another tab.
    expect(find.text('Group A'), findsOneWidget);
    expect(find.text(kCombinedCategoryLabel), findsNothing);
    // Off the Games tab the merged tours fall back to the slow cadence.
    expect(container.read(combinedLiveTourIdsProvider), isEmpty);
    await _drain(tester);
  });
}
