import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_grouped_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  test('loaded games bypass shimmer while round metadata is still loading', () {
    final resolution = resolveGamesTourRounds(
      gamesAppBar: const AsyncValue<GamesAppBarViewModel>.loading(),
      rawGames: <Games>[_rawGame()],
    );

    expect(resolution.isLoading, isFalse);
    expect(resolution.rounds.map((round) => round.id), ['round-1']);
  });

  test('game evidence fills a missing canonical round start while live', () {
    final detectedMoveTime = DateTime.utc(2026, 7, 16, 20, 29);
    const canonicalRound = GamesAppBarModel(
      id: 'round-1',
      name: 'Round One',
      startsAt: null,
      roundStatus: RoundStatus.live,
    );

    final resolution = resolveGamesTourRounds(
      gamesAppBar: const AsyncValue.data(
        GamesAppBarViewModel(
          gamesAppBarModels: <GamesAppBarModel>[canonicalRound],
          selectedId: 'round-1',
          userSelectedId: false,
        ),
      ),
      rawGames: <Games>[_rawGame(lastMoveTime: detectedMoveTime)],
    );

    expect(resolution.isLoading, isFalse);
    expect(resolution.rounds.single.id, canonicalRound.id);
    expect(resolution.rounds.single.name, canonicalRound.name);
    expect(resolution.rounds.single.roundStatus, canonicalRound.roundStatus);
    expect(resolution.rounds.single.startsAt, detectedMoveTime);
  });

  test('canonical round start remains authoritative over game evidence', () {
    final canonicalStart = DateTime.utc(2026, 7, 16, 20, 27);
    final detectedMoveTime = DateTime.utc(2026, 7, 16, 20, 29);
    final canonicalRound = GamesAppBarModel(
      id: 'round-1',
      name: 'Round One',
      startsAt: canonicalStart,
      roundStatus: RoundStatus.live,
    );

    final resolution = resolveGamesTourRounds(
      gamesAppBar: AsyncValue.data(
        GamesAppBarViewModel(
          gamesAppBarModels: <GamesAppBarModel>[canonicalRound],
          selectedId: 'round-1',
          userSelectedId: false,
        ),
      ),
      rawGames: <Games>[_rawGame(lastMoveTime: detectedMoveTime)],
    );

    expect(resolution.rounds.single.startsAt, canonicalStart);
  });

  test('keeps initial shimmer when neither games nor rounds have loaded', () {
    final resolution = resolveGamesTourRounds(
      gamesAppBar: const AsyncValue<GamesAppBarViewModel>.loading(),
      rawGames: const <Games>[],
    );

    expect(resolution.isLoading, isTrue);
    expect(resolution.rounds, isEmpty);
  });

  test('formats a slug-shaped fallback round name for display', () {
    final resolution = resolveGamesTourRounds(
      gamesAppBar: const AsyncValue<GamesAppBarViewModel>.loading(),
      rawGames: <Games>[_rawGame(roundSlug: 'round-4')],
    );

    expect(resolution.rounds.single.name, 'Round 4');
  });
}

Games _rawGame({String roundSlug = 'Round 1', DateTime? lastMoveTime}) {
  return Games(
    id: 'game-1',
    roundId: 'round-1',
    roundSlug: roundSlug,
    tourId: 'loaded-tour',
    tourSlug: 'loaded-tour',
    status: '*',
    lastMove: 'e2e4',
    lastMoveTime: lastMoveTime,
    fen: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2',
    players: <Player>[
      Player(
        name: 'White Player',
        title: 'GM',
        rating: 2500,
        fideId: 1,
        fed: 'USA',
        clock: 6000,
        team: '',
      ),
      Player(
        name: 'Black Player',
        title: 'IM',
        rating: 2450,
        fideId: 2,
        fed: 'USA',
        clock: 6000,
        team: '',
      ),
    ],
  );
}
