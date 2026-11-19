import 'package:chessever2/widgets/ink_fab.dart';
import 'package:flutter/material.dart';

/// The floating search over a list tab that floats nothing else (Favorites'
/// own list and Rankings, Countrymen's Events and Rankings, a database):
/// the same [SearchInkFab] the Games tabs float, searching the list in view.
abstract final class TabSearchFab {
  /// How far up from the bottom the lone search button reaches: its disc,
  /// lifted by the Scaffold's margin and the home indicator's inset. A list
  /// under it ends this far clear (`SearchModeListEnd`), so the button never
  /// covers its last row. Read it from the list's context: inside the button
  /// slot the Scaffold has already taken the inset away.
  static double reach(BuildContext context) =>
      InkFabSize.regular.side +
      kFloatingActionButtonMargin +
      MediaQuery.viewPaddingOf(context).bottom;
}
