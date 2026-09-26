import 'dart:async';

import 'package:chessever2/repository/gamebase/collections/collections_models.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/services/pgn_file_intake_service.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
      return CollectionGame(
        card: card,
        game: collectionGameModel(card.id, pgn),
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
    return _api.getCollection(
      slug,
      bearer: await _accessToken(),
      fresh: fresh,
    );
  }

  /// All of a collection's games with their PGN, in the API's order. A
  /// Premium collection the viewer is not entitled to throws a
  /// [CollectionsRequestException] with
  /// [CollectionsRequestException.isPremiumGate].
  Future<List<CollectionGame>> fetchGames(String slug) async {
    final fresh = isFreshAccess(slug);
    final bearer = await _accessToken();
    final cards = await _allPages<CollectionGameCard>(
      pageSize: gamesPageSize,
      fetch: (offset) async {
        final page = await _api.getCollectionGames(
          slug,
          includePgn: true,
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
        if (seen.add(card.id)) ?CollectionGame.fromCard(card),
    ];
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

/// Whether [error] is the server keeping a Premium collection's games from
/// this viewer (the paywall, not an error).
bool isCollectionPremiumGate(Object? error) =>
    error is CollectionsRequestException && error.isPremiumGate;

/// Whether this viewer reads [collection]'s games, or sees its preview and
/// the paywall.
///
/// The server decides: once a detail read carries its verdict
/// ([Collection.contentLocked]) that is the answer, whatever the app
/// believes about the subscription (a subscriber whose store purchase has
/// not reached the server yet is still locked; a web subscriber the app
/// does not know about is not). Until then (the list row, or a server from
/// before the gate) a Premium collection is locked for a viewer the app
/// knows is not subscribed, and open while the subscription is still
/// loading, so a subscriber never sees a lock flash.
bool isCollectionLocked(
  Collection collection, {
  required bool isSubscribed,
  required bool subscriptionLoading,
}) {
  if (!collection.isPremium) return false;
  final verdict = collection.contentLocked;
  if (verdict != null) return verdict;
  return !isSubscribed && !subscriptionLoading;
}

/// The paywall's feature id for a Premium collection: a fixed identifier
/// for the upgrade analytics, never the collection's own name or id.
String collectionPaywallFeatureId(CollectionKind kind) =>
    kind == CollectionKind.book ? 'collection_books' : 'collection_events';

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
