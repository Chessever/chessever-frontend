import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/screens/group_event/model/about_tour_model.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/tour_detail/about_tour_screen.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_tour_id_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/tournament_detail_screen.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  const tourUrl = 'https://lichess.org/broadcast/test-open/tour-1';

  GroupBroadcast broadcast({required String writer}) => GroupBroadcast.fromJson({
    'id': 'gb-1',
    'created_at': '2026-08-24T12:00:00.000Z',
    'name': 'Test Open',
    'search': const <String>[],
    'broadcast_writer': writer,
  });

  AboutTourModel aboutModel() => const AboutTourModel(
    id: 'tour-1',
    slug: 'test-open',
    name: 'Test Open',
    description: 'A representative about model.',
    imageUrl: '',
    players: [],
    timeControl: '90+30',
    date: '1 Jan 2026',
    location: '',
    websiteUrl: '',
    standingsUrl: '',
    tourUrl: tourUrl,
    groupBroadcastId: 'gb-1',
  );

  TourDetailViewModel viewModel() => TourDetailViewModel(
    aboutTourModel: aboutModel(),
    liveTourIds: const [],
    tours: const [],
  );

  List<Override> baseOverrides({
    required GroupBroadcast selected,
    required TourDetailViewModel data,
  }) {
    return [
      selectedBroadcastModelProvider.overrideWith((ref) => selected),
      canonicalSelectedBroadcastProvider.overrideWith((ref) async => selected),
      tourDetailScreenProviderOverride(data),
      selectedTourModeProvider.overrideWith(
        (ref) => TournamentDetailScreenMode.about,
      ),
      liveTourIdProvider.overrideWith(
        (ref) => Stream<List<String>>.value(const <String>[]),
      ),
      shouldStreamProvider.overrideWith((ref) => false),
      knockoutTournamentStateProvider.overrideWith(
        (ref, tourId) => const KnockoutTournamentState.empty(),
      ),
      gamesTourScreenProvider.overrideWith(
        (ref) => GamesTourScreenProvider.loading(ref: ref),
      ),
    ];
  }

  Future<void> pumpHost(
    WidgetTester tester, {
    required List<Override> overrides,
    required Widget child,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return child;
            },
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'About footer still shows Powered by with a Lichess writer and tour URL',
    (tester) async {
      final selected = broadcast(writer: GroupBroadcast.lichessDataHubWriter);
      await pumpHost(
        tester,
        overrides: baseOverrides(selected: selected, data: viewModel()),
        child: AboutTourScreen(),
      );

      expect(find.textContaining('Powered by'), findsOneWidget);
      expect(find.text('Lichess'), findsOneWidget);
      expect(find.text('ChessEver'), findsNothing);
    },
  );

  testWidgets(
    'About footer uses ChessEver when the selected broadcast is direct',
    (tester) async {
      final selected = broadcast(writer: GroupBroadcast.chesseverDirectWriter);
      await pumpHost(
        tester,
        overrides: baseOverrides(selected: selected, data: viewModel()),
        child: AboutTourScreen(),
      );

      expect(find.textContaining('Powered by'), findsOneWidget);
      expect(find.text('ChessEver'), findsOneWidget);
      expect(find.text('Lichess'), findsNothing);
    },
  );

  testWidgets(
    'tournament-detail success appbar does not render Powered by chrome',
    (tester) async {
      final selected = broadcast(writer: GroupBroadcast.chesseverDirectWriter);
      await pumpHost(
        tester,
        overrides: baseOverrides(selected: selected, data: viewModel()),
        child: const TournamentDetailScreen(),
      );

      final appBar = find.byKey(tournamentDetailSuccessAppBarKey);
      expect(appBar, findsOneWidget);
      expect(find.text('About'), findsWidgets);
      expect(find.text('Games'), findsWidgets);

      expect(
        find.descendant(
          of: appBar,
          matching: find.text('Powered by Lichess'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: appBar,
          matching: find.text('Powered by ChessEver'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: appBar, matching: find.textContaining('Powered by')),
        findsNothing,
      );
    },
  );
}
