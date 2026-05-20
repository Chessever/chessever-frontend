String normalizePlayerSearchText(String value) {
  return value
      .toLowerCase()
      .replaceAll(',', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

List<String> playerNameSearchVariants(String playerName) {
  final variants = <String>{};
  final normalized = normalizePlayerSearchText(playerName);
  if (normalized.isNotEmpty) variants.add(normalized);

  if (playerName.contains(',')) {
    final parts = playerName.split(',');
    if (parts.length >= 2) {
      final lastName = parts.first.trim();
      final firstNames = parts.sublist(1).join(' ').trim();
      final displayOrder = normalizePlayerSearchText('$firstNames $lastName');
      if (displayOrder.isNotEmpty) variants.add(displayOrder);
    }
  }

  return variants.toList(growable: false);
}

int playerNameSearchMatchScore(String playerName, String query) {
  final normalizedQuery = normalizePlayerSearchText(query);
  if (normalizedQuery.isEmpty) return 0;

  final variants = playerNameSearchVariants(playerName);
  if (variants.isEmpty) return 0;

  if (variants.any((variant) => variant == normalizedQuery)) return 100;

  if (variants.any(
    (variant) => _startsWithWholeQuery(variant, normalizedQuery),
  )) {
    return 95;
  }

  if (variants.any((variant) => variant.startsWith(normalizedQuery))) {
    return 90;
  }

  final queryWords =
      normalizedQuery.split(' ').where((word) => word.isNotEmpty).toList();
  final variantWords =
      variants
          .expand((variant) => variant.split(' '))
          .where((word) => word.isNotEmpty)
          .toSet();

  if (queryWords.isNotEmpty &&
      queryWords.every((word) => variantWords.contains(word))) {
    return 85;
  }

  if (queryWords.isNotEmpty &&
      queryWords.every(
        (queryWord) => variantWords.any((word) => word.startsWith(queryWord)),
      )) {
    return 80;
  }

  if (variants.any((variant) => variant.contains(normalizedQuery))) return 70;

  if (queryWords.isNotEmpty &&
      queryWords.every(
        (queryWord) => variants.any((variant) => variant.contains(queryWord)),
      )) {
    return 50;
  }

  return 0;
}

bool _startsWithWholeQuery(String value, String query) {
  if (!value.startsWith(query)) return false;
  if (value.length == query.length) return true;
  return value.codeUnitAt(query.length) == 0x20;
}
