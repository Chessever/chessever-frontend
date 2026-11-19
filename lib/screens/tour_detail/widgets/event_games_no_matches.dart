import 'package:chessever2/widgets/search_mode/search_mode.dart';
import 'package:chessever2/widgets/search_no_matches.dart';
import 'package:flutter/widgets.dart';

/// What an event's Games list (one category, or Combined) shows when its
/// search leaves nothing: the app's one no-hits state ([SearchNoMatches]),
/// the field's words echoed back on the list's gutter, drawn whole from its
/// first frame.
///
/// While the search is open, "Clear search" under it empties the field, as
/// the field's own clear button does: the search stays open and every game
/// comes back under it.
class EventGamesNoMatches extends StatelessWidget {
  const EventGamesNoMatches({super.key, required this.query});

  /// The words searched. Null or blank says only that nothing matched.
  final String? query;

  @override
  Widget build(BuildContext context) {
    final search = SearchModeScope.maybeOf(context);
    final field = search != null && search.isSearching
        ? search.controller.text
        : null;
    return SearchNoMatches(query: query, onClear: field?.clear);
  }
}
