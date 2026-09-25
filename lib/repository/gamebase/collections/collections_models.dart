import 'package:flutter/foundation.dart';

/// Models for the gamebase Collections API (`/api/collections…`): curated
/// sets of annotated games, either one tournament's (`event`) or a book's
/// (`book`). The ChessEver team uploads them in the chessever.com admin
/// console (Content > Collections); the app only reads published ones.
///
/// Every parser here tolerates nulls, wrong scalar types and unknown keys, so
/// a field the backend adds later (or leaves null) never breaks the list.

/// What a collection holds.
enum CollectionKind {
  /// Annotated games from one tournament.
  event,

  /// The games of a book.
  book;

  String get apiValue => name;

  static CollectionKind parse(Object? raw) =>
      raw?.toString().trim().toLowerCase() == 'book'
          ? CollectionKind.book
          : CollectionKind.event;
}

/// What a node of a collection's section tree stands for.
enum CollectionSectionKind {
  /// One round of an event, dated by [CollectionSection.startsOn].
  round,

  /// A stage of an event (e.g. a knockout stage).
  stage,

  /// A part of a book; its chapters are its children.
  part,

  /// A chapter of a book, which may open with an intro text.
  chapter,

  /// A kind this build does not know yet, drawn like a round.
  other;

  static CollectionSectionKind parse(Object? raw) {
    return switch (raw?.toString().trim().toLowerCase()) {
      'round' => CollectionSectionKind.round,
      'stage' => CollectionSectionKind.stage,
      'part' => CollectionSectionKind.part,
      'chapter' => CollectionSectionKind.chapter,
      _ => CollectionSectionKind.other,
    };
  }
}

/// A collections request gamebase refused, carrying its own `error.message`.
///
/// [toString] keeps the HTTP status (" (HTTP 404)") so `userFacingError`
/// still classifies it; the UI never shows this text verbatim.
@immutable
class CollectionsRequestException implements Exception {
  const CollectionsRequestException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() =>
      statusCode == null ? message : '$message (HTTP $statusCode)';
}

/// The `data` payload of a gamebase `{status, data}` envelope. Throws a
/// [CollectionsRequestException] with the server's own message on
/// `{status: "error"}`, and a [FormatException] on a body that is not an
/// envelope at all. [statusCode] is the HTTP status the body came with.
Object? unwrapCollectionsEnvelope(Object? body, {int? statusCode}) {
  if (body is! Map) {
    throw const FormatException('Unexpected collections response format');
  }
  if (body['status'] == 'error') {
    final error = body['error'];
    final message =
        error is Map ? _nullableString(error['message']) : _nullableString(error);
    throw CollectionsRequestException(
      message ?? 'Collections request failed',
      statusCode: statusCode,
    );
  }
  return body['data'];
}

/// One collection: a list row (`CollectionSummary`) or, when read by slug,
/// the full `CollectionDetail` with [about] and the [sections] tree.
@immutable
class Collection {
  const Collection({
    required this.id,
    required this.slug,
    required this.kind,
    required this.title,
    this.subtitle,
    this.author,
    this.annotator,
    this.coverUrl,
    this.location,
    this.dateStart,
    this.dateEnd,
    this.publisher,
    this.publishedYear,
    this.sortOrder = 0,
    this.publishedAt,
    this.gameCount = 0,
    this.sectionCount = 0,
    this.annotatedCount = 0,
    this.plyTotal = 0,
    this.players = const [],
    this.ecos = const [],
    this.contentVersion,
    this.updatedAt,
    this.about,
    this.sections = const [],
    this.unsortedCount = 0,
  });

  final String id;

  /// The API key of the collection: every read after the list is by slug.
  final String slug;
  final CollectionKind kind;
  final String title;

  /// One line under the title: where and when, or a book's edition.
  final String? subtitle;

  /// The book's author (for an event, whoever the team credits).
  final String? author;

  /// Who annotated the games.
  final String? annotator;
  final String? coverUrl;

  /// Where an event was played.
  final String? location;
  final DateTime? dateStart;
  final DateTime? dateEnd;

  /// A book's publisher and year.
  final String? publisher;
  final int? publishedYear;

  final int sortOrder;
  final DateTime? publishedAt;
  final int gameCount;
  final int sectionCount;
  final int annotatedCount;
  final int plyTotal;

  /// Display names, most games first (at most 50; the Players tab has all).
  final List<String> players;

  /// Distinct ECO codes of the games.
  final List<String> ecos;
  final String? contentVersion;
  final DateTime? updatedAt;

  /// The About tab's text; blank lines separate paragraphs. Detail only.
  final String? about;

  /// Rounds / stages of an event, parts (holding chapters) / chapters of a
  /// book, ordered by [CollectionSection.orderIndex]. Detail only.
  final List<CollectionSection> sections;

  /// Games that sit in no section. Detail only.
  final int unsortedCount;

  factory Collection.fromJson(Map<String, dynamic> json) {
    final id = _string(json['id']);
    final sections = _maps(json['sections'])
        .map(CollectionSection.fromJson)
        .toList(growable: false);
    return Collection(
      id: id,
      slug: _nullableString(json['slug']) ?? id,
      kind: CollectionKind.parse(json['kind']),
      title: _nullableString(json['title']) ?? 'Untitled',
      subtitle: _nullableString(json['subtitle']),
      author: _nullableString(json['author']),
      annotator: _nullableString(json['annotator']),
      coverUrl: _nullableString(json['coverUrl']),
      location: _nullableString(json['location']),
      dateStart: _day(json['dateStart']),
      dateEnd: _day(json['dateEnd']),
      publisher: _nullableString(json['publisher']),
      publishedYear: _nullableInt(json['publishedYear']),
      sortOrder: _int(json['sortOrder']),
      publishedAt: _timestamp(json['publishedAt']),
      gameCount: _int(json['gameCount']),
      sectionCount: _int(json['sectionCount']),
      annotatedCount: _int(json['annotatedCount']),
      plyTotal: _int(json['plyTotal']),
      players: _strings(json['players']),
      ecos: _strings(json['ecos']),
      contentVersion: _nullableString(json['contentVersion']),
      updatedAt: _timestamp(json['updatedAt']),
      about: _nullableString(json['about']),
      sections: _sortedSections(sections),
      unsortedCount: _int(json['unsortedCount']),
    );
  }
}

/// One node of a collection's section tree.
@immutable
class CollectionSection {
  const CollectionSection({
    required this.id,
    required this.kind,
    required this.label,
    this.parentId,
    this.number,
    this.title,
    this.intro,
    this.sourceTag,
    this.startsOn,
    this.orderIndex = 0,
    this.gameCount = 0,
    this.children = const [],
  });

  final String id;
  final String? parentId;
  final CollectionSectionKind kind;

  /// Display label as printed: "Round 5", "Chapter 7", "Part I".
  final String label;

  /// "5", "7", "I", "1.2" as printed.
  final String? number;

  /// "The Pin".
  final String? title;

  /// A chapter's introduction, shown above its games.
  final String? intro;
  final String? sourceTag;

  /// A round's date.
  final DateTime? startsOn;
  final int orderIndex;

  /// Games directly in this section (not in its children).
  final int gameCount;

  /// Only parts have children (their chapters).
  final List<CollectionSection> children;

  factory CollectionSection.fromJson(Map<String, dynamic> json) {
    final children = _maps(json['children'])
        .map(CollectionSection.fromJson)
        .toList(growable: false);
    final number = _nullableString(json['number']);
    final title = _nullableString(json['title']);
    return CollectionSection(
      id: _string(json['id']),
      parentId: _nullableString(json['parentId']),
      kind: CollectionSectionKind.parse(json['kind']),
      label: _nullableString(json['label']) ?? title ?? number ?? '',
      number: number,
      title: title,
      intro: _nullableString(json['intro']),
      sourceTag: _nullableString(json['sourceTag']),
      startsOn: _day(json['startsOn']),
      orderIndex: _int(json['orderIndex']),
      gameCount: _int(json['gameCount']),
      children: _sortedSections(children),
    );
  }
}

/// One side of a [CollectionGameCard].
@immutable
class CollectionPlayerSide {
  const CollectionPlayerSide({
    required this.name,
    required this.key,
    this.elo,
    this.title,
    this.fed,
    this.fideId,
    this.playerId,
  });

  final String name;

  /// `fide:<id>` or `name:<lower>`; the same key a [CollectionPlayer] has.
  final String key;
  final int? elo;
  final String? title;
  final String? fed;
  final String? fideId;
  final String? playerId;

  /// [fallbackName] stands in for a missing name ("White" / "Black").
  factory CollectionPlayerSide.fromJson(
    Map<String, dynamic> json, {
    String fallbackName = '',
  }) {
    final name = _string(json['name']);
    final fideId = _nullableString(json['fideId']);
    return CollectionPlayerSide(
      name: name.isEmpty ? fallbackName : name,
      key:
          _nullableString(json['key']) ??
          (fideId != null ? 'fide:$fideId' : 'name:${name.toLowerCase()}'),
      elo: _positiveInt(json['elo']),
      title: _nullableString(json['title']),
      fed: _nullableString(json['fed']),
      fideId: fideId,
      playerId: _nullableString(json['playerId']),
    );
  }
}

/// A game of a collection as the games endpoint lists it. [pgn] is only
/// present when the request asked for `include=pgn`.
@immutable
class CollectionGameCard {
  const CollectionGameCard({
    required this.id,
    required this.white,
    required this.black,
    this.sectionId,
    this.orderIndex = 0,
    this.result = '*',
    this.roundTag,
    this.board,
    this.playedOn,
    this.event,
    this.site,
    this.eco,
    this.opening,
    this.annotator,
    this.startingFen,
    this.finalFen,
    this.lastMove,
    this.plyCount = 0,
    this.commentCount = 0,
    this.nagCount = 0,
    this.variationCount = 0,
    this.hasAnnotations = false,
    this.contentHash,
    this.updatedAt,
    this.pgn,
  });

  final String id;

  /// Null for a game in no section (shown last, under the other games).
  final String? sectionId;
  final int orderIndex;
  final CollectionPlayerSide white;
  final CollectionPlayerSide black;

  /// "1-0", "0-1", "1/2-1/2" or "*".
  final String result;
  final String? roundTag;
  final int? board;
  final DateTime? playedOn;
  final String? event;
  final String? site;
  final String? eco;
  final String? opening;
  final String? annotator;

  /// Null for the standard start.
  final String? startingFen;
  final String? finalFen;

  /// UCI, e.g. "e2e4".
  final String? lastMove;
  final int plyCount;
  final int commentCount;
  final int nagCount;
  final int variationCount;
  final bool hasAnnotations;
  final String? contentHash;
  final DateTime? updatedAt;
  final String? pgn;

  /// Whether [playerKey] (a [CollectionPlayer.key]) played this game.
  bool involves(String playerKey) =>
      white.key == playerKey || black.key == playerKey;

  factory CollectionGameCard.fromJson(Map<String, dynamic> json) {
    CollectionPlayerSide side(Object? raw, String fallback) =>
        CollectionPlayerSide.fromJson(
          raw is Map ? Map<String, dynamic>.from(raw) : const {},
          fallbackName: fallback,
        );

    final pgn = json['pgn'];
    return CollectionGameCard(
      id: _string(json['id']),
      sectionId: _nullableString(json['sectionId']),
      orderIndex: _int(json['orderIndex']),
      white: side(json['white'], 'White'),
      black: side(json['black'], 'Black'),
      result: _nullableString(json['result']) ?? '*',
      roundTag: _nullableString(json['roundTag']),
      board: _nullableInt(json['board']),
      playedOn: _day(json['playedOn']),
      event: _nullableString(json['event']),
      site: _nullableString(json['site']),
      eco: _nullableString(json['eco']),
      opening: _nullableString(json['opening']),
      annotator: _nullableString(json['annotator']),
      startingFen: _nullableString(json['startingFen']),
      finalFen: _nullableString(json['finalFen']),
      lastMove: _nullableString(json['lastMove']),
      plyCount: _int(json['plyCount']),
      commentCount: _int(json['commentCount']),
      nagCount: _int(json['nagCount']),
      variationCount: _int(json['variationCount']),
      hasAnnotations: _bool(json['hasAnnotations']),
      contentHash: _nullableString(json['contentHash']),
      updatedAt: _timestamp(json['updatedAt']),
      pgn: pgn is String && pgn.trim().isNotEmpty ? pgn : null,
    );
  }
}

/// One player of a collection and their score in it.
@immutable
class CollectionPlayer {
  const CollectionPlayer({
    required this.key,
    required this.name,
    this.title,
    this.fed,
    this.fideId,
    this.playerId,
    this.bestElo,
    this.games = 0,
    this.wins = 0,
    this.draws = 0,
    this.losses = 0,
  });

  /// `fide:<id>` or `name:<lower>`; matches [CollectionPlayerSide.key].
  final String key;
  final String name;
  final String? title;
  final String? fed;
  final String? fideId;
  final String? playerId;
  final int? bestElo;
  final int games;
  final int wins;
  final int draws;
  final int losses;

  factory CollectionPlayer.fromJson(Map<String, dynamic> json) {
    final name = _string(json['name']);
    final fideId = _nullableString(json['fideId']);
    return CollectionPlayer(
      key:
          _nullableString(json['key']) ??
          (fideId != null ? 'fide:$fideId' : 'name:${name.toLowerCase()}'),
      name: name,
      title: _nullableString(json['title']),
      fed: _nullableString(json['fed']),
      fideId: fideId,
      playerId: _nullableString(json['playerId']),
      bestElo: _positiveInt(json['bestElo']),
      games: _int(json['games']),
      wins: _int(json['wins']),
      draws: _int(json['draws']),
      losses: _int(json['losses']),
    );
  }

  /// The `{items}` payload of `GET /api/collections/:slug/players`.
  static List<CollectionPlayer> listFromJson(Object? data) {
    final items = data is Map ? data['items'] : data;
    return [
      for (final item in _maps(items))
        if (_nullableString(item['name']) != null)
          CollectionPlayer.fromJson(item),
    ];
  }
}

/// One page of `GET /api/collections`.
@immutable
class CollectionsPage {
  const CollectionsPage({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  final List<Collection> items;
  final int total;
  final int limit;
  final int offset;

  factory CollectionsPage.fromJson(Object? data) {
    final map = data is Map ? data : const {};
    final items = [
      for (final item in _maps(map['items']))
        if (_nullableString(item['id']) != null ||
            _nullableString(item['slug']) != null)
          Collection.fromJson(item),
    ];
    return CollectionsPage(
      items: items,
      total: map.containsKey('total') ? _int(map['total']) : items.length,
      limit: _int(map['limit']),
      offset: _int(map['offset']),
    );
  }
}

/// One page of `GET /api/collections/:slug/games`.
@immutable
class CollectionGamesPage {
  const CollectionGamesPage({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  final List<CollectionGameCard> items;
  final int total;
  final int limit;
  final int offset;

  factory CollectionGamesPage.fromJson(Object? data) {
    final map = data is Map ? data : const {};
    final items = [
      for (final item in _maps(map['items']))
        if (_nullableString(item['id']) != null)
          CollectionGameCard.fromJson(item),
    ];
    return CollectionGamesPage(
      items: items,
      total: map.containsKey('total') ? _int(map['total']) : items.length,
      limit: _int(map['limit']),
      offset: _int(map['offset']),
    );
  }
}

List<CollectionSection> _sortedSections(List<CollectionSection> sections) {
  if (sections.length < 2) return sections;
  // Stable: equal orderIndex keeps the server's order.
  final indexed = [for (var i = 0; i < sections.length; i++) (i, sections[i])];
  indexed.sort((a, b) {
    final byOrder = a.$2.orderIndex.compareTo(b.$2.orderIndex);
    return byOrder != 0 ? byOrder : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

Iterable<Map<String, dynamic>> _maps(Object? raw) sync* {
  if (raw is! List) return;
  for (final item in raw) {
    if (item is Map) yield Map<String, dynamic>.from(item);
  }
}

List<String> _strings(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (_nullableString(item) case final String s) s,
  ];
}

String _string(Object? value) => value?.toString().trim() ?? '';

String? _nullableString(Object? value) {
  if (value == null) return null;
  final trimmed = value.toString().trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _nullableInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

int _int(Object? value) => _nullableInt(value) ?? 0;

/// Ratings: 0 and below mean unrated.
int? _positiveInt(Object? value) {
  final parsed = _nullableInt(value);
  return parsed != null && parsed > 0 ? parsed : null;
}

bool _bool(Object? value) {
  if (value is bool) return value;
  final normalized = value?.toString().trim().toLowerCase();
  return normalized == 'true' || normalized == '1';
}

/// A calendar day (`YYYY-MM-DD`), kept as that local date so it never shifts
/// by a time zone.
DateTime? _day(Object? value) {
  final raw = _nullableString(value);
  if (raw == null) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  return DateTime(year, month, day);
}

DateTime? _timestamp(Object? value) {
  final raw = _nullableString(value);
  return raw == null ? null : DateTime.tryParse(raw);
}
