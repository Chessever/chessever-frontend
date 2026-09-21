import 'dart:async';

import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/tour_game_snapshot_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/tournament_card_visibility_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/viewport_game_card.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:visibility_detector/visibility_detector.dart';

GamesTourModel _preview(String id) => GamesTourModel.fromGame(
  Games(
    id: id,
    tourId: 'tour',
    tourSlug: 'tour',
    roundId: 'round',
    roundSlug: 'round',
    status: '1-0',
    players: [
      for (final name in ['White', 'Black'])
        Player(
          name: name,
          title: '',
          rating: 0,
          fideId: 0,
          fed: '',
          clock: 0,
          team: '',
        ),
    ],
    isPgnDeferred: true,
  ),
);

Future<void> _frame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pump();
}

Widget _app(ProviderContainer container, Widget child) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: Align(alignment: Alignment.topLeft, child: child),
            );
          },
        ),
      ),
    );

void main() {
  setUp(() {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });
  tearDown(() {
    VisibilityDetectorController.instance.updateInterval = const Duration(
      milliseconds: 500,
    );
  });

  testWidgets(
    'mounted offscreen team boards load only after scrolling into view',
    (tester) async {
      final requests = <String>[];
      final replies = <String, Completer<Games?>>{};
      final container = ProviderContainer(
        overrides: [
          tourGameSnapshotProvider.overrideWith((ref, id) {
            requests.add(id);
            return (replies[id] = Completer<Games?>()).future;
          }),
        ],
      );
      final controller = ScrollController();
      final built = <String>{};
      Widget card(String id) => ViewportGameCard(
        key: ValueKey(id),
        game: _preview(id),
        builder: (_) {
          built.add(id);
          return SizedBox(height: 100, child: Text('loaded $id'));
        },
      );
      await tester.pumpWidget(
        _app(
          container,
          SizedBox(
            width: 360,
            height: 200,
            // A Column deliberately mounts every child, as nested team lists do.
            child: SingleChildScrollView(
              controller: controller,
              child: Column(
                children: [
                  card('top'),
                  const SizedBox(height: 700),
                  card('bottom'),
                ],
              ),
            ),
          ),
        ),
      );
      await _frame(tester);
      expect(find.byType(ViewportGameCard), findsNWidgets(2));
      expect(requests, ['top']);
      expect(built, isEmpty);
      expect(find.byType(TournamentCardShimmer), findsNWidgets(2));
      replies['top']!.complete(null);
      await _frame(tester);
      expect(find.text('loaded top'), findsOneWidget);
      expect(container.read(visibleTournamentCardsProvider).values, ['top']);

      controller.jumpTo(controller.position.maxScrollExtent);
      await _frame(tester);
      expect(requests, ['top', 'bottom']);
      expect(built, {'top'});
      expect(container.read(visibleTournamentCardsProvider).values, ['bottom']);
      replies['bottom']!.complete(null);
      await _frame(tester);
      expect(find.text('loaded bottom'), findsOneWidget);
      expect(find.text('loaded top'), findsNothing);

      controller.jumpTo(0);
      await _frame(tester);
      expect(find.text('loaded top'), findsOneWidget);
      expect(requests, [
        'top',
        'bottom',
      ]); // Cached snapshot, no second download.
      await tester.pumpWidget(const SizedBox());
      await _frame(tester);
      expect(container.read(visibleTournamentCardsProvider), isEmpty);
      container.dispose();
      controller.dispose();
    },
  );

  testWidgets('live batches omit offscreen games and retain shared channels', (
    tester,
  ) async {
    final container = ProviderContainer();
    final topToken = Object();
    final nextToken = Object();
    final batch = LiveGamesBatchKey(
      scopeId: 'round',
      gameIds: ['top', 'next', 'hidden'],
    );
    LiveGamesBatchKey? resolved;
    Widget reader() => Consumer(
      builder: (context, ref, _) {
        resolved = watchVisibleTournamentBatch(ref, batch);
        return const SizedBox();
      },
    );
    container.read(visibleTournamentCardsProvider.notifier).state = {
      topToken: 'top',
    };
    await tester.pumpWidget(
      _app(container, TournamentCardViewport(child: reader())),
    );
    expect(resolved!.gameIds, ['top']);
    container.read(visibleTournamentCardsProvider.notifier).state = {
      topToken: 'top',
      nextToken: 'next',
    };
    await _frame(tester);
    expect(resolved!.gameIds, ['next', 'top']);
    expect(resolved!.isScopedFilter, isFalse);
    // The same helper in other app surfaces keeps its original policy.
    await tester.pumpWidget(_app(container, reader()));
    expect(resolved, batch);
    await tester.pumpWidget(const SizedBox());
    await _frame(tester);
    container.dispose();
  });
}
