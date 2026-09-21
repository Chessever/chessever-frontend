import 'dart:collection';

import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';

/// A read-only navigation snapshot over an immutable list from widget/provider
/// state. Updating visible boards costs O(visible boards), not O(event size).
/// The backing list must be replaced, never mutated, just like provider state.
class GameListSnapshot extends ListBase<GamesTourModel> {
  GameListSnapshot(this._games, {Map<int, GamesTourModel> updates = const {}})
    : _updates = Map.unmodifiable(updates);

  final List<GamesTourModel> _games;
  final Map<int, GamesTourModel> _updates;

  @override
  int get length => _games.length;

  @override
  GamesTourModel operator [](int index) {
    RangeError.checkValidIndex(index, this);
    return _updates[index] ?? _games[index];
  }

  @override
  set length(int value) => throw UnsupportedError('Read-only game snapshot');

  @override
  void operator []=(int index, GamesTourModel value) =>
      throw UnsupportedError('Read-only game snapshot');
}

/// Route-owned cache. Board moves change a handful of visible rows, while the
/// tournament catalog usually remains identical. Merge that catalog only when
/// either source list is replaced, keeping the launch list's order/membership.
class BoardGameListCache {
  List<GamesTourModel>? _originals;
  List<GamesTourModel>? _updates;
  List<GamesTourModel>? _merged;

  List<GamesTourModel> merge(
    List<GamesTourModel> originals,
    List<GamesTourModel> updates,
  ) {
    if (identical(_originals, originals) && identical(_updates, updates)) {
      return _merged!;
    }
    _originals = originals;
    _updates = updates;
    if (identical(originals, updates)) return _merged = originals;
    final byId = {for (final game in updates) game.gameId: game};
    return _merged = [for (final game in originals) byId[game.gameId] ?? game];
  }
}
