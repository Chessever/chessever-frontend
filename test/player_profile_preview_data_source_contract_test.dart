import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'TWIC Player Profile data source reaches board and grid player rows',
    () {
      final playerGamesSource =
          File(
            'lib/screens/player_profile/tabs/player_games_tab.dart',
          ).readAsStringSync();

      for (final wrapperName in [
        'BoardGameCardWrapperWidget',
        'GridGameCardWrapperWidget',
      ]) {
        final playerProfileCalls = _constructorArguments(
          playerGamesSource,
          wrapperName,
        ).where(
          (arguments) =>
              arguments.contains('viewSource: ChessboardView.playerProfile'),
        );

        expect(
          playerProfileCalls,
          isNotEmpty,
          reason: 'Player Profile must keep its $wrapperName preview',
        );
        for (final arguments in playerProfileCalls) {
          expect(
            _topLevelNamedArgument(arguments, 'playerProfileDataSource'),
            'widget.dataSource',
            reason:
                '$wrapperName must receive the active Player Profile backend '
                'instead of defaulting TWIC previews to Supabase',
          );
        }
      }

      const wrapperContracts = {
        'lib/screens/tour_detail/games_tour/widgets/game_card_wrapper/'
                'board_game_card_wrapper_widget.dart':
            'ChessBoardFromFENNew',
        'lib/screens/tour_detail/games_tour/widgets/game_card_wrapper/'
                'grid_game_card_wrapper_widget.dart':
            'GridChessBoardFromFENNew',
      };

      for (final entry in wrapperContracts.entries) {
        final source = File(entry.key).readAsStringSync();
        expect(
          source,
          contains('final PlayerProfileDataSource playerProfileDataSource;'),
          reason: '${entry.key} must own the data-source contract',
        );

        final previewCalls = _constructorArguments(
          source,
          entry.value,
        ).where((arguments) => arguments.contains('gamesTourModel: liveGame'));
        expect(previewCalls, hasLength(1));
        expect(
          _topLevelNamedArgument(
            previewCalls.single,
            'playerProfileDataSource',
          ),
          'playerProfileDataSource',
          reason: '${entry.key} must forward the contract to ${entry.value}',
        );
      }

      final previewSource =
          File(
            'lib/screens/chessboard/widgets/chess_board_from_fen_new.dart',
          ).readAsStringSync();
      final rowCalls = _constructorArguments(
        previewSource,
        '_PlayerRow',
      ).where((arguments) => arguments.contains('gamesTourModel:'));
      expect(rowCalls, isNotEmpty);
      for (final arguments in rowCalls) {
        expect(
          _topLevelNamedArgument(arguments, 'playerProfileDataSource'),
          'playerProfileDataSource',
          reason:
              'every board/grid player row must receive the preview data '
              'source',
        );
      }

      final detailCalls = _constructorArguments(
        previewSource,
        'PlayerFirstRowDetailWidget',
      ).where((arguments) => arguments.contains('gamesTourModel:'));
      expect(detailCalls, hasLength(1));
      expect(
        _topLevelNamedArgument(detailCalls.single, 'playerProfileDataSource'),
        'playerProfileDataSource',
        reason:
            '_PlayerRow must deliver the preview data source to the '
            'player-name tap handler',
      );
    },
  );

  test('Chessboard dropdown player rows keep the route data source', () {
    final source =
        File(
          'lib/screens/chessboard/chess_board_screen_new.dart',
        ).readAsStringSync();

    final overlayCalls = _constructorArguments(
      source,
      '_GameDropdownOverlay',
    ).where((arguments) => arguments.contains('triggerRect: anchor'));
    expect(overlayCalls, hasLength(1));
    expect(
      _topLevelNamedArgument(overlayCalls.single, 'playerProfileDataSource'),
      'widget.playerProfileDataSource',
      reason:
          'ChessBoardScreenNew must hand its immutable route backend to the '
          'dropdown overlay',
    );

    final contentCalls = _constructorArguments(
      source,
      '_GameDropdownContent',
    ).where((arguments) => arguments.contains('dropdownWidth: dropdownWidth'));
    expect(contentCalls, hasLength(1));
    expect(
      _topLevelNamedArgument(contentCalls.single, 'playerProfileDataSource'),
      'playerProfileDataSource',
      reason: 'the dropdown overlay must forward the route backend to content',
    );

    final selectorCalls = _constructorArguments(
      source,
      '_GameSelectorCard',
    ).where((arguments) => arguments.contains('isSelected: isSelected'));
    expect(selectorCalls, hasLength(1));
    expect(
      _topLevelNamedArgument(selectorCalls.single, 'playerProfileDataSource'),
      'widget.playerProfileDataSource',
      reason: 'dropdown content must forward the route backend to every card',
    );

    final dropdownPlayerRows = _constructorArguments(
      source,
      'PlayerFirstRowDetailWidget',
    ).where((arguments) => arguments.contains('compactName: true'));
    expect(dropdownPlayerRows, hasLength(1));
    expect(
      _topLevelNamedArgument(
        dropdownPlayerRows.single,
        'playerProfileDataSource',
      ),
      'playerProfileDataSource',
      reason:
          'the dropdown player-name tap must not fall back to the Supabase '
          'backend on a TWIC board route',
    );
  });

  test(
    'Chessboard main PageView player rows keep the route-owned scorecard context',
    () {
      final source =
          File(
            'lib/screens/chessboard/chess_board_screen_new.dart',
          ).readAsStringSync();

      final pageCalls = _constructorArguments(
        source,
        '_GamePage',
      ).where((arguments) => arguments.contains('game: chessBoardState.game'));
      expect(pageCalls, hasLength(1));
      expect(
        _topLevelNamedArgument(pageCalls.single, 'scoreCardViewSource'),
        'widget.viewSource',
        reason:
            'the PageView must hand its immutable route source to the visible '
            'board page instead of making player taps infer it from globals',
      );

      final bodyCalls = _constructorArguments(
        source,
        '_GameBody',
      ).where((arguments) => arguments.contains('game: game'));
      expect(bodyCalls, hasLength(1));
      expect(
        _topLevelNamedArgument(bodyCalls.single, 'scoreCardViewSource'),
        'scoreCardViewSource',
      );
      expect(
        _topLevelNamedArgument(bodyCalls.single, 'scoreCardGamesContext'),
        'games',
        reason:
            'the board page must retain the exact visible PageView list for '
            'player-name scorecard navigation',
      );

      final analysisCalls = _constructorArguments(
        source,
        '_AnalysisGameBody',
      ).where((arguments) => arguments.contains('game: game'));
      expect(analysisCalls, hasLength(1));
      expect(
        _topLevelNamedArgument(analysisCalls.single, 'scoreCardViewSource'),
        'scoreCardViewSource',
      );
      expect(
        _topLevelNamedArgument(analysisCalls.single, 'scoreCardGamesContext'),
        'scoreCardGamesContext',
      );

      final mainPlayerRows = _constructorArguments(
        source,
        'PlayerFirstRowDetailWidget',
      ).where(
        (arguments) => arguments.contains('playerView: PlayerView.boardView'),
      );
      expect(mainPlayerRows, hasLength(2));
      for (final arguments in mainPlayerRows) {
        expect(
          _topLevelNamedArgument(arguments, 'scoreCardViewSource'),
          'scoreCardViewSource',
          reason:
              'phone and tablet player-name taps must keep the board route '
              'source',
        );
        expect(
          _topLevelNamedArgument(arguments, 'scoreCardGamesContext'),
          'scoreCardGamesContext',
          reason:
              'phone and tablet player-name taps must keep the exact board '
              'PageView list',
        );
      }
    },
  );

  test('Every tablet board player row keeps the route profile backend', () {
    final source =
        File(
          'lib/screens/chessboard/chess_board_screen_new.dart',
        ).readAsStringSync();

    final tabletPlayerRows = _constructorArguments(
      source,
      '_TabletPlayerCard',
    ).where(
      (arguments) =>
          arguments.contains('game: game') &&
          arguments.contains('state: state'),
    );
    expect(
      tabletPlayerRows,
      hasLength(4),
      reason:
          'tablet landscape and portrait layouts each render two player rows',
    );
    for (final arguments in tabletPlayerRows) {
      expect(
        _topLevelNamedArgument(arguments, 'playerProfileDataSource'),
        'playerProfileDataSource',
        reason:
            'a TWIC/archive board must not default a tablet player-name tap '
            'back to the Supabase profile backend',
      );
    }
  });

  group('Gamebase archive player rows use the TWIC profile backend', () {
    test('GamebaseSearchGameCard defaults archive callers to TWIC', () {
      final source =
          File(
            'lib/screens/library/widgets/gamebase_search_game_card.dart',
          ).readAsStringSync();

      final constructors = _constructorArguments(
        source,
        'GamebaseSearchGameCard',
      ).where(
        (arguments) =>
            arguments.contains('required this.game,') &&
            arguments.contains('required this.allGames,'),
      );
      expect(constructors, hasLength(1));
      expect(
        _topLevelDefaultValue(
          constructors.single,
          'this.playerProfileDataSource',
        ),
        'PlayerProfileDataSource.twic',
        reason:
            'archive card callers such as Library, Gamebase search, and '
            'Miniatures scorecards must not silently inherit Supabase',
      );
    });

    test('Library board and grid previews and launches keep TWIC', () {
      final source =
          File(
            'lib/screens/library/widgets/library_search_results_view.dart',
          ).readAsStringSync();

      const previewKeys = {
        'GridChessBoardFromFENNew': 'lib_grid_game_',
        'ChessBoardFromFENNew': 'lib_board_game_',
      };
      for (final entry in previewKeys.entries) {
        final previewName = entry.key;
        final previewCalls = _constructorArguments(source, previewName).where(
          (arguments) =>
              arguments.contains('gamesTourModel: game') &&
              arguments.contains(entry.value),
        );
        expect(
          previewCalls,
          hasLength(1),
          reason: 'Library must keep one $previewName archive preview',
        );
        expect(
          _topLevelNamedArgument(
            previewCalls.single,
            'playerProfileDataSource',
          ),
          'PlayerProfileDataSource.twic',
          reason:
              '$previewName player-name taps must query the Gamebase/TWIC '
              'backend',
        );
      }

      final launchCalls = _constructorArguments(
        source,
        'navigateToChessBoard',
      ).where(
        (arguments) =>
            arguments.contains('orderedGames: allGames') &&
            arguments.contains('gameIndex: gameIndex'),
      );
      expect(
        launchCalls,
        hasLength(2),
        reason: 'Library board and grid previews must each launch the board',
      );
      for (final arguments in launchCalls) {
        expect(
          _topLevelNamedArgument(arguments, 'playerProfileDataSource'),
          'PlayerProfileDataSource.twic',
          reason: 'Library board launches must retain the preview TWIC backend',
        );
      }
    });

    test('Miniatures card, board, grid, and direct launcher keep TWIC', () {
      final tabSource =
          File(
            'lib/screens/library/miniatures/miniatures_games_tab.dart',
          ).readAsStringSync();

      final cardAndBoardCalls = _constructorArguments(
        tabSource,
        'GameCardWrapperWidget',
      ).where(
        (arguments) => arguments.contains('isChessBoardVisible: entry.isBoard'),
      );
      expect(
        cardAndBoardCalls,
        hasLength(1),
        reason: 'Miniatures card and board modes share one wrapper contract',
      );
      expect(
        _topLevelNamedArgument(
          cardAndBoardCalls.single,
          'playerProfileDataSource',
        ),
        'PlayerProfileDataSource.twic',
        reason:
            'Miniatures card/board player rows must query the archive backend',
      );

      final gridCalls = _constructorArguments(
        tabSource,
        'GridGameCardWrapperWidget',
      ).where((arguments) => arguments.contains("'mini_grid_\${game.gameId}'"));
      expect(gridCalls, hasLength(1));
      expect(
        _topLevelNamedArgument(gridCalls.single, 'playerProfileDataSource'),
        'PlayerProfileDataSource.twic',
        reason: 'Miniatures grid player rows must query the archive backend',
      );

      final launcherSource =
          File(
            'lib/screens/library/miniatures/miniature_game_launcher.dart',
          ).readAsStringSync();
      final boardCalls = _constructorArguments(
        launcherSource,
        'ChessBoardScreenNew',
      ).where(
        (arguments) =>
            arguments.contains('games: boardGames') &&
            arguments.contains('showGamebaseButton: false'),
      );
      expect(boardCalls, hasLength(1));
      expect(
        _topLevelNamedArgument(boardCalls.single, 'playerProfileDataSource'),
        'PlayerProfileDataSource.twic',
        reason: 'the hydrated Miniatures board must retain the archive backend',
      );
    });

    test('position sheet and in-board FEN results keep TWIC', () {
      final sheetSource =
          File(
            'lib/screens/gamebase/widgets/position_games_sheet.dart',
          ).readAsStringSync();
      final sheetBoardCalls = _constructorArguments(
        sheetSource,
        'ChessBoardScreenNew',
      ).where(
        (arguments) =>
            arguments.contains('games: boardGames') &&
            arguments.contains('initialFen: initialFen'),
      );
      expect(sheetBoardCalls, hasLength(1));
      expect(
        _topLevelNamedArgument(
          sheetBoardCalls.single,
          'playerProfileDataSource',
        ),
        'PlayerProfileDataSource.twic',
        reason: 'a Gamebase position-result board must use Gamebase player IDs',
      );

      final boardSource =
          File(
            'lib/screens/chessboard/chess_board_screen_new.dart',
          ).readAsStringSync();
      final fenTableBoardCalls = _constructorArguments(
        boardSource,
        'ChessBoardScreenNew',
      ).where(
        (arguments) =>
            arguments.contains('games: boardGames') &&
            arguments.contains('initialFen: widget.fen'),
      );
      expect(fenTableBoardCalls, hasLength(1));
      expect(
        _topLevelNamedArgument(
          fenTableBoardCalls.single,
          'playerProfileDataSource',
        ),
        'PlayerProfileDataSource.twic',
        reason:
            'the board FEN table must not open an archive result as Supabase',
      );
    });

    test('Gamebase deep links keep TWIC on the destination board', () {
      final source =
          File('lib/services/deep_link_service.dart').readAsStringSync();
      final boardCalls = _constructorArguments(
        source,
        'ChessBoardScreenNew',
      ).where(
        (arguments) =>
            arguments.contains("ValueKey('deep-link-gamebase-\$gameId')"),
      );
      expect(boardCalls, hasLength(1));
      expect(
        _topLevelNamedArgument(boardCalls.single, 'playerProfileDataSource'),
        'PlayerProfileDataSource.twic',
        reason:
            'a Gamebase deep link must resolve player taps against Gamebase',
      );
    });
  });
}

String? _topLevelNamedArgument(String arguments, String name) {
  for (final argument in _splitTopLevelArguments(arguments)) {
    final trimmed = argument.trim();
    final prefix = '$name:';
    if (trimmed.startsWith(prefix)) {
      return trimmed.substring(prefix.length).trim();
    }
  }
  return null;
}

String? _topLevelDefaultValue(String arguments, String name) {
  var parameterList = arguments.trim();
  if (parameterList.startsWith('{') && parameterList.endsWith('}')) {
    parameterList = parameterList.substring(1, parameterList.length - 1);
  }

  for (final argument in _splitTopLevelArguments(parameterList)) {
    final trimmed = argument.trim();
    final prefix = '$name =';
    if (trimmed.startsWith(prefix)) {
      return trimmed.substring(prefix.length).trim();
    }
  }
  return null;
}

List<String> _splitTopLevelArguments(String arguments) {
  final result = <String>[];
  var start = 0;
  var parentheses = 0;
  var brackets = 0;
  var braces = 0;
  String? quote;
  var escaped = false;

  for (var index = 0; index < arguments.length; index++) {
    final character = arguments[index];
    if (quote != null) {
      if (escaped) {
        escaped = false;
      } else if (character == r'\') {
        escaped = true;
      } else if (character == quote) {
        quote = null;
      }
      continue;
    }

    if (character == "'" || character == '"') {
      quote = character;
      continue;
    }

    if (character == '(') {
      parentheses++;
    } else if (character == ')') {
      parentheses--;
    } else if (character == '[') {
      brackets++;
    } else if (character == ']') {
      brackets--;
    } else if (character == '{') {
      braces++;
    } else if (character == '}') {
      braces--;
    } else if (character == ',' &&
        parentheses == 0 &&
        brackets == 0 &&
        braces == 0) {
      result.add(arguments.substring(start, index));
      start = index + 1;
    }
  }

  result.add(arguments.substring(start));
  return result;
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
