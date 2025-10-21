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
}
