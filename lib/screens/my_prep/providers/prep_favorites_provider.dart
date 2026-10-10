import 'dart:async';

import 'package:chessever2/repository/supabase/chess_player/chess_player_repository.dart';
import 'package:chessever2/screens/favorites/rankings/ranking_filters.dart';
import 'package:chessever2/screens/my_prep/data/prep_favorites.dart';
import 'package:chessever2/utils/transient_request_retry.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The Favorites tab's suggestions: the FIDE ranking the Favorites Players
/// tab reads, a page at a time. Every one of them is a ChessEver source.
@immutable
class PrepRankedPlayers {
  const PrepRankedPlayers({
    this.players = const [],
    this.query = '',
    this.loading = true,
    this.hasMore = true,
    this.failed = false,
  });

  final List<ChessPlayer> players;
  final String query;
  final bool loading;
  final bool hasMore;
  final bool failed;
}

final prepRankedPlayersProvider =
    StateNotifierProvider.autoDispose<
      PrepRankedPlayersNotifier,
      PrepRankedPlayers
    >((ref) => PrepRankedPlayersNotifier(ref));

class PrepRankedPlayersNotifier extends StateNotifier<PrepRankedPlayers> {
  PrepRankedPlayersNotifier(this._ref) : super(const PrepRankedPlayers()) {
    _load(reset: true);
  }

  final Ref _ref;
  static const _pageSize = 40;
  int _generation = 0;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void search(String text) {
    final query = text.trim();
    if (query == state.query) return;
    _generation++;
    _debounce?.cancel();
    state = PrepRankedPlayers(query: query);
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _load(reset: true),
    );
  }

  void loadMore() {
    if (state.loading || !state.hasMore || state.failed) return;
    _load(reset: false);
  }

  void retry() => _load(reset: state.players.isEmpty);

  Future<void> _load({required bool reset}) async {
    final generation = _generation;
    final query = state.query;
    final current = reset ? const <ChessPlayer>[] : state.players;
    state = PrepRankedPlayers(players: current, query: query);
    try {
      final repo = _ref.read(chessPlayerRepositoryProvider);
      final page = await retryTransientRead(
        () => repo.getRankedPlayers(
          // A search also reaches retired players; the list itself is the
          // active ranking.
          filters: query.isEmpty
              ? RankingFilters.defaults
              : RankingFilters.defaults.copyWith(activity: RankingActivity.all),
          searchQuery: query,
          limit: _pageSize,
          offset: reset ? 0 : _serverOffset,
        ),
      );
      // A handle (`DrNykterstein`) finds its player too.
      final byHandle = reset && query.isNotEmpty
          ? await repo.getPlayersByFideIds([
              for (final f in kPrepFavorites)
                if (f.matches(query)) ?int.tryParse(f.fideId),
            ])
          : const <int, ChessPlayer>{};
      if (!mounted || generation != _generation) return;
      final seen = <int>{};
      state = PrepRankedPlayers(
        players: [
          for (final player in [...current, ...byHandle.values, ...page])
            if (seen.add(player.fideid)) player,
        ],
        query: query,
        loading: false,
        hasMore: page.length == _pageSize,
      );
      _serverOffset = (reset ? 0 : _serverOffset) + page.length;
    } catch (_) {
      if (!mounted || generation != _generation) return;
      state = PrepRankedPlayers(
        players: current,
        query: query,
        loading: false,
        failed: true,
      );
    }
  }

  /// Rows already read from the ranking. Handle matches are extra, so the
  /// list's length is not the offset.
  int _serverOffset = 0;
}
