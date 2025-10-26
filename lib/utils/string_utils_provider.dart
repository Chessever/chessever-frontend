import 'package:hooks_riverpod/hooks_riverpod.dart';

final stringUtilsProvider = AutoDisposeProvider(
  (ref) => _StringUtilsController(ref),
);

class _StringUtilsController {
  _StringUtilsController(this.ref);

  final Ref ref;

  String getTrimmedString(String name) {
    if (name.length > 18) {
      final firstAndLastName = name.split(',');
      if (firstAndLastName.length == 2) {
        final lastName = firstAndLastName[0].trim();
        final firstName = firstAndLastName[1].trim();

        if (firstName.isNotEmpty) {
          final firstInitial = firstName[0].toUpperCase();
          final targetFormat = '$lastName, $firstInitial.';

          if (targetFormat.length <= 18) {
            return targetFormat;
          } else {
            final maxLastNameLength = 18 - 4; // 18 - ", I.".length
            final truncatedLastName =
                '${lastName.substring(0, maxLastNameLength)}…';
            return '$truncatedLastName, $firstInitial.';
          }
        } else {
          // No first name, just return truncated last name
          return lastName.length > 18
              ? '${lastName.substring(0, 15)}…'
              : lastName;
        }
      } else {
        // Not in "LastName, FirstName" format, just truncate
        return '${name.substring(0, 15)}…';
      }
    } else {
      return name;
    }
  }

  String getTrimmedStringWithScore(String name, double score) {
    const maxTotalLength = 16;
    const scoreStartIndex = 12; // score starts at 14th character (1-based)
    const nameMaxLength = scoreStartIndex - 1; // 13 chars for name area

    // Format score: no decimal if whole, 1 decimal if fractional
    final scoreStr =
        score % 1 == 0 ? score.toStringAsFixed(0) : score.toStringAsFixed(1);

    // Trim and add ellipsis if name is too long
    String formattedName =
        name.length > nameMaxLength
            ? '${name.substring(0, nameMaxLength - 1)}…'
            : name;

    // Pad so the score always starts at the 14th position
    formattedName = formattedName.padRight(nameMaxLength);

    // Combine
    String result = '$formattedName $scoreStr';

    // If total exceeds max length, trim the name part but keep score intact
    if (result.length > maxTotalLength) {
      final allowedNameLength = maxTotalLength - (scoreStr.length + 1);
      final safeName =
          name.length > allowedNameLength
              ? '${name.substring(0, allowedNameLength - 1)}…'
              : name.padRight(allowedNameLength);
      result = '$safeName $scoreStr';
    }

    return result;
  }
}
