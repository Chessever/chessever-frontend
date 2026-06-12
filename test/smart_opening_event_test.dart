import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/group_event/smart_opening_event.dart';
import 'package:flutter_test/flutter_test.dart';

Games _game({String? eco, String? openingName, String? name}) {
  return Games(
    id: 'game-${eco ?? openingName ?? name}',
    roundId: 'round-1',
    roundSlug: 'round-1',
    tourId: 'tour-1',
    tourSlug: 'tour-1',
    name: name,
    eco: eco,
    openingName: openingName,
    players: const <Player>[],
  );
}

void main() {
  group('SmartOpeningQuery', () {
    test('parses exact ECO codes', () {
      final query = SmartOpeningQuery.parse('B90');

      expect(query, isNotNull);
      expect(query!.title, 'ECO: B90');
      expect(query.matchesGame(_game(eco: 'B90')), isTrue);
      expect(query.matchesGame(_game(eco: 'B91')), isFalse);
    });

    test('parses short same-family ECO ranges', () {
      final query = SmartOpeningQuery.parse('B90-98');

      expect(query, isNotNull);
      expect(query!.title, 'ECO: B90–B98');
      expect(query.matchesGame(_game(eco: 'B90')), isTrue);
      expect(query.matchesGame(_game(eco: 'B95')), isTrue);
      expect(query.matchesGame(_game(eco: 'B98')), isTrue);
      expect(query.matchesGame(_game(eco: 'B99')), isFalse);
      expect(query.matchesGame(_game(eco: 'C95')), isFalse);
    });

    test('parses explicit ECO ranges', () {
      final query = SmartOpeningQuery.parse('B90-B98');

      expect(query, isNotNull);
      expect(query!.matchesGame(_game(eco: 'B93')), isTrue);
      expect(query.matchesGame(_game(eco: 'B89')), isFalse);
    });

    test('matches broad opening text by token', () {
      final query = SmartOpeningQuery.parse('Sicilian');

      expect(query, isNotNull);
      expect(
        query!.matchesGame(
          _game(openingName: 'Sicilian Defense: Najdorf Variation'),
        ),
        isTrue,
      );
      expect(query.matchesGame(_game(openingName: 'French Defense')), isFalse);
    });

    test('narrows opening text when variation is supplied', () {
      final query = SmartOpeningQuery.parse('sicilian najdorf');

      expect(query, isNotNull);
      expect(
        query!.matchesGame(
          _game(openingName: 'Sicilian Defense: Najdorf Variation'),
        ),
        isTrue,
      );
      expect(
        query.matchesGame(_game(openingName: 'Sicilian Defense: Dragon')),
        isFalse,
      );
    });

    test('does not hijack unrelated player/event searches', () {
      expect(SmartOpeningQuery.parse('Magnus Carlsen'), isNull);
      expect(SmartOpeningQuery.parse('World Championship'), isNull);
    });
  });
}
