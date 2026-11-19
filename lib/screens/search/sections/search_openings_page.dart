import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart'
    show SmartEventRequest;
import 'package:chessever2/screens/search/search_carousel.dart';
import 'package:chessever2/screens/search/search_feeds.dart';
import 'package:chessever2/screens/search/search_page_sections.dart';
import 'package:chessever2/screens/search/sections/search_section_pages.dart';
import 'package:chessever2/widgets/search/opening_search_suggestion.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Openings, the Search section's own page: every opening the catalog can
/// open as a smart event (the main ones first, then the rest of the
/// catalog), the half cards My Space sets side by side, read on a page at a
/// time as the reader nears the end. The same source as the section's row
/// ([searchOpeningsFeedProvider]), so nothing is read twice.
///
/// Each card opens its smart event through [onOpening] (the tab remembers
/// the pick) and keeps its own long-press (Open, My Space).
class SearchOpeningsPage extends ConsumerWidget {
  const SearchOpeningsPage({super.key, this.onOpening});

  final ValueChanged<OpeningSearchSelection>? onOpening;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(searchOpeningsFeedProvider);
    final notifier = ref.read(searchOpeningsFeedProvider.notifier);
    final openings = feed.items;
    final requests = [
      for (final opening in openings)
        SmartEventRequest.forOpeningSelection(opening.selection),
    ];
    final open = onOpening;
    return SearchSectionPageScaffold(
      title: SearchSectionId.openings.title,
      sliver: SearchPagedRows<SmartEventRequest>(
        section: 'openings-page',
        items: requests,
        columns: searchSmartEventColumns,
        row: (context, items, start, columns, width) => searchSmartEventRow(
          items,
          start,
          columns,
          keyFor: (index) =>
              ValueKey('search-openings-page-${openings[index].id}'),
          onTap: open == null
              ? null
              : (index) =>
                    () => open(openings[index].selection),
        ),
        hasMore: feed.hasMore,
        loading: feed.loading || !feed.ready,
        failed: feed.failed,
        onLoadMore: notifier.loadMore,
        onRetry: notifier.retry,
      ),
    );
  }
}
