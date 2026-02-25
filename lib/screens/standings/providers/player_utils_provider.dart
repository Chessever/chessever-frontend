import 'package:hooks_riverpod/hooks_riverpod.dart';

final playerUtilsProvider = AutoDisposeProvider(
  (ref) => _PlayerUtilsController(ref),
);

class _PlayerUtilsController {
  _PlayerUtilsController(this.ref);

  final Ref ref;

  /// Checks if a player matches by fideId first (most reliable), then by name.
  /// Returns true if fideIds match OR if names match using fuzzy logic.
  bool isSamePlayerWithFideId(
    String? name1,
    String? name2, {
    int? fideId1,
    int? fideId2,
  }) {
    // Prefer fideId matching - most reliable
    if (fideId1 != null && fideId2 != null && fideId1 > 0 && fideId2 > 0) {
      return fideId1 == fideId2;
    }

    // Fall back to name matching
    return isSamePlayer(name1, name2);
  }

  bool isSamePlayer(String? name1, String? name2) {
    if (name1 == null || name2 == null) return false;
    if (name1.isEmpty || name2.isEmpty) return false;

    String normalize(String name) => name
        .toLowerCase()
        .replaceAll(',', '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .join(' ');

    final n1 = normalize(name1);
    final n2 = normalize(name2);

    // Exact match after normalization
    if (n1 == n2) return true;

    final parts1 = n1.split(' ');
    final parts2 = n2.split(' ');

    // Handle 2-part names in different order: "First Last" vs "Last First"
    if (parts1.length == 2 && parts2.length == 2) {
      if (parts1[0] == parts2[1] && parts1[1] == parts2[0]) {
        return true;
      }
    }

    // Handle multi-part names (3+ parts): e.g., "Van Foreest, Jorden" vs "Jorden Van Foreest"
    // Strategy: Check if all parts from both names exist in the other (ignoring order)
    if (parts1.length >= 2 && parts2.length >= 2) {
      final set1 = Set<String>.from(parts1);
      final set2 = Set<String>.from(parts2);

      // If sets are equal, names contain the same words
      if (set1.length == set2.length && set1.containsAll(set2)) {
        return true;
      }

      // Check if one is a subset of the other (handles middle names being present/absent)
      // At least 2 parts must match for this to work reliably
      final intersection = set1.intersection(set2);
      if (intersection.length >= 2) {
        // If intersection covers most of the smaller name, consider it a match
        final smallerSize =
            set1.length < set2.length ? set1.length : set2.length;
        if (intersection.length >= smallerSize - 1 &&
            intersection.length >= 2) {
          return true;
        }
      }
    }

    return false;
  }
}
