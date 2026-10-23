import 'package:flutter/cupertino.dart';
import '../../repository/supabase/game/games.dart';
import '../core/watch_models.dart';
import '../core/watch_repository.dart';
import '../watch_controller.dart';
import 'watch_game_page.dart';
import 'watch_widgets.dart';

Widget watchEventPage(WatchController controller, WatchEvent event) =>
    WatchDataPage<WatchTour>(
      title: event.name,
      load: (_) => controller.repository.tours(event.id),
      empty: 'Sections have not been published yet.',
      items: (context, tours) => [
        for (final tour in tours)
          WatchRow(
            label: tour.name,
            detail: '${tour.players.length} players',
            onTap: () => watchPush(context, watchTourPage(controller, tour)),
          ),
      ],
    );

Widget watchTourPage(
  WatchController controller,
  WatchTour tour,
) => WatchDataPage<WatchRound>(
  title: tour.name,
  load: (_) => controller.repository.rounds(tour.id),
  items: (context, rounds) => [
    WatchRow(
      label: 'Players & scores',
      icon: CupertinoIcons.person_2,
      onTap: () => watchPush(context, watchStandingsPage(controller, tour)),
    ),
    const WatchNote('Rounds'),
    // Latest scheduled/played rounds first on a small display. The canonical
    // source order is retained for scorecards below.
    for (final round in rounds.reversed)
      WatchRow(
        label: round.name,
        detail: round.startsAt == null ? null : _roundDate(round.startsAt!),
        onTap: () =>
            watchPush(context, watchRoundPage(controller, tour, round)),
      ),
  ],
);

String _roundDate(DateTime date) {
  final local = date.toLocal();
  return '${local.day}/${local.month} · '
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

Widget watchRoundPage(
  WatchController controller,
  WatchTour tour,
  WatchRound round,
) => WatchDataPage<Games>(
  title: round.name,
  pageSize: WatchRepository.pageSize,
  load: (offset) => controller.repository.games(round.id, offset: offset),
  empty: 'Pairings have not been published yet.',
  items: (context, games) => [
    for (final game in games)
      WatchRow(
        label: _pairing(game),
        detail: 'Board ${game.boardNr ?? '—'} · ${watchResult(game.status)}',
        onTap: () => watchPush(
          context,
          WatchGamePage(controller: controller, game: game, tour: tour),
        ),
      ),
  ],
);

String _pairing(Games game) => game.players == null || game.players!.length < 2
    ? game.name ?? 'Game'
    : '${game.players![0].name}\n${game.players![1].name}';

Widget watchStandingsPage(WatchController controller, WatchTour initialTour) =>
    _StandingsPage(controller: controller, tour: initialTour);

class _StandingsPage extends StatefulWidget {
  const _StandingsPage({required this.controller, required this.tour});
  final WatchController controller;
  final WatchTour tour;
  @override
  State<_StandingsPage> createState() => _StandingsPageState();
}

class _StandingsPageState extends State<_StandingsPage> {
  bool _following = false;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => _standingsContent(
      widget.controller,
      widget.tour,
      _following && widget.controller.account.signedIn,
      () => setState(() => _following = !_following),
    ),
  );
}

Widget _standingsContent(
  WatchController controller,
  WatchTour initialTour,
  bool following,
  VoidCallback toggle,
) => WatchDataPage<WatchTour>(
  title: 'Players & scores',
  load: (_) async {
    final tours = await controller.repository.tours(initialTour.eventId);
    return tours.where((t) => t.id == initialTour.id).toList();
  },
  items: (context, tours) => [
    if (controller.account.signedIn)
      WatchRow(
        label: following ? 'Show all players' : 'Show followed players',
        onTap: toggle,
      ),
    for (final tour in tours) ...[
      if (following &&
          !tour.players.any(
            (p) => controller.account.followsPlayer(p.fideId, p.name),
          ))
        const WatchNote('No followed players in this section.'),
      if (tour.players.isEmpty)
        const WatchNote('Standings have not been published yet.'),
      for (final player in tour.standings.where(
        (p) => !following || controller.account.followsPlayer(p.fideId, p.name),
      ))
        WatchRow(
          label: player.name,
          detail: [
            if (player.rank != null) '#${player.rank}',
            if (player.title.isNotEmpty) player.title,
            if (player.rating != null) '${player.rating}',
            if (player.score != null)
              '${watchScore(player.score)} / ${player.played}',
          ].join(' · '),
          trailing: controller.account.followsPlayer(player.fideId, player.name)
              ? const Icon(
                  CupertinoIcons.star_fill,
                  semanticLabel: 'Followed on iPhone',
                  size: 14,
                  color: WatchStyle.ink,
                )
              : null,
          onTap: () =>
              watchPush(context, watchScorecardPage(controller, tour, player)),
        ),
    ],
  ],
);

class _PlayerCard {
  const _PlayerCard(this.tour, this.player, this.games);
  final WatchTour tour;
  final WatchStanding player;
  final List<Games> games;
}

Widget watchScorecardPage(
  WatchController controller,
  WatchTour tour,
  WatchStanding player,
) => WatchDataPage<_PlayerCard>(
  title: player.name,
  load: (_) async {
    final tours = await controller.repository.tours(tour.eventId);
    final currentTour = tours.where((t) => t.id == tour.id).firstOrNull ?? tour;
    final currentPlayer =
        currentTour.players
            .where(
              (p) => player.fideId != null
                  ? p.fideId == player.fideId
                  : p.name == player.name,
            )
            .firstOrNull ??
        player;
    final games = await controller.repository.scorecard(tour.id, currentPlayer);
    return [_PlayerCard(currentTour, currentPlayer, games)];
  },
  items: (context, cards) => [
    for (final card in cards) ...[
      Semantics(
        label:
            'Published score ${watchScore(card.player.score)} '
            'from ${card.player.played} games',
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            card.player.score == null
                ? 'Score unavailable'
                : '${watchScore(card.player.score)} / ${card.player.played}',
            style: const TextStyle(
              fontSize: 32,
              color: WatchStyle.ink,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ),
      ),
      if (card.player.rank != null)
        WatchNote('Published rank ${card.player.rank}'),
      if (card.player.performance != null || card.player.ratingDiff != null)
        WatchNote(
          [
            if (card.player.performance != null)
              'Performance ${card.player.performance}',
            if (card.player.ratingDiff != null)
              'Rating ${card.player.ratingDiff! >= 0 ? '+' : ''}${card.player.ratingDiff}',
          ].join('\n'),
        ),
      if (card.games.isEmpty)
        const WatchNote('No individual games have been published.'),
      for (final game in card.games)
        WatchRow(
          label: _opponent(game, card.player),
          detail:
              '${game.roundSlug.replaceAll('-', ' ')} · '
              '${_playerResult(game, card.player)}',
          onTap: () => watchPush(
            context,
            WatchGamePage(controller: controller, game: game, tour: card.tour),
          ),
        ),
    ],
  ],
);

String _opponent(Games game, WatchStanding player) =>
    game.players
        ?.where((p) => !watchPlayerMatches(p, player))
        .firstOrNull
        ?.name ??
    'Opponent unavailable';

String _playerResult(Games game, WatchStanding player) {
  if (watchGameIsLive(game)) return 'Live';
  final white = game.players?.firstOrNull;
  final isWhite = white != null && watchPlayerMatches(white, player);
  return switch (game.status) {
    '1-0' => isWhite ? 'Win · White' : 'Loss · Black',
    '0-1' => isWhite ? 'Loss · White' : 'Win · Black',
    '1/2-1/2' => 'Draw · ${isWhite ? 'White' : 'Black'}',
    _ => 'Scheduled',
  };
}
