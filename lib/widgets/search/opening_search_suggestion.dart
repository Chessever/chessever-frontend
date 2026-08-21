import 'package:chessever2/utils/eco_openings.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';

/// A locally indexed ECO destination shown alongside remote search results.
class OpeningSearchSuggestion {
  const OpeningSearchSuggestion({
    required this.filter,
    required this.title,
    required this.subtitle,
    required this.score,
  });

  final GameEcoFilter filter;
  final String title;
  final String subtitle;
  final int score;
}

/// Searches the bundled ECO catalog without adding a network or database hop.
///
/// Safe parent families (for example B9 / Najdorf) are included so a single
/// result can open all of its child codes. Exact codes remain ranked first.
List<OpeningSearchSuggestion> searchOpeningSuggestions(
  String rawQuery, {
  int limit = 4,
}) {
  final query = rawQuery.trim().toLowerCase();
  if (query.isEmpty || limit <= 0) return const [];

  final suggestions = <OpeningSearchSuggestion>[];

  for (final family in EcoOpenings.families) {
    final code = family.codePrefix.toLowerCase();
    final name = family.name.toLowerCase();
    final score = _matchScore(
      query: query,
      code: code,
      name: name,
      family: true,
    );
    if (score == null) continue;
    suggestions.add(
      OpeningSearchSuggestion(
        filter: GameEcoFilter.forFamily(family.codePrefix),
        title: family.name,
        subtitle:
            '${family.codePrefix} · ${family.codePrefix}0–${family.codePrefix}9',
        score: score,
      ),
    );
  }

  for (final entry in EcoOpenings.codeToName.entries) {
    final code = entry.key.toLowerCase();
    final name = entry.value.toLowerCase();
    final score = _matchScore(
      query: query,
      code: code,
      name: name,
      family: false,
    );
    if (score == null) continue;
    suggestions.add(
      OpeningSearchSuggestion(
        filter: GameEcoFilter.forCode(entry.key),
        title: entry.value,
        subtitle: entry.key,
        score: score,
      ),
    );
  }

  suggestions.sort((a, b) {
    final scoreOrder = b.score.compareTo(a.score);
    if (scoreOrder != 0) return scoreOrder;
    final titleOrder = a.title.compareTo(b.title);
    if (titleOrder != 0) return titleOrder;
    return a.subtitle.compareTo(b.subtitle);
  });
  return suggestions.take(limit).toList(growable: false);
}

int? _matchScore({
  required String query,
  required String code,
  required String name,
  required bool family,
}) {
  if (!family && code == query) return 1200;
  if (family && code == query) return 1150;
  if (name == query) return family ? 1100 : 1050;
  if (code.startsWith(query)) return family ? 1000 : 980;
  if (name.startsWith(query)) return family ? 960 : 920;
  if (_wordStartsWith(name, query)) return family ? 900 : 860;
  if (name.contains(query)) return family ? 820 : 780;
  return null;
}

bool _wordStartsWith(String value, String query) {
  return value
      .split(RegExp(r'[^a-z0-9]+'))
      .any((word) => word.startsWith(query));
}
