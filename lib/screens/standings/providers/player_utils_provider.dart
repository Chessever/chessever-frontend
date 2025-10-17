import 'package:hooks_riverpod/hooks_riverpod.dart';

final playerUtilsProvider = AutoDisposeProvider(
  (ref) => _PlayerUtilsController(ref),
);

class _PlayerUtilsController {
  _PlayerUtilsController(this.ref);

  final Ref ref;

  bool isSamePlayer(String? name1, String? name2) {
    if (name1 == null || name2 == null) return false;

    String normalize(String name) => name
        .toLowerCase()
        .replaceAll(',', '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .join(' ');

    final n1 = normalize(name1);
    final n2 = normalize(name2);

    if (n1 == n2) return true;

    // Handle "First Last" vs "Last First"
    final parts1 = n1.split(' ');
    final parts2 = n2.split(' ');

    if (parts1.length == 2 && parts2.length == 2) {
      return parts1[0] == parts2[1] && parts1[1] == parts2[0];
    }

    return false;
  }
}
