import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart'
    show SmartEventRequest;
import 'package:chessever2/screens/search/search_carousel.dart';
import 'package:chessever2/screens/search/search_feeds.dart';
import 'package:chessever2/screens/search/search_page_sections.dart';
import 'package:chessever2/screens/search/sections/search_section_pages.dart';
import 'package:flutter/material.dart';

/// Smart events, the Search section's own page: every built-in smart event
/// ([searchSmartEventRequests]: each level, then each time control), the
/// half cards My Space sets side by side. Each opens itself, without
/// Filters, and keeps its own star and long-press (Open, My Space).
class SearchSmartEventsPage extends StatelessWidget {
  const SearchSmartEventsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final requests = searchSmartEventRequests;
    return SearchSectionPageScaffold(
      title: SearchSectionId.smartEvents.title,
      sliver: SearchPagedRows<SmartEventRequest>(
        section: 'smart-page',
        items: requests,
        columns: searchSmartEventColumns,
        row: (context, items, start, columns, width) => searchSmartEventRow(
          items,
          start,
          columns,
          keyFor: (index) =>
              ValueKey('search-smart-page-${requests[index].tierLabel}'),
        ),
      ),
    );
  }
}
