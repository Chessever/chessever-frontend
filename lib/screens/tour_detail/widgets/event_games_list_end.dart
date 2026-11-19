import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart';
import 'package:flutter/material.dart';

/// Where an event's Games list ends, as its last row (the board list, the
/// team matchup list and Combined alike): clear of the home indicator, and
/// of the floating buttons over the list while they float.
///
/// That room is the shared [SearchModeListEnd]: it gives way on the search
/// mode's own timeline as the Games search opens (the buttons step away
/// with it) and grows back as it closes, so a reader at the very end of the
/// list sees it settle with the morph instead of jumping by the buttons'
/// height, as on every other Games list.
class EventGamesListEnd extends StatelessWidget {
  const EventGamesListEnd({super.key});

  /// Between the list's last row and the bottom edge whatever floats: the
  /// list's own margin.
  static double get margin => 8.sp;

  /// How far up from the screen's bottom edge the Games tab's floating
  /// buttons reach: the search disc, the Live first capsule above it (the
  /// stack's 12pt step between), lifted by the Scaffold's margin and the
  /// home indicator's inset. Live first counts whether it floats or not, so
  /// the end of the list never jumps as games start and finish. Read it
  /// from the list's context: inside the button slot the Scaffold has
  /// already taken the inset away.
  static double buttonsReach(BuildContext context) =>
      InkFabSize.regular.side +
      12 +
      InkFabSize.small.side +
      kFloatingActionButtonMargin +
      MediaQuery.viewPaddingOf(context).bottom;

  @override
  Widget build(BuildContext context) {
    final indicator = MediaQuery.viewPaddingOf(context).bottom;
    return SearchModeListEnd(
      base: indicator + margin,
      buttons: buttonsReach(context) - indicator,
    );
  }
}
