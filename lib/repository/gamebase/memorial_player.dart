class MemorialPlayer {
  const MemorialPlayer({
    required this.id,
    required this.profileKey,
    required this.routeId,
    required this.sourceIdentity,
    required this.name,
    required this.fed,
    required this.ratingClassical,
    this.ratingRapid = 0,
    this.ratingBlitz = 0,
    required this.hasGames,
    required this.sourceBacked,
    this.aliases = const [],
    this.title,
    this.fideId,
    this.fideIdStatus,
    this.birthDate,
    this.deathDate,
    this.gamebasePlayerId,
  });

  final String id;
  final String profileKey;
  final String routeId;
  final String sourceIdentity;
  final String name;
  final String? title;
  final String fed;
  final String? fideId;
  final String? fideIdStatus;
  final int ratingClassical;
  final int ratingRapid;
  final int ratingBlitz;
  final String? birthDate;
  final String? deathDate;
  final bool hasGames;
  final bool sourceBacked;
  final List<String> aliases;
  final String? gamebasePlayerId;

  factory MemorialPlayer.fromJson(Map<String, dynamic> json) {
    final profileKey = json['profileKey']?.toString() ?? '';
    return MemorialPlayer(
      id: json['id']?.toString() ?? profileKey,
      profileKey: profileKey,
      routeId: json['routeId']?.toString() ?? '',
      sourceIdentity: json['sourceIdentity']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      title: json['title']?.toString(),
      fed: json['fed']?.toString() ?? '',
      fideId: json['fideId']?.toString(),
      fideIdStatus: json['fideIdStatus']?.toString(),
      ratingClassical: (json['ratingClassical'] as num?)?.toInt() ?? 0,
      ratingRapid: (json['ratingRapid'] as num?)?.toInt() ?? 0,
      ratingBlitz: (json['ratingBlitz'] as num?)?.toInt() ?? 0,
      birthDate: json['birthDate']?.toString(),
      deathDate: json['deathDate']?.toString(),
      hasGames: json['hasGames'] == true,
      sourceBacked: json['sourceBacked'] == true,
      aliases: (json['aliases'] as List<dynamic>? ?? const <dynamic>[])
          .map((alias) => alias.toString())
          .where((alias) => alias.trim().isNotEmpty)
          .toList(growable: false),
      gamebasePlayerId: json['gamebasePlayerId']?.toString(),
    );
  }
}

/// Public, license-reviewed Memorial portraits are served by the web app.
/// The image widget still owns 404/error fallback because not every profile has
/// a portrait yet.
String? memorialPlayerPhotoUrl({
  required String playerName,
  String? sourceIdentity,
}) {
  final identity = sourceIdentity?.trim();
  if (identity == null || identity.isEmpty) return null;

  final commaParts = playerName.split(',');
  var naturalName = playerName;
  if (commaParts.length > 1) {
    final surname = commaParts.first.trim();
    final givenNames = commaParts.skip(1).join(' ').trim();
    naturalName = '$givenNames $surname'.trim();
  }

  var slug = naturalName.toLowerCase();
  const replacements = <String, String>{
    r'[àáâãäåāăą]': 'a',
    r'[æ]': 'ae',
    r'[çćĉċč]': 'c',
    r'[ďđ]': 'd',
    r'[èéêëēĕėęě]': 'e',
    r'[ĝğġģ]': 'g',
    r'[ĥħ]': 'h',
    r'[ìíîïĩīĭįı]': 'i',
    r'[ĵ]': 'j',
    r'[ķ]': 'k',
    r'[ĺļľŀł]': 'l',
    r'[ñńņňŉŋ]': 'n',
    r'[òóôõöøōŏő]': 'o',
    r'[œ]': 'oe',
    r'[ŕŗř]': 'r',
    r'[śŝşš]': 's',
    r'[ß]': 'ss',
    r'[ţťŧ]': 't',
    r'[ùúûüũūŭůűų]': 'u',
    r'[ŵ]': 'w',
    r'[ýÿŷ]': 'y',
    r'[źżž]': 'z',
  };
  for (final replacement in replacements.entries) {
    slug = slug.replaceAll(RegExp(replacement.key), replacement.value);
  }
  slug = slug
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.isEmpty) return null;
  return 'https://chessever.com/images/memorial/players/$slug.webp';
}
