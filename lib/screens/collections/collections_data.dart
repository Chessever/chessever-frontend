import 'package:chessever2/repository/gamebase/collections/collections_models.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/services/pgn_file_intake_service.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

export 'package:chessever2/repository/gamebase/collections/collections_models.dart';

/// A collection's game, as the app's game card and board take it: players,
/// result and the final position from its PGN, which it carries whole
/// (comments, NAGs and variations included) for the board to replay.
@immutable
class CollectionGame {
  const CollectionGame({required this.card, required this.game});

  /// The game as the API lists it: its section, order and player keys.
  final CollectionGameCard card;
  final GamesTourModel game;

  String get id => card.id;
  String? get sectionId => card.sectionId;

  /// Null when the card has no PGN or the PGN cannot be read at all.
  static CollectionGame? fromCard(CollectionGameCard card) {
    final pgn = card.pgn;
    if (card.id.isEmpty || pgn == null || pgn.trim().isEmpty) return null;
    try {
      return CollectionGame(card: card, game: collectionGameModel(card.id, pgn));
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
  final parsed = PgnGame.parsePgn(pgn);
  Position position = PgnGame.startingPosition(parsed.headers);
  String? last;
  for (final node in parsed.moves.mainline()) {
    final move = position.parseSan(node.san);
    if (move == null) break;
    position = position.play(move);
    last = move.uci;
  }
  return base.copyWith(pgn: pgn, fen: position.fen, lastMove: last);
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
  List<CollectionGame> games,
) {
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
    _sortByOrderIndex(list);
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
    groups.add(
      CollectionGameGroup(section: null, games: unsorted, offset: offset),
    );
  }
  return groups;
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

/// Reads published collections from the gamebase API. Everyone may read
/// them; nothing here writes (uploads happen in the chessever.com admin
/// console, Content > Collections).
class CollectionsRepository {
  CollectionsRepository(this._api);

  final GamebaseRepository _api;

  /// The list endpoint's page cap.
  static const int listPageSize = 100;

  /// The games endpoint's page cap.
  static const int gamesPageSize = 200;

  /// Pages fetched at once after the first one tells the total.
  static const int _parallelPages = 4;

  /// A ceiling on pages, so a server that keeps reporting more never loops.
  static const int _maxPages = 100;

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

  /// One collection with its About text and section tree.
  Future<Collection> fetchCollection(String slug) => _api.getCollection(slug);

  /// All of a collection's games with their PGN, in the API's order.
  Future<List<CollectionGame>> fetchGames(String slug) async {
    final cards = await _allPages<CollectionGameCard>(
      pageSize: gamesPageSize,
      fetch: (offset) async {
        final page = await _api.getCollectionGames(
          slug,
          includePgn: true,
          limit: gamesPageSize,
          offset: offset,
        );
        return (page.items, page.total);
      },
    );
    final seen = <String>{};
    return [
      for (final card in cards)
        if (seen.add(card.id)) ?CollectionGame.fromCard(card),
    ];
  }

  /// Everyone in a collection, most games first, then by name.
  Future<List<CollectionPlayer>> fetchPlayers(String slug) =>
      _api.getCollectionPlayers(slug);

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
      (ref, slug) => ref.watch(collectionsRepositoryProvider).fetchPlayers(slug),
    );

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
