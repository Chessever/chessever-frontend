/// Port of web switcherSectionLabels: keep nested category paths and strip
/// a shared separator-ended prefix, without shortening overlapping words.
List<String> combinedSwitcherLabels(List<String> names, {String? groupName}) {
  String section(String name) {
    final title = name.trim();
    if (title.isEmpty) return 'Section';
    final family = groupName?.trim();
    if (family != null &&
        family.isNotEmpty &&
        title.toLowerCase().startsWith(family.toLowerCase())) {
      final rest = title
          .substring(family.length)
          .replaceFirst(RegExp(r'^[\s|:\-–—]+'), '')
          .trim();
      if (rest.isNotEmpty) return rest.replaceAll(RegExp(r'\s+'), ' ');
    }
    for (final separator in [' | ', ' |', '| ', ':', ' - ']) {
      final index = title.indexOf(separator);
      if (index > 0) {
        final rest = title.substring(index + separator.length).trim();
        if (rest.isNotEmpty) return rest.replaceAll(RegExp(r'\s+'), ' ');
      }
    }
    return title;
  }

  final raw = names.map(section).toList();
  if (raw.length < 2) return raw;
  var prefix = raw.first;
  for (final label in raw.skip(1)) {
    var index = 0;
    while (index < prefix.length &&
        index < label.length &&
        prefix[index] == label[index]) {
      index++;
    }
    prefix = prefix.substring(0, index);
  }
  if (!RegExp(r'[|:\u2014\u2013\u2212-]\s*$').hasMatch(prefix) ||
      prefix.replaceFirst(RegExp(r'[\s|:\u2014\u2013\u2212-]+$'), '').length <
          2) {
    return raw;
  }
  final stripped = raw
      .map((label) => label.substring(prefix.length).trim())
      .toList();
  return stripped.any((label) => label.isEmpty) ? raw : stripped;
}
