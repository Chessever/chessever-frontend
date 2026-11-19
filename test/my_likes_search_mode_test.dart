import 'dart:async';

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart'
    show playerPhotoProvider;
import 'package:chessever2/screens/my_likes/my_likes_screen.dart';
import 'package:chessever2/screens/my_likes/provider/my_likes_provider.dart';
import 'package:chessever2/screens/my_likes/widgets/date_section_header.dart';
import 'package:chessever2/screens/my_likes/widgets/my_likes_game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The standalone Likes archive searches the way every Games tab does: the
/// same cards stay while a search is read, the chevron holds still as the
/// title row turns into the search, the dates open for the hits and the
/// reader's folds come back after.

SavedAnalysis _like(String id, String white, DateTime liked) => SavedAnalysis(
  id: id,
  userId: 'u1',
  title: 'A saved game',
  chessGame: ChessGame.fromPgn(
    id,
    '[White "$white"]\n[Black "Opponent, $id"]\n[Result "1-0"]\n\n1. e4 e5 1-0',
  ),
  analysisState: const {},
  variationComments: const {},
  lastViewedPosition: -1,
  tags: const [],
  isFavorite: false,
  createdAt: liked,
  updatedAt: liked,
);

final _likes = [
  _like('a', 'Carlsen, Magnus', DateTime(2026, 9, 29)),
  _like('b', 'Caruana, Fabiano', DateTime(2026, 9, 29)),
  _like('c', 'Nakamura, Hikaru', DateTime(2026, 9, 20)),
];

class _Library extends Fake implements LibraryRepository {}

class _Likes extends LikedGamesNotifier {
  @override
  Future<List<SavedAnalysis>> build() async => _likes;
}

class _Subscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _Subscription() : super(SubscriptionState(isSubscribed: true));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BoardSettings extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

class _EngineSettings extends AsyncNotifier<EngineSettings>
    implements EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async => const EngineSettings();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _NoSpoilers extends EventNoSpoilersController {
  _NoSpoilers({required super.ref, required super.tourId});

  @override
  Future<void> load() async {
    state = const EventNoSpoilersState(enabled: false, isLoading: false);
  }
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 14; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Finder get _cards => find.byType(MyLikesGameCard);

/// A search's read, held until the test lets it land.
class _Reads {
  Completer<void>? reading;
}

/// The standalone archive over [_likes]; a search is read until
/// [_Reads.reading] completes.
Future<ProviderContainer> _pumpArchive(
  WidgetTester tester,
  _Reads reads,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      subscriptionProvider.overrideWith((ref) => _Subscription()),
      playerPhotoProvider.overrideWith((ref, fideId) async => null),
      boardSettingsProviderNew.overrideWith(_BoardSettings.new),
      engineSettingsProviderNew.overrideWith(_EngineSettings.new),
      eventNoSpoilersProvider.overrideWith(
        (ref, tourId) => _NoSpoilers(ref: ref, tourId: tourId),
      ),
      likedGamesProvider.overrideWith(_Likes.new),
      libraryRepositoryProvider.overrideWithValue(_Library()),
      myLikesTagCountsProvider.overrideWith((ref) async => const {}),
      myLikesViewProvider.overrideWith((ref) async {
        final query = ref.watch(myLikesFilterProvider).searchQuery;
        if (query.isEmpty) {
          return buildMyLikesData(
            matches: _likes,
            totalLiked: _likes.length,
            window: null,
          );
        }
        await (reads.reading = Completer<void>()).future;
        final hits = [
          for (final like in _likes)
            if ((like.whiteName ?? '').toLowerCase().contains(
              query.toLowerCase(),
            ))
              like,
        ];
        return buildMyLikesData(
          matches: hits,
          totalLiked: _likes.length,
          window: null,
          isNarrowed: true,
        );
      }),
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
            return const MyLikesScreen();
          },
        ),
      ),
    ),
  );
  return container;
}

void main() {
  testWidgets('the archive searches its own list in place, from the title '
      "row's chevron and back", (tester) async {
    final reads = _Reads();
    final container = await _pumpArchive(tester, reads);
    await _frames(tester);
    expect(_cards, findsNWidgets(3));
    // The reader folds the older day before searching.
    final headers = find.byType(DateSectionHeader);
    expect(headers, findsNWidgets(2));
    await tester.tap(headers.last);
    await _frames(tester);
    expect(_cards, findsNWidgets(2));
    final back = tester.getCenter(find.byTooltip('Back'));
    // The Filters end the title row as they end the search row.
    expect(find.byTooltip('Filter games'), findsOneWidget);

    // The list's own scroll state: the same one before, during and after
    // the search, never remounted.
    ScrollableState listState() => tester.state<ScrollableState>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('my_likes_list_end')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    final list = listState();

    final fab = find.byKey(const ValueKey('my_likes_search_fab'));
    await tester.tap(fab);
    await _frames(tester);
    final field = find.byKey(const ValueKey('my_likes_search'));
    expect(field, findsOneWidget);
    expect(tester.getCenter(find.byTooltip('Close search')), back);
    expect(
      find.byKey(const ValueKey('my_likes_filters')).hitTestable(),
      findsOneWidget,
    );
    expect(_cards, findsNWidgets(2));

    await tester.enterText(field, 'nakamura');
    await tester.pump(const Duration(milliseconds: 450));
    await _frames(tester);
    // Read quietly over the same cards: no spinner in their place.
    expect(_cards, findsNWidgets(2));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    reads.reading!.complete();
    await _frames(tester);
    // The hit sits in the day the reader had folded: the day opens for it.
    expect(_cards, findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(listState(), same(list));

    await tester.tap(find.byKey(const ValueKey('my_likes_search_close')));
    await _frames(tester);
    expect(field, findsNothing);
    expect(container.read(myLikesFilterProvider).searchQuery, '');
    // Every like is back, with the reader's own fold, in the same list.
    expect(_cards, findsNWidgets(2));
    expect(listState(), same(list));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.getCenter(find.byTooltip('Back')), back);
    expect(fab.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('a search that finds nothing says so where the first like '
      'was, and Clear search empties the field and brings every like back', (
    tester,
  ) async {
    final reads = _Reads();
    final container = await _pumpArchive(tester, reads);
    await _frames(tester);
    expect(_cards, findsNWidgets(3));

    await tester.tap(find.byKey(const ValueKey('my_likes_search_fab')));
    await _frames(tester);
    final field = find.byKey(const ValueKey('my_likes_search'));
    await tester.enterText(field, 'zzz');
    await tester.pump(const Duration(milliseconds: 450));
    await _frames(tester);
    reads.reading!.complete();
    await _frames(tester);

    expect(_cards, findsNothing);
    expect(find.text('No matches for "zzz"'), findsOneWidget);
    expect(find.text('Clear search'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('search_no_matches_clear')));
    await _frames(tester);
    // Still searching, the field empty, over every like.
    expect(field, findsOneWidget);
    expect(
      find.descendant(of: field, matching: find.text('zzz')),
      findsNothing,
    );
    expect(container.read(myLikesFilterProvider).searchQuery, '');
    expect(_cards, findsNWidgets(3));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });
}
