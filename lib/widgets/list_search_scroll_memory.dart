import 'package:flutter/widgets.dart';

/// Keeps a searched list's place, the way a Games tab keeps it.
///
/// When a search's answer replaces the list, the list starts at its top: a
/// search reads from its first hit. When the search is cleared, the list
/// goes back to where the reader left it before searching, as near as the
/// list's length now allows. Nothing is remounted; the list's own scroll
/// position just moves, after the frame that lays out the new rows.
///
/// Call [follow] from the list's build with the query the rows on screen
/// answer (not one still being read): it notes the offset of the rows
/// being replaced before they are laid out again.
///
/// For a list read through the page's [PrimaryScrollController] (an event
/// view's tabs) see `EventViewSearchPlace`; this one follows a list that
/// owns its [ScrollController].
class ListSearchScrollMemory {
  String _shown = '';
  double? _before;

  void follow(ScrollController controller, String? query) {
    final next = query?.trim() ?? '';
    if (next == _shown) return;
    final from = _shown;
    _shown = next;
    if (from.isEmpty) {
      // Still the full list's layout: where the reader was in it.
      _before = controller.positions.length == 1 ? controller.offset : null;
    }
    final target = next.isEmpty ? _before : 0.0;
    if (next.isEmpty) _before = null;
    if (target == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (controller.positions.length != 1) return;
      final position = controller.position;
      if (!position.hasContentDimensions) return;
      final to = target.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((position.pixels - to).abs() > 0.5) controller.jumpTo(to);
    });
  }
}
