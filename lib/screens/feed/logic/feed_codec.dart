/// Captions and the first-page cache for the Feed. Pure Dart over the
/// shared models, so it is testable without the feed's repositories.
library;

import 'dart:convert';

import 'package:chessever2/screens/chessboard/classification_fx/move_class.dart';
import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';

/// Where a feed item came from; drives its caption.
enum FeedSource { annotated, favorite, miniature, decisive }

/// Miniature hint for the week window (`MiniatureGamesWindow.week.name`).
const String kFlowMiniatureWeekHint = 'week';

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// The caption under a clip. Recomputed on cache reads so "today" stays true.
///
/// [hint] is the followed player's display name for [FeedSource.favorite]
/// and the miniature window name (`today` / `week`) for
/// [FeedSource.miniature].
String feedReasonFor({
  required FeedSource source,
  required String? hint,
  required GamesTourModel game,
  required List<FeedPly> plies,
  required String result,
  required DateTime now,
}) {
  final plyCount = plies.length - 1;
  final moves = (plyCount + 1) ~/ 2;
  switch (source) {
    case FeedSource.favorite:
      if (hint != null && hint.isNotEmpty) return 'Because you follow $hint';
    case FeedSource.miniature:
      final when = hint == kFlowMiniatureWeekHint
          ? "This week's miniature"
          : "Today's miniature";
      return '$when · $moves moves';
    case FeedSource.annotated:
    case FeedSource.decisive:
      break;
  }

  // Where the clip's biggest beat sits decides "finish" versus "move".
  FeedMomentType? beat;
  var beatIndex = 0;
  for (var i = 1; i < plies.length; i++) {
    final moment = plies[i].moment;
    if (moment == null || !moment.isHeadline) continue;
    if (beat == null || _beatRank(moment.type) <= _beatRank(beat)) {
      beat = moment.type;
      beatIndex = i;
    }
  }
  final late = plies.length > 1 && beatIndex >= (plies.length - 1) * 0.6;
  switch (beat) {
    case FeedMomentType.checkmate:
      return 'Brilliant finish';
    case FeedMomentType.brilliant:
    case FeedMomentType.sacrifice:
      return late ? 'Brilliant finish' : 'Brilliant move';
    case FeedMomentType.blunder:
    case FeedMomentType.missedWin:
      return late ? 'Dramatic finish' : 'Turning point';
    default:
      break;
  }

  final played = game.bucketDate;
  final today = played != null && _sameDay(played.toLocal(), now);
  final day = today ? 'today' : 'this week';
  if ((game.boardNr ?? 99) <= 2) {
    return today ? 'Top board today' : 'Top board';
  }
  return result == '½-½' ? 'Hard-fought draw' : 'Decisive $day';
}

int _beatRank(FeedMomentType type) => switch (type) {
  FeedMomentType.checkmate => 0,
  FeedMomentType.brilliant => 1,
  FeedMomentType.sacrifice => 2,
  FeedMomentType.blunder => 3,
  _ => 4,
};

// -----------------------------------------------------------------------------
// Cache codec — the first page, fully parsed, so a warm launch paints at once.
// -----------------------------------------------------------------------------

/// v2 adds each ply's [FeedPly.moveClass]; a v1 page is simply re-fetched.
const int _cacheVersion = 2;

/// Serialises a feed page for `AppDatabase.setCache`.
String encodeFlowFeedCache(List<FeedItem> items) => jsonEncode({
  'v': _cacheVersion,
  'items': [for (final item in items) _itemToJson(item)],
});

/// Inverse of [encodeFlowFeedCache]. Malformed entries are dropped, a
/// malformed payload yields an empty page. Captions are recomputed against
/// [now] so a cached "today" never outlives its day.
List<FeedItem> decodeFlowFeedCache(String raw, {required DateTime now}) {
  try {
    final json = jsonDecode(raw);
    if (json is! Map || json['v'] != _cacheVersion) return const [];
    final items = json['items'];
    if (items is! List) return const [];
    return [
      for (final entry in items)
        if (entry is Map) _itemFromJson(entry.cast<String, Object?>(), now),
    ].whereType<FeedItem>().toList(growable: false);
  } catch (_) {
    return const [];
  }
}

Map<String, Object?> _itemToJson(FeedItem item) {
  final plies = item.plies;
  return {
    'game': _gameToJson(item.game),
    'reason': item.reason,
    'event': item.eventLabel,
    'result': item.result,
    'evals': item.hasEvals,
    if (item.likes > 0) 'likes': item.likes,
    // A streak is re-derived from the live wall on every read, never stored.
    if (item.signal != null && item.signal!.kind != FeedSignalKind.streak)
      'signal': _signalToJson(item.signal!),
    'plies': [
      for (final ply in plies)
        [
          ply.fen,
          ply.san,
          ply.uci,
          ply.cp,
          ply.mate,
          ply.moment?.type.name,
          ply.moment?.label,
          ply.moment?.severity,
          ply.moveClass?.name,
        ],
    ],
  };
}

FeedItem? _itemFromJson(Map<String, Object?> json, DateTime now) {
  try {
    final game = _gameFromJson((json['game'] as Map).cast<String, Object?>());
    final plies = <FeedPly>[
      for (final raw in json['plies'] as List)
        _plyFromJson((raw as List).cast<Object?>()),
    ];
    if (plies.length < 2) return null;
    final result = json['result'] as String?;
    final storedReason = json['reason'] as String? ?? '';
    final rawSignal = json['signal'];
    return FeedItem(
      game: game,
      plies: List.unmodifiable(plies),
      reason: _refreshReason(storedReason, game, plies, result, now),
      eventLabel: json['event'] as String?,
      result: result,
      hasEvals: json['evals'] == true,
      likes: (json['likes'] as num?)?.toInt() ?? 0,
      signal:
          rawSignal is Map
              ? _signalFromJson(rawSignal.cast<String, Object?>())
              : feedSignalFromReason(storedReason),
    );
  } catch (_) {
    return null;
  }
}

/// Follow and miniature captions are stable; board/day captions are rebuilt
/// so yesterday's "Top board today" reads "Top board".
String _refreshReason(
  String stored,
  GamesTourModel game,
  List<FeedPly> plies,
  String? result,
  DateTime now,
) {
  if (stored.startsWith('Because you follow') || stored.contains('miniature')) {
    if (stored.startsWith("Today's miniature")) {
      // Miniature dates are calendar days stored as UTC midnight; `toLocal()`
      // would shift them to the previous day west of UTC. Compare the UTC
      // calendar day with the viewer's local today, as
      // `isMiniatureArchiveDay` does.
      final played = game.bucketDate?.toUtc();
      if (played != null &&
          !_sameDay(DateTime(played.year, played.month, played.day), now)) {
        return stored.replaceFirst("Today's", 'Recent');
      }
    }
    return stored;
  }
  return feedReasonFor(
    source: FeedSource.annotated,
    hint: null,
    game: game,
    plies: plies,
    result: result ?? '',
    now: now,
  );
}

/// The header mark a caption stood for, for pages cached before items
/// carried a [FeedSignal]: a follow caption names the player, a miniature
/// caption is a miniature. Everything else was a generic caption and earns
/// no mark. Streak captions are re-derived from the live wall on read.
FeedSignal? feedSignalFromReason(String reason) {
  const follow = 'Because you follow ';
  if (reason.startsWith(follow)) {
    final name = reason.substring(follow.length).trim();
    return name.isEmpty ? null : FeedSignal(FeedSignalKind.favorite, name: name);
  }
  if (reason.toLowerCase().contains('miniature')) {
    return const FeedSignal(FeedSignalKind.miniature);
  }
  return null;
}

Map<String, Object?> _signalToJson(FeedSignal signal) => {
  'k': signal.kind.name,
  if (signal.name != null) 'name': signal.name,
  if (signal.count != null) 'n': signal.count,
};

FeedSignal? _signalFromJson(Map<String, Object?> json) {
  final kind = FeedSignalKind.values.asNameMap()[json['k'] as String? ?? ''];
  if (kind == null) return null;
  return FeedSignal(
    kind,
    name: json['name'] as String?,
    count: (json['n'] as num?)?.toInt(),
  );
}

FeedPly _plyFromJson(List<Object?> raw) {
  final typeName = raw.length > 5 ? raw[5] as String? : null;
  FeedMoment? moment;
  if (typeName != null) {
    final type = FeedMomentType.values.asNameMap()[typeName];
    if (type != null) {
      moment = FeedMoment(
        type: type,
        label: raw[6] as String? ?? '',
        severity: (raw[7] as num?)?.toInt() ?? 1,
      );
    }
  }
  final className = raw.length > 8 ? raw[8] as String? : null;
  return FeedPly(
    fen: raw[0] as String,
    san: raw[1] as String?,
    uci: raw[2] as String?,
    cp: (raw[3] as num?)?.toInt(),
    mate: (raw[4] as num?)?.toInt(),
    moment: moment,
    moveClass:
        className == null ? null : MoveClass.values.asNameMap()[className],
  );
}

Map<String, Object?> _playerToJson(PlayerCard player) => {
  'name': player.name,
  'fed': player.federation,
  'title': player.title,
  'rating': player.rating,
  'cc': player.countryCode,
  'fide': player.fideId,
  'team': player.team,
  'gb': player.gamebasePlayerId,
  'pts': player.customPoints,
};

PlayerCard _playerFromJson(Map<String, Object?> json) => PlayerCard(
  name: json['name'] as String? ?? '',
  federation: json['fed'] as String? ?? '',
  title: json['title'] as String? ?? '',
  rating: (json['rating'] as num?)?.toInt() ?? 0,
  countryCode: json['cc'] as String? ?? '',
  fideId: (json['fide'] as num?)?.toInt(),
  team: json['team'] as String?,
  gamebasePlayerId: json['gb'] as String?,
  customPoints: (json['pts'] as num?)?.toDouble(),
);

String? _date(DateTime? value) => value?.toIso8601String();

DateTime? _parseDate(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

Map<String, Object?> _gameToJson(GamesTourModel game) => {
  'id': game.gameId,
  'source': game.source.name,
  'white': _playerToJson(game.whitePlayer),
  'black': _playerToJson(game.blackPlayer),
  'wTime': game.whiteTimeDisplay,
  'bTime': game.blackTimeDisplay,
  'wCs': game.whiteClockCentiseconds,
  'bCs': game.blackClockCentiseconds,
  'wSec': game.whiteClockSeconds,
  'bSec': game.blackClockSeconds,
  'status': game.gameStatus.name,
  'fen': game.fen,
  'pgn': game.pgn,
  'lastMove': game.lastMove,
  'board': game.boardNr,
  'roundId': game.roundId,
  'roundSlug': game.roundSlug,
  'tourId': game.tourId,
  'tourSlug': game.tourSlug,
  'lastMoveTime': _date(game.lastMoveTime),
  'dateStart': _date(game.dateStart),
  'gameDay': _date(game.gameDay),
  'eco': game.eco,
  'opening': game.openingName,
  'tc': game.timeControl,
  'tcText': game.timeControlText,
  'avgElo': game.avgElo,
  'online': game.isOnline,
  'sourceGameId': game.sourceGameId,
};

GamesTourModel _gameFromJson(Map<String, Object?> json) => GamesTourModel(
  gameId: json['id'] as String,
  source:
      GameSource.values.asNameMap()[json['source'] as String? ?? ''] ??
      GameSource.supabase,
  whitePlayer: _playerFromJson((json['white'] as Map).cast<String, Object?>()),
  blackPlayer: _playerFromJson((json['black'] as Map).cast<String, Object?>()),
  whiteTimeDisplay: json['wTime'] as String? ?? '--:--',
  blackTimeDisplay: json['bTime'] as String? ?? '--:--',
  whiteClockCentiseconds: (json['wCs'] as num?)?.toInt() ?? 0,
  blackClockCentiseconds: (json['bCs'] as num?)?.toInt() ?? 0,
  whiteClockSeconds: (json['wSec'] as num?)?.toInt(),
  blackClockSeconds: (json['bSec'] as num?)?.toInt(),
  gameStatus:
      GameStatus.values.asNameMap()[json['status'] as String? ?? ''] ??
      GameStatus.unknown,
  fen: json['fen'] as String?,
  pgn: json['pgn'] as String?,
  lastMove: json['lastMove'] as String?,
  boardNr: (json['board'] as num?)?.toInt(),
  roundId: json['roundId'] as String? ?? '',
  roundSlug: json['roundSlug'] as String?,
  tourId: json['tourId'] as String? ?? '',
  tourSlug: json['tourSlug'] as String?,
  lastMoveTime: _parseDate(json['lastMoveTime']),
  dateStart: _parseDate(json['dateStart']),
  gameDay: _parseDate(json['gameDay']),
  eco: json['eco'] as String?,
  openingName: json['opening'] as String?,
  timeControl: json['tc'] as String?,
  timeControlText: json['tcText'] as String?,
  avgElo: (json['avgElo'] as num?)?.toInt(),
  isOnline: json['online'] == true,
  sourceGameId: json['sourceGameId'] as String?,
);
