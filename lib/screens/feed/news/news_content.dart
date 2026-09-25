import 'dart:convert';

import 'package:chessever2/screens/feed/news/news_models.dart';
import 'package:chessever2/widgets/federation_flag.dart';

/// Pure ChessEver News logic, ported from the web so the app and
/// chessever.com agree on what an article is and how it reads:
///
/// * `src/lib/news.ts`: `newsSlug`, `cleanText`, `cleanContent`,
///   `normalizeNewsRow`, and the source link (`normalizeInternalHref`,
///   `newsSourceContextHref`, `newsSourceContextLabel`);
/// * `src/lib/news-rich-content.ts`: the paragraph markers (author, section,
///   YouTube, hidden metadata) and the base64url team results / pairings
///   snapshots, validated exactly as strictly (a snapshot that does not
///   reconcile is dropped, never shown raw).
///
/// Deviations, all deliberate: rows without a parsable date are skipped (the
/// Feed needs a real date), a missing cover stays null (the web substitutes
/// its brand frame), a blank `source_url` counts as none, and federation
/// checks use the app's own flag table.

const String kChesseverSiteUrl = 'https://chessever.com';

// -----------------------------------------------------------------------------
// news.ts
// -----------------------------------------------------------------------------

/// `newsSlug` from news.ts: lower-case, NFKD, strip combining marks, collapse
/// everything outside `[a-z0-9]` to `-`, trim dashes, cap at 120.
String newsSlug(String title) {
  final folded = _foldNfkd(title.toLowerCase());
  var slug = folded
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.length > 120) slug = slug.substring(0, 120);
  return slug.isEmpty ? 'chessever-news' : slug;
}

/// `https://chessever.com/news/<id>/<slug>`, the web's canonical URL.
String newsWebUrl(int id, String slug) =>
    '$kChesseverSiteUrl/news/${Uri.encodeComponent('$id')}/'
    '${Uri.encodeComponent(slug)}';

/// `cleanText` from news.ts: collapse whitespace runs, trim.
String cleanNewsText(Object? value) {
  if (value is! String) return '';
  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// `cleanContent` from news.ts: normalise newlines, split on blank lines,
/// collapse spaces/tabs inside each paragraph, drop empty paragraphs.
String cleanNewsContent(Object? value) {
  if (value is! String) return '';
  return _contentParagraphs(value).join('\n\n');
}

/// `normalizeNewsRow` from news.ts. Returns null for rows the web would not
/// publish (no id, title, content or date).
FeedNews? normalizeNewsRow(Map<String, dynamic> row) {
  final id = _rowId(row['id']);
  final title = cleanNewsText(row['title']);
  final content = cleanNewsContent(row['content']);
  final summaryField = cleanNewsText(row['summary']);
  final summary = summaryField.isNotEmpty
      ? summaryField
      : cleanNewsText(newsContentText(content));
  // `??` in the web: an empty published_at does not fall back.
  final publishedRaw = row['published_at'] ?? row['created_at'];

  if (id == null || title.isEmpty || content.isEmpty) return null;
  if (publishedRaw is! String || publishedRaw.isEmpty) return null;
  final publishedAt = DateTime.tryParse(publishedRaw);
  if (publishedAt == null) return null;

  final updatedRaw = row['updated_at'];
  final updatedAt = updatedRaw is String && updatedRaw.isNotEmpty
      ? DateTime.tryParse(updatedRaw) ?? publishedAt
      : publishedAt;

  final slug = newsSlug(title);
  return FeedNews(
    id: id,
    title: title,
    summary: summary,
    content: content,
    publishedAt: publishedAt,
    updatedAt: updatedAt,
    imageUrl: _httpUrl(row['image_url']),
    webUrl: newsWebUrl(id, slug),
    sourceUrl: switch (row['source_url']) {
      final String source when source.trim().isNotEmpty => source.trim(),
      _ => null,
    },
  );
}

int? _rowId(Object? value) {
  final id = switch (value) {
    final int v => v,
    final double v when v == v.truncateToDouble() && v.isFinite => v.toInt(),
    final String v => int.tryParse(v.trim()),
    _ => null,
  };
  return id != null && id > 0 ? id : null;
}

String? _httpUrl(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasAuthority) return null;
  if (uri.scheme != 'https' && uri.scheme != 'http') return null;
  return trimmed;
}

List<String> _contentParagraphs(String content) => content
    .replaceAll(RegExp(r'\r\n?'), '\n')
    .split(RegExp(r'\n{2,}'))
    .map((p) => p.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
    .where((p) => p.isNotEmpty)
    .toList();

// -----------------------------------------------------------------------------
// news-rich-content.ts
// -----------------------------------------------------------------------------

final RegExp _authorMarker = RegExp(
  r'^<!--\s*news-author\s*:\s*([a-z0-9-]+)\s*-->$',
  caseSensitive: false,
);
final RegExp _sectionMarker = RegExp(
  r'^<!--\s*news-section\s*:\s*([^<>\n]{1,120})\s*-->$',
  caseSensitive: false,
);
final RegExp _youtubeMarker = RegExp(
  r'^<!--\s*news-youtube\s*:\s*([A-Za-z0-9_-]{11})\s*-->$',
);
final RegExp _resultsMarker = RegExp(
  r'^<!--\s*news-results\s*:\s*([A-Za-z0-9_-]+)\s*-->$',
);
final RegExp _versionedResultsMarker = RegExp(
  r'^<!--\s*news-results:v([12]):([A-Za-z0-9_-]+)\s*-->$',
);
final RegExp _pairingsMarker = RegExp(
  r'^<!--\s*news-pairings:v(1):([A-Za-z0-9_-]+)\s*-->$',
);
final RegExp _structuredMarkerPrefix = RegExp(
  r'^<!--\s*news-(?:results|pairings)(?:\s*:|:v\d+:)',
  caseSensitive: false,
);
final RegExp _hiddenMetadataMarker = RegExp(
  r'^<!--\s*(?:related|country-relevance)\s*:',
  caseSensitive: false,
);

const int _maxResultsTokenLength = 180000;
const int _maxResultsJsonBytes = 135000;
const int _maxResultsMatches = 128;
const int _maxNotPairedTeams = 32;
const Set<String> _officialTeamScores = {
  '0',
  '½',
  '1',
  '1½',
  '2',
  '2½',
  '3',
  '3½',
  '4',
};
const Set<String> _officialPlayerTitles = {
  '',
  'GM',
  'IM',
  'FM',
  'CM',
  'WGM',
  'WIM',
  'WFM',
  'WCM',
};

/// Chess-Results federations missing from flag tables, accepted by the web.
const Set<String> _pairingsFederationExceptions = {'KIR', 'MHL'};

const Map<String, NewsAuthor> _knownAuthors = {
  'vasif-durarbayli': NewsAuthor(
    displayName: 'GM Vasif Durarbayli',
    role: 'Founder of ChessEver',
  ),
};

/// Byline for the article, when it carries a known author marker.
NewsAuthor? resolveNewsAuthor(String content) {
  for (final paragraph in _contentParagraphs(content)) {
    final match = _authorMarker.firstMatch(paragraph);
    if (match == null) continue;
    return _knownAuthors[match.group(1)!.toLowerCase()];
  }
  return null;
}

/// `newsContentBlocks` from the web, block for block.
List<NewsBlock> newsContentBlocks(String content) {
  final blocks = <NewsBlock>[];
  for (final paragraph in _contentParagraphs(content)) {
    if (_authorMarker.hasMatch(paragraph) ||
        _hiddenMetadataMarker.hasMatch(paragraph)) {
      continue;
    }
    if (_structuredMarkerPrefix.hasMatch(paragraph)) {
      final snapshot = parseNewsResultsMarker(paragraph);
      if (snapshot is NewsPairingsSnapshot) {
        blocks.add(NewsPairingsBlock(snapshot));
      } else if (snapshot is NewsResultsSnapshot) {
        blocks.add(NewsResultsBlock(snapshot));
      }
      continue;
    }
    final section = _sectionMarker.firstMatch(paragraph);
    if (section != null) {
      blocks.add(NewsSectionBlock(section.group(1)!.trim()));
      continue;
    }
    final youtube = _youtubeMarker.firstMatch(paragraph);
    if (youtube != null) {
      blocks.add(NewsYoutubeBlock(youtube.group(1)!));
      continue;
    }
    blocks.add(NewsParagraphBlock(paragraph));
  }
  return blocks;
}

/// `newsContentText` from the web: the readable prose only.
String newsContentText(String content) => newsContentBlocks(content)
    .map(
      (block) => switch (block) {
        NewsParagraphBlock(:final text) => text,
        NewsSectionBlock(:final text) => text,
        _ => null,
      },
    )
    .whereType<String>()
    .join(' ');

/// Blocks for the in-app reader: [newsContentBlocks], with consecutive prose
/// paragraphs merged into one markdown run (so lists, tables and fenced
/// blocks survive the blank-line split) and sanitised: HTML comments are
/// removed, JSON is never shown raw (a JSON array of flat records becomes a
/// markdown table, anything else is dropped), and empty runs disappear.
List<NewsBlock> newsReaderBlocks(String content) {
  final out = <NewsBlock>[];
  final prose = <String>[];

  void flush() {
    if (prose.isEmpty) return;
    final markdown = sanitizeNewsMarkdown(prose.join('\n\n'));
    prose.clear();
    if (markdown.isNotEmpty) out.add(NewsMarkdownBlock(markdown));
  }

  for (final block in newsContentBlocks(content)) {
    if (block is NewsParagraphBlock) {
      prose.add(block.text);
    } else {
      flush();
      out.add(block);
    }
  }
  flush();
  return out;
}

final RegExp _htmlComment = RegExp(r'<!--[\s\S]*?(?:-->|$)');
final RegExp _fence = RegExp(r'^ {0,3}(`{3,}|~{3,})\s*([^\s`]*)[^\n]*$');

/// Makes one markdown run safe to render (see [newsReaderBlocks]).
String sanitizeNewsMarkdown(String markdown) {
  final withoutComments = markdown.replaceAll(_htmlComment, '');
  final lines = withoutComments.split('\n');
  final out = <String>[];
  var i = 0;
  while (i < lines.length) {
    final open = _fence.firstMatch(lines[i]);
    if (open == null) {
      out.add(lines[i]);
      i++;
      continue;
    }
    final marker = open.group(1)!;
    final info = open.group(2)!.toLowerCase();
    var end = i + 1;
    while (end < lines.length &&
        !lines[end].trimLeft().startsWith(marker[0] * marker.length)) {
      end++;
    }
    final body = lines.sublist(i + 1, end.clamp(i + 1, lines.length));
    final json = _decodeJson(body.join('\n'));
    if (json == null && info != 'json') {
      out.addAll(lines.sublist(i, (end + 1).clamp(0, lines.length)));
    } else {
      final table = json == null ? null : _jsonRecordsTable(json);
      if (table != null) out.add(table);
    }
    i = end + 1;
  }

  // Bare JSON paragraphs (not fenced) never render raw either.
  final paragraphs = out
      .join('\n')
      .split(RegExp(r'\n{2,}'))
      .map((paragraph) {
        final trimmed = paragraph.trim();
        if (!(trimmed.startsWith('{') || trimmed.startsWith('['))) {
          return paragraph;
        }
        final json = _decodeJson(trimmed);
        if (json == null) return paragraph;
        return _jsonRecordsTable(json) ?? '';
      })
      .where((paragraph) => paragraph.trim().isNotEmpty);
  return paragraphs.join('\n\n').trim();
}

Object? _decodeJson(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  final first = trimmed[0];
  if (first != '{' && first != '[') return null;
  try {
    final decoded = jsonDecode(trimmed);
    return decoded is Map || decoded is List ? decoded : null;
  } on FormatException {
    return null;
  }
}

/// A JSON array of flat objects as a GFM table; null for any other shape.
String? _jsonRecordsTable(Object json) {
  if (json is! List || json.isEmpty || json.length > 200) return null;
  final columns = <String>[];
  for (final row in json) {
    if (row is! Map || row.isEmpty) return null;
    for (final entry in row.entries) {
      final value = entry.value;
      if (value is Map || value is List) return null;
      final key = '${entry.key}';
      if (!columns.contains(key)) columns.add(key);
    }
  }
  if (columns.length > 12) return null;
  String cell(Object? value) => value == null
      ? ''
      : '$value'.replaceAll('|', r'\|').replaceAll(RegExp(r'\s+'), ' ');
  final buffer = StringBuffer()
    ..writeln('| ${columns.map(cell).join(' | ')} |')
    ..writeln('|${List.filled(columns.length, ' --- ').join('|')}|');
  for (final row in json.cast<Map>()) {
    buffer.writeln('| ${columns.map((c) => cell(row[c])).join(' | ')} |');
  }
  return buffer.toString().trimRight();
}

/// `parseNewsResultsMarker` from the web: a validated snapshot, or null.
Object? parseNewsResultsMarker(String marker) {
  final pairings = _pairingsMarker.firstMatch(marker);
  if (pairings != null) {
    return _normalizeOfficialPairings(
      _decodeResultsToken(pairings.group(2)!),
      int.parse(pairings.group(1)!),
    );
  }
  final legacy = _resultsMarker.firstMatch(marker);
  if (legacy != null) {
    return _legacyResults(_decodeResultsToken(legacy.group(1)!));
  }
  final versioned = _versionedResultsMarker.firstMatch(marker);
  if (versioned == null) return null;
  return _normalizeOfficialResults(
    _decodeResultsToken(versioned.group(2)!),
    int.parse(versioned.group(1)!),
  );
}

Object? _decodeResultsToken(String token) {
  if (token.length > _maxResultsTokenLength || token.length % 4 == 1) {
    return null;
  }
  try {
    final padded = token.padRight((token.length + 3) ~/ 4 * 4, '=');
    final bytes = base64Url.decode(padded);
    // Canonical tokens only, like the web's re-encode check.
    if (bytes.isEmpty ||
        bytes.length > _maxResultsJsonBytes ||
        base64Url.encode(bytes).replaceAll('=', '') != token) {
      return null;
    }
    return jsonDecode(utf8.decode(bytes));
  } on FormatException {
    return null;
  }
}

// ------------------------------------------------------------- validators

bool _hasExactKeys(Object? value, List<String> keys) =>
    value is Map &&
    value.length == keys.length &&
    keys.every(value.containsKey);

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is double && value.isFinite && value == value.truncateToDouble()) {
    return value.toInt();
  }
  return null;
}

final RegExp _unsafeTextChars = RegExp(r'[\u0000-\u001f\u007f<>]');
final RegExp _federationCode = RegExp(r'^[A-Z]{3}$');

bool _isSafeText(Object? value, int maxLength) =>
    value is String &&
    value.isNotEmpty &&
    value.length <= maxLength &&
    value == value.trim() &&
    !_unsafeTextChars.hasMatch(value);

bool _isSafeOptionalText(Object? value, int maxLength) =>
    value is String &&
    value.length <= maxLength &&
    value == value.trim() &&
    !_unsafeTextChars.hasMatch(value);

bool _isFederationCode(Object? value) =>
    value is String && _federationCode.hasMatch(value);

bool _isKnownFederation(Object? value) =>
    _isFederationCode(value) && FederationFlag.hasVisibleFlag(value as String);

bool _isKnownPairingsFederation(Object? value) =>
    _isFederationCode(value) &&
    (FederationFlag.hasVisibleFlag(value as String) ||
        _pairingsFederationExceptions.contains(value));

String _formatHalf(num value) =>
    value == value.truncate() ? '${value.toInt()}' : '$value';

// ------------------------------------------------------- legacy v1 results

NewsResultsSnapshot? _legacyResults(Object? value) {
  if (!_hasExactKeys(value, const ['v', 'title', 'matches'])) return null;
  final map = value! as Map;
  final matchesRaw = map['matches'];
  if (_asInt(map['v']) != 1 ||
      !_isSafeText(map['title'], 100) ||
      matchesRaw is! List ||
      matchesRaw.isEmpty ||
      matchesRaw.length > _maxResultsMatches) {
    return null;
  }
  final matches = <NewsResultsMatch>[];
  for (final candidate in matchesRaw) {
    final match = _legacyMatch(candidate);
    if (match == null) return null;
    matches.add(match);
  }
  return NewsResultsSnapshot(
    version: 1,
    title: map['title'] as String,
    matches: matches,
  );
}

NewsTeam? _legacyTeam(Object? value) {
  if (!_hasExactKeys(value, const ['n', 'f'])) return null;
  final map = value! as Map;
  if (!_isSafeText(map['n'], 100) || !_isKnownFederation(map['f'])) {
    return null;
  }
  return NewsTeam(name: map['n'] as String, federation: map['f'] as String);
}

NewsResultsMatch? _legacyMatch(Object? value) {
  if (!_hasExactKeys(value, const ['a', 'b', 's', 'g'])) return null;
  final map = value! as Map;
  final teamA = _legacyTeam(map['a']);
  final teamB = _legacyTeam(map['b']);
  final score = map['s'];
  final gamesRaw = map['g'];
  if (teamA == null ||
      teamB == null ||
      score is! String ||
      !RegExp(r'^\d(?:\.5)?-\d(?:\.5)?$').hasMatch(score) ||
      gamesRaw is! List ||
      gamesRaw.length != 4) {
    return null;
  }
  final games = <NewsResultGame>[];
  for (var i = 0; i < gamesRaw.length; i++) {
    final game = gamesRaw[i];
    if (!_hasExactKeys(game, const ['n', 'a', 'b', 'c', 'r'])) return null;
    final g = game as Map;
    final result = g['r'];
    if (_asInt(g['n']) != i + 1 ||
        !_isSafeText(g['a'], 100) ||
        !_isSafeText(g['b'], 100) ||
        (g['c'] != 'w' && g['c'] != 'b') ||
        (result != '1-0' && result != '0-1' && result != '0.5-0.5')) {
      return null;
    }
    games.add(
      NewsResultGame(
        board: i + 1,
        playerA: g['a'] as String,
        playerB: g['b'] as String,
        colorA: g['c'] as String,
        result: result as String,
      ),
    );
  }
  var scoreA = 0.0;
  for (final game in games) {
    if (game.result == '1-0') scoreA += 1;
    if (game.result == '0.5-0.5') scoreA += 0.5;
  }
  final expected =
      '${_formatHalf(scoreA)}-${_formatHalf(games.length - scoreA)}';
  if (score != expected) return null;
  return NewsResultsMatch(
    teamA: teamA,
    teamB: teamB,
    score: score,
    games: games,
  );
}

// ---------------------------------------------------- official v1/v2 results

bool _isChessResultsUrl(
  Object? value,
  int round, {
  required String article,
  bool strict = false,
}) {
  if (value is! String || value.length > 500 || value != value.trim()) {
    return false;
  }
  final uri = Uri.tryParse(value);
  if (uri == null) return false;
  if (uri.scheme != 'https' || uri.host.toLowerCase() != 'chess-results.com') {
    return false;
  }
  if (strict && (uri.userInfo.isNotEmpty || uri.hasFragment)) return false;
  if (!RegExp(r'^/tnr\d+\.aspx$').hasMatch(uri.path)) return false;
  String? first(String key) => uri.queryParametersAll[key]?.first;
  return first('art') == article && first('rd') == '$round';
}

typedef _OfficialHeader = ({
  String section,
  int round,
  String source,
  String updated,
  List<Object?> matches,
  List<Object?> notPaired,
});

_OfficialHeader? _officialHeader(
  Object? value,
  int markerVersion, {
  required String article,
  required bool strictUrl,
}) {
  if (!_hasExactKeys(value, const ['v', 's', 'r', 'src', 'u', 'm', 'np'])) {
    return null;
  }
  final map = value! as Map;
  final round = _asInt(map['r']);
  final section = map['s'];
  final matches = map['m'];
  final notPaired = map['np'];
  if (_asInt(map['v']) != markerVersion ||
      (section != 'open' && section != 'women') ||
      round == null ||
      round < 1 ||
      round > 99 ||
      !_isChessResultsUrl(
        map['src'],
        round,
        article: article,
        strict: strictUrl,
      ) ||
      !_isSafeText(map['u'], 80) ||
      matches is! List ||
      matches.isEmpty ||
      matches.length > _maxResultsMatches ||
      notPaired is! List ||
      notPaired.length > _maxNotPairedTeams) {
    return null;
  }
  return (
    section: section as String,
    round: round,
    source: map['src'] as String,
    updated: map['u'] as String,
    matches: matches,
    notPaired: notPaired,
  );
}

String _sectionLabel(String section) => section == 'open' ? 'Open' : 'Women';

NewsTeam? _officialTeam(Object? value, {required bool pairings}) {
  if (value is! List || value.length != (pairings ? 3 : 4)) return null;
  final seed = _asInt(value[2]);
  final federationOk = pairings
      ? _isKnownPairingsFederation(value[1])
      : _isFederationCode(value[1]);
  if (!_isSafeText(value[0], 100) ||
      !federationOk ||
      seed == null ||
      seed <= 0 ||
      seed > 999) {
    return null;
  }
  if (!pairings && !_officialTeamScores.contains(value[3])) return null;
  return NewsTeam(
    name: value[0] as String,
    federation: value[1] as String,
    seed: seed,
  );
}

int _teamScoreHalfPoints(String score) =>
    const {
      '0': 0,
      '½': 1,
      '1': 2,
      '1½': 3,
      '2': 4,
      '2½': 5,
      '3': 6,
      '3½': 7,
      '4': 8,
    }[score] ??
    -1;

NewsResultsSnapshot? _normalizeOfficialResults(
  Object? value,
  int markerVersion,
) {
  final header = _officialHeader(
    value,
    markerVersion,
    article: '3',
    strictUrl: false,
  );
  if (header == null) return null;

  final seenTeams = <String>{};
  final matches = <NewsResultsMatch>[];
  for (var index = 0; index < header.matches.length; index++) {
    final candidate = header.matches[index];
    if (!_hasExactKeys(candidate, const ['n', 'a', 'b', 'g'])) return null;
    final map = candidate! as Map;
    final rawA = map['a'];
    final rawB = map['b'];
    final teamA = _officialTeam(rawA, pairings: false);
    final teamB = _officialTeam(rawB, pairings: false);
    final boards = map['g'];
    if (_asInt(map['n']) != index + 1 ||
        teamA == null ||
        teamB == null ||
        boards is! List ||
        boards.length != 4) {
      return null;
    }

    final keyA = '${teamA.federation}\u0000${teamA.name}';
    final keyB = '${teamB.federation}\u0000${teamB.name}';
    if (keyA == keyB || seenTeams.contains(keyA) || seenTeams.contains(keyB)) {
      return null;
    }
    seenTeams
      ..add(keyA)
      ..add(keyB);

    var halfA = 0;
    var halfB = 0;
    final games = <NewsResultGame>[];
    for (var b = 0; b < boards.length; b++) {
      final game = _officialResultBoard(boards[b], b + 1);
      if (game == null) return null;
      if (game.status != NewsBoardStatus.notPlayed) {
        switch (game.result) {
          case '1-0':
            halfA += 2;
          case '0-1':
            halfB += 2;
          default:
            halfA += 1;
            halfB += 1;
        }
      }
      games.add(game);
    }

    final scoreA = (rawA as List)[3] as String;
    final scoreB = (rawB as List)[3] as String;
    if (halfA != _teamScoreHalfPoints(scoreA) ||
        halfB != _teamScoreHalfPoints(scoreB)) {
      return null;
    }
    matches.add(
      NewsResultsMatch(
        teamA: teamA,
        teamB: teamB,
        score:
            '${scoreA.replaceAll('½', '.5')}-${scoreB.replaceAll('½', '.5')}',
        games: games,
      ),
    );
  }

  final notPaired = <NewsTeam>[];
  for (final candidate in header.notPaired) {
    final team = _notPairedTeam(
      candidate,
      pairings: false,
      seenTeams: seenTeams,
      kinds: const {'not_paired'},
    );
    if (team == null) return null;
    notPaired.add(team.$1);
  }

  return NewsResultsSnapshot(
    version: 2,
    title:
        'Round ${header.round} · ${_sectionLabel(header.section)} '
        'full results',
    matches: matches,
    round: header.round,
    sourceUrl: header.source,
    lastUpdate: header.updated,
    notPaired: notPaired,
  );
}

NewsResultGame? _officialResultBoard(Object? value, int board) {
  if (value is! List || value.length != 11) return null;
  final ratingA = _asInt(value[3]);
  final ratingB = _asInt(value[7]);
  final colorA = value[4];
  final colorB = value[8];
  bool isColor(Object? c) => c == 'w' || c == 'b' || c == '';
  if (_asInt(value[0]) != board ||
      !_isSafeText(value[1], 100) ||
      !_isSafeOptionalText(value[2], 12) ||
      ratingA == null ||
      ratingA < 0 ||
      ratingA > 4000 ||
      !isColor(colorA) ||
      !_isSafeText(value[5], 100) ||
      !_isSafeOptionalText(value[6], 12) ||
      ratingB == null ||
      ratingB < 0 ||
      ratingB > 4000 ||
      !isColor(colorB)) {
    return null;
  }
  if (colorA != '' && colorB != '' && colorA == colorB) return null;

  final result = value[9];
  final NewsBoardStatus status;
  switch (value[10]) {
    case 'played':
      if (result != '1-0' &&
          result != '0-1' &&
          result != '½-½' &&
          result != '0.5-0.5') {
        return null;
      }
      status = NewsBoardStatus.played;
    case 'forfeit':
      if (result != '1-0' && result != '0-1') return null;
      status = NewsBoardStatus.forfeit;
    case 'not_played':
      if (result != '0-0' && result != '—') return null;
      status = NewsBoardStatus.notPlayed;
    default:
      return null;
  }

  final normalizedResult = switch (status) {
    NewsBoardStatus.notPlayed => '0-0',
    _ when result == '½-½' => '0.5-0.5',
    _ => result as String,
  };
  final titleA = value[2] as String;
  final titleB = value[6] as String;
  return NewsResultGame(
    board: board,
    playerA: value[1] as String,
    playerB: value[5] as String,
    colorA: colorA as String,
    result: normalizedResult,
    status: status,
    titleA: titleA.isEmpty ? null : titleA,
    ratingA: ratingA > 0 ? ratingA : null,
    titleB: titleB.isEmpty ? null : titleB,
    ratingB: ratingB > 0 ? ratingB : null,
  );
}

(NewsTeam, String)? _notPairedTeam(
  Object? candidate, {
  required bool pairings,
  required Set<String> seenTeams,
  required Set<String> kinds,
}) {
  if (candidate is! List || candidate.length != 4) return null;
  final seed = _asInt(candidate[2]);
  final federationOk = pairings
      ? _isKnownPairingsFederation(candidate[1])
      : _isFederationCode(candidate[1]);
  if (!_isSafeText(candidate[0], 100) ||
      !federationOk ||
      seed == null ||
      seed <= 0 ||
      seed > 999 ||
      !kinds.contains(candidate[3])) {
    return null;
  }
  final name = candidate[0] as String;
  final federation = candidate[1] as String;
  final rawKey = '$federation\u0000$name';
  final key = pairings ? rawKey.toLowerCase() : rawKey;
  if (seenTeams.contains(key)) return null;
  seenTeams.add(key);
  return (
    NewsTeam(name: name, federation: federation, seed: seed),
    candidate[3] as String,
  );
}

// ---------------------------------------------------------- official pairings

NewsPairingsSnapshot? _normalizeOfficialPairings(
  Object? value,
  int markerVersion,
) {
  if (markerVersion != 1) return null;
  final header = _officialHeader(
    value,
    markerVersion,
    article: '2',
    strictUrl: true,
  );
  if (header == null) return null;

  final seenTeams = <String>{};
  final seenPlayers = <String>{};
  final matches = <NewsPairingsMatch>[];
  for (var index = 0; index < header.matches.length; index++) {
    final candidate = header.matches[index];
    if (!_hasExactKeys(candidate, const ['n', 'a', 'b', 'g'])) return null;
    final map = candidate! as Map;
    final teamA = _officialTeam(map['a'], pairings: true);
    final teamB = _officialTeam(map['b'], pairings: true);
    final boards = map['g'];
    if (_asInt(map['n']) != index + 1 ||
        teamA == null ||
        teamB == null ||
        boards is! List ||
        (boards.isNotEmpty && boards.length != 4)) {
      return null;
    }

    final keyA = '${teamA.federation}\u0000${teamA.name}'.toLowerCase();
    final keyB = '${teamB.federation}\u0000${teamB.name}'.toLowerCase();
    if (keyA == keyB || seenTeams.contains(keyA) || seenTeams.contains(keyB)) {
      return null;
    }
    seenTeams
      ..add(keyA)
      ..add(keyB);

    final games = <NewsPairingGame>[];
    for (var b = 0; b < boards.length; b++) {
      final game = _officialPairingBoard(boards[b], b + 1);
      if (game == null) return null;
      final playerA = game.playerA.toLowerCase();
      final playerB = game.playerB.toLowerCase();
      if (playerA == playerB ||
          seenPlayers.contains(playerA) ||
          seenPlayers.contains(playerB)) {
        return null;
      }
      seenPlayers
        ..add(playerA)
        ..add(playerB);
      games.add(game);
    }
    matches.add(NewsPairingsMatch(teamA: teamA, teamB: teamB, games: games));
  }

  final notPaired = <NewsTeam>[];
  final byes = <NewsTeam>[];
  for (final candidate in header.notPaired) {
    final team = _notPairedTeam(
      candidate,
      pairings: true,
      seenTeams: seenTeams,
      kinds: const {'not_paired', 'bye'},
    );
    if (team == null) return null;
    (team.$2 == 'bye' ? byes : notPaired).add(team.$1);
  }

  return NewsPairingsSnapshot(
    title:
        'Round ${header.round} · ${_sectionLabel(header.section)} '
        'full pairings',
    matches: matches,
    round: header.round,
    sourceUrl: header.source,
    lastUpdate: header.updated,
    notPaired: notPaired,
    byes: byes,
  );
}

NewsPairingGame? _officialPairingBoard(Object? value, int board) {
  if (value is! List || value.length != 9) return null;
  final ratingA = _asInt(value[3]);
  final ratingB = _asInt(value[7]);
  final colorA = value[4];
  final colorB = value[8];
  bool isColor(Object? c) => c == 'w' || c == 'b';
  if (_asInt(value[0]) != board ||
      !_isSafeText(value[1], 100) ||
      !_officialPlayerTitles.contains(value[2]) ||
      ratingA == null ||
      ratingA < 0 ||
      ratingA > 4000 ||
      !isColor(colorA) ||
      !_isSafeText(value[5], 100) ||
      !_officialPlayerTitles.contains(value[6]) ||
      ratingB == null ||
      ratingB < 0 ||
      ratingB > 4000 ||
      !isColor(colorB) ||
      colorA == colorB) {
    return null;
  }
  final titleA = value[2] as String;
  final titleB = value[6] as String;
  return NewsPairingGame(
    board: board,
    playerA: value[1] as String,
    playerB: value[5] as String,
    colorA: colorA as String,
    titleA: titleA.isEmpty ? null : titleA,
    ratingA: ratingA > 0 ? ratingA : null,
    titleB: titleB.isEmpty ? null : titleB,
    ratingB: ratingB > 0 ? ratingB : null,
  );
}

// -----------------------------------------------------------------------------
// Links
// -----------------------------------------------------------------------------

const Set<String> _chesseverHosts = {'chessever.com', 'www.chessever.com'};

/// Resolves a markdown link target to an absolute http(s) URI; relative
/// paths are chessever.com paths. Null for anything else (`javascript:`,
/// fragments, junk).
Uri? resolveNewsHref(String? href) {
  if (href == null) return null;
  final cleaned = href.trim().replaceAll(RegExp(r'[\s.,;:!?]+$'), '');
  if (cleaned.isEmpty || cleaned.startsWith('#')) return null;
  final uri = Uri.tryParse(
    cleaned.startsWith('/') && !cleaned.startsWith('//')
        ? '$kChesseverSiteUrl$cleaned'
        : cleaned,
  );
  if (uri == null || !uri.hasAuthority) return null;
  if (uri.scheme != 'https' && uri.scheme != 'http') return null;
  return uri;
}

bool isChesseverUri(Uri uri) => _chesseverHosts.contains(uri.host);

/// The article id when [uri] points at another ChessEver News article.
int? newsArticleIdOf(Uri uri) {
  if (!isChesseverUri(uri)) return null;
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.length < 2 || segments.first != 'news') return null;
  return int.tryParse(segments[1]);
}

/// `normalizeInternalHref` from news.ts: a chessever.com link as a
/// root-relative href (`/broadcast/<slug>/<id>?tab=standings`), with share
/// images and OG player cards rewritten to the page they picture. Null for
/// other origins (only `https://chessever.com`, as on the web), the home
/// page, articles and any other `/api/og/` URL.
String? normalizeNewsInternalHref(String url) {
  try {
    final cleaned = url.trim().replaceAll(RegExp(r'[\s.,;:!?]+$'), '');
    final parsed = Uri.parse(kChesseverSiteUrl).resolve(cleaned);
    if (parsed.scheme != 'https' ||
        parsed.host != 'chessever.com' ||
        parsed.port != 443) {
      return null;
    }
    final path = parsed.path.isEmpty ? '/' : parsed.path;

    final standings = RegExp(
      r'^/broadcast/([^/]+)/([^/]+)/standings\.png$',
    ).firstMatch(path);
    if (standings != null) {
      return '/broadcast/${standings.group(1)}/${standings.group(2)}'
          '?tab=standings';
    }

    final profile = RegExp(
      r'^/broadcast/([^/]+)/([^/]+)/player/([^/]+)/profile\.png$',
    ).firstMatch(path);
    if (profile != null) {
      return '/broadcast/${profile.group(1)}/${profile.group(2)}'
          '/player/${profile.group(3)}';
    }

    if (path == '/api/og/player-profile' || path == '/api/og/player') {
      // `searchParams.get`: the first value wins.
      final fideId = parsed.queryParametersAll['fideId']?.first.trim() ?? '';
      if (RegExp(r'^\d+$').hasMatch(fideId)) {
        return '/player/${Uri.encodeComponent(fideId)}';
      }
    }

    final href = '$path${parsed.query.isEmpty ? '' : '?${parsed.query}'}';
    if (href == '/' || href.startsWith('/news/')) return null;
    if (href.startsWith('/api/og/')) return null;
    return href;
  } on FormatException {
    return null;
  } on ArgumentError {
    return null;
  }
}

/// `newsSourceContextHref` from news.ts: where the article's source link
/// goes, a root-relative chessever.com href or the stored URL as is. Null
/// when the row has no `source_url`. Resolve it with [resolveNewsHref].
String? newsSourceContextHref(FeedNews news) {
  final source = news.sourceUrl;
  if (source == null) return null;
  return normalizeNewsInternalHref(source) ?? source;
}

/// `newsSourceContextLabel` from news.ts, for a [newsSourceContextHref].
String newsSourceContextLabel(String href) {
  if (href.contains('tab=standings') || href.endsWith('/standings')) {
    return 'Open Standings';
  }
  if (href.startsWith('/broadcast/')) return 'Open Event';
  if (href.startsWith('/player/')) return 'Open Player Profile';
  if (href.startsWith('/games/')) return 'Open Game';
  return 'Open Source';
}

/// The chessever.com link the app's deep-link router can open in place, or
/// null when [uri] has no in-app screen (the browser takes it then).
///
/// Mirrors the web's `normalizeInternalHref` rewrites first: share images
/// (`standings.png`, `profile.png`) and OG player cards point at the page they
/// picture.
Uri? newsInAppRoute(Uri uri) {
  if (!isChesseverUri(uri)) return null;
  var path = uri.path;
  var query = uri.query;

  final standings = RegExp(
    r'^/broadcast/([^/]+)/([^/]+)/standings\.png$',
  ).firstMatch(path);
  final profile = RegExp(
    r'^/broadcast/([^/]+)/([^/]+)/player/([^/]+)/profile\.png$',
  ).firstMatch(path);
  if (standings != null) {
    path = '/broadcast/${standings.group(1)}/${standings.group(2)}';
    query = 'tab=standings';
  } else if (profile != null) {
    path =
        '/broadcast/${profile.group(1)}/${profile.group(2)}'
        '/player/${profile.group(3)}';
    query = '';
  } else if (path == '/api/og/player-profile' || path == '/api/og/player') {
    final fideId = uri.queryParameters['fideId']?.trim() ?? '';
    if (!RegExp(r'^\d+$').hasMatch(fideId)) return null;
    path = '/player/$fideId';
    query = '';
  }

  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  const routable = {
    'games',
    'books',
    'databases',
    'folders',
    'broadcast',
    'player',
  };
  if (segments.length < 2 || !routable.contains(segments.first)) return null;
  return Uri.parse('$kChesseverSiteUrl$path${query.isEmpty ? '' : '?$query'}');
}

// -----------------------------------------------------------------------------
// NFKD folding for newsSlug
// -----------------------------------------------------------------------------

/// Lower-case characters whose NFKD form (minus U+0300–U+036F combining
/// marks) contains ASCII letters or digits, grouped by that form. Generated
/// from Unicode 16 for Latin-1 Supplement, Latin Extended A/B, spacing
/// modifiers, Latin Extended Additional, super/subscripts, number forms,
/// enclosed alphanumerics, Latin ligatures and fullwidth ASCII: everything a
/// news title plausibly carries. Anything else folds to itself, exactly as
/// NFKD leaves it, and `[^a-z0-9]` turns it into a dash either way.
const String _kNfkdFoldTable =
    '0=⁰₀⓪０ 1=¹₁①１ 2=²₂②２ 3=³₃③３ 4=⁴₄④４ 5=⁵₅⑤５ 6=⁶₆⑥６ 7=⁷₇⑦７ '
    '8=⁸₈⑧８ 9=⁹₉⑨９ a=ªàáâãäåāăąǎǟǡǻȁȃȧḁạảấầẩẫậắằẳẵặₐⓐａ b=ḃḅḇⓑｂ '
    'c=çćĉċčḉⅽⓒｃ d=ďḋḍḏḑḓⅾⓓｄ e=èéêëēĕėęěȅȇȩḕḗḙḛḝẹẻẽếềểễệₑⓔｅ '
    'f=ḟⓕｆ g=ĝğġģǧǵḡⓖｇ h=ĥȟʰḣḥḧḩḫẖₕⓗｈ i=ìíîïĩīĭįǐȉȋḭḯỉịⁱⅰⓘｉ '
    'j=ĵǰʲⓙｊ k=ķǩḱḳḵₖⓚｋ l=ĺļľˡḷḹḻḽₗⅼⓛｌ m=ḿṁṃₘⅿⓜｍ n=ñńņňǹṅṇṉṋⁿₙⓝｎ '
    'o=ºòóôõöōŏőơǒǫǭȍȏȫȭȯȱṍṏṑṓọỏốồổỗộớờởỡợₒⓞｏ p=ṕṗₚⓟｐ q=ⓠｑ '
    'r=ŕŗřȑȓʳṙṛṝṟⓡｒ s=śŝşšſșˢṡṣṥṧṩẛₛⓢｓ t=ţťțṫṭṯṱẗₜⓣｔ '
    'u=ùúûüũūŭůűųưǔǖǘǚǜȕȗṳṵṷṹṻụủứừửữựⓤｕ v=ṽṿⅴⓥｖ w=ŵʷẁẃẅẇẉẘⓦｗ '
    'x=ˣẋẍₓⅹⓧｘ y=ýÿŷȳʸẏẙỳỵỷỹⓨｙ z=źżžẑẓẕⓩｚ 1.=⒈ 10=⑩ 11=⑪ 12=⑫ '
    '13=⑬ 14=⑭ 15=⑮ 16=⑯ 17=⑰ 18=⑱ 19=⑲ 1⁄=⅟ 2.=⒉ 20=⑳ 3.=⒊ 4.=⒋ '
    '5.=⒌ 6.=⒍ 7.=⒎ 8.=⒏ 9.=⒐ aʾ=ẚ dz=ǆǳ ff=ﬀ fi=ﬁ fl=ﬂ ii=ⅱ '
    'ij=ĳ iv=ⅳ ix=ⅸ lj=ǉ l·=ŀ nj=ǌ st=ﬅﬆ vi=ⅵ xi=ⅺ ʼn=ŉ (1)=⑴ '
    '(2)=⑵ (3)=⑶ (4)=⑷ (5)=⑸ (6)=⑹ (7)=⑺ (8)=⑻ (9)=⑼ (a)=⒜ (b)=⒝ '
    '(c)=⒞ (d)=⒟ (e)=⒠ (f)=⒡ (g)=⒢ (h)=⒣ (i)=⒤ (j)=⒥ (k)=⒦ (l)=⒧ '
    '(m)=⒨ (n)=⒩ (o)=⒪ (p)=⒫ (q)=⒬ (r)=⒭ (s)=⒮ (t)=⒯ (u)=⒰ (v)=⒱ '
    '(w)=⒲ (x)=⒳ (y)=⒴ (z)=⒵ 0⁄3=↉ 10.=⒑ 11.=⒒ 12.=⒓ 13.=⒔ 14.=⒕ '
    '15.=⒖ 16.=⒗ 17.=⒘ 18.=⒙ 19.=⒚ 1⁄2=½ 1⁄3=⅓ 1⁄4=¼ 1⁄5=⅕ 1⁄6=⅙ '
    '1⁄7=⅐ 1⁄8=⅛ 1⁄9=⅑ 20.=⒛ 2⁄3=⅔ 2⁄5=⅖ 3⁄4=¾ 3⁄5=⅗ 3⁄8=⅜ 4⁄5=⅘ '
    '5⁄6=⅚ 5⁄8=⅝ 7⁄8=⅞ ffi=ﬃ ffl=ﬄ iii=ⅲ vii=ⅶ xii=ⅻ (10)=⑽ '
    '(11)=⑾ (12)=⑿ (13)=⒀ (14)=⒁ (15)=⒂ (16)=⒃ (17)=⒄ (18)=⒅ '
    '(19)=⒆ (20)=⒇ 1⁄10=⅒ viii=ⅷ';

final Map<int, String> _nfkdFold = () {
  final map = <int, String>{};
  for (final token in _kNfkdFoldTable.split(' ')) {
    final split = token.indexOf('=');
    if (split <= 0) continue;
    final folded = token.substring(0, split);
    for (final rune in token.substring(split + 1).runes) {
      map[rune] = folded;
    }
  }
  return map;
}();

String _foldNfkd(String input) {
  final out = StringBuffer();
  for (final rune in input.runes) {
    // Combining diacritical marks (the web strips U+0300–U+036F after NFKD).
    if (rune >= 0x300 && rune <= 0x36f) continue;
    final folded = _nfkdFold[rune];
    if (folded != null) {
      out.write(folded);
    } else {
      out.writeCharCode(rune);
    }
  }
  return out.toString();
}
