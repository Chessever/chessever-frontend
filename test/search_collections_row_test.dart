import 'dart:io';

import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/supabase/game/games.dart'
    show SearchPlayer;
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/screens/collections/collections_data.dart'
    show Collection, CollectionKind;
import 'package:chessever2/screens/collections/collections_screen.dart'
    show CollectionCard;
import 'package:chessever2/screens/feed/news/news_models.dart' show FeedNews;
import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart'
    show discoverySmartEventMembersProvider;
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/search/search_carousel.dart'
    show searchCarouselItemWidth;
import 'package:chessever2/screens/search/search_feeds.dart';
import 'package:chessever2/screens/search/search_landing.dart';
import 'package:chessever2/screens/search/search_page_landing.dart';
import 'package:chessever2/screens/search/search_page_sections.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/search/opening_search_suggestion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The Search tab's Collections row: each book in the card the Collections
/// page draws, side by side, the row exactly as tall as the tallest card it
/// holds, so no card stands in a box taller than its words.
void main() {
  // Measured in the app's own face: the square test font's wide figures
  // would wrap every tally.
  setUpAll(() async {
    final fonts = FontLoader('InterDisplay');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      fonts.addFont(
        Future.value(
          File(
            'assets/fonts/Inter-$weight.otf',
          ).readAsBytesSync().buffer.asByteData(),
        ),
      );
    }
    await fonts.load();
  });

  testWidgets('the row stands as tall as its tallest card, and every card '
      'fills it: no card floats in empty room', (tester) async {
    await _pumpLanding(tester, [_short, _tall, _bare]);
    final row = tester.getRect(
      find.byKey(const PageStorageKey<String>('search-carousel-collections')),
    );
    double natural(Collection c) => tester
        .getSize(find.byKey(ValueKey('natural-${c.id}'), skipOffstage: false))
        .height;
    final tallest = [
      _short,
      _tall,
      _bare,
    ].map(natural).reduce((a, b) => a > b ? a : b);
    // The fixtures differ, or the test proves nothing.
    expect(natural(_bare), lessThan(tallest - 16));
    expect(row.height, closeTo(tallest, 0.5));

    for (final collection in [_short, _tall]) {
      final card = tester.getRect(
        find.byKey(ValueKey('search-collection-${collection.id}')),
      );
      expect(card.top, closeTo(row.top, 0.5), reason: collection.title);
      expect(card.height, closeTo(row.height, 0.5), reason: collection.title);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a row of short cards stands short', (tester) async {
    await _pumpLanding(tester, [_bare, _short]);
    final row = tester.getRect(
      find.byKey(const PageStorageKey<String>('search-carousel-collections')),
    );
    final tallest = [_bare, _short]
        .map(
          (c) => tester
              .getSize(
                find.byKey(ValueKey('natural-${c.id}'), skipOffstage: false),
              )
              .height,
        )
        .reduce((a, b) => a > b ? a : b);
    expect(row.height, closeTo(tallest, 0.5));
    final card = tester.getRect(
      find.byKey(ValueKey('search-collection-${_bare.id}')),
    );
    expect(card.height, closeTo(row.height, 0.5));
  });
}

/// A two-line title over a one-line byline, its tally on one line.
final _short = Collection(
  id: 'book-short',
  slug: 'my-sixty-memorable-games',
  kind: CollectionKind.book,
  title: 'My 60 Memorable Games',
  author: 'Bobby Fischer',
  gameCount: 60,
  viewCount: 1200,
  starCount: 40,
);

/// A two-line title, a two-line byline, a tally on two lines.
final _tall = Collection(
  id: 'book-tall',
  slug: 'garry-kasparov-on-my-great-predecessors',
  kind: CollectionKind.book,
  title: 'Garry Kasparov on My Great Predecessors, Part One',
  author: 'Garry Kasparov and Dmitry Plisetsky',
  gameCount: 1210,
  eventCount: 14,
  viewCount: 12800,
  starCount: 320,
);

/// A one-line title, no byline: no taller than its cover.
final _bare = Collection(
  id: 'book-bare',
  slug: 'tal',
  kind: CollectionKind.book,
  title: 'Tal',
  gameCount: 10,
);

Future<void> _pumpLanding(
  WidgetTester tester,
  List<Collection> collections,
) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(393, 852) * 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        searchLiveNowProvider.overrideWith(_NoLiveNow.new),
        searchTopPlayersFeedProvider.overrideWith(_NoTopPlayers.new),
        searchOpeningsFeedProvider.overrideWith(_NoOpenings.new),
        searchComingUpFeedProvider.overrideWith(_NoComingUp.new),
        searchNewsFeedProvider.overrideWith(_NoNews.new),
        searchCollectionsFeedProvider.overrideWith(
          () => _FixedCollections(collections),
        ),
        discoverySmartEventMembersProvider.overrideWith(
          (ref, criteria) async => const <GroupEventCardModel>[],
        ),
        favoriteEventsProvider.overrideWith(_NoFavoriteEvents.new),
        spaceShortcutsProvider.overrideWith(_NoSpaceShortcuts.new),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            final width = searchCarouselItemWidth(
              MediaQuery.sizeOf(context).width - searchPageGutter * 2,
              tabletMinWidth: 340,
            );
            return Scaffold(
              body: Stack(
                children: [
                  SearchPageLanding(picks: SearchPicks(event: (_) {})),
                  // Each card as it stands on its own at a row card's
                  // width: laid out, never painted.
                  Offstage(
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      maxHeight: double.infinity,
                      child: SizedBox(
                        width: width,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final c in collections)
                              CollectionCard(
                                key: ValueKey('natural-${c.id}'),
                                collection: c,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  // The Collections row on screen.
  await tester.scrollUntilVisible(
    find.byKey(ValueKey('search-collection-${collections.first.id}')),
    200,
    scrollable: find
        .descendant(
          of: find.byKey(const ValueKey('search_landing')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pump();
}

class _FixedCollections extends SearchCollectionsFeed {
  _FixedCollections(this.items);

  final List<Collection> items;

  @override
  SearchFeed<Collection> build() => SearchFeed(items: items);
}

class _NoLiveNow extends SearchLiveNowNotifier {
  @override
  SearchLiveNow build() => SearchLiveNow.none;
}

class _NoTopPlayers extends SearchTopPlayersFeed {
  @override
  SearchFeed<SearchPlayer> build() => const SearchFeed();
}

class _NoOpenings extends SearchOpeningsFeed {
  @override
  SearchFeed<OpeningSearchSuggestion> build() => const SearchFeed();
}

class _NoComingUp extends SearchComingUpFeed {
  @override
  SearchFeed<GroupEventCardModel> build() => const SearchFeed();
}

class _NoNews extends SearchNewsFeed {
  @override
  SearchFeed<FeedNews> build() => const SearchFeed();
}

class _NoFavoriteEvents extends FavoriteEventsNotifier {
  @override
  Future<List<FavoriteEvent>> build() async => const <FavoriteEvent>[];
}

class _NoSpaceShortcuts extends SpaceShortcutsNotifier {
  @override
  Future<List<SpaceShortcut>> build() async => const [];
}
