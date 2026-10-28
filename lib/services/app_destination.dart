import 'package:chessever2/utils/eco_openings.dart';
import 'package:dartchess/dartchess.dart';

/// The explicit notification route catalog. Unknown leaves are rejected rather
/// than silently opening a parent page. See docs/mobile-app-routes.md.
enum AppDestinationKind {
  home,
  events,
  collections,
  collection,
  inbox,
  feed,
  likes,
  miniatures,
  reports,
  myPrep,
  prepProfile,
  library,
  database,
  myLikes,
  calendar,
  favorites,
  settings,
  player,
  playerOpenings,
  streaks,
  explorer,
  legacy,
}

typedef AppExplorerLine = ({String fen, List<String> moves});

class AppDestination {
  const AppDestination._({
    required this.kind,
    required this.uri,
    this.id,
    this.section,
    this.line,
    this.legacyLink,
  });

  final AppDestinationKind kind;

  /// Always normalized to https://chessever.com/app/....
  final Uri uri;
  final String? id;
  final String? section;
  final AppExplorerLine? line;

  /// Existing content resolver URL, without /app, when [kind] is legacy.
  final String? legacyLink;

  Map<String, String> get query => uri.queryParameters;
}

final _controlCharacters = RegExp(r'[\x00-\x1f\x7f]');
final _invalidPercent = RegExp(r'%(?![0-9a-fA-F]{2})');
final _dotPathSegment = RegExp(
  r'(?:^|/)(?:\.|%2e){1,2}(?:/|[?#]|$)',
  caseSensitive: false,
);
final _positiveFideId = RegExp(r'^[0-9]{1,12}$');

/// Accepts /app/..., canonical HTTPS URLs, and
/// com.chessever.app://app/... . All path and query components are consumed.
/// It never accepts an arbitrary Flutter named route or an external host.
AppDestination? parseAppDestination(String raw) {
  try {
    return _parseAppDestination(raw.trim());
  } on FormatException {
    return null;
  } on ArgumentError {
    return null;
  }
}

AppDestination? _parseAppDestination(String raw) {
  if (raw.isEmpty ||
      raw.length > 4096 ||
      _controlCharacters.hasMatch(raw) ||
      _invalidPercent.hasMatch(raw) ||
      _dotPathSegment.hasMatch(raw.split('?').first.split('#').first)) {
    return null;
  }
  final parsed = Uri.tryParse(raw);
  if (parsed == null || parsed.hasFragment || parsed.userInfo.isNotEmpty) {
    return null;
  }
  final List<String> segments;
  if (!parsed.hasScheme && !parsed.hasAuthority && raw.startsWith('/')) {
    segments = parsed.pathSegments.toList();
  } else if (parsed.scheme == 'https' &&
      const {'chessever.com', 'www.chessever.com'}.contains(parsed.host) &&
      parsed.port == 443) {
    segments = parsed.pathSegments.toList();
  } else if (parsed.scheme == 'com.chessever.app' &&
      !parsed.hasPort &&
      (parsed.host == 'app' || parsed.host.isEmpty)) {
    segments = [if (parsed.host == 'app') 'app', ...parsed.pathSegments];
  } else {
    return null;
  }
  if (segments.lastOrNull == '') segments.removeLast();
  if (segments.isEmpty ||
      segments.first != 'app' ||
      segments.any((s) => !_validSegment(s))) {
    return null;
  }
  final allQuery = parsed.queryParametersAll;
  if (allQuery.values.any((values) => values.length != 1)) return null;
  final query = parsed.queryParameters;
  if (query.values.any(
    (value) => value.trim().isEmpty || _controlCharacters.hasMatch(value),
  )) {
    return null;
  }
  final path = segments.skip(1).toList(growable: false);
  final normalized = Uri(
    scheme: 'https',
    host: 'chessever.com',
    pathSegments: segments,
    queryParameters: query.isEmpty ? null : query,
  );
  bool only(Set<String> keys) => query.keys.every(keys.contains);
  AppDestination target(
    AppDestinationKind kind, {
    String? id,
    String? section,
    AppExplorerLine? line,
    bool legacy = false,
  }) => AppDestination._(
    kind: kind,
    uri: normalized,
    id: id,
    section: section,
    line: line,
    legacyLink: legacy
        ? Uri(
            scheme: 'https',
            host: 'chessever.com',
            pathSegments: path,
            queryParameters: query.isEmpty ? null : query,
          ).toString()
        : null,
  );

  if (path.isEmpty && query.isEmpty) return target(AppDestinationKind.home);
  if (path.isEmpty) return null;
  final root = path.first;
  if (path.length == 1 && query.isEmpty) {
    final kind = switch (root) {
      'home' => AppDestinationKind.home,
      'events' => AppDestinationKind.events,
      'collections' => AppDestinationKind.collections,
      'inbox' => AppDestinationKind.inbox,
      'feed' => AppDestinationKind.feed,
      'likes' => AppDestinationKind.likes,
      'miniatures' => AppDestinationKind.miniatures,
      'reports' => AppDestinationKind.reports,
      'my-prep' => AppDestinationKind.myPrep,
      'library' => AppDestinationKind.library,
      'my-likes' => AppDestinationKind.myLikes,
      'favorites' => AppDestinationKind.favorites,
      'settings' => AppDestinationKind.settings,
      _ => null,
    };
    if (kind != null) return target(kind);
  }
  switch (root) {
    case 'likes':
      if (path.length == 2 &&
          const {'today', 'week', 'month', 'year'}.contains(path[1]) &&
          only({'date', 'view'}) &&
          (!query.containsKey('date') || _validDate(query['date'])) &&
          (!query.containsKey('view') ||
              const {'games', 'players'}.contains(query['view']))) {
        return target(AppDestinationKind.likes, section: path[1]);
      }
    case 'home':
      if (path.length == 2 &&
          query.isEmpty &&
          const {'today', 'my-space', 'discovery'}.contains(path[1])) {
        return target(AppDestinationKind.home, section: path[1]);
      }
    case 'inbox':
      if (path.length == 2 && query.isEmpty) {
        return target(AppDestinationKind.inbox, id: path[1]);
      }
    case 'collections':
      if (path.length == 2 && query.isEmpty) {
        return target(AppDestinationKind.collection, id: path[1]);
      }
    case 'my-prep':
      if (path.length == 2 && only({'account'})) {
        return target(AppDestinationKind.prepProfile, id: path[1]);
      }
    case 'library':
      if (path.length == 2 && path[1] == 'database' && only({'event'})) {
        return target(AppDestinationKind.database);
      }
    case 'calendar':
      if (path.length == 1 && only({'date'}) && _validDate(query['date'])) {
        return target(AppDestinationKind.calendar);
      }
    case 'favorites':
      if (path.length == 2 &&
          query.isEmpty &&
          const {'events', 'list', 'games', 'players'}.contains(path[1])) {
        return target(AppDestinationKind.favorites, section: path[1]);
      }
    case 'settings':
      if (path.length == 2 &&
          query.isEmpty &&
          const {
            'board',
            'engine',
            'botvinnik',
            'notifications',
            'customization',
          }.contains(path[1])) {
        return target(AppDestinationKind.settings, section: path[1]);
      }
    case 'players':
      if ((path.length == 2 || path.length == 3) && _validFideId(path[1])) {
        final section = path.length == 3 ? path[2] : 'about';
        if (const {'about', 'games', 'events'}.contains(section) &&
            only({'name'})) {
          return target(
            AppDestinationKind.player,
            id: path[1],
            section: section,
          );
        }
        if (section == 'openings' &&
            only({'name', 'color', 'fen', 'moves'}) &&
            (query['color'] == null ||
                const {'white', 'black', 'all'}.contains(query['color']))) {
          final line = _routeLine(query['fen'], query['moves']);
          if ((query.containsKey('fen') || query.containsKey('moves')) &&
              line == null) {
            return null;
          }
          return target(
            AppDestinationKind.playerOpenings,
            id: path[1],
            line: line,
          );
        }
      }
    case 'streaks':
      if ((path.length == 1 || (path.length == 2 && _validFideId(path[1]))) &&
          only({'tc'}) &&
          (query['tc'] == null ||
              const {'standard', 'rapid', 'blitz'}.contains(query['tc']))) {
        return target(
          AppDestinationKind.streaks,
          id: path.length == 2 ? path[1] : null,
        );
      }
    case 'explorer':
    case 'positions':
      if (path.length == 1 && only({'fen', 'moves'})) {
        if (root == 'positions' && !query.containsKey('fen')) return null;
        final line = _routeLine(query['fen'], query['moves']);
        if ((query.isNotEmpty || root == 'positions') && line == null) {
          return null;
        }
        return target(AppDestinationKind.explorer, line: line);
      }
    case 'openings':
      if (path.length == 2 &&
          query.isEmpty &&
          RegExp(r'^[A-E][0-9]{2}$').hasMatch(path[1])) {
        final moves =
            EcoOpenings.canonicalRecordForCode(path[1])?.moves ??
            EcoOpenings.getFamily(path[1])?.moves;
        final line = _routeLine(null, moves);
        if (line != null) {
          return target(AppDestinationKind.explorer, line: line);
        }
      }
    case 'games':
      if (path.length == 2 &&
          only({'fen', 'src'}) &&
          (query['src'] == null || query['src'] == 'gamebase') &&
          (query['fen'] == null || _routeLine(query['fen'], null) != null)) {
        return target(AppDestinationKind.legacy, legacy: true);
      }
    case 'books':
    case 'databases':
    case 'folders':
      if (path.length == 2 && query.isEmpty) {
        return target(AppDestinationKind.legacy, legacy: true);
      }
    case 'player':
      if ((path.length == 2 || path.length == 3) && query.isEmpty) {
        return target(AppDestinationKind.legacy, legacy: true);
      }
    case 'broadcast':
      if ((path.length == 2 || path.length == 3) &&
          only({'tab'}) &&
          (query['tab'] == null ||
              const {
                'about',
                'games',
                'standings',
                'bracket',
                'players',
              }.contains(query['tab']))) {
        return target(AppDestinationKind.legacy, legacy: true);
      }
      if (path.length == 5 &&
          query.isEmpty &&
          ((path[3] == 'player' && _validFideId(path[4])) ||
              path[3] == 'team')) {
        return target(AppDestinationKind.legacy, legacy: true);
      }
  }
  return null;
}

bool _validSegment(String segment) =>
    segment.isNotEmpty &&
    segment.length <= 200 &&
    segment == segment.trim() &&
    segment != '.' &&
    segment != '..' &&
    !segment.contains('/') &&
    !segment.contains('\\') &&
    !_controlCharacters.hasMatch(segment);

bool _validFideId(String value) =>
    _positiveFideId.hasMatch(value) && (int.tryParse(value) ?? 0) > 0;

bool _validDate(String? value) {
  if (value == null) return true;
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
  final parsed = DateTime.tryParse(value);
  return parsed != null && parsed.toIso8601String().startsWith('${value}T');
}

/// Unlike a restored shortcut, a configured route cannot silently discard an
/// invalid move or a mismatched FEN: publishing the wrong position is a typo.
AppExplorerLine? _routeLine(String? fen, String? moves) {
  try {
    String? target;
    if (fen != null) target = Chess.fromSetup(Setup.parseFen(fen)).fen;
    if (moves == null) {
      return target == null ? null : (fen: target, moves: const <String>[]);
    }
    final tokens = EcoOpenings.moveTokens(
      moves.replaceAll(RegExp(r'\b\d+\.(?:\.\.)?\s*'), ''),
    );
    if (tokens.isEmpty || tokens.length > 300) return null;
    Position position = Chess.initial;
    final ucis = <String>[];
    for (final token in tokens) {
      Move? move;
      if (RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$').hasMatch(token)) {
        final uci = NormalMove.fromUci(token);
        if (position.isLegal(uci)) {
          move = uci;
        } else {
          final alternate = _castlingUcis[token];
          if (alternate != null) {
            final castle = NormalMove.fromUci(alternate);
            if (position.isLegal(castle)) move = castle;
          }
        }
      } else {
        move = position.parseSan(token.replaceAll(RegExp(r'[!?]'), ''));
      }
      if (move == null) return null;
      final isCastle =
          move is NormalMove &&
          position.board.pieceAt(move.from)?.role == Role.king &&
          position.board.pieceAt(move.to)?.role == Role.rook;
      ucis.add(isCastle ? _castlingUcis[move.uci] ?? move.uci : move.uci);
      position = position.play(move);
    }
    if (target != null &&
        target.split(' ').take(4).join(' ') !=
            position.fen.split(' ').take(4).join(' ')) {
      return null;
    }
    return (fen: target ?? position.fen, moves: List.unmodifiable(ucis));
  } catch (_) {
    return null;
  }
}

const _castlingUcis = {
  'e1g1': 'e1h1',
  'e1h1': 'e1g1',
  'e1c1': 'e1a1',
  'e1a1': 'e1c1',
  'e8g8': 'e8h8',
  'e8h8': 'e8g8',
  'e8c8': 'e8a8',
  'e8a8': 'e8c8',
};
