import 'package:chessground/chessground.dart';
import 'package:chessever2/theme/app_theme.dart';

/// Board theme option with display name and color scheme
class BoardThemeOption {
  const BoardThemeOption({required this.name, required this.colorScheme});

  final String name;
  final ChessboardColorScheme colorScheme;
}

/// Available board themes from chessground package
const List<BoardThemeOption> kBoardThemes = [
  BoardThemeOption(name: 'Brown', colorScheme: ChessboardColorScheme.brown),
  BoardThemeOption(name: 'Blue', colorScheme: ChessboardColorScheme.blue),
  BoardThemeOption(name: 'Green', colorScheme: ChessboardColorScheme.green),
  BoardThemeOption(name: 'IC', colorScheme: ChessboardColorScheme.ic),
  BoardThemeOption(name: 'Blue 2', colorScheme: ChessboardColorScheme.blue2),
  BoardThemeOption(name: 'Blue 3', colorScheme: ChessboardColorScheme.blue3),
  BoardThemeOption(
    name: 'Blue Marble',
    colorScheme: ChessboardColorScheme.blueMarble,
  ),
  BoardThemeOption(name: 'Canvas', colorScheme: ChessboardColorScheme.canvas),
  BoardThemeOption(
    name: 'Green Plastic',
    colorScheme: ChessboardColorScheme.greenPlastic,
  ),
  BoardThemeOption(name: 'Grey', colorScheme: ChessboardColorScheme.grey),
  BoardThemeOption(name: 'Horsey', colorScheme: ChessboardColorScheme.horsey),
  BoardThemeOption(name: 'Leather', colorScheme: ChessboardColorScheme.leather),
  BoardThemeOption(name: 'Maple', colorScheme: ChessboardColorScheme.maple),
  BoardThemeOption(name: 'Maple 2', colorScheme: ChessboardColorScheme.maple2),
  BoardThemeOption(name: 'Marble', colorScheme: ChessboardColorScheme.marble),
  BoardThemeOption(name: 'Metal', colorScheme: ChessboardColorScheme.metal),
  BoardThemeOption(
    name: 'Newspaper',
    colorScheme: ChessboardColorScheme.newspaper,
  ),
  BoardThemeOption(name: 'Olive', colorScheme: ChessboardColorScheme.olive),
  BoardThemeOption(
    name: 'Pink Pyramid',
    colorScheme: ChessboardColorScheme.pinkPyramid,
  ),
  BoardThemeOption(name: 'Purple', colorScheme: ChessboardColorScheme.purple),
  BoardThemeOption(
    name: 'Purple Diag',
    colorScheme: ChessboardColorScheme.purpleDiag,
  ),
  BoardThemeOption(name: 'Wood', colorScheme: ChessboardColorScheme.wood),
  BoardThemeOption(name: 'Wood 2', colorScheme: ChessboardColorScheme.wood2),
  BoardThemeOption(name: 'Wood 3', colorScheme: ChessboardColorScheme.wood3),
  BoardThemeOption(name: 'Wood 4', colorScheme: ChessboardColorScheme.wood4),
];

/// Available piece sets from chessground package
const List<PieceSet> kPieceSets = PieceSet.values;

/// Get board theme by index, with fallback to brown (index 0)
BoardThemeOption getBoardThemeByIndex(int index) {
  if (index >= 0 && index < kBoardThemes.length) {
    return kBoardThemes[index];
  }
  return kBoardThemes[0]; // Default to brown
}

/// Get piece set by index, with fallback to cburnett (index 0)
PieceSet getPieceSetByIndex(int index) {
  if (index >= 0 && index < kPieceSets.length) {
    return kPieceSets[index];
  }
  return PieceSet.cburnett; // Default to cburnett
}

/// Get ChessboardColorScheme by index with our custom colors applied
/// This preserves our app's custom colors while using chessground board themes
ChessboardColorScheme getColorSchemeByIndex(int index) {
  final theme = getBoardThemeByIndex(index);
  return _applyCustomColors(theme.colorScheme);
}

/// Apply our custom colors to a color scheme
/// - lastMove: kPrimaryColor (teal)
/// - selected: kPrimaryColor (teal)
/// - validMoves: kPrimaryColor (teal)
/// - validPremoves: kPrimaryColor (teal)
ChessboardColorScheme _applyCustomColors(ChessboardColorScheme scheme) {
  return ChessboardColorScheme(
    lightSquare: scheme.lightSquare,
    darkSquare: scheme.darkSquare,
    background: scheme.background,
    whiteCoordBackground: scheme.whiteCoordBackground,
    blackCoordBackground: scheme.blackCoordBackground,
    lastMove: const HighlightDetails(solidColor: kPrimaryColor),
    selected: const HighlightDetails(solidColor: kPrimaryColor),
    validMoves: kPrimaryColor,
    validPremoves: kPrimaryColor,
  );
}

/// Get PieceAssets by index
PieceAssets getPieceAssetsByIndex(int index) {
  return getPieceSetByIndex(index).assets;
}

/// Mapping from old boardColorIndex (0-7) to new boardThemeIndex
/// This provides backwards compatibility for existing users
int migrateOldBoardColorToTheme(int oldBoardColorIndex) {
  // Old mapping:
  // 0 = default (teal) -> closest is Blue (1)
  // 1 = brown -> Brown (0)
  // 2 = grey -> Grey (9)
  // 3 = green -> Green (2)
  // 4 = orange -> Maple (12) - closest to orange
  // 5 = purple -> Purple (19)
  // 6 = blue -> Blue (1)
  // 7 = pink -> Pink Pyramid (18)
  const migrationMap = {
    0: 1, // default -> Blue
    1: 0, // brown -> Brown
    2: 9, // grey -> Grey
    3: 2, // green -> Green
    4: 12, // orange -> Maple
    5: 19, // purple -> Purple
    6: 1, // blue -> Blue
    7: 18, // pink -> Pink Pyramid
  };
  return migrationMap[oldBoardColorIndex] ?? 0;
}
