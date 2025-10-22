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
    const maxTotalLength = 18;
    const scoreStartIndex = 14; // score starts at char 14 (1-based)
    const nameMaxLength = scoreStartIndex - 1; // 13 chars for name area

    final scoreStr = score.toStringAsFixed(
      score % 1 == 0 ? 0 : 1,
    ); // "1", "1.5"
    String formattedName;

    // Parse name like "LastName, FirstName"
    formattedName =
        name.length > nameMaxLength
            ? '${name.substring(0, nameMaxLength - 1)}…'
            : name;

    // Pad to align score to fixed position
    if (formattedName.length < nameMaxLength) {
      formattedName = formattedName.padRight(nameMaxLength);
    }

    final result = '$formattedName $scoreStr';

    // Ensure not longer than 18 chars total
    return result.length > maxTotalLength
        ? result.substring(0, maxTotalLength)
        : result;
  }
}
