import 'package:intl/intl.dart';

final NumberFormat _decimalCountFormatter = NumberFormat.decimalPattern();

/// Formats a number with compact notation for display.
///
/// - Under 1,000: "842"
/// - 1,000–999,999: "3.9M" style NOT used; instead comma-separated: "3,980"
/// - 1M+: "4M", "4.2M"
///
/// Examples:
///   42       → "42"
///   3980     → "3,980"
///   397996   → "397,996"
///   3979963  → "3.9M"
///   12500000 → "12.5M"
String formatCompactCount(int count) {
  if (count < 1000) return count.toString();

  if (count >= 1000000) {
    final millions = count / 1000000;
    // Show one decimal if it's not a whole number
    if (count % 1000000 == 0) {
      return '${millions.toInt()}M';
    }
    return '${millions.toStringAsFixed(1)}M';
  }

  return _decimalCountFormatter.format(count);
}
