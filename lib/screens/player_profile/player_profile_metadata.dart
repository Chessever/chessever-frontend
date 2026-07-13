class PlayerProfileMetadata {
  const PlayerProfileMetadata({
    required this.fideId,
    required this.name,
    this.title,
    this.federation,
    this.classicalRating,
    this.rapidRating,
    this.blitzRating,
    this.classicalGames,
    this.rapidGames,
    this.blitzGames,
    this.birthday,
    this.sex,
  });

  final int fideId;
  final String name;
  final String? title;
  final String? federation;
  final int? classicalRating;
  final int? rapidRating;
  final int? blitzRating;
  final int? classicalGames;
  final int? rapidGames;
  final int? blitzGames;
  final String? birthday;
  final String? sex;
}

PlayerProfileMetadata resolvePlayerProfileMetadata({
  required PlayerProfileMetadata fallback,
  PlayerProfileMetadata? authoritative,
}) {
  if (authoritative == null) return fallback;

  return PlayerProfileMetadata(
    fideId: authoritative.fideId > 0 ? authoritative.fideId : fallback.fideId,
    name: _nonBlank(authoritative.name) ?? fallback.name,
    title: _nonBlank(authoritative.title) ?? fallback.title,
    federation: _nonBlank(authoritative.federation) ?? fallback.federation,
    classicalRating:
        _positive(authoritative.classicalRating) ?? fallback.classicalRating,
    rapidRating: _positive(authoritative.rapidRating) ?? fallback.rapidRating,
    blitzRating: _positive(authoritative.blitzRating) ?? fallback.blitzRating,
    classicalGames: authoritative.classicalGames ?? fallback.classicalGames,
    rapidGames: authoritative.rapidGames ?? fallback.rapidGames,
    blitzGames: authoritative.blitzGames ?? fallback.blitzGames,
    birthday: _nonBlank(authoritative.birthday) ?? fallback.birthday,
    sex: _nonBlank(authoritative.sex) ?? fallback.sex,
  );
}

String? _nonBlank(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

int? _positive(int? value) => value != null && value > 0 ? value : null;
