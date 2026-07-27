/// Formats the compact average-rating metadata used by event cards.
///
/// Cross-month date ranges already consume more horizontal space, so their
/// rating keeps the numeric value and drops the optional average marker.
String formatEventAverageRating({
  required int elo,
  required DateTime? startDate,
  required DateTime? endDate,
}) {
  final spansMultipleMonths =
      startDate != null &&
      endDate != null &&
      (startDate.year != endDate.year || startDate.month != endDate.month);

  return spansMultipleMonths ? '$elo' : 'Ø $elo';
}
