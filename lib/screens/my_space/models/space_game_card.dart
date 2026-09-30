import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/library/utils/load_saved_analysis.dart'
    show savedAnalysisToCardGame;
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/live_game_position_resolver.dart';
import 'package:chessever2/utils/pgn_clock_utils.dart';

/// The params key a game shortcut's card snapshot rides under.
const String kSpaceGameCardParam = 'card';

/// Bumped only if the snapshot's shape ever changes meaning.
const int kSpaceGameCardVersion = 1;

/// What the app's game card needs to draw a game (status, last move, and each
/// side's name, title, federation, rating, ids and clocks) as the card had it
/// when the shortcut was made, so a My Space tile shows the same rows without
/// a fetch.
///
/// Returned as params to merge into a game shortcut: the snapshot sits under
/// its own versioned key beside the plain `white` / `black` names that search
/// and older builds read, plus the final `fen` when the game knows it. Only
/// values the card would show are kept.
Map<String, Object?> spaceGameCardParams(GamesTourModel game) {
  final pgnEnd = resolveFinalPositionFromPgn(game.pgn);
  final fen = resolveFreshestGameFen(
    fen: game.fen,
    pgn: game.pgn,
    lastMove: game.lastMove,
  );
  final lastMove = _text(game.lastMove) ?? pgnEnd?.lastMoveUci;
  return {
    if (fen != null) 'fen': fen,
    kSpaceGameCardParam: <String, Object?>{
      'v': kSpaceGameCardVersion,
      'status': game.gameStatus.name,
      if (lastMove != null) 'lastMove': lastMove,
      if (_text(game.timeControl) case final tc?) 'tc': tc,
      if (_text(game.roundSlug) case final slug?) 'roundSlug': slug,
      'white': _side(
        game.whitePlayer,
        time: game.whiteTimeDisplay,
        centiseconds: game.whiteClockCentiseconds,
        seconds: game.whiteClockSeconds,
      ),
      'black': _side(
        game.blackPlayer,
        time: game.blackTimeDisplay,
        centiseconds: game.blackClockCentiseconds,
        seconds: game.blackClockSeconds,
      ),
    },
  };
}

Map<String, Object?> _side(
  PlayerCard p, {
  required String time,
  required int centiseconds,
  required int? seconds,
}) {
  final fed = _text(p.countryCode) ?? _text(p.federation);
  return {
    'name': p.name.trim(),
    if (_text(p.title) case final title?) 'title': title,
    if (fed != null) 'fed': fed,
    if (p.rating > 0) 'rating': p.rating,
    if ((p.fideId ?? 0) > 0) 'fideId': p.fideId,
    if (_text(p.gamebasePlayerId) case final id?) 'gbId': id,
    if (p.customPoints case final points? when points != 0) 'pts': points,
    if (hasUsableClockDisplay(time)) 'time': time.trim(),
    if (centiseconds > 0) 'cs': centiseconds,
    if (seconds != null) 'sec': seconds,
  };
}

/// Whether [s] carries a card snapshot this build can read.
bool spaceGameHasCard(SpaceShortcut s) {
  final card = s.params[kSpaceGameCardParam];
  return card is Map && _int(card['v']) == kSpaceGameCardVersion;
}

/// The saved copy a liked or saved game shortcut opens, if it has one.
String? spaceGameAnalysisId(SpaceShortcut s) => _text(s.params['analysisId']);

/// The game a game shortcut stands for, rebuilt from what it stores: the full
/// card snapshot when it has one, else the names, position and ids alone.
GamesTourModel spaceGameCardSeed(SpaceShortcut s) {
  final p = s.params;
  final rawCard = p[kSpaceGameCardParam];
  final card = rawCard is Map && spaceGameHasCard(s)
      ? Map<String, Object?>.from(rawCard)
      : const <String, Object?>{};
  final analysisId = spaceGameAnalysisId(s);
  final fromAnalysisOnly = s.targetId.startsWith('analysis:');
  final source = analysisId != null
      ? GameSource.savedAnalysis
      : _text(p['source']) == 'gamebase'
      ? GameSource.gamebase
      : GameSource.supabase;

  PlayerCard side(String key) {
    final raw = card[key];
    final m = raw is Map ? raw : const <String, Object?>{};
    final fed = _text(m['fed']) ?? '';
    return PlayerCard(
      name: _text(m['name']) ?? _text(p[key]) ?? '',
      federation: fed,
      title: _text(m['title']) ?? '',
      rating: _int(m['rating']) ?? 0,
      countryCode: fed,
      team: null,
      fideId: _int(m['fideId']),
      gamebasePlayerId: _text(m['gbId']),
      customPoints: _num(m['pts'])?.toDouble(),
    );
  }

  final white = card['white'] is Map ? card['white'] as Map : const {};
  final black = card['black'] is Map ? card['black'] as Map : const {};
  final status =
      GameStatus.values.asNameMap()[_text(card['status'])] ??
      GameStatus.unknown;

  return GamesTourModel(
    // A saved copy is its own row, like the My Likes card; the game it was
    // saved from stays its like identity.
    gameId: analysisId ?? s.targetId,
    source: source,
    sourceGameId: analysisId != null && !fromAnalysisOnly ? s.targetId : null,
    whitePlayer: side('white'),
    blackPlayer: side('black'),
    whiteTimeDisplay: _text(white['time']) ?? '--:--',
    blackTimeDisplay: _text(black['time']) ?? '--:--',
    whiteClockCentiseconds: _int(white['cs']) ?? 0,
    blackClockCentiseconds: _int(black['cs']) ?? 0,
    whiteClockSeconds: _int(white['sec']),
    blackClockSeconds: _int(black['sec']),
    gameStatus: status,
    fen: _text(p['fen']),
    lastMove: _text(card['lastMove']),
    roundId: _text(p['roundId']) ?? '',
    roundSlug: _text(card['roundSlug']),
    tourId: _text(p['tourId']) ?? '',
    tourSlug: _text(p['tourSlug']),
    eco: _text(p['eco']),
    timeControl: _text(card['tc']),
  );
}

/// Whether a tile has to look the game up to draw it like the card: it has
/// no snapshot, or the game was still being played when the snapshot was
/// taken (a live game's result and position move on). A saved copy never
/// changes, so a liked game with a snapshot is never looked up.
bool spaceGameCardNeedsFetch(SpaceShortcut s) {
  if (!spaceGameHasCard(s)) return true;
  if (spaceGameAnalysisId(s) != null) return false;
  final status = GameStatus.values
      .asNameMap()[_text((s.params[kSpaceGameCardParam] as Map)['status'])];
  return status == null || !status.isFinished;
}

/// A liked or saved game as the game card draws it: the My Likes card model
/// ([savedAnalysisToCardGame]) at the game's final position.
GamesTourModel spaceGameFromAnalysis(SavedAnalysis analysis) {
  final game = savedAnalysisToCardGame(analysis);
  final mainline = analysis.chessGame.mainline;
  if (mainline.isEmpty) {
    final start = analysis.chessGame.startingFen.trim();
    return start.isEmpty ? game : game.copyWith(fen: start);
  }
  final last = mainline.last;
  return game.copyWith(fen: last.fen, lastMove: last.uci);
}

String? _text(Object? v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

int? _int(Object? v) {
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '');
}

num? _num(Object? v) {
  if (v is num) return v;
  return num.tryParse(v?.toString() ?? '');
}
