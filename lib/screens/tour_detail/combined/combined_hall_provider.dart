import 'package:chessever2/screens/tour_detail/games_tour/providers/games_priority_matching.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/repository/supabase/round/round_repository.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'combined_hall_loader.dart';

final combinedHallProvider = StateNotifierProvider.autoDispose
    .family<CombinedHall, int, String>((ref, ids) => CombinedHall(ref, ids));

/// One hall owns its requests and parsed board cache. Lifecycle suspension also
/// covers a hidden browser tab; responses from a previous epoch are ignored.
class CombinedHall extends StateNotifier<int> with WidgetsBindingObserver {
  CombinedHall(
    Ref ref,
    String ids, {
    Future<List<Round>> Function(String)? readSource,
    Future<List<Games>> Function(Round, int, int)? readPage,
    Duration backgroundDelay = const Duration(milliseconds: 120),
    Duration publishDelay = const Duration(milliseconds: 200),
  }) : super(0) {
    loader = CombinedHallLoader<Round, Games>(
      sourceIds: ids.split(',').where((id) => id.isNotEmpty).toList(),
      readSource:
          readSource ?? ref.read(roundRepositoryProvider).getRoundsByTourId,
      backgroundDelay: backgroundDelay,
      publishDelay: publishDelay,
      readPage:
          readPage ??
          (r, offset, limit) => ref
              .read(gameRepositoryProvider)
              .getCombinedRoundGamesPage(
                r.tourId,
                r.id,
                offset: offset,
                limit: limit,
              ),
      roundId: (r) => r.id,
      sourceId: (r) => r.tourId,
      validGame: (r, g) => g.tourId == r.tourId && g.roundId == r.id,
      finished: (g) => GameStatus.fromString(g.status).isFinished,
      orderRounds: (rounds) {
        final now = DateTime.now();
        return List<Round>.of(rounds)..sort((a, b) {
          final x = a.startsAt ?? a.createdAt, y = b.startsAt ?? b.createdAt;
          final xf = x.isAfter(now), yf = y.isAfter(now);
          if (xf != yf) return xf ? 1 : -1;
          return xf ? x.compareTo(y) : y.compareTo(x);
        });
      },
      onChange: () {
        if (mounted) state++;
      },
    );
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    loader.setActive(_foreground);
  }
  late final CombinedHallLoader<Round, Games> loader;
  String? initiallyExpandedRoundId;
  bool _foreground = true, _visible = true;
  final Map<String, int> _visibleRounds = {};
  void mountRound(String id, int delta) {
    final count = (_visibleRounds[id] ?? 0) + delta;
    if (count <= 0) {
      _visibleRounds.remove(id);
    } else {
      _visibleRounds[id] = count;
    }
    loader.watch(_visibleRounds.keys);
  }

  final Map<String, (Games, GamesTourModel)> _models = {};
  void setVisible(bool value) {
    _visible = value;
    loader.setActive(_visible && _foreground);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    loader.setActive(_visible && _foreground);
  }

  Map<String, List<GamesTourModel>> get gamesByTour {
    final result = <String, List<GamesTourModel>>{};
    final retained = <String>{};
    for (final rows in loader.games.values) {
      for (final game in rows) {
        retained.add(game.id);
        try {
          final prior = _models[game.id];
          final model = prior != null && _hasSameListInputs(prior.$1, game)
              ? prior.$2
              : GamesTourModel.fromGameIndex(game);
          _models[game.id] = (game, model);
          (result[game.tourId] ??= []).add(model);
        } catch (_) {
          /* A malformed pairing must not hide its source round. */
        }
      }
    }
    _models.removeWhere((id, _) => !retained.contains(id));
    return result;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    loader.dispose();
    super.dispose();
  }
}

bool _hasSameListInputs(Games a, Games b) {
  if (identical(a, b)) return true;
  return a.id == b.id &&
      a.roundId == b.roundId &&
      a.roundSlug == b.roundSlug &&
      a.status == b.status &&
      a.boardNr == b.boardNr &&
      a.lastMove == b.lastMove &&
      a.fen == b.fen &&
      a.isPgnDeferred == b.isPgnDeferred &&
      (identical(a.pgn, b.pgn) || a.pgn == b.pgn) &&
      haveSameRawGamePriorityInputs(a, b);
}
