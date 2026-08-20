/// Utilities for string formatting and manipulation
class StringUtils {
  /// Converts a slug to a properly formatted title
  ///
  /// Examples:
  /// - "us-chess-championship" -> "US Chess Championship"
  /// - "world-cup-2024" -> "World Cup 2024"
  /// - "fide-grand-prix" -> "FIDE Grand Prix"
  static String slugToTitle(String slug) {
    if (slug.isEmpty) return '';

    // Replace hyphens and underscores with spaces
    String result = slug.replaceAll(RegExp(r'[-_]'), ' ');

    // Split into words
    List<String> words = result.split(' ');

    // Capitalize each word, with special handling for common acronyms
    final acronyms = {
      'us',
      'fide',
      'usa',
      'gm',
      'im',
      'fm',
      'cm',
      'wgm',
      'wim',
      'wfm',
      'wcm',
    };

    words =
        words.map((word) {
          if (word.isEmpty) return word;

          // Check if it's a known acronym
          if (acronyms.contains(word.toLowerCase())) {
            return word.toUpperCase();
          }

          // Capitalize first letter, keep rest as-is (preserves mixed case like "iPhone")
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        }).toList();

    return words.join(' ');
  }

  /// A real URL slug: lowercase alphanumerics joined by `-`/`_` and nothing
  /// else. Capitals, spaces or other punctuation mean the value is already a
  /// written name.
  static final RegExp _slugPattern = RegExp(r'^[a-z0-9]+(?:[-_][a-z0-9]+)*$');

  /// True when [value] is a genuine URL slug (not a written event name).
  ///
  /// Gamebase/TWIC archive rows reuse `tourSlug` for display labels like
  /// "TCh-RUS 2026"; those must not be interpolated into `/broadcast/...`.
  static bool looksLikeUrlSlug(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return false;
    return _slugPattern.hasMatch(trimmed);
  }

  /// Title-cases [value] only when it is a slug, otherwise returns it as-is.
  ///
  /// `GamesTourModel.tourSlug` carries a genuine slug for broadcast games
  /// ("tata-steel-masters-2024"), but gamebase/TWIC archive rows reuse the same
  /// field for the raw event name (see `buildGameShareUrl`). Pushing those
  /// through [slugToTitle] flattens their casing — "TCh-RUS 2026" comes back as
  /// "Tch Rus 2026" — so leave a written name alone.
  ///
  /// Examples:
  /// - "tata-steel-masters-2024" -> "Tata Steel Masters 2024"
  /// - "TCh-RUS 2026" -> "TCh-RUS 2026"
  static String titleFromSlugOrName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    return _slugPattern.hasMatch(trimmed) ? slugToTitle(trimmed) : trimmed;
  }

  /// Formats a round slug into a readable round label
  ///
  /// Examples:
  /// - "round-1" -> "Round 1"
  /// - "round-12-game-2" -> "Round 12, Game 2"
  /// - "rapid-8" -> "Rapid 8"
  /// - "blitz-finals" -> "Blitz Finals"
  /// - "losers-r3--armageddon" -> "Losers R3 Armageddon"
  static String formatRoundLabel(String? slug) {
    if (slug == null || slug.isEmpty) {
      return 'Round';
    }

    // Replace hyphens/underscores with spaces
    String cleaned = slug.replaceAll(RegExp(r'[-_]+'), ' ');

    // Remove extra spaces
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Split into words
    List<String> words = cleaned.split(' ');

    // Capitalize each word
    words =
        words.map((word) {
          if (word.isEmpty) return word;

          // Keep numbers as-is
          if (RegExp(r'^\d+$').hasMatch(word)) {
            return word;
          }

          // Capitalize first letter
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        }).toList();

    String result = words.join(' ');

    // Special formatting for common patterns
    // "Round 12 Game 2" -> "Round 12, Game 2"
    result = result.replaceAllMapped(
      RegExp(r'Round (\d+) Game (\d+)', caseSensitive: false),
      (match) => 'Round ${match.group(1)}, Game ${match.group(2)}',
    );

    // "Losers R3 Armageddon" is fine as-is

    return result;
  }

  /// Capitalizes the first letter of each word in a string
  ///
  /// Examples:
  /// - "rapid" -> "Rapid"
  /// - "classical chess" -> "Classical Chess"
  /// - "15+10" -> "15+10" (numbers preserved)
  static String capitalizeWords(String text) {
    if (text.isEmpty) return text;

    return text
        .split(' ')
        .map((word) {
          if (word.isEmpty) return word;
          // Keep words that start with numbers as-is
          if (RegExp(r'^\d').hasMatch(word)) return word;
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        })
        .join(' ');
  }
}
