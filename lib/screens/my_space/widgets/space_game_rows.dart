import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/live_game_card_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// One side of a game exactly as the app's game card draws it: the card's
/// own row ([PlayerFirstRowDetailWidget]), with its result, flag, title,
/// name, rating and clock, untouched.
///
/// Inside My Space the row never takes a touch. The tile or sheet row around
/// it owns tap, hold and drag, and the card's name tap (the scorecard) must
/// not steal them. It is also silent to a screen reader: read piecemeal, its
/// result digits and clocks land apart from the names they belong to, so the
/// tile or sheet row around it speaks for the game.
///
/// A live game streams its clock, result and status the way the card does,
/// over [liveBatchKey] when the caller shares one across its live games, or
/// otherwise over the game's own key (both sides of a game share it).
class SpaceGamePlayerRow extends StatelessWidget {
  const SpaceGamePlayerRow({
    super.key,
    required this.game,
    required this.white,
    required this.view,
    this.showClock,
    this.liveBatchKey,
  });

  final GamesTourModel game;
  final bool white;
  final PlayerView view;

  /// Null shows the clock wherever the card does (once the game started).
  final bool? showClock;

  /// The realtime batch this game streams in; null uses [spaceLiveBatchKey].
  final LiveGamesBatchKey? liveBatchKey;

  @override
  Widget build(BuildContext context) {
    final side = white ? Side.white : Side.black;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: PlayerFirstRowDetailWidget(
          gamesTourModel: game,
          isWhitePlayer: white,
          isCurrentPlayer: game.activePlayer == side,
          playerView: view,
          showClock: showClock ?? game.hasStarted,
          liveBatchKey: liveBatchKey ?? spaceLiveBatchKey(game),
          playerProfileDataSource: game.source == GameSource.supabase
              ? PlayerProfileDataSource.supabase
              : PlayerProfileDataSource.twic,
          nameMenu: false,
        ),
      ),
    );
  }
}

/// A grid game row held in place while its game is looked up: the card's
/// row for a finished game, which is what most pins are (the result lane,
/// the flag's slot, the name at the card's own size), so the card's row
/// lands over it with nothing moving. While [loading] the flag's slot is a
/// faint block; after a miss it stays empty and the pinned [name] is all
/// the row has to say.
///
/// Mirrors [PlayerFirstRowDetailWidget] in grid view: the 16 x 12 flag, the
/// 4pt gap after it, and the name's unscaled 8pt style. Keep them in step.
class SpaceGamePlayerRowStandIn extends StatelessWidget {
  const SpaceGamePlayerRowStandIn({
    super.key,
    required this.name,
    required this.loading,
  });

  final String name;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ExcludeSemantics(
      child: Row(
        children: [
          SizedBox(width: spacePlayerRowFullLead(PlayerView.gridView)),
          SizedBox(
            key: const ValueKey('space-row-flag-slot'),
            width: 16.w,
            height: 12.h,
            child: loading
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.textPrimary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(2.br),
                    ),
                  )
                : null,
          ),
          SizedBox(width: 4.w),
          Expanded(
            // RichText, like the card's name: no theme font, no text scaling.
            child: RichText(
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                text: name,
                style: TextStyle(
                  fontSize: 8.f,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                  height: 1.15,
                  letterSpacing: -0.15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The realtime batch a lone My Space game streams in, or null for a game
/// with nothing live to stream. Value-equal across calls, so the tile's two
/// rows (and its board, if it watches [watchLiveGamePosition] with it) share
/// one channel.
LiveGamesBatchKey? spaceLiveBatchKey(GamesTourModel game) =>
    liveContextBatchKeyForGame(
      game: game,
      contextGames: [game],
      scopePrefix: 'my_space',
    );

/// How far a [PlayerFirstRowDetailWidget] row sets its flag in from its own
/// start (past the board-view margin): the result / eval lane, and the gap
/// after a result.
///
/// Mirrors the row's `engineGaugeWidth` and `revealSpoilers` rules
/// (player_first_row_detail_widget.dart); keep the two in step. My Space
/// reads it to line a row up with its board, and a sheet's event line with
/// the names.
double spacePlayerRowLead(WidgetRef ref, GamesTourModel game, PlayerView view) {
  final broadcast = game.source == GameSource.supabase;
  final spoilers = broadcast
      ? ref.watch(eventNoSpoilersProvider(game.tourId))
      : null;
  final hideEvaluation =
      spoilers != null &&
      shouldHideEventEvaluation(isBroadcastGame: true, spoilerState: spoilers);
  final finished = game.gameStatus.isFinished;
  final revealedHere = broadcast && finished
      ? ref.watch(
          eventNoSpoilersRevealedGamesProvider.select(
            (ids) => ids.contains(game.gameId),
          ),
        )
      : false;
  final reveal =
      !broadcast ||
      !finished ||
      revealedHere ||
      (spoilers != null && !spoilers.isLoading && !spoilers.enabled);

  final grid = view == PlayerView.gridView;
  final lane = grid ? 10.w : 20.w;
  final resultGap = grid ? 4.w : (view == PlayerView.listView ? 5.w : 6.w);
  if (finished && reveal) return lane + resultGap;

  final settings = ref.watch(engineSettingsProviderNew).valueOrNull;
  final gauge = view == PlayerView.boardView
      ? (settings?.shouldShowEngineGaugeOnBoard ?? true) &&
            (settings?.showEngineAnalysis ?? true)
      : settings?.shouldShowEngineGaugeInGrid ?? true;
  final evaluating =
      gauge && !hideEvaluation && game.hasStarted && game.gameStatus.isOngoing;
  return evaluating ? lane : 0;
}

/// The widest [spacePlayerRowLead] a row of [view] can have: its lane plus
/// the gap after a result. A list of games insets the rows that lead with
/// less, so every flag and name lines up down the list.
double spacePlayerRowFullLead(PlayerView view) => switch (view) {
  PlayerView.gridView => 10.w + 4.w,
  PlayerView.listView => 20.w + 5.w,
  PlayerView.boardView => 20.w + 6.w,
};

/// Whether the card's mini board hides a finished game's ending (the fallen
/// king, the draw marks): No Spoilers is on for its event, or still being
/// read. Mirrors the grid card's `_hideFinishedSpoilers`
/// (chess_board_from_fen_new.dart).
bool spaceBoardHidesEnding(WidgetRef ref, GamesTourModel game) {
  if (!game.gameStatus.isFinished) return false;
  if (game.source != GameSource.supabase) return false;
  final spoilers = ref.watch(eventNoSpoilersProvider(game.tourId));
  return spoilers.isLoading || spoilers.enabled;
}
