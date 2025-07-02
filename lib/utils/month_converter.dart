import 'package:intl/intl.dart';

class MonthConverter {
  /// Convert month number (1-12) to month name
  /// [monthNumber] should be between 1-12
  /// [locale] defaults to 'en_US', can be 'es_ES', 'fr_FR', etc.
  /// [isShort] if true, returns abbreviated month name (Jan, Feb, etc.)
  static String monthNumberToName(
    int monthNumber, {
    String locale = 'en_US',
    bool isShort = false,
  }) {
    if (monthNumber < 1 || monthNumber > 12) {
      throw ArgumentError('Month number must be between 1 and 12');
    }

    // Create a DateTime with the given month
    final date = DateTime(2024, monthNumber, 1);

    // Format based on whether we want short or full name
    final formatter =
        isShort
            ? DateFormat.MMM(locale) // Short month name (Jan, Feb, etc.)
            : DateFormat.MMMM(
              locale,
            ); // Full month name (January, February, etc.)

    return formatter.format(date);
  }

  /// Convert month name to number (1-12)
  /// [monthName] can be full name or abbreviated
  /// [locale] defaults to 'en_US'
  static int monthNameToNumber(String monthName, {String locale = 'en_US'}) {
    final cleanedName = monthName.trim().toLowerCase();

    // Try to find the month by comparing with all possible month names
    for (int i = 1; i <= 12; i++) {
      final date = DateTime(2024, i, 1);
      final fullName = DateFormat.MMMM(locale).format(date).toLowerCase();
      final shortName = DateFormat.MMM(locale).format(date).toLowerCase();

      if (fullName == cleanedName || shortName == cleanedName) {
        return i;
      }
    }

    throw ArgumentError('Invalid month name: $monthName');
  }

  /// Get all month names for a given locale
  /// [locale] defaults to 'en_US'
  /// [isShort] if true, returns abbreviated month names
  static List<String> getAllMonthNames({
    String locale = 'en_US',
    bool isShort = false,
  }) {
    final List<String> months = [];

    for (int i = 1; i <= 12; i++) {
      months.add(monthNumberToName(i, locale: locale, isShort: isShort));
    }

    return months;
  }

  /// Get month names with their corresponding numbers as a Map
  static Map<String, int> getMonthNamesMap({
    String locale = 'en_US',
    bool isShort = false,
  }) {
    final Map<String, int> monthsMap = {};

    for (int i = 1; i <= 12; i++) {
      final monthName = monthNumberToName(i, locale: locale, isShort: isShort);
      monthsMap[monthName] = i;
    }

    return monthsMap;
  }
}
