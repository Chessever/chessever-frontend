import 'dart:math' show Random;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chessever2/repository/gamebase/collections/collection_search_query.dart';
import 'dart:async';

import 'package:chessever2/repository/gamebase/collections/collections_models.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/services/pgn_file_intake_service.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

export 'package:chessever2/repository/gamebase/collections/collections_models.dart';

/// A collection game with either safe browse metadata or an authorized PGN.
/// Browse models must be resolved through fetchPlayableGames before board use.
@immutable
class CollectionGame {
  const CollectionGame({required this.card, required this.game});

  /// The game as the API lists it: its section, order and player keys.
  final CollectionGameCard card;
  final GamesTourModel game;

  String get id => card.id;
  String? get sectionId => card.sectionId;

  /// Browse-only: structured metadata, never PGN, comments or variations.
  static CollectionGame? fromPreviewCard(CollectionGameCard card) {
    card = card.withoutPgn();
    if (card.id.isEmpty) return null;
    PlayerCard side(CollectionPlayerSide data) => PlayerCard(
      name: data.name,
      title: data.title ?? '',
      rating: data.elo ?? 0,
      federation: data.fed ?? '',
      countryCode: data.fed ?? '',
      fideId: int.tryParse(data.fideId ?? ''),
      gamebasePlayerId: data.playerId,
      team: null,
    );
    return CollectionGame(
      card: card,
      game: GamesTourModel(
        gameId: card.id,
        source: GameSource.localAnalysis,
        whitePlayer: side(card.white),
        blackPlayer: side(card.black),
        whiteTimeDisplay: '--:--',
        blackTimeDisplay: '--:--',
        whiteClockCentiseconds: 0,
        blackClockCentiseconds: 0,
        gameStatus: switch (card.result) {
          '1-0' => GameStatus.whiteWins,
          '0-1' => GameStatus.blackWins,
          '1/2-1/2' => GameStatus.draw,
          _ => GameStatus.ongoing,
        },
        roundId: card.roundTag ?? '',
        tourId: card.event ?? '',
        fen: card.finalFen,
        lastMove: card.lastMove,
        boardNr: card.board,
        gameDay: card.playedOn,
        lastMoveTime: card.playedAt,
        eco: card.eco,
        openingName: card.opening,
      ),
    );
  }

  /// Null when the card has no PGN or the PGN cannot be read at all.
  static CollectionGame? fromCard(CollectionGameCard card) {
    final pgn = card.pgn;
    if (card.id.isEmpty || pgn == null || pgn.trim().isEmpty) return null;
    try {
      return CollectionGame(
        card: card,
        game: hydrateCollectionGameCard(
          card,
          collectionGameModel(card.id, pgn),
        ),
      );
    } catch (e) {
      debugPrint('[Collections] game ${card.id} unreadable: $e');
      return null;
    }
  }
}

/// [pgn] as the game card models it. The card draws the final position, so
/// the mainline is played out to it; the board replays [pgn] itself.
@visibleForTesting
GamesTourModel collectionGameModel(String id, String pgn) {
  final base = chessGameToImportedGamesTourModel(ChessGame.fromPgn(id, pgn));
  // The shared PGN mapper already hydrates the card's final position and
  // metadata. Keep the exact source text for annotations and board replay.
  return base.copyWith(pgn: pgn);
}

/// Import enrichment belongs to the structured card. Keep the original PGN
/// byte-for-byte for replay, while using verified player links on the cards.
GamesTourModel hydrateCollectionGameCard(
  CollectionGameCard card,
  GamesTourModel game,
) {
  PlayerCard side(CollectionPlayerSide data, PlayerCard parsed) =>
      parsed.copyWith(
        name:
            RegExp(
              r'^(white|black|\?|nn|n\.\s?n\.?)?$',
              caseSensitive: false,
            ).hasMatch(data.name.trim())
            ? null
            : data.name,
        title: data.title,
        rating: data.elo != null && data.elo! > 0 ? data.elo : null,
        federation: data.fed,
        countryCode: data.fed,
        fideId: int.tryParse(data.fideId ?? ''),
        gamebasePlayerId: data.playerId,
      );
  return game.copyWith(
    whitePlayer: side(card.white, game.whitePlayer),
    blackPlayer: side(card.black, game.blackPlayer),
    boardNr: card.board,
    gameDay: card.playedOn,
    eco: card.eco,
    openingName: card.opening,
  );
}

/// One run of games under one header of the Games tab: a round, a part, a
/// chapter, or the games in no section ([section] null).
@immutable
class CollectionGameGroup {
  const CollectionGameGroup({
    required this.section,
    required this.games,
    required this.offset,
    this.depth = 0,
  });

  /// Null for the games in no section.
  final CollectionSection? section;

  /// 0 for a top-level section, 1 for a part's chapter.
  final int depth;

  /// This group's games, in order. Empty only for a part whose games all sit
  /// in its chapters (the part's header still leads them).
  final List<CollectionGame> games;

  /// Where [games] start in the whole ordered list (the board's prev/next).
  final int offset;
}

/// The Games tab's layout: [games] grouped under the [sections] tree in its
/// order (a part, then its chapters), games in no section (or in a section
/// the tree does not know) last. Sections without games are left out, so a
/// player filter leaves only the headers that still lead a game.
///
/// The groups' games, concatenated, are the order the board steps through.
List<CollectionGameGroup> groupCollectionGames(
  List<CollectionSection> sections,
  List<CollectionGame> games, {
  bool preserveGameOrder = false,
}) {
  if (preserveGameOrder) return _groupsInGameOrder(sections, games);
  final bySection = <String, List<CollectionGame>>{};
  final known = <String>{};
  void index(List<CollectionSection> nodes) {
    for (final s in nodes) {
      known.add(s.id);
      index(s.children);
    }
  }

  index(sections);
  final unsorted = <CollectionGame>[];
  for (final g in games) {
    final id = g.sectionId;
    if (id != null && known.contains(id)) {
      (bySection[id] ??= []).add(g);
    } else {
      unsorted.add(g);
    }
  }
  for (final list in bySection.values) {
    if (!preserveGameOrder) _sortByOrderIndex(list);
  }

  final groups = <CollectionGameGroup>[];
  var offset = 0;
  bool hasGames(CollectionSection s) =>
      (bySection[s.id]?.isNotEmpty ?? false) || s.children.any(hasGames);
  void walk(List<CollectionSection> nodes, int depth) {
    for (final s in nodes) {
      if (!hasGames(s)) continue;
      final own = bySection[s.id] ?? const <CollectionGame>[];
      groups.add(
        CollectionGameGroup(
          section: s,
          depth: depth,
          games: own,
          offset: offset,
        ),
      );
      offset += own.length;
      walk(s.children, depth + 1);
    }
  }

  walk(sections, 0);
  if (unsorted.isNotEmpty) {
    // A book without author chapters still has the tournament's round cards.
    // Use event + date + round, never a guessed publication date or midnight
    // labelled as a known start time. Preserve first appearance and file order.
    final buckets = <String, List<CollectionGame>>{};
    for (final game in unsorted) {
      final card = game.card;
      final date = _collectionGameDay(game);
      final event =
          _collectionTag(card.event) ?? _collectionTag(game.game.tourId) ?? '';
      final round =
          _collectionTag(card.roundTag) ??
          _collectionTag(game.game.roundId) ??
          '';
      final key =
          '${event.toLowerCase()}|${date?.toIso8601String() ?? ''}|$round';
      (buckets[key] ??= []).add(game);
    }
    for (final entry in buckets.entries) {
      final bucket = entry.value;
      final first = bucket.first;
      final event =
          _collectionTag(first.card.event) ?? _collectionTag(first.game.tourId);
      final round =
          _collectionTag(first.card.roundTag) ??
          _collectionTag(first.game.roundId);
      final label = event ?? 'Other games';
      final instants =
          bucket.map((g) => g.card.playedAt).whereType<DateTime>().toList()
            ..sort();
      groups.add(
        CollectionGameGroup(
          section: CollectionSection(
            id: 'collection-auto-${entry.key}',
            kind: CollectionSectionKind.round,
            label: label,
            title: round != null ? 'Round $round' : null,
            startsOn: _collectionGameDay(first),
            startsAt: instants.firstOrNull,
            gameCount: bucket.length,
          ),
          games: bucket,
          offset: offset,
        ),
      );
      offset += bucket.length;
    }
  }
  return groups;
}

/// A selected sort is authoritative across chapters and dates. Keep
/// contiguous runs in the server's order, repeating a header when needed,
/// rather than moving an earlier game behind another chapter's later game.
List<CollectionGameGroup> _groupsInGameOrder(
  List<CollectionSection> sections,
  List<CollectionGame> games,
) {
  final paths = <String, List<CollectionSection>>{};
  void index(List<CollectionSection> nodes, List<CollectionSection> ancestors) {
    for (final section in nodes) {
      final path = [...ancestors, section];
      paths[section.id] = path;
      index(section.children, path);
    }
  }

  index(sections, const []);
  String runKey(CollectionGame game) {
    if (paths.containsKey(game.sectionId)) return 'section:${game.sectionId}';
    final event =
        _collectionTag(game.card.event) ??
        _collectionTag(game.game.tourId) ??
        '';
    final round =
        _collectionTag(game.card.roundTag) ??
        _collectionTag(game.game.roundId) ??
        '';
    return '${event.toLowerCase()}|${_collectionGameDay(game)?.toIso8601String() ?? ''}|$round';
  }

  final groups = <CollectionGameGroup>[];
  var offset = 0;
  var parents = <CollectionSection>[];
  while (offset < games.length) {
    final start = offset;
    final key = runKey(games[start]);
    while (offset < games.length && runKey(games[offset]) == key) {
      offset++;
    }
    final run = games.sublist(start, offset);
    final path = paths[run.first.sectionId];
    if (path == null) {
      parents = [];
      final fallback = groupCollectionGames(const [], run).single;
      groups.add(
        CollectionGameGroup(
          section: fallback.section,
          games: run,
          offset: start,
        ),
      );
      continue;
    }
    final nextParents = path.take(path.length - 1).toList();
    for (var depth = 0; depth < nextParents.length; depth++) {
      if (depth >= parents.length ||
          parents[depth].id != nextParents[depth].id) {
        groups.add(
          CollectionGameGroup(
            section: nextParents[depth],
            depth: depth,
            games: const [],
            offset: start,
          ),
        );
      }
    }
    parents = nextParents;
    groups.add(
      CollectionGameGroup(
        section: path.last,
        depth: path.length - 1,
        games: run,
        offset: start,
      ),
    );
  }
  return groups;
}

String? _collectionTag(String? value) {
  final tag = value?.trim();
  return tag == null || tag.isEmpty || tag == '?' || tag == 'import_preview'
      ? null
      : tag;
}

DateTime? _collectionGameDay(CollectionGame game) {
  final day =
      game.card.playedOn ?? game.game.gameDay ?? game.card.playedAt?.toUtc();
  return day == null ? null : DateTime(day.year, day.month, day.day);
}

/// The selector's games and board navigation share the same membership. An
/// ancestor header keeps a chapter's context without including sibling games.
List<CollectionGameGroup> selectCollectionGameGroups(
  List<CollectionGameGroup> groups,
  String selected,
) {
  final byId = {
    for (final g in groups)
      if (g.section != null) g.section!.id: g,
  };
  final picked = byId[selected]?.section;
  if (selected == 'all' || picked == null) return groups;
  final included = <String>{};
  void include(CollectionSection section) {
    included.add(section.id);
    for (final child in section.children) {
      include(child);
    }
  }

  include(picked);
  final ancestors = <String>{};
  var parent = picked.parentId;
  while (parent != null && ancestors.add(parent)) {
    parent = byId[parent]?.section?.parentId;
  }
  var offset = 0;
  return [
    for (final group in groups)
      if (included.contains(group.section?.id) ||
          ancestors.contains(group.section?.id))
        () {
          final games = included.contains(group.section?.id)
              ? group.games
              : const <CollectionGame>[];
          final filtered = CollectionGameGroup(
            section: group.section,
            depth: group.depth,
            games: games,
            offset: offset,
          );
          offset += games.length;
          return filtered;
        }(),
  ];
}

void _sortByOrderIndex(List<CollectionGame> games) {
  if (games.length < 2) return;
  // Stable: equal orderIndex keeps the server's order.
  final indexed = [for (var i = 0; i < games.length; i++) (i, games[i])];
  indexed.sort((a, b) {
    final byOrder = a.$2.card.orderIndex.compareTo(b.$2.card.orderIndex);
    return byOrder != 0 ? byOrder : a.$1.compareTo(b.$1);
  });
  games
    ..clear()
    ..addAll([for (final e in indexed) e.$2]);
}

/// The signed-in viewer's session token, or null (signed out, or Supabase
/// not initialised, as in tests). Gamebase verifies it to decide whether a
/// Premium collection's games are theirs to read.
Future<String?> collectionsSessionToken() {
  final GoTrueClient auth;
  try {
    auth = Supabase.instance.client.auth;
  } catch (_) {
    return Future.value(null);
  }
  return freshSessionToken(
    current: () => auth.currentSession,
    changes: auth.onAuthStateChange,
  );
}

/// How long [freshSessionToken] waits for the SDK to replace a spent token.
const Duration kSessionTokenRefreshWait = Duration(seconds: 4);

/// The [current] session's access token, never a spent one when a fresh one
/// is on its way.
///
/// A token that has run out (or runs out within [margin], as it travels) is
/// refused by the server, and a Premium viewer would read as locked. That
/// happens when the app comes back from the background and asks before the
/// SDK's own resume refresh has landed. The SDK is the one refresh
/// authority (the app never refreshes a session itself: two refreshers
/// revoke the whole session), so this waits up to [wait] for the SDK to
/// announce a live session on [changes], then sends whatever it holds.
Future<String?> freshSessionToken({
  required Session? Function() current,
  required Stream<AuthState> changes,
  Duration wait = kSessionTokenRefreshWait,
  Duration margin = const Duration(seconds: 5),
  DateTime Function() now = DateTime.now,
}) async {
  bool spent(Session s) {
    final expiresAt = s.expiresAt;
    if (expiresAt == null) return false;
    return now()
        .add(margin)
        .isAfter(DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000));
  }

  var session = current();
  if (session != null && spent(session)) {
    try {
      // The stream replays what it already said: only a session that is
      // live now ends the wait.
      await changes
          .where((state) {
            final s = state.session;
            return s != null && !spent(s);
          })
          .first
          .timeout(wait);
    } catch (_) {
      // No refresh in time (offline, or the app is about to sign out): the
      // server says so, and the page offers a retry.
    }
    session = current();
  }
  final token = session?.accessToken;
  return token == null || token.isEmpty ? null : token;
}

/// Reads published collections from the gamebase API. Everyone may read
/// the list, the covers and the tables of contents; a Premium collection's
/// games and players need an entitled session, sent as [accessToken]'s
/// bearer. Nothing here writes: superadmins edit collections on
/// chessever.com.
class CollectionsRepository {
  CollectionsRepository(this._api, {FutureOr<String?> Function()? accessToken})
    : _accessToken = accessToken ?? collectionsSessionToken;

  final GamebaseRepository _api;
  final FutureOr<String?> Function() _accessToken;

  /// The list endpoint's page cap.
  static const int listPageSize = 100;

  /// The games endpoint's page cap.
  static const int gamesPageSize = 200;

  /// Pages fetched at once after the first one tells the total.
  static const int _parallelPages = 4;

  /// A ceiling on pages, so a server that keeps reporting more never loops.
  static const int _maxPages = 100;

  /// Slugs whose reads ask the server to judge the viewer's Premium anew,
  /// with how many holds each has (see [holdFreshAccess]).
  final Map<String, int> _freshHolds = {};

  /// Makes [slug]'s reads skip the "not Premium" answer the server keeps
  /// for a few seconds, until the returned release runs (once; a second
  /// call does nothing). The Premium confirm holds it around each re-check,
  /// so a purchase opens the book on the first read that can see it.
  VoidCallback holdFreshAccess(String slug) {
    _freshHolds[slug] = (_freshHolds[slug] ?? 0) + 1;
    var released = false;
    return () {
      if (released) return;
      released = true;
      final left = (_freshHolds[slug] ?? 1) - 1;
      if (left > 0) {
        _freshHolds[slug] = left;
      } else {
        _freshHolds.remove(slug);
      }
    };
  }

  /// Whether [slug]'s reads are held fresh right now.
  @visibleForTesting
  bool isFreshAccess(String slug) => _freshHolds.containsKey(slug);

  /// Every published collection, in the team's order.
  Future<List<Collection>> fetchCollections() async {
    final items = await _allPages<Collection>(
      pageSize: listPageSize,
      fetch: (offset) async {
        final page = await _api.getCollections(
          limit: listPageSize,
          offset: offset,
        );
        return (page.items, page.total);
      },
    );
    final seen = <String>{};
    return [
      for (final c in items)
        if (seen.add(c.slug)) c,
    ];
  }

  /// One collection with its About text, section tree, bound events and,
  /// for a Premium one, the server's verdict for this viewer.
  Future<Collection> fetchCollection(String slug) async {
    // Read before the token wait: a hold covers the reads it started.
    final fresh = isFreshAccess(slug);
    return _api.getCollection(slug, bearer: await _accessToken(), fresh: fresh);
  }

  /// Browse requests never ask for protected PGN. Older servers still gate
  /// this metadata endpoint; preserve that refusal instead of a payload fallback.
  Future<List<CollectionGame>> fetchGames(String slug) =>
      _fetchGames(slug, includePgn: false);

  /// Protected content, requested only by the gated opening action.
  Future<List<CollectionGame>> fetchPlayableGames(String slug) =>
      _fetchGames(slug, includePgn: true);

  Future<List<CollectionGame>> _fetchGames(
    String slug, {
    required bool includePgn,
  }) async {
    final fresh = isFreshAccess(slug);
    final bearer = await _accessToken();
    final cards = await _allPages<CollectionGameCard>(
      pageSize: gamesPageSize,
      fetch: (offset) async {
        final page = await _api.getCollectionGames(
          slug,
          includePgn: includePgn,
          limit: gamesPageSize,
          offset: offset,
          bearer: bearer,
          fresh: fresh,
        );
        return (page.items, page.total);
      },
    );
    final seen = <String>{};
    return [
      for (final card in cards)
        if (seen.add(card.id))
          ?(includePgn
              ? CollectionGame.fromCard(card)
              : CollectionGame.fromPreviewCard(card)),
    ];
  }

  Future<List<CollectionGame>> searchGames(
    String slug,
    CollectionSearchQuery search, {
    String? playerKey,
  }) async {
    final fresh = isFreshAccess(slug);
    final bearer = await _accessToken();
    final cards = await _allPages<CollectionGameCard>(
      pageSize: gamesPageSize,
      fetch: (offset) async {
        final page = await _api.getCollectionGames(
          slug,
          search: search,
          playerKey: playerKey,
          includePgn: false,
          limit: gamesPageSize,
          offset: offset,
          bearer: bearer,
          fresh: fresh,
        );
        return (page.items, page.total);
      },
    );
    final seen = <String>{};
    return [
      for (final card in cards)
        if (seen.add(card.id)) ?CollectionGame.fromPreviewCard(card),
    ];
  }

  Future<({List<CollectionAuthor> items, int total})> searchAuthors(
    CollectionSearchQuery query,
    int offset,
  ) => _api.searchCollectionAuthors(search: query, offset: offset);

  /// Public opening metadata stays available even when game access is gated.
  Future<List<CollectionOpening>> fetchOpenings({String? slug}) =>
      _allPages<CollectionOpening>(
        pageSize: listPageSize,
        fetch: (offset) async {
          final page = await _api.getCollectionOpenings(
            slug: slug,
            limit: listPageSize,
            offset: offset,
          );
          return (page.items, page.total);
        },
      );

  Future<List<Collection>> fetchBooksForOpening(String eco) =>
      _allPages<Collection>(
        pageSize: listPageSize,
        fetch: (offset) async {
          final page = await _api.getBooksForOpening(
            eco,
            limit: listPageSize,
            offset: offset,
          );
          return (page.items, page.total);
        },
      );

  Future<List<CollectionGame>> fetchGamesForOpening(
    String slug,
    String eco,
  ) async {
    final bearer = await _accessToken();
    final fresh = isFreshAccess(slug);
    final cards = await _allPages<CollectionGameCard>(
      pageSize: gamesPageSize,
      fetch: (offset) async {
        final page = await _api.getCollectionGames(
          slug,
          eco: eco,
          includePgn: false,
          limit: gamesPageSize,
          offset: offset,
          bearer: bearer,
          fresh: fresh,
        );
        return (page.items, page.total);
      },
    );
    final seen = <String>{};
    return [
      for (final card in cards)
        if (seen.add(card.id)) ?CollectionGame.fromPreviewCard(card),
    ];
  }

  Future<List<String>> fetchAuthors() => _allPages<String>(
    pageSize: listPageSize,
    fetch: (offset) async {
      final page = await _api.getCollectionAuthors(
        offset: offset,
        limit: listPageSize,
      );
      return (page.items, page.total);
    },
  );

  Future<CollectionsPage> searchBooks(
    CollectionSearchQuery query,
    int offset,
  ) => _api.searchCollectionBooks(search: query, offset: offset);

  Future<CollectionOpeningsPage> searchOpenings(
    CollectionSearchQuery query,
    int offset,
  ) => _api.getCollectionOpenings(search: query, offset: offset, limit: 40);

  Future<PublishedGamesBatch> fetchPublishedGames({
    int offset = 0,
    CollectionSearchQuery search = const CollectionSearchQuery(),
  }) async {
    final page = await _api.getPublishedCollectionGames(
      search: search,
      limit: 40,
      offset: offset,
      bearer: await _accessToken(),
    );
    return PublishedGamesBatch(
      games: [for (final card in page.items) ?CollectionGame.fromCard(card)],
      total: page.total,
      nextOffset: offset + page.items.length,
      hasMore: page.items.isNotEmpty && offset + page.items.length < page.total,
    );
  }

  /// Everyone in a collection, most games first, then by name. Gated like
  /// [fetchGames].
  Future<List<CollectionPlayer>> fetchPlayers(String slug) async {
    final fresh = isFreshAccess(slug);
    return _api.getCollectionPlayers(
      slug,
      bearer: await _accessToken(),
      fresh: fresh,
    );
  }

  /// The published books bound to the event [anchors] name, in the team's
  /// order, each carrying the team's note for the binding.
  Future<List<Collection>> fetchBooksForEvent(CollectionEventAnchors anchors) {
    if (anchors.isEmpty) return Future.value(const []);
    return _api.getCollectionsForEvent(anchors);
  }

  /// Reads the first page, then the rest (a few at a time) until the total
  /// the first page reported.
  static Future<List<T>> _allPages<T>({
    required int pageSize,
    required Future<(List<T> items, int total)> Function(int offset) fetch,
  }) async {
    final (first, total) = await fetch(0);
    if (first.isEmpty || first.length >= total) return first;
    // Step by what a page actually returned, in case the server caps lower.
    final step = first.length;
    final offsets = <int>[
      for (var o = step; o < total && o ~/ step < _maxPages; o += step) o,
    ];
    final pages = <int, List<T>>{0: first};
    for (var i = 0; i < offsets.length; i += _parallelPages) {
      final batch = offsets.skip(i).take(_parallelPages).toList();
      final results = await Future.wait([
        for (final o in batch) fetch(o).then((r) => r.$1),
      ]);
      for (var j = 0; j < batch.length; j++) {
        pages[batch[j]] = results[j];
      }
      if (results.any((r) => r.isEmpty)) break;
    }
    final keys = pages.keys.toList()..sort();
    return [for (final k in keys) ...pages[k]!];
  }
}

final collectionsRepositoryProvider = Provider<CollectionsRepository>(
  (ref) => CollectionsRepository(ref.watch(gamebaseRepositoryProvider)),
);

/// Every published collection, in the team's order.
final collectionsProvider = FutureProvider.autoDispose<List<Collection>>(
  (ref) => ref.watch(collectionsRepositoryProvider).fetchCollections(),
);

final collectionOpeningsProvider = FutureProvider.autoDispose
    .family<List<CollectionOpening>, String?>(
      (ref, slug) =>
          ref.watch(collectionsRepositoryProvider).fetchOpenings(slug: slug),
    );

final collectionBooksForOpeningProvider = FutureProvider.autoDispose
    .family<List<Collection>, String>(
      (ref, eco) =>
          ref.watch(collectionsRepositoryProvider).fetchBooksForOpening(eco),
    );

final collectionOpeningContentsProvider = FutureProvider.autoDispose
    .family<CollectionContents, ({String slug, String eco})>((ref, key) async {
      final results = await Future.wait<Object>([
        ref.watch(collectionDetailProvider(key.slug).future),
        ref
            .watch(collectionsRepositoryProvider)
            .fetchGamesForOpening(key.slug, key.eco),
      ]);
      return CollectionContents(
        sections: (results[0] as Collection).sections,
        games: results[1] as List<CollectionGame>,
      );
    });

@immutable
class PublishedGamesBatch {
  const PublishedGamesBatch({
    required this.games,
    required this.total,
    required this.nextOffset,
    required this.hasMore,
  });
  final List<CollectionGame> games;
  final int total;
  final int nextOffset;
  final bool hasMore;
}

/// One collection by slug, with its About text and section tree.
final collectionDetailProvider = FutureProvider.autoDispose
    .family<Collection, String>(
      (ref, slug) =>
          ref.watch(collectionsRepositoryProvider).fetchCollection(slug),
    );

/// One collection's games (with PGN), by slug.
final collectionGamesProvider = FutureProvider.autoDispose
    .family<List<CollectionGame>, String>(
      (ref, slug) => ref.watch(collectionsRepositoryProvider).fetchGames(slug),
    );

/// One collection's players, by slug.
final collectionPlayersProvider = FutureProvider.autoDispose
    .family<List<CollectionPlayer>, String>(
      (ref, slug) =>
          ref.watch(collectionsRepositoryProvider).fetchPlayers(slug),
    );

/// The published books bound to one event page, for its About tab. An
/// event with no books, or a request that fails, is an empty list: the
/// books are a companion to the event, never a reason for it to show an
/// error.
final collectionBooksForEventProvider = FutureProvider.autoDispose
    .family<List<Collection>, CollectionEventAnchors>((ref, anchors) async {
      if (anchors.isEmpty) return const [];
      try {
        return await ref
            .watch(collectionsRepositoryProvider)
            .fetchBooksForEvent(anchors);
      } catch (e) {
        debugPrint('[Collections] books for event unavailable: $e');
        return const [];
      }
    });

/// The published books bound to one event collection (by its id), for that
/// collection's Books tab. Unlike [collectionBooksForEventProvider] a
/// failed read stays an error: on a tab of their own, "no books" would be a
/// wrong answer, so the tab says it could not load them and offers a retry.
final collectionBooksOfEventCollectionProvider = FutureProvider.autoDispose
    .family<List<Collection>, String>((ref, collectionId) {
      final anchors = CollectionEventAnchors(collections: [collectionId]);
      if (anchors.isEmpty) return Future.value(const <Collection>[]);
      return ref
          .watch(collectionsRepositoryProvider)
          .fetchBooksForEvent(anchors);
    });

/// Whether [error] is the server keeping a Premium collection's games from
/// this viewer (the paywall, not an error).
bool isCollectionPremiumGate(Object? error) =>
    error is CollectionsRequestException && error.isPremiumGate;

/// The paywall's feature id for a Premium collection: a fixed identifier
/// for the upgrade analytics, never the collection's own name or id.
String collectionPaywallFeatureId(CollectionKind kind) => switch (kind) {
  CollectionKind.book => 'collection_books',
  CollectionKind.event => 'collection_events',
  CollectionKind.analysis => 'collection_analysis',
};

/// Where a collection's paywall resumes: the collection page it opened on.
const String kCollectionPaywallReturnTo = 'collections/collection';

/// What the Games tab draws: the section tree and the games, read together
/// so the list never shows ungrouped and then regroups.
@immutable
class CollectionContents {
  const CollectionContents({required this.sections, required this.games});

  final List<CollectionSection> sections;
  final List<CollectionGame> games;
}

final collectionContentsProvider = FutureProvider.autoDispose
    .family<CollectionContents, String>((ref, slug) async {
      // Both requests start at once; Future.wait handles either one failing.
      final results = await Future.wait<Object>([
        ref.watch(collectionDetailProvider(slug).future),
        ref.watch(collectionGamesProvider(slug).future),
      ]);
      return CollectionContents(
        sections: (results[0] as Collection).sections,
        games: results[1] as List<CollectionGame>,
      );
    });

// Counters update independently of favorite ordering and existing saved rows.
final collectionEngagementCountsProvider =
    StateProvider.family<Map<String, dynamic>?, String>((ref, slug) => null);
final _collectionReaderId = FutureProvider<String>((ref) async {
  final preferences = await SharedPreferences.getInstance();
  final previous = preferences.getString('collection_reader_id');
  if (previous != null) return previous;
  final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  final id =
      '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  await preferences.setString('collection_reader_id', id);
  return id;
});
Future<void> trackCollectionRead(WidgetRef ref, Collection collection) async {
  try {
    final id = await ref.read(_collectionReaderId.future);
    final counts = await ref
        .read(gamebaseRepositoryProvider)
        .recordCollectionEngagement(collection.slug, {'viewerId': id});
    ref
            .read(collectionEngagementCountsProvider(collection.slug).notifier)
            .state =
        counts;
  } catch (_) {
    /* Counts never interrupt reading. */
  }
}

Future<void> syncCollectionStar(
  WidgetRef ref,
  Collection collection,
  bool starred,
) async {
  try {
    final token = await collectionsSessionToken();
    if (token == null) return;
    final counts = await ref
        .read(gamebaseRepositoryProvider)
        .recordCollectionEngagement(
          collection.slug,
          {'starred': starred},
          bearer: token,
          star: true,
        );
    ref
            .read(collectionEngagementCountsProvider(collection.slug).notifier)
            .state =
        counts;
  } catch (_) {
    /* The existing favorite remains authoritative for pinning. */
  }
}

final collectionFilteredContentsProvider = FutureProvider.autoDispose
    .family<
      CollectionContents,
      ({String slug, CollectionSearchQuery query, String? player})
    >((ref, key) async {
      final results = await Future.wait<Object>([
        ref.watch(collectionDetailProvider(key.slug).future),
        ref
            .watch(collectionsRepositoryProvider)
            .searchGames(key.slug, key.query, playerKey: key.player),
      ]);
      return CollectionContents(
        sections: (results[0] as Collection).sections,
        games: results[1] as List<CollectionGame>,
      );
    });
