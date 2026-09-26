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

/// Who may read a collection's games.
enum CollectionAccess {
  /// Everyone.
  free,

  /// Premium subscribers only; everyone else sees the cover, the credits and
  /// the table of contents, and the paywall.
  premium;

  /// The value the server applies when a row has none of its own: books are
  /// Premium, everything else is free. An unknown value reads as that default
  /// too, so a later server value never opens a Premium book by accident.
  static CollectionAccess parse(Object? raw, CollectionKind kind) {
    return switch (raw?.toString().trim().toLowerCase()) {
      'free' => CollectionAccess.free,
      'premium' => CollectionAccess.premium,
      _ =>
        kind == CollectionKind.book
            ? CollectionAccess.premium
            : CollectionAccess.free,
    };
  }
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

/// The lock reason (and error code) for a session the server did not
/// accept: none was sent, or it was spent or refused.
const String kCollectionLockAuthRequired = 'auth_required';

/// A collections request gamebase refused, carrying its own `error.message`.
///
/// [toString] keeps the HTTP status (" (HTTP 404)") so `userFacingError`
/// still classifies it; the UI never shows this text verbatim.
@immutable
class CollectionsRequestException implements Exception {
  const CollectionsRequestException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;

  /// The envelope's machine-readable `error.code` ("premium_required",
  /// "auth_required", "access_check_unavailable", ...), when it has one.
  final String? code;

  /// The server kept a Premium collection's games from this viewer: no
  /// entitlement ("premium_required"), or no account to check
  /// ("auth_required"). A reason to show the paywall, never an error.
  bool get isPremiumGate =>
      code == 'premium_required' || code == kCollectionLockAuthRequired;

  /// The gate is the session: none was sent, or the server refused it.
  bool get isSignInGate => code == kCollectionLockAuthRequired;

  /// The server could not reach the entitlement check just now. The viewer
  /// may well be entitled, so this is a retry, not a paywall.
  bool get isAccessCheckUnavailable => code == 'access_check_unavailable';

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
    final message = error is Map
        ? _nullableString(error['message'])
        : _nullableString(error);
    throw CollectionsRequestException(
      message ?? 'Collections request failed',
      statusCode: statusCode,
      code: error is Map ? _nullableString(error['code']) : null,
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
    this.foreword,
    this.sections = const [],
    this.unsortedCount = 0,
    CollectionAccess? access,
    this.contentLocked,
    this.lockReason,
    this.eventCount = 0,
    this.bookCount,
    this.events = const [],
    this.note,
    this.linkId,
  }) : access =
           access ??
           (kind == CollectionKind.book
               ? CollectionAccess.premium
               : CollectionAccess.free);

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

  /// A book's foreword, as its author wrote it; blank lines separate
  /// paragraphs. Null when the book has none, and from a server that does
  /// not send one yet. Detail only.
  final String? foreword;

  /// Rounds / stages of an event, parts (holding chapters) / chapters of a
  /// book, ordered by [CollectionSection.orderIndex]. Detail only.
  final List<CollectionSection> sections;

  /// Games that sit in no section. Detail only.
  final int unsortedCount;

  /// Who may read the games: [CollectionAccess.premium] for books unless the
  /// team opened one up.
  final CollectionAccess access;

  /// The server's verdict for this viewer, on a detail read: true when the
  /// games are closed to them (a Premium collection and no verified
  /// entitlement), false when they may read them. Null when the server did
  /// not say (a list row, or a server from before the Premium gate).
  final bool? contentLocked;

  /// Why the server keeps the games from this viewer, when it does (or
  /// could not tell): the code the games route answers with,
  /// "premium_required", "auth_required" (no session, or one it refused),
  /// "access_check_unavailable". Null when the viewer reads the games, and
  /// from a server that does not say.
  final String? lockReason;

  /// The server refused (or never got) this viewer's session: signing in
  /// again is the way in, not waiting for a purchase to sync.
  bool get lockedForSignIn => lockReason == kCollectionLockAuthRequired;

  /// How many real-world events the collection is bound to.
  final int eventCount;

  /// How many published books are bound to this event collection, on a
  /// list row. Null when the server did not say (a server from before the
  /// count, or a book's row): unknown, never "no books".
  final int? bookCount;

  /// The events a book is bound to, in the team's order. Detail only.
  final List<CollectionEventRef> events;

  /// The team's line on why this book belongs to the event it was listed
  /// for (`GET /api/collections/for-event` rows only).
  final String? note;

  /// The binding a `for-event` row came through.
  final String? linkId;

  bool get isPremium => access == CollectionAccess.premium;

  factory Collection.fromJson(Map<String, dynamic> json) {
    final id = _string(json['id']);
    final kind = CollectionKind.parse(json['kind']);
    final sections = _maps(
      json['sections'],
    ).map(CollectionSection.fromJson).toList(growable: false);
    final events = [
      for (final e in _maps(json['events'])) ?CollectionEventRef.fromJson(e),
    ];
    final locked = json['contentLocked'];
    return Collection(
      id: id,
      slug: _nullableString(json['slug']) ?? id,
      kind: kind,
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
      foreword: _nullableString(json['foreword']),
      sections: _sortedSections(sections),
      unsortedCount: _int(json['unsortedCount']),
      access: CollectionAccess.parse(json['access'], kind),
      contentLocked: locked == null ? null : _bool(locked),
      lockReason: _nullableString(json['lockReason']),
      eventCount: json.containsKey('eventCount')
          ? _int(json['eventCount'])
          : events.length,
      bookCount: _nullableInt(json['bookCount']),
      events: events,
      note: _nullableString(json['note']),
      linkId: _nullableString(json['linkId']),
    );
  }
}

/// How the app opens one of a book's events, as the server resolved it.
enum CollectionEventOpenKind {
  /// A ChessEver broadcast: [CollectionEventOpen.groupBroadcastId], with the
  /// tour to land on when known.
  broadcast,

  /// A broadcast known only by its slug (`tours.slug`).
  broadcastSlug,

  /// A database (TWIC) event, by its PGN Event name, and its Site when the
  /// server knows one (today it binds a database event by name alone, so
  /// the event opens under its name).
  database,

  /// A curated event collection, by its slug.
  collection,
}

/// Where one of a book's events opens (`CollectionEventRef.open`).
@immutable
class CollectionEventOpen {
  const CollectionEventOpen._({
    required this.kind,
    this.groupBroadcastId,
    this.tourId,
    this.slug,
    this.eventName,
    this.site,
  });

  const CollectionEventOpen.broadcast({
    required String groupBroadcastId,
    String? tourId,
  }) : this._(
         kind: CollectionEventOpenKind.broadcast,
         groupBroadcastId: groupBroadcastId,
         tourId: tourId,
       );

  const CollectionEventOpen.broadcastSlug(String slug)
    : this._(kind: CollectionEventOpenKind.broadcastSlug, slug: slug);

  const CollectionEventOpen.database({required String eventName, String? site})
    : this._(
        kind: CollectionEventOpenKind.database,
        eventName: eventName,
        site: site,
      );

  const CollectionEventOpen.collection(String slug)
    : this._(kind: CollectionEventOpenKind.collection, slug: slug);

  final CollectionEventOpenKind kind;
  final String? groupBroadcastId;
  final String? tourId;

  /// [CollectionEventOpenKind.broadcastSlug]'s tour slug, or
  /// [CollectionEventOpenKind.collection]'s collection slug.
  final String? slug;
  final String? eventName;

  /// [CollectionEventOpenKind.database]'s Site; null when the server binds
  /// the event by its name alone.
  final String? site;

  /// Null for a kind this build does not know, or one missing the id it
  /// needs: the row then shows, but does not open.
  static CollectionEventOpen? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final kind = _nullableString(raw['kind'])?.toLowerCase();
    switch (kind) {
      case 'broadcast':
        final group = _nullableString(raw['groupBroadcastId']);
        final tour = _nullableString(raw['tourId']);
        if (group == null && tour == null) return null;
        return CollectionEventOpen.broadcast(
          // A tour id resolves to its group as well (the deep-link resolver
          // probes both), so a row with only the tour still opens.
          groupBroadcastId: group ?? tour!,
          tourId: tour,
        );
      case 'broadcast_slug':
        final slug = _nullableString(raw['slug']);
        return slug == null ? null : CollectionEventOpen.broadcastSlug(slug);
      case 'database':
        final name = _nullableString(raw['eventName']);
        return name == null
            ? null
            : CollectionEventOpen.database(
                eventName: name,
                site: _nullableString(raw['site']),
              );
      case 'collection':
        final slug = _nullableString(raw['slug']);
        return slug == null ? null : CollectionEventOpen.collection(slug);
    }
    return null;
  }
}

/// One real-world event a book is bound to, as its detail lists it.
@immutable
class CollectionEventRef {
  const CollectionEventRef({
    required this.linkId,
    required this.title,
    this.location,
    this.dateStart,
    this.dateEnd,
    this.imageUrl,
    this.note,
    this.open,
  });

  final String linkId;
  final String title;
  final String? location;
  final DateTime? dateStart;
  final DateTime? dateEnd;
  final String? imageUrl;

  /// The team's caption for the binding.
  final String? note;

  /// Null when the server could not resolve the event to anything the app
  /// opens (the row still shows what the book covers).
  final CollectionEventOpen? open;

  /// Null for a row with neither a link id nor a title.
  static CollectionEventRef? fromJson(Map<String, dynamic> json) {
    final title = _nullableString(json['title']);
    final linkId =
        _nullableString(json['linkId']) ?? _nullableString(json['id']);
    if (title == null || linkId == null) return null;
    return CollectionEventRef(
      linkId: linkId,
      title: title,
      location: _nullableString(json['location']),
      dateStart: _day(json['dateStart']),
      dateEnd: _day(json['dateEnd']),
      imageUrl: _nullableString(json['imageUrl']),
      note: _nullableString(json['note']),
      open: CollectionEventOpen.fromJson(json['open']),
    );
  }
}

/// Every identity one event page is known by, as
/// `GET /api/collections/for-event` takes them: the server expands each
/// through its mirror of the broadcast tables, so a re-minted group or a
/// database twin of the same event still finds the books bound to it.
///
/// Values are trimmed, deduplicated and sorted, so two pages naming the same
/// event share one cache entry; each list keeps at most [maxValues] values of
/// at most [maxLength] characters, as the endpoint accepts.
@immutable
class CollectionEventAnchors {
  CollectionEventAnchors({
    Iterable<String?> groups = const [],
    Iterable<String?> tours = const [],
    Iterable<String?> slugs = const [],
    Iterable<String?> events = const [],
    String? site,
    Iterable<String?> collections = const [],
  }) : groups = _clean(groups),
       tours = _clean(tours),
       slugs = _clean(slugs, lower: true),
       events = _clean(events),
       site = _clip(site),
       collections = _clean(collections);

  static const int maxValues = 20;
  static const int maxLength = 200;

  /// Group broadcast ids (`gb_<tourId>` or a data-hub slug).
  final List<String> groups;

  /// Lichess tour ids.
  final List<String> tours;

  /// Tour slugs (lower case, as `game.broadcast_slug` stores them).
  final List<String> slugs;

  /// PGN Event names of database events.
  final List<String> events;

  /// The database event's Site. It does not narrow [events]: a database
  /// event's books match on its Event name alone. The server reads a Lichess
  /// broadcast URL here as that broadcast's slug, so the database twin of a
  /// broadcast finds the books bound to the broadcast.
  final String? site;

  /// Ids of curated event collections.
  final List<String> collections;

  bool get isEmpty =>
      groups.isEmpty &&
      tours.isEmpty &&
      slugs.isEmpty &&
      events.isEmpty &&
      collections.isEmpty;

  /// The query string, each value repeated under its key.
  Map<String, List<String>> toQuery({
    CollectionKind kind = CollectionKind.book,
  }) {
    return {
      if (groups.isNotEmpty) 'group': groups,
      if (tours.isNotEmpty) 'tour': tours,
      if (slugs.isNotEmpty) 'slug': slugs,
      if (events.isNotEmpty) 'event': events,
      if (events.isNotEmpty && site != null) 'site': [site!],
      if (collections.isNotEmpty) 'collection': collections,
      'kind': [kind.apiValue],
    };
  }

  static List<String> _clean(Iterable<String?> raw, {bool lower = false}) {
    final out = <String>{};
    for (final value in raw) {
      var v = _clip(value);
      if (v == null) continue;
      if (lower) v = v.toLowerCase();
      out.add(v);
    }
    final sorted = out.toList()..sort();
    return List.unmodifiable(sorted.take(maxValues));
  }

  static String? _clip(String? value) {
    final v = value?.trim();
    if (v == null || v.isEmpty) return null;
    return v.length > maxLength ? v.substring(0, maxLength) : v;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CollectionEventAnchors &&
          listEquals(groups, other.groups) &&
          listEquals(tours, other.tours) &&
          listEquals(slugs, other.slugs) &&
          listEquals(events, other.events) &&
          site == other.site &&
          listEquals(collections, other.collections);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(groups),
    Object.hashAll(tours),
    Object.hashAll(slugs),
    Object.hashAll(events),
    site,
    Object.hashAll(collections),
  );

  @override
  String toString() => 'CollectionEventAnchors(${toQuery()})';
}

/// The `{books}` payload of `GET /api/collections/for-event`: the published
/// books bound to one event, in the team's order, each with its [note].
List<Collection> collectionsForEventFromJson(Object? data) {
  final items = data is Map ? (data['books'] ?? data['items']) : data;
  return [
    for (final item in _maps(items))
      if (_nullableString(item['id']) != null ||
          _nullableString(item['slug']) != null)
        Collection.fromJson(item),
  ];
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
    final children = _maps(
      json['children'],
    ).map(CollectionSection.fromJson).toList(growable: false);
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
