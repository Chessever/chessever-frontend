import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/widget/player_search_cards.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/search/enhanced_group_broadcast_local_storage.dart';
import 'package:chessever2/widgets/media_card.dart';
import 'package:chessever2/widgets/search/search_result_model.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// The cards above search results come from the results being shown. They
// used to read the Events tab's query, so Home search showed the last Events
// search's players, or none at all.
void main() {
  test('cards are the distinct players of the given results, in order', () {
    final results = _results([
      _player('Hikaru Nakamura', fideId: 2016192),
      _player('Hikaru Nakamura', fideId: 2016192),
      _player('Wesley So', fideId: 5202213),
    ]);

    expect(topSearchedPlayers(results).map((p) => p.name), [
      'Hikaru Nakamura',
      'Wesley So',
    ]);
  });

  test('same name without a FIDE id stays one card per person', () {
    final results = _results([
      _player('Ivan Petrov', memorialId: 'chessgames:1'),
      _player('Ivan Petrov', memorialId: 'chessgames:2'),
    ]);

    expect(topSearchedPlayers(results), hasLength(2));
  });

  test('at most four cards, and none for event-only results', () {
    final results = _results([
      for (var i = 0; i < 6; i++) _player('Player $i', fideId: 100 + i),
    ]);

    expect(topSearchedPlayers(results), hasLength(4));
    expect(topSearchedPlayers(EnhancedSearchResult.empty()), isEmpty);
  });

  test('a caller may ask for every distinct player', () {
    final results = _results([
      for (var i = 0; i < 6; i++) _player('Player $i', fideId: 100 + i),
      _player('Player 0', fideId: 100),
    ]);
    expect(topSearchedPlayers(results, limit: 99), hasLength(6));
  });

  group('the cards', () {
    testWidgets('by default they settle in as on the Events page, fully '
        'visible from their first frame', (tester) async {
      await _pumpCards(tester, players: [_player('A B', fideId: 1)]);
      // Nothing fades in from nothing: no opacity anywhere above the words,
      // on the very first frame.
      expect(_hidden(tester), findsNothing);
      expect(
        find.descendant(
          of: find.byType(PlayerSearchCards),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );
      expect(find.text('A B'), findsOneWidget);
      // They start a few points above their place and settle onto it.
      final start = tester.getTopLeft(find.text('A B')).dy;
      await tester.pumpAndSettle();
      final rest = tester.getTopLeft(find.text('A B')).dy;
      expect(rest - start, closeTo(MediaCardsEntrance.rise, 0.5));
      expect(
        find.descendant(
          of: find.byType(PlayerSearchCards),
          matching: find.byType(MediaCardsEntrance),
        ),
        findsOneWidget,
      );
    });

    testWidgets('under reduced motion they stand still', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: MediaCardsEntrance(child: const Text('still')),
          ),
        ),
      );
      final start = tester.getTopLeft(find.text('still')).dy;
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('still')).dy, start);
      expect(find.byType(Transform), findsNothing);
    });

    testWidgets('without the entrance they are fully there on their first '
        'frame', (tester) async {
      await _pumpCards(
        tester,
        players: [_player('A B', fideId: 1), _player('C D', fideId: 2)],
        animateIn: false,
      );
      expect(_hidden(tester), findsNothing);
      expect(find.text('A B'), findsOneWidget);
    });

    testWidgets('onOpen takes the tap in place of the profile push, after '
        'the card\'s one haptic', (tester) async {
      final haptics = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final opened = <SearchPlayer>[];
      final observer = _Pushes();
      await _pumpCards(
        tester,
        players: [_player('Hikaru Nakamura', fideId: 2016192)],
        animateIn: false,
        onOpen: opened.add,
        observer: observer,
      );
      final pushedBefore = observer.count;
      await tester.tap(find.text('Hikaru Nakamura'));
      await tester.pump();
      expect(opened.single.fideId, 2016192);
      expect(observer.count, pushedBefore);
      expect(haptics, hasLength(1));
    });

    testWidgets('bottomPadding replaces the 16 under the cards', (
      tester,
    ) async {
      await _pumpCards(
        tester,
        players: [_player('A B', fideId: 1)],
        animateIn: false,
      );
      final withGap = tester.getSize(find.byType(PlayerSearchCards)).height;
      await _pumpCards(
        tester,
        players: [_player('A B', fideId: 1)],
        animateIn: false,
        bottomPadding: 0,
      );
      final flush = tester.getSize(find.byType(PlayerSearchCards)).height;
      expect(withGap - flush, closeTo(16.sp, 0.01));
    });

    // The flag fills the card at full strength, so a federation the flag
    // package cannot draw (FIDE's neutral players map to "XX") must leave
    // the plain card: its stand-in is a white tile with a question mark.
    testWidgets('a federation with no flag leaves the plain card, never the '
        'flag package\'s question mark', (tester) async {
      await _pumpCards(
        tester,
        players: [
          _player('Ian Nepomniachtchi', fideId: 4168119, fed: 'FID'),
          _player('Magnus Carlsen', fideId: 1503014, fed: 'NOR'),
        ],
        animateIn: false,
      );
      await tester.pump();
      expect(
        find.byKey(const Key('countryFlags_NotFound_ColoredBox')),
        findsNothing,
      );
      // Norway's backdrop (the vector flag in its own colours) and the
      // small flag beside its rating; nothing at all for the neutral
      // player.
      expect(find.byType(MediaFlagBackdrop), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(MediaFlagBackdrop),
          matching: find.byType(CountryFlag),
        ),
        findsOneWidget,
      );
      expect(find.byType(CountryFlag), findsNWidgets(2));
      final neutral = find.ancestor(
        of: find.text('Ian Nepomniachtchi'),
        matching: find.byType(MediaTextScrim),
      );
      expect(
        find.descendant(of: neutral, matching: find.byType(CountryFlag)),
        findsNothing,
      );
      expect(MediaFlagBackdrop.knows('XX'), isFalse);
      expect(MediaFlagBackdrop.knows('NO'), isTrue);
      expect(MediaFlagBackdrop.knows(null), isFalse);
    });
  });
}

Finder _hidden(WidgetTester tester) => find.descendant(
  of: find.byType(PlayerSearchCards),
  matching: find.byWidgetPredicate(
    (w) =>
        (w is Opacity && w.opacity == 0) ||
        (w is FadeTransition && w.opacity.value == 0),
  ),
);

class _Pushes extends NavigatorObserver {
  int count = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => count++;
}

Future<void> _pumpCards(
  WidgetTester tester, {
  required List<SearchPlayer> players,
  bool animateIn = true,
  double? bottomPadding,
  ValueChanged<SearchPlayer>? onOpen,
  NavigatorObserver? observer,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        navigatorObservers: [?observer],
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: PlayerSearchCards(
                    players: players,
                    animateIn: animateIn,
                    bottomPadding: bottomPadding,
                    onOpen: onOpen,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

EnhancedSearchResult _results(List<SearchPlayer> players) {
  return EnhancedSearchResult(
    tournamentResults: const [],
    playerResults: [
      for (final player in players)
        SearchResult(
          tournament: _event,
          score: 1,
          matchedText: player.name,
          type: SearchResultType.player,
          player: player,
        ),
    ],
  );
}

SearchPlayer _player(
  String name, {
  int? fideId,
  String? memorialId,
  String? fed,
}) {
  return SearchPlayer(
    id: '${fideId ?? memorialId ?? name}',
    name: name,
    fideId: fideId,
    fed: fed,
    memorialSourceIdentity: memorialId,
    tournamentId: _event.id,
    tournamentName: _event.title,
  );
}

final _event = GroupEventCardModel(
  id: 'tour-1',
  title: 'Sinquefield Cup 2026',
  dates: 'Aug 20, 2026',
  maxAvgElo: 2750,
  timeUntilStart: '',
  tourEventCategory: TourEventCategory.completed,
  timeControl: 'Classical',
  startDate: DateTime.utc(2026, 8, 20),
  endDate: DateTime.utc(2026, 8, 30),
);
