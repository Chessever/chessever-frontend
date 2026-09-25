import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/services/pgn_file_intake_service.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// What a collection holds.
enum CollectionKind {
  /// Annotated games from one tournament.
  event,

  /// The games of a book.
  book;

  static CollectionKind parse(Object? raw) =>
      raw == 'book' ? CollectionKind.book : CollectionKind.event;
}

/// One entry of Discovery › Collection: a tournament's annotated games, or a
/// book's. Uploaded by the ChessEver team (see docs/collections.md).
@immutable
class Collection {
  const Collection({
    required this.id,
    required this.slug,
    required this.kind,
    required this.title,
    required this.gameCount,
    this.subtitle,
    this.author,
    this.about,
    this.coverUrl,
  });

  final String id;
  final String slug;
  final CollectionKind kind;
  final String title;
  final int gameCount;

  /// One line under the title: where and when, or a book's edition.
  final String? subtitle;

  /// The annotator, or the book's author.
  final String? author;

  /// The About tab's text; blank lines separate paragraphs.
  final String? about;
  final String? coverUrl;

  static String? _text(Object? raw) {
    if (raw is! String) return null;
    final t = raw.trim();
    return t.isEmpty ? null : t;
  }

  factory Collection.fromRow(Map<String, dynamic> row) {
    var count = 0;
    final games = row['discovery_collection_games'];
    if (games is List && games.isNotEmpty && games.first is Map) {
      final raw = (games.first as Map)['count'];
      count = raw is int ? raw : int.tryParse('$raw') ?? 0;
    }
    return Collection(
      id: row['id'].toString(),
      slug: _text(row['slug']) ?? row['id'].toString(),
      kind: CollectionKind.parse(row['kind']),
      title: _text(row['title']) ?? 'Untitled',
      gameCount: count,
      subtitle: _text(row['subtitle']),
      author: _text(row['author']),
      about: _text(row['about']),
      coverUrl: _text(row['cover_url']),
    );
  }
}

/// A collection's game, as the app's game card and board take it: players,
/// result and the final position from its PGN, which it carries whole
/// (comments, NAGs and variations included) for the board to replay.
@immutable
class CollectionGame {
  const CollectionGame({required this.id, required this.game});

  final String id;
  final GamesTourModel game;

  /// Null when the PGN cannot be read at all.
  static CollectionGame? fromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString() ?? '';
    final pgn = row['pgn'];
    if (id.isEmpty || pgn is! String || pgn.trim().isEmpty) return null;
    try {
      return CollectionGame(id: id, game: collectionGameModel(id, pgn));
    } catch (e) {
      debugPrint('[Collections] game $id unreadable: $e');
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

/// One player of a collection and how many of its games they played.
@immutable
class CollectionPlayer {
  const CollectionPlayer({
    required this.name,
    required this.games,
    this.title,
    this.rating,
    this.federation,
  });

  final String name;
  final int games;
  final String? title;
  final int? rating;
  final String? federation;
}

/// Everyone in [games], most games first, then by name. A player's title,
/// best rating and federation come from any game that has them.
List<CollectionPlayer> collectionPlayers(List<CollectionGame> games) {
  final byName =
      <
        String,
        ({String name, int games, String? title, int? rating, String? fed})
      >{};
  void add(PlayerCard p) {
    final name = p.name.trim();
    if (name.isEmpty || name == 'White' || name == 'Black') return;
    final key = name.toLowerCase();
    final prior = byName[key];
    final title = p.title.trim();
    final fed = p.federation.trim();
    final rating = p.rating > 0 ? p.rating : null;
    byName[key] = (
      name: prior?.name ?? name,
      games: (prior?.games ?? 0) + 1,
      title: (prior?.title?.isNotEmpty ?? false)
          ? prior!.title
          : title.isEmpty
          ? null
          : title,
      rating: switch ((prior?.rating, rating)) {
        (final int a, final int b) => a > b ? a : b,
        (final int a, null) => a,
        (null, final int b) => b,
        _ => null,
      },
      fed: (prior?.fed?.isNotEmpty ?? false)
          ? prior!.fed
          : fed.isEmpty
          ? null
          : fed,
    );
  }

  for (final g in games) {
    add(g.game.whitePlayer);
    add(g.game.blackPlayer);
  }
  final out = [
    for (final p in byName.values)
      CollectionPlayer(
        name: p.name,
        games: p.games,
        title: p.title,
        rating: p.rating,
        federation: p.fed,
      ),
  ];
  out.sort((a, b) {
    final byGames = b.games.compareTo(a.games);
    return byGames != 0
        ? byGames
        : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return out;
}

/// Reads the published collections and their games. Everyone may read them;
/// nothing here writes.
class CollectionsRepository {
  CollectionsRepository(this._db);

  final SupabaseClient _db;

  Future<List<Collection>> fetchCollections() async {
    final rows = await _db
        .from('discovery_collections')
        .select(
          'id, slug, kind, title, subtitle, author, about, cover_url, '
          'discovery_collection_games(count)',
        )
        .eq('published', true)
        .order('sort_order')
        .order('created_at', ascending: false);
    return [
      for (final row in rows as List)
        Collection.fromRow(Map<String, dynamic>.from(row as Map)),
    ];
  }

  Future<List<CollectionGame>> fetchGames(String collectionId) async {
    final rows = await _db
        .from('discovery_collection_games')
        .select('id, pgn')
        .eq('collection_id', collectionId)
        .order('sort_order')
        .order('created_at');
    return [
      for (final row in rows as List)
        ?CollectionGame.fromRow(Map<String, dynamic>.from(row as Map)),
    ];
  }
}

final collectionsRepositoryProvider = Provider<CollectionsRepository>(
  (ref) => CollectionsRepository(Supabase.instance.client),
);

/// Every published collection, in the team's order.
final collectionsProvider = FutureProvider.autoDispose<List<Collection>>(
  (ref) => ref.watch(collectionsRepositoryProvider).fetchCollections(),
);

/// One collection's games, in the team's order.
final collectionGamesProvider = FutureProvider.autoDispose
    .family<List<CollectionGame>, String>(
      (ref, id) => ref.watch(collectionsRepositoryProvider).fetchGames(id),
    );
