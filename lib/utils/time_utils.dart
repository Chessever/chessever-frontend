import 'package:intl/intl.dart';

class TimeUtils {
  static DateTime? toLocal(DateTime? dateTime) {
    return dateTime?.toLocal();
  }

  static String formatDateRange(DateTime? start, DateTime? end) {
    final localStart = toLocal(start);
    final localEnd = toLocal(end);

    if (localStart != null && localEnd != null) {
      if (localStart.month == localEnd.month &&
          localStart.year == localEnd.year) {
        return "${DateFormat('MMM d').format(localStart)} - ${DateFormat('d, yyyy').format(localEnd)}";
      } else if (localStart.year == localEnd.year) {
        return "${DateFormat('MMM d').format(localStart)} - ${DateFormat('d MMM, yyyy').format(localEnd)}";
      } else {
        return "${DateFormat('MMM d, yyyy').format(localStart)} - ${DateFormat('MMM d, yyyy').format(localEnd)}";
      }
    } else if (localStart != null) {
      return DateFormat('MMM d, yyyy').format(localStart);
    } else if (localEnd != null) {
      return DateFormat('MMM d, yyyy').format(localEnd);
    } else {
      return "";
    }
  }

  static String timeUntilStart(DateTime? startDateTime) {
    final localStart = toLocal(startDateTime);
    if (localStart == null) return "";

    final now = DateTime.now();
    if (localStart.isBefore(now)) return "Started";

    final diff = localStart.difference(now);
    final days = diff.inDays;

    if (days < 30) {
      if (days == 0) {
        final hours = diff.inHours;
        if (hours == 0) {
          final minutes = diff.inMinutes;
          return "In $minutes minute${minutes == 1 ? '' : 's'}";
        }
        return "In $hours hour${hours == 1 ? '' : 's'}";
      } else if (days == 1) {
        return "In 1 day";
      } else {
        return "In $days days";
      }
    } else if (days < 365) {
      final months = (days / 30).round();
      return "In $months month${months == 1 ? '' : 's'}";
    } else {
      final years = (days / 365).round();
      return "In $years year${years == 1 ? '' : 's'}";
    }
  }

  static String formatSingleDate(DateTime? date) {
    final localDate = toLocal(date);
    if (localDate == null) return 'TBD';
    return DateFormat('d MMMM, h:mm a').format(localDate);
  }
}
