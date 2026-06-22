import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/utils/chess_title_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Adapts a gamebase-only event (no broadcast page in our Supabase) into the
/// Supabase-shaped models the real [TournamentDetailScreen] consumes, so a
/// gamebase event tap opens the SAME view as a broadcasted event instead of a
/// bespoke screen.
///
/// Everything is keyed by a sentinel `gamebase::<eventName>` id. Every consumer
/// branch is guarded by [isVirtualGamebaseId], so real tournaments take their
/// exact existing code path (zero behaviour change).

const String _virtualPrefix = 'gamebase::';

String virtualBroadcastId(String eventName) => '$_virtualPrefix${eventName.trim()}';

bool isVirtualGamebaseId(String? id) =>
    id != null && id.startsWith(_virtualPrefix);

String? eventNameFromVirtualId(String? id) =>
    isVirtualGamebaseId(id) ? id!.substring(_virtualPrefix.length) : null;

/// Synthesized event view for an exact gamebase event [name]. Cached one week
/// server-side; the client just renders. Shared by the virtual tour/games
/// adapters and [DatabaseEventScreen].
final gamebaseEventViewProvider = FutureProvider.autoDispose
    .family<GamebaseEventView?, String>((ref, eventName) async {
  return ref.read(gamebaseRepositoryProvider).getEventView(eventName);
});

/// Minimal synthetic broadcast to drive [selectedBroadcastModelProvider]. The
/// real data is loaded lazily by the tour/games notifiers via the sentinel id.
GroupBroadcast virtualGroupBroadcastForEvent(String eventName) {
  final clean = eventName.trim();
  return GroupBroadcast(
    id: virtualBroadcastId(clean),
    createdAt: DateTime.now(),
    name: clean,
    search: [clean],
  );
}

/// One synthetic [Tour] representing the whole gamebase event.
List<Tour> virtualToursFromView(GamebaseEventView view) {
  final about = view.about;
  return [
    Tour.virtual(
      id: virtualBroadcastId(view.event),
      name: view.event,
      slug: view.event,
      // Render as a standard tournament (player standings + game list). We do
      // NOT emit team/knockout format tokens here: team events route to a
      // different screen and knockout brackets need broadcast-shaped round
      // structure — both are out of scope for the synthesized view.
      format: about.roundCount > 0 ? '${about.roundCount}-round event' : null,
      timeControl: about.timeControl,
      location: about.site,
      dates: [
        if (about.startDate != null) about.startDate!,
        if (about.endDate != null) about.endDate!,
      ],
      players: _virtualPlayers(view),
      avgElo: about.avgElo,
    ),
  ];
}

/// Pre-ranked standings → [TournamentPlayer]s. Because every entry carries a
/// [TournamentPlayer.rank], the standings screen trusts this order verbatim.
List<TournamentPlayer> _virtualPlayers(GamebaseEventView view) {
  return view.standings.players
      .map(
        (p) => TournamentPlayer(
          name: p.name ?? 'Unknown',
          federation: p.fed,
          title: ChessTitleUtils.normalize((p.title ?? '').trim()),
          fideId: int.tryParse(p.fideId ?? ''),
          played: p.played,
          rating: p.elo,
          score: p.points,
          rank: p.rank,
        ),
      )
      .toList(growable: false);
}

/// All games of the event as Supabase-shaped [Games], in round order. The PGN
/// is header-only on purpose — the board re-fetches the full game by [id]
/// (gamebase UUID) on tap, which works because [GamesTourModel.fromGame] tags
/// these with `GameSource.gamebase` (sentinel-guarded).
List<Games> virtualGamesFromView(GamebaseEventView view) {
  final tourId = virtualBroadcastId(view.event);
  final out = <Games>[];
  var seq = 0;
  for (final round in view.rounds) {
    for (final g in round.games) {
      seq++;
      final whiteName = (g.white.name ?? '').trim().isEmpty
          ? 'White'
          : g.white.name!.trim();
      final blackName = (g.black.name ?? '').trim().isEmpty
          ? 'Black'
          : g.black.name!.trim();
      out.add(
        Games(
          id: g.id,
          roundId: '$tourId::r::${round.label}',
          roundSlug: round.displayLabel,
          tourId: tourId,
          tourSlug: view.event,
          players: [
            _player(g.white, fallbackName: whiteName),
            _player(g.black, fallbackName: blackName),
          ],
          status: g.result, // "1-0" | "0-1" | "1/2-1/2" | "*"
          pgn: buildHeaderOnlyPgn(
            whiteName: whiteName,
            blackName: blackName,
            result: g.result,
            event: view.event,
            site: view.site,
            date: g.date,
            eco: g.eco,
            opening: g.opening,
          ),
          boardNr: g.board ?? seq,
          dateStart: g.date,
          lastMoveTime: g.date,
          eco: g.eco,
          openingName: g.opening,
          timeControl: view.about.timeControl,
          avgElo: view.about.avgElo,
        ),
      );
    }
  }
  return out;
}

Player _player(GamebaseEventPlayerRef ref, {required String fallbackName}) {
  return Player(
    name: fallbackName,
    title: ChessTitleUtils.normalize((ref.title ?? '').trim()),
    rating: ref.elo ?? 0,
    fideId: int.tryParse(ref.fideId ?? '') ?? 0,
    fed: ref.fed ?? '',
    clock: 0,
    team: ref.team ?? '',
  );
}
