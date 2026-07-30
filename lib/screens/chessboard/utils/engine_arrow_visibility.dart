import 'package:dartchess/dartchess.dart';

/// Engine arrows represent playable recommendations, so they should be hidden
/// once the displayed board position is a final checkmate.
bool shouldSuppressEngineArrowsForPosition(Position position) {
  return position.isCheckmate;
}
