import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normal gamebase card uses its collection source end to end', () {
    final source =
        File(
          'lib/screens/library/widgets/gamebase_search_game_card.dart',
        ).readAsStringSync();

    expect(source, contains('this.viewSource = ChessboardView.tour'));
    expect(
      source,
      contains(
        'this.navigationListPolicy = BoardNavigationListPolicy.preserve',
      ),
    );
    expect(source, contains('final ChessboardView viewSource;'));
    expect(
      source,
      contains('final BoardNavigationListPolicy navigationListPolicy;'),
    );
    expect(
      source,
      contains(
        'ref.read(chessboardViewFromProviderNew.notifier).state = viewSource;',
      ),
    );
    expect(source, contains('viewSource: viewSource,'));
    expect(source, contains('listPolicy: navigationListPolicy,'));
    expect(
      'ChessboardView.tour'.allMatches(source),
      hasLength(1),
      reason:
          'tour is only the backward-compatible constructor default; neither '
          'the provider write nor board navigation may hardcode it',
    );
  });

  test('live wrapper forwards its collection source to the normal card', () {
    final source =
        File(
          'lib/screens/library/widgets/live_gamebase_search_game_card.dart',
        ).readAsStringSync();

    expect(source, contains('this.viewSource = ChessboardView.tour'));
    expect(
      source,
      contains(
        'this.navigationListPolicy = BoardNavigationListPolicy.preserve',
      ),
    );
    expect(source, contains('final ChessboardView viewSource;'));
    expect(
      source,
      contains('final BoardNavigationListPolicy navigationListPolicy;'),
    );
    expect(source, contains('viewSource: viewSource,'));
    expect(source, contains('navigationListPolicy: navigationListPolicy,'));
    expect(
      'ChessboardView.tour'.allMatches(source),
      hasLength(1),
      reason:
          'tour must remain only the wrapper default, not a forwarded value',
    );
  });

  test('collection surfaces identify every live normal-card list', () {
    const expectedSources = {
      'lib/screens/favorites/tabs/favorites_games_tab.dart':
          'ChessboardView.favorites',
      'lib/screens/favorites/player_games/favorites_combined_games_screen.dart':
          'ChessboardView.favorites',
      'lib/screens/countrymen/tabs/countrymen_games_tab.dart':
          'ChessboardView.countryman',
      'lib/screens/countrymen/countrymen_combined_games_screen.dart':
          'ChessboardView.countryman',
      'lib/screens/player_profile/tabs/player_games_tab.dart':
          'ChessboardView.playerProfile',
    };

    for (final entry in expectedSources.entries) {
      final source = File(entry.key).readAsStringSync();
      final liveCardArguments = _constructorArguments(
        source,
        'LiveGamebaseSearchGameCard',
      );

      expect(
        liveCardArguments,
        isNotEmpty,
        reason: '${entry.key} must keep a live normal-card surface',
      );
      for (final arguments in liveCardArguments) {
        expect(
          arguments,
          contains('viewSource: ${entry.value}'),
          reason:
              'every LiveGamebaseSearchGameCard in ${entry.key} must preserve '
              'its owning collection',
        );
      }
    }
  });
}

List<String> _constructorArguments(String source, String constructorName) {
  final marker = '$constructorName(';
  final results = <String>[];
  var searchFrom = 0;

  while (true) {
    final callStart = source.indexOf(marker, searchFrom);
    if (callStart < 0) return results;

    final openParen = callStart + constructorName.length;
    var depth = 0;
    for (var index = openParen; index < source.length; index++) {
      final character = source[index];
      if (character == '(') {
        depth++;
      } else if (character == ')') {
        depth--;
        if (depth == 0) {
          results.add(source.substring(openParen + 1, index));
          searchFrom = index + 1;
          break;
        }
      }
    }

    if (searchFrom <= callStart) {
      throw StateError('Unclosed $constructorName invocation');
    }
  }
}
