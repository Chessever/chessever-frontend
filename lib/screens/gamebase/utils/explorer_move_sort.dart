import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:dartchess/dartchess.dart';

/// Column the opening-explorer move table can be ordered by.
enum ExplorerMoveSortField { move, score, games, last }

enum ExplorerResultSortSide { white, black }

class ExplorerMoveSort {
  const ExplorerMoveSort({
    required this.field,
    required this.ascending,
    this.resultSide,
  });

  final ExplorerMoveSortField field;
  final bool ascending;
  final ExplorerResultSortSide? resultSide;

  /// Header tap cycle retained for legacy callers that still expose direction.
  static ExplorerMoveSort? cycle(
    ExplorerMoveSort? current,
    ExplorerMoveSortField field,
  ) {
    if (current == null || current.field != field) {
      return ExplorerMoveSort(field: field, ascending: true);
    }
    if (current.ascending) {
      return ExplorerMoveSort(field: field, ascending: false);
    }
    return null;
  }
}

/// Explorer headers use one predictable, useful direction per column so the
/// active column can be shown without ambiguous arrow glyphs.
ExplorerMoveSort defaultExplorerMoveSort(ExplorerMoveSortField field) {
  return ExplorerMoveSort(
    field: field,
    ascending: field == ExplorerMoveSortField.move,
    resultSide:
        field == ExplorerMoveSortField.score
            ? ExplorerResultSortSide.white
            : null,
  );
}

ExplorerMoveSort nextExplorerMoveSort(
  ExplorerMoveSort current,
  ExplorerMoveSortField field,
) {
  if (field != ExplorerMoveSortField.score) {
    return defaultExplorerMoveSort(field);
  }
  final side =
      current.field == ExplorerMoveSortField.score &&
              current.resultSide == ExplorerResultSortSide.white
          ? ExplorerResultSortSide.black
          : ExplorerResultSortSide.white;
  return ExplorerMoveSort(
    field: ExplorerMoveSortField.score,
    ascending: false,
    resultSide: side,
  );
}

/// Orders [aggs] for display. A null [sort] keeps the backend order (most
/// played first), which is what the table shows until the user picks a column.
///
/// Shared shape with the desktop explorer so a position sorted by SCORE there
/// lists in the same order on mobile — including the tie-break on total games.
/// [fen] is only needed to render SAN for the move-name ordering.
List<MoveAggregate> applyExplorerMoveSort(
  List<MoveAggregate> aggs,
  ExplorerMoveSort? sort,
  String fen,
) {
  if (sort == null || aggs.length < 2) return aggs;

  final sanCache = <String, String>{};
  String sanFor(MoveAggregate a) {
    return sanCache.putIfAbsent(a.uci, () {
      try {
        final position = Chess.fromSetup(
          Setup.parseFen(fen),
          ignoreImpossibleCheck: true,
        );
        final move = Move.parse(a.uci);
        if (move == null) return a.uci;
        return position.makeSan(move).$2;
      } catch (_) {
        return a.uci;
      }
    });
  }

  double resultRateFor(MoveAggregate a) {
    if (a.total <= 0) return 0;
    return (sort.resultSide == ExplorerResultSortSide.black
            ? a.black
            : a.white) /
        a.total;
  }

  int cmp(MoveAggregate a, MoveAggregate b) {
    final int c;
    switch (sort.field) {
      case ExplorerMoveSortField.move:
        c = sanFor(a).toLowerCase().compareTo(sanFor(b).toLowerCase());
        break;
      case ExplorerMoveSortField.score:
        c = resultRateFor(a).compareTo(resultRateFor(b));
        break;
      case ExplorerMoveSortField.games:
        c = a.total.compareTo(b.total);
        break;
      case ExplorerMoveSortField.last:
        final ta = a.lastPlayed?.millisecondsSinceEpoch ?? -1;
        final tb = b.lastPlayed?.millisecondsSinceEpoch ?? -1;
        c = ta.compareTo(tb);
        break;
    }
    // Stable, meaningful tie-break: more played first.
    if (c == 0) return b.total.compareTo(a.total);
    return sort.ascending ? c : -c;
  }

  return List<MoveAggregate>.of(aggs)..sort(cmp);
}
