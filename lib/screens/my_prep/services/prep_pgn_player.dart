import 'dart:math' as math;

import 'package:chessever2/screens/my_prep/services/prep_repository.dart'
    show PrepException;
import 'package:chessever2/services/game_tree/game_tree_codec.dart';

/// A name a PGN could belong to, with the playable games it plays.
class PrepPgnCandidate {
  const PrepPgnCandidate(this.name, this.games);
  final String name;
  final int games;
}

/// Whose games a PGN holds. Either [names] (resolved, most frequent first)
/// or, when two players share the file evenly, the [candidates] to choose
/// between.
class PrepPgnReading {
  const PrepPgnReading({
    this.names = const [],
    this.games = 0,
    this.candidates = const [],
  });

  /// Every spelling the player goes by in the file: a full name, a
  /// shortened one, an online handle.
  final List<String> names;

  /// The playable games played under [names].
  final int games;
  final List<PrepPgnCandidate> candidates;

  bool get resolved => names.isNotEmpty;
  String get name => names.first;
}

/// Names that stand for nobody: `[White "?"]`, `NN`, a blank seat.
const _placeholders = {
  '',
  'nn',
  'unknown',
  'anonymous',
  'white',
  'black',
  'player',
  'player1',
  'player2',
};

/// Reads who [texts] belong to, the way a person would: the player is the
/// name in (nearly) every game. A name joins them when it never sits across
/// the board from them and clearly leads the games they are missing from
/// (another handle, a changed spelling), or when it is the same person
/// written differently (`Durarbayli, V` beside `Durarbayli, Vasif`).
///
/// [known] names (the profile's own) are taken first wherever they appear.
/// With nothing known and two players level across the file (a match, a
/// single game) the reading holds [PrepPgnReading.candidates] instead.
PrepPgnReading readPrepPgnPlayer(
  List<String> texts, {
  Iterable<String> known = const [],
}) {
  final games = <List<String>>[];
  final counts = <String, int>{};
  final spellings = <String, Map<String, int>>{};
  final opponents = <String, Set<String>>{};
  for (final text in texts) {
    for (final game in splitPgnGames(text)) {
      final scan = scanPgnGame(game, sanLimit: 1);
      if (scan.sans.isEmpty) continue;
      final keys = <String>[];
      for (final side in const ['White', 'Black']) {
        final raw = scan.tag(side)?.trim();
        if (raw == null) continue;
        final key = treePlayerKey(raw);
        if (_placeholders.contains(key) || keys.contains(key)) continue;
        keys.add(key);
        counts[key] = (counts[key] ?? 0) + 1;
        spellings
            .putIfAbsent(key, () => {})
            .update(raw, (n) => n + 1, ifAbsent: () => 1);
      }
      if (keys.length == 2) {
        opponents.putIfAbsent(keys[0], () => {}).add(keys[1]);
        opponents.putIfAbsent(keys[1], () => {}).add(keys[0]);
      }
      games.add(keys);
    }
  }
  if (games.isEmpty) {
    throw const PrepException('No playable games in this PGN.');
  }
  if (counts.isEmpty) {
    throw const PrepException('These games do not name their players.');
  }

  String spelling(String key) => _mostFrequent(spellings[key]!);
  final ranked = counts.keys.toList()
    ..sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      return byCount != 0 ? byCount : a.compareTo(b);
    });

  final knownKeys = {for (final name in known) treePlayerKey(name)}
    ..removeWhere((k) => k.isEmpty);
  final chosen = {
    for (final key in ranked)
      if (knownKeys.contains(key)) key,
  };
  if (chosen.isEmpty) {
    final top = ranked.first;
    // Level with the leader across the board from them: the file is as
    // much theirs, and only the reader can say whose it is.
    final level = [
      for (final key in ranked.skip(1))
        if (counts[key]! * 10 >= counts[top]! * 9 &&
            (opponents[top]?.contains(key) ?? false))
          key,
    ];
    if (level.isNotEmpty) {
      return PrepPgnReading(
        candidates: [
          for (final key in [top, ...level].take(6))
            PrepPgnCandidate(spelling(key), counts[key]!),
        ],
      );
    }
    chosen.add(top);
  }

  bool faces(String key) =>
      chosen.any((c) => opponents[c]?.contains(key) ?? false);

  // The player's other names cover the games their main one is absent
  // from. One person's spellings count together (`Durarbayli, Vasif` and
  // `Durarbayli, V.`), and a name sharing a word with the player's
  // (`vasif_lichess`, `VasifChesscom`) is taken before a mere frequent one.
  String cluster(String key) => _signature(spelling(key)) ?? key;
  final share = math.max(2, (games.length * 0.05).ceil());
  while (true) {
    final words = {
      for (final key in chosen)
        for (final raw in spellings[key]!.keys) ..._words(raw),
    };
    final local = <String, int>{};
    final members = <String, Set<String>>{};
    for (final game in games) {
      if (game.any(chosen.contains)) continue;
      for (final key in game) {
        if (faces(key)) continue;
        final id = cluster(key);
        local[id] = (local[id] ?? 0) + 1;
        members.putIfAbsent(id, () => {}).add(key);
      }
    }
    if (local.isEmpty) break;
    bool related(String id) => members[id]!.any(
      (key) =>
          spellings[key]!.keys.any((raw) => _words(raw).any(words.contains)),
    );
    final order = local.keys.toList()
      ..sort((a, b) => local[b]!.compareTo(local[a]!));
    final kin = order.where(related).firstOrNull;
    if (kin != null) {
      chosen.addAll(members[kin]!);
      continue;
    }
    final best = local[order.first]!;
    final next = order.length > 1 ? local[order[1]]! : 0;
    if (best < share || best <= next) break;
    chosen.addAll(members[order.first]!);
  }

  // The same person written another way, however rarely.
  final signatures = {
    for (final key in chosen)
      for (final raw in spellings[key]!.keys) ?_signature(raw),
  };
  for (final key in ranked) {
    if (chosen.contains(key) || faces(key)) continue;
    if (spellings[key]!.keys.any(
      (raw) => signatures.contains(_signature(raw)),
    )) {
      chosen.add(key);
    }
  }

  final names = ranked.where(chosen.contains).toList();
  return PrepPgnReading(
    names: [for (final key in names) spelling(key)],
    games: games.where((g) => g.any(chosen.contains)).length,
  );
}

String _mostFrequent(Map<String, int> spellings) =>
    spellings.entries.reduce((a, b) => b.value > a.value ? b : a).key;

/// Words that name a player rather than a site: `vasif_lichess` and
/// `VasifChesscom` both say `vasif`.
const _siteWords = {
  'chess',
  'lichess',
  'chesscom',
  'player',
  'official',
  'online',
  'blitz',
  'bullet',
  'rapid',
};
final _camel = RegExp(r'(?<=\p{Ll})(?=\p{Lu})', unicode: true);
final _nonWord = RegExp(r'[^\p{L}]+', unicode: true);

Set<String> _words(String raw) => {
  for (final word
      in raw.replaceFirst(_title, '').replaceAll(_camel, ' ').split(_nonWord))
    if (word.length >= 4 && !_siteWords.contains(word.toLowerCase()))
      word.toLowerCase(),
};

final _title = RegExp(
  r'^(?:gm|wgm|im|wim|fm|wfm|cm|wcm|nm|wnm)\.?\s+',
  caseSensitive: false,
);
final _notLetter = RegExp(r'[^\p{L}]', unicode: true);

/// Family name and first initial: `Durarbayli, Vasif`, `Durarbayli,V.` and
/// `Vasif Durarbayli` all read `durarbayli|v`. A one-word handle has none.
String? _signature(String raw) {
  final clean = raw.replaceFirst(_title, '').trim().toLowerCase();
  final String family;
  final String given;
  if (clean.contains(',')) {
    final comma = clean.indexOf(',');
    family = clean.substring(0, comma);
    given = clean.substring(comma + 1);
  } else {
    final words = clean.split(RegExp(r'\s+'));
    if (words.length < 2) return null;
    family = words.last;
    given = words.first;
  }
  final f = family.replaceAll(_notLetter, '');
  final g = given.replaceAll(_notLetter, '');
  if (f.length < 2 || g.isEmpty) return null;
  return '$f|${String.fromCharCode(g.runes.first)}';
}

final _tagLine = RegExp(r'^\s*\[[A-Za-z0-9_]+\s+"');
final _eventTag = RegExp(r'^\s*\[Event\s', multiLine: true);

/// Splits a PGN database into games as the standard reads it: a game is a
/// tag section and the movetext after it, so a new one starts at the first
/// tag line once movetext has begun. Brace comments may run over lines and
/// `;` comments to the end of one; neither starts a game. `%` lines are
/// escapes. Each game is given an `[Event]` tag when it lacks one, so the
/// stored file splits the same way.
List<String> splitPgnGames(String text) {
  final games = <String>[];
  final current = StringBuffer();
  var moves = false;
  var inComment = false;

  void close() {
    final game = current.toString().trim();
    current.clear();
    moves = false;
    if (game.isEmpty) return;
    games.add(_eventTag.hasMatch(game) ? game : '[Event "?"]\n$game');
  }

  final source = text.startsWith('﻿') ? text.substring(1) : text;
  for (final line in source.replaceAll('\r\n', '\n').split('\n')) {
    if (!inComment) {
      if (line.startsWith('%')) continue;
      if (_tagLine.hasMatch(line)) {
        if (moves) close();
        current.writeln(line);
        continue;
      }
    }
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (inComment) {
        if (c == '}') inComment = false;
      } else if (c == '{') {
        inComment = true;
      } else if (c == ';') {
        break;
      } else if (c.trim().isNotEmpty) {
        moves = true;
      }
    }
    current.writeln(line);
  }
  close();
  return games;
}
