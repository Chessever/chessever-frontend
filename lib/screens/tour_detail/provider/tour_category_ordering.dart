import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';

/// Display order for the category half of the tournament-detail dropdown.
///
/// Categories are the stages and sections of one event, and the popup reads
/// newest-first: whatever is being played now sits on top and the earliest
/// stage at the bottom. A Playoffs stage therefore heads the list it grew out
/// of instead of trailing its own group stage.
///
/// The rounds nested under each category already order this way (see
/// `sortRoundsForDisplay`), so both halves of the same popup now agree on what
/// "latest" means:
///
/// 1. Started categories first — live, ongoing, completed, or a start time
///    already past — newest start first.
/// 2. Upcoming categories after them, soonest first, so a stage with no games
///    yet never pushes stages that do have games down the list.
///
/// Ties on the start time are the common case rather than an edge case: most
/// multi-tour events are parallel sections that all begin together
/// (Masters/Challengers/Amateur, U18…U8, Boards 1-10/11-20). Those fall back to
/// the stronger section first, which is the order players expect, and then to
/// the label read naturally, so `Group A` precedes `Group B` instead of landing
/// wherever average rating happened to put it.
List<TourModel> sortTourCategoriesForDisplay(
  List<TourModel> models, {
  DateTime? now,
}) {
  if (models.length <= 1) {
    return List<TourModel>.from(models);
  }

  final effectiveNow = now ?? DateTime.now();
  final started = <TourModel>[];
  final upcoming = <TourModel>[];
  for (final model in models) {
    if (_hasStarted(model, effectiveNow)) {
      started.add(model);
    } else {
      upcoming.add(model);
    }
  }

  started.sort((a, b) => _compareCategories(a, b, ascending: false));
  upcoming.sort((a, b) => _compareCategories(a, b, ascending: true));

  final ordered = <TourModel>[...started, ...upcoming];
  _readSeriesInOrder(ordered);
  return ordered;
}

/// Re-reads a lettered or numbered series that shares one slot in the schedule.
///
/// Rating order is right for named sections — Open above Major above Minor — but
/// wrong for a plain series: `Group A` … `Group D` are peers, so the letter is
/// the order, not whichever group happened to draw the stronger field. Only
/// categories scheduled identically are eligible, so this never overrides the
/// chronology above it.
///
/// This runs as a pass over the sorted list rather than as a branch inside the
/// comparator, because a comparator that swapped rules per pair would not be
/// transitive — `Group A` < `Group B` by letter, `Group B` < `Masters` by
/// rating, `Masters` < `Group A` by rating is a cycle, and `sort` is free to
/// emit anything at all when fed one.
void _readSeriesInOrder(List<TourModel> ordered) {
  var start = 0;
  while (start < ordered.length) {
    var end = start + 1;
    while (end < ordered.length && _sameSchedule(ordered[start], ordered[end])) {
      end++;
    }
    _readSeriesInSegment(ordered, start, end);
    start = end;
  }
}

void _readSeriesInSegment(List<TourModel> ordered, int start, int end) {
  final slotsByStem = <String, List<int>>{};
  for (var i = start; i < end; i++) {
    final stem = _seriesStem(tourCategoryLabel(ordered[i].tour.name));
    if (stem == null) continue;
    slotsByStem.putIfAbsent(stem, () => <int>[]).add(i);
  }

  for (final slots in slotsByStem.values) {
    if (slots.length < 2) continue;
    final members = [for (final slot in slots) ordered[slot]]..sort(
      (a, b) => compareLabelsNaturally(
        tourCategoryLabel(a.tour.name),
        tourCategoryLabel(b.tour.name),
      ),
    );
    // The series keeps the slots it already holds, so it is re-read in order
    // without displacing anything ranked around it.
    for (var i = 0; i < slots.length; i++) {
      ordered[slots[i]] = members[i];
    }
  }
}

bool _sameSchedule(TourModel a, TourModel b) =>
    _startOf(a) == _startOf(b) && _endOf(a) == _endOf(b);

/// A series label is a stem plus a trailing enumerator — `Group A`, `GM-A`,
/// `Round 2`. Deliberately narrow: anything longer than a letter or a short
/// number is a name, not an index, and names stay on rating order.
final RegExp _seriesLabel = RegExp(
  r'^(.{2,}?)[ \-_]([a-z]|\d{1,4})$',
  caseSensitive: false,
);

String? _seriesStem(String label) =>
    _seriesLabel.firstMatch(label.trim())?.group(1)!.trim().toLowerCase();

/// The text the dropdown shows for a category, trimmed off the full tour name.
///
/// Broadcast names repeat the event before the part that actually
/// distinguishes one category from another ("Esports World Cup 2026 |
/// Playoffs"), so the trailing segment is both what the row renders and what
/// the ordering compares.
String tourCategoryLabel(String fullName) {
  if (fullName.contains('|')) {
    return fullName.split('|').last.trim();
  }
  if (fullName.contains(':')) {
    return fullName.split(':').last.trim();
  }

  // Common category patterns like "Boards 1-10" or "Boards 21+".
  final boardsMatch = RegExp(
    r'(Boards?\s+\d+[\-\+]?\d*\+?)$',
    caseSensitive: false,
  ).firstMatch(fullName);
  if (boardsMatch != null) {
    return boardsMatch.group(0)!.trim();
  }

  // Patterns like "Group A", "Section B", "Division 1".
  final groupMatch = RegExp(
    r'((?:Group|Section|Division|Category)\s+\w+)$',
    caseSensitive: false,
  ).firstMatch(fullName);
  if (groupMatch != null) {
    return groupMatch.group(0)!.trim();
  }

  // No recognisable suffix — the marquee handles the length.
  return fullName;
}

/// Case-insensitive comparison that reads digit runs as numbers, so `Boards 2`
/// sorts before `Boards 11` rather than after it.
int compareLabelsNaturally(String a, String b) {
  final left = a.toLowerCase();
  final right = b.toLowerCase();

  var i = 0;
  var j = 0;
  while (i < left.length && j < right.length) {
    final leftIsDigit = _isDigit(left.codeUnitAt(i));
    final rightIsDigit = _isDigit(right.codeUnitAt(j));

    if (leftIsDigit && rightIsDigit) {
      final leftEnd = _digitRunEnd(left, i);
      final rightEnd = _digitRunEnd(right, j);
      // Compared as text rather than parsed, so an absurdly long digit run in
      // a broadcast name cannot overflow an int and throw mid-sort.
      final leftRun = _stripLeadingZeros(left.substring(i, leftEnd));
      final rightRun = _stripLeadingZeros(right.substring(j, rightEnd));
      if (leftRun.length != rightRun.length) {
        return leftRun.length.compareTo(rightRun.length);
      }
      final runCompare = leftRun.compareTo(rightRun);
      if (runCompare != 0) {
        return runCompare;
      }
      i = leftEnd;
      j = rightEnd;
      continue;
    }

    final charCompare = left[i].compareTo(right[j]);
    if (charCompare != 0) {
      return charCompare;
    }
    i++;
    j++;
  }

  final remainderCompare = (left.length - i).compareTo(right.length - j);
  if (remainderCompare != 0) {
    return remainderCompare;
  }
  // Identical apart from case — fall back so the sort stays deterministic.
  return a.compareTo(b);
}

bool _hasStarted(TourModel model, DateTime now) {
  // Tours with no dates at all (TCEC/CCC style imports) are classified live or
  // completed upstream, never upcoming, so they land in the started group.
  if (model.roundStatus != RoundStatus.upcoming) {
    return true;
  }
  final start = _startOf(model);
  return start != null && !start.isAfter(now);
}

DateTime? _startOf(TourModel model) =>
    model.tour.dates.isEmpty ? null : model.tour.dates.first;

DateTime? _endOf(TourModel model) =>
    model.tour.dates.isEmpty ? null : model.tour.dates.last;

int _compareCategories(TourModel a, TourModel b, {required bool ascending}) {
  final byStart = _compareDates(_startOf(a), _startOf(b), ascending);
  if (byStart != 0) return byStart;

  // Same start: a stage that ran longer is the later one of the pair.
  final byEnd = _compareDates(_endOf(a), _endOf(b), ascending);
  if (byEnd != 0) return byEnd;

  final byStrength = (b.tour.avgElo ?? 0).compareTo(a.tour.avgElo ?? 0);
  if (byStrength != 0) return byStrength;

  final byLabel = compareLabelsNaturally(
    tourCategoryLabel(a.tour.name),
    tourCategoryLabel(b.tour.name),
  );
  if (byLabel != 0) return byLabel;

  return a.tour.id.compareTo(b.tour.id);
}

/// Dateless tours sink to the bottom of their group whichever direction the
/// dates are being read in, so they never head the list on missing data.
int _compareDates(DateTime? a, DateTime? b, bool ascending) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  final compare = a.compareTo(b);
  return ascending ? compare : -compare;
}

bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

int _digitRunEnd(String value, int start) {
  var end = start;
  while (end < value.length && _isDigit(value.codeUnitAt(end))) {
    end++;
  }
  return end;
}

String _stripLeadingZeros(String digits) {
  var start = 0;
  while (start < digits.length - 1 && digits.codeUnitAt(start) == 0x30) {
    start++;
  }
  return digits.substring(start);
}
