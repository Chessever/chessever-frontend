import 'dart:ui';

import 'package:chessever2/repository/local_storage/board_settings_repository/board_settings_repository.dart';
import 'package:chessever2/theme/app_theme.dart';

class BoardThemePair {
  final Color darkSquare;
  final Color lightSquare;

  const BoardThemePair({
    required this.darkSquare,
    required this.lightSquare,
  });
}

const Map<BoardColor, BoardThemePair> boardThemes = {
  BoardColor.defaultColor: BoardThemePair(
    darkSquare: kBoardColorDefault, // Your existing dark default
    lightSquare: kBoardLightDefault,
  ),
  BoardColor.brown: BoardThemePair(
    darkSquare: kBoardColorBrown, // Your existing dark brown
    lightSquare: kBoardLightBrown,
  ),
  BoardColor.grey: BoardThemePair(
    darkSquare: kBoardColorGrey, // Your existing dark grey
    lightSquare: kBoardLightGrey,
  ),
  BoardColor.green: BoardThemePair(
    darkSquare: kBoardColorGreen,
    lightSquare: kBoardLightGreen,
  ),
};