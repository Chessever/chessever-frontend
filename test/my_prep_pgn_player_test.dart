import 'package:chessever2/screens/my_prep/services/prep_pgn_player.dart';
import 'package:chessever2/screens/my_prep/services/prep_repository.dart';
import 'package:flutter_test/flutter_test.dart';

String game(String white, String black, {String? event = 'Open'}) =>
    '${event == null ? '' : '[Event "$event"]\n'}'
    '[White "$white"]\n[Black "$black"]\n[Result "1-0"]\n\n1. e4 e5 2. Nf3 1-0';

void main() {
  test('the name in every game is the player, whichever colour', () {
    final pgn = [
      game('Durarbayli, Vasif', 'Aronian, Levon'),
      game('Giri, Anish', 'Durarbayli, Vasif'),
      game('Durarbayli, Vasif', 'Aronian, Levon'),
      game('So, Wesley', 'Durarbayli, Vasif'),
    ].join('\n\n');
    final reading = readPrepPgnPlayer([pgn]);
    expect(reading.names, ['Durarbayli, Vasif']);
    expect(reading.games, 4);
  });

  test('other handles that cover the remaining games join the player', () {
    final pgn = [
      for (var i = 0; i < 6; i++) game('vasif_lichess', 'opp$i'),
      for (var i = 0; i < 4; i++) game('opp_c$i', 'VasifChesscom'),
      game('Durarbayli, Vasif', 'Mamedov, Rauf'),
      game('Mamedov, Rauf', 'Durarbayli, V.'),
    ].join('\n');
    final reading = readPrepPgnPlayer([pgn]);
    expect(reading.names.toSet(), {
      'vasif_lichess',
      'VasifChesscom',
      'Durarbayli, Vasif',
      'Durarbayli, V.',
    });
    expect(reading.names.first, 'vasif_lichess');
    expect(reading.games, 12);
  });

  test('a frequent opponent never becomes the player', () {
    final pgn = [
      for (var i = 0; i < 10; i++) game('Me', 'Rival'),
      for (var i = 0; i < 10; i++) game('Me', 'other$i'),
    ].join('\n');
    expect(readPrepPgnPlayer([pgn]).names, ['Me']);
  });

  test(
    'a match or a single game asks whose it is, unless the name is known',
    () {
      final match = [
        for (var i = 0; i < 7; i++)
          game('Carlsen, Magnus', 'Nepomniachtchi, Ian'),
        for (var i = 0; i < 7; i++)
          game('Nepomniachtchi, Ian', 'Carlsen, Magnus'),
      ].join('\n');
      final reading = readPrepPgnPlayer([match]);
      expect(reading.resolved, isFalse);
      expect(reading.candidates.map((c) => c.name).toSet(), {
        'Carlsen, Magnus',
        'Nepomniachtchi, Ian',
      });
      expect(readPrepPgnPlayer([match], known: ['carlsen,magnus']).names, [
        'Carlsen, Magnus',
      ]);
      expect(readPrepPgnPlayer([game('A', 'B')]).resolved, isFalse);
    },
  );

  test(
    'placeholders, unplayed games and comments are not players or games',
    () {
      final pgn = '''
﻿[White "Me"]
[Black "?"]

{ A comment that runs
[White "Ghost"] across lines }
1. d4 d5 ; [Black "Ghost"]
2. c4 1-0

[Event "Empty"]
[White "Ghost"]
[Black "Ghost2"]

*

[White "NN"]
[Black "Me"]

1. e4 0-1
''';
      final games = splitPgnGames(pgn);
      expect(games, hasLength(3));
      expect(games.first, startsWith('[Event "?"]'));
      final reading = readPrepPgnPlayer([pgn]);
      expect(reading.names, ['Me']);
      expect(reading.games, 2);
    },
  );

  test('a file with no playable games is refused', () {
    expect(
      () => readPrepPgnPlayer(['[White "A"]\n[Black "B"]\n\n*']),
      throwsA(isA<PrepException>()),
    );
  });
}
