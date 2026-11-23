import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:hooks_riverpod/hooks_riverpod.dart';

final stringUtilsProvider = AutoDisposeProvider(
  (ref) => _StringUtilsController(ref),
);

class _StringUtilsController {
  _StringUtilsController(this.ref);

  final Ref ref;

  /// A game card's player name: "Surname, Given" past 18 characters becomes
  /// "Surname, G.". Never cut with an ellipsis: a name still too wide for its
  /// card fades out at its end (the caller's [TextOverflow.fade]).
  String getTrimmedString(String name) {
    if (name.length <= 18) return name;
    final parts = name.split(',');
    if (parts.length != 2) return name;
    final lastName = parts[0].trim();
    final firstName = parts[1].trim();
    if (lastName.isEmpty || firstName.isEmpty) return name;
    return '$lastName, ${firstName.characters.first.toUpperCase()}.';
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
    formattedName = name.length > nameMaxLength
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
