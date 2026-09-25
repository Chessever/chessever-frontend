import 'package:flutter/foundation.dart';

/// Everything a user can pin into My Space. Each kind is a deep link into one
/// surface of the app; [SpaceShortcut.params] carries whatever that surface
/// needs to open in the exact state the user saved it in.
enum SpaceShortcutKind {
  /// A player's profile. targetId: FIDE id (or gamebase player id / name).
  player,

  /// A player's Games tab. Same targetId as [player].
  playerGames,

  /// A player's opening tree in the explorer. params: `color`, `fen`.
  playerOpenings,

  /// A tournament / broadcast. targetId: tour or group broadcast id, or a
  /// gamebase virtual event id (`gamebase::` / `gamebasev2::`) for a
  /// database-only event. A calendar (community or FIDE major) event keeps
  /// this kind with params `source: 'calendar'` and `calendarEventId` (the
  /// calendar event's name); older calendar pins carry the card's
  /// `cal_event_` id and `eventSource: 'communityEvent'` instead.
  event,

  /// One round of an event. targetId: round id. params: `tourId`, and
  /// `groupBroadcastId` / `eventName` when known.
  round,

  /// One game on the board. targetId: game id. params: `tourId`, `roundId`.
  game,

  /// An explorer position. targetId: FEN. params: `moves` (SAN list), `eco`,
  /// `openingName`, optional `playerId`/`playerName` filter.
  position,

  /// An opening family by ECO. targetId: ECO code. params: `name`.
  opening,

  /// A library folder or database. targetId: folder id. One event of the
  /// ChessEver Database is `<kTwicBookId>:<event>` with params `event`.
  folder,

  /// A saved smart event. targetId: criteria key. params: `request` json.
  smartEvent,

  /// Countrymen for a federation. targetId: country code (ISO alpha-2, or a
  /// FIDE three-letter code).
  countrymen,

  /// Today's miniatures. targetId: `today`.
  miniatures,

  /// My Likes. targetId: `me`.
  likes,

  /// One player's streak card. targetId: FIDE id. Lives in the Players row:
  /// a streak is about a player. My Space offers no streaks of its own (they
  /// belong to Discovery); this kind keeps every existing pin opening.
  streak,

  /// Any chessever.com link the app can already open (a team or player
  /// scorecard, an event tab, a profile, a game, a shared database, a streak
  /// card). targetId: the URL.
  link,

  /// A published ChessEver collection (an annotated event or a book, from
  /// Discovery's Collection). targetId: the collection id. params: `slug`,
  /// `collectionKind`, `coverUrl`, `gameCount`. Sits with the databases.
  collection,
}

/// The row a shortcut lives in on My Space, in page order. Never persisted:
/// a shortcut's row is derived from its kind, so reordering rows is safe.
enum SpaceSection {
  library,
  players,
  events,
  likes,
  games,
  smartEvents,

  /// Named lines and saved positions (board editor setups, explorer spots).
  openings,
  links,
}

extension SpaceShortcutKindX on SpaceShortcutKind {
  SpaceSection get section => switch (this) {
    SpaceShortcutKind.player ||
    SpaceShortcutKind.playerGames ||
    SpaceShortcutKind.countrymen ||
    SpaceShortcutKind.streak => SpaceSection.players,
    SpaceShortcutKind.event || SpaceShortcutKind.round => SpaceSection.events,
    SpaceShortcutKind.position ||
    SpaceShortcutKind.opening ||
    SpaceShortcutKind.playerOpenings => SpaceSection.openings,
    SpaceShortcutKind.folder ||
    SpaceShortcutKind.miniatures ||
    SpaceShortcutKind.collection => SpaceSection.library,
    SpaceShortcutKind.likes => SpaceSection.likes,
    SpaceShortcutKind.game => SpaceSection.games,
    SpaceShortcutKind.smartEvent => SpaceSection.smartEvents,
    SpaceShortcutKind.link => SpaceSection.links,
  };

  static SpaceShortcutKind? tryParse(String? raw) {
    if (raw == null) return null;
    for (final k in SpaceShortcutKind.values) {
      if (k.name == raw) return k;
    }
    return null;
  }
}

extension SpaceSectionX on SpaceSection {
  /// Row title on My Space.
  String get title => switch (this) {
    SpaceSection.library => 'Library',
    SpaceSection.players => 'Players',
    SpaceSection.events => 'Events',
    SpaceSection.likes => 'My Likes',
    SpaceSection.games => 'Games',
    SpaceSection.smartEvents => 'Smart Events',
    SpaceSection.openings => 'Openings',
    SpaceSection.links => 'Shortcuts',
  };

  /// The action label on the row's door tile. Every door but My Likes adds
  /// in place; My Likes opens the full list.
  String get doorLabel => switch (this) {
    SpaceSection.library => 'Add to Library',
    SpaceSection.players => 'Add a player',
    SpaceSection.events => 'Add an event',
    SpaceSection.likes => 'All likes',
    SpaceSection.games => 'Add a game',
    SpaceSection.smartEvents => 'Build a Smart Event',
    SpaceSection.openings => 'Add an opening',
    SpaceSection.links => 'Add a shortcut',
  };
}

@immutable
class SpaceShortcut {
  const SpaceShortcut({
    required this.id,
    required this.kind,
    required this.targetId,
    required this.title,
    this.subtitle,
    this.params = const {},
    this.sortIndex = 0,
    this.openCount = 0,
    this.lastOpenedAt,
    this.createdAt,
  });

  /// Row id. Locally created shortcuts use a `local:` prefix until the server
  /// assigns a uuid.
  final String id;
  final SpaceShortcutKind kind;
  final String targetId;
  final String title;
  final String? subtitle;
  final Map<String, dynamic> params;
  final double sortIndex;
  final int openCount;
  final DateTime? lastOpenedAt;
  final DateTime? createdAt;

  SpaceSection get section => kind.section;

  /// Identity used for dedupe and "is this already in My Space?" checks.
  String get key => keyFor(kind, targetId);

  static String keyFor(SpaceShortcutKind kind, String targetId) =>
      '${kind.name}:$targetId';

  /// A new shortcut built by a long-press action, before it is stored.
  factory SpaceShortcut.draft({
    required SpaceShortcutKind kind,
    required String targetId,
    required String title,
    String? subtitle,
    Map<String, dynamic> params = const {},
  }) {
    return SpaceShortcut(
      id: 'local:${kind.name}:${DateTime.now().microsecondsSinceEpoch}',
      kind: kind,
      targetId: targetId,
      title: title,
      subtitle: subtitle,
      params: params,
      createdAt: DateTime.now(),
    );
  }

  SpaceShortcut copyWith({
    String? id,
    String? title,
    String? subtitle,
    Map<String, dynamic>? params,
    double? sortIndex,
    int? openCount,
    DateTime? lastOpenedAt,
  }) {
    return SpaceShortcut(
      id: id ?? this.id,
      kind: kind,
      targetId: targetId,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      params: params ?? this.params,
      sortIndex: sortIndex ?? this.sortIndex,
      openCount: openCount ?? this.openCount,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      createdAt: createdAt,
    );
  }

  static SpaceShortcut? fromJson(Map<String, dynamic> json) {
    final kind = SpaceShortcutKindX.tryParse(json['kind'] as String?);
    final target = json['target_id'] as String?;
    final title = json['title'] as String?;
    if (kind == null || target == null || target.isEmpty || title == null) {
      return null;
    }
    final rawParams = json['params'];
    return SpaceShortcut(
      id: (json['id'] ?? '').toString(),
      kind: kind,
      targetId: target,
      title: title,
      subtitle: json['subtitle'] as String?,
      params: rawParams is Map
          ? Map<String, dynamic>.from(rawParams)
          : const <String, dynamic>{},
      sortIndex: (json['sort_index'] as num?)?.toDouble() ?? 0,
      openCount: (json['open_count'] as num?)?.toInt() ?? 0,
      lastOpenedAt: DateTime.tryParse(json['last_opened_at']?.toString() ?? ''),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'target_id': targetId,
    'title': title,
    'subtitle': subtitle,
    'params': params,
    'sort_index': sortIndex,
    'open_count': openCount,
    'last_opened_at': lastOpenedAt?.toIso8601String(),
    'created_at': createdAt?.toIso8601String(),
  };

  /// Columns sent on insert/upsert. `id` and `user_id` come from defaults.
  Map<String, dynamic> toInsert() => {
    'kind': kind.name,
    'target_id': targetId,
    'title': title,
    'subtitle': subtitle,
    'params': params,
    'sort_index': sortIndex,
  };

  bool get isLocal => id.startsWith('local:');
}
