import 'dart:math' as math;

import 'package:chessever2/screens/gamebase/event_view/gamebase_virtual_event.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/library/twic_contents_screen.dart';
import 'package:chessever2/screens/library/widgets/add_to_folder_sheet.dart';
import 'package:chessever2/screens/library/widgets/gamebase_search_game_card.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/location_service_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/time_utils.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Event page for events that exist only in the gamebase (no broadcast page in
/// the cloud Supabase). Reconstructs an About / Games / Standings experience
/// from the gamebase games, rendered per format (regular / team / knockout).
/// Pushed as the fallback from a player-profile event tap when no canonical
/// ChessEver event exists.
class DatabaseEventScreen extends ConsumerWidget {
  const DatabaseEventScreen({
    super.key,
    required this.eventName,
    this.site,
  });

  final String eventName;
  final String? site;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(gamebaseEventViewProvider(eventName));

    return Scaffold(
      backgroundColor: context.colors.background,
      // Only the top inset matters here — the bottom inset added a dead gap
      // under the Games list. Let the lists run to the bottom edge.
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(title: eventName),
            Expanded(
              child: async.when(
                data: (view) {
                  if (view == null) {
                    return _EmptyState(eventName: eventName);
                  }
                  return _EventTabs(view: view);
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => _ErrorState(
                  message: userFacingError(error),
                  onRetry: () =>
                      ref.invalidate(gamebaseEventViewProvider(eventName)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(4.w, 8.h, 16.w, 8.h),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              HapticFeedbackService.light();
              Navigator.of(context).pop();
            },
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: context.colors.textPrimary.withValues(alpha: 0.7),
              size: 20.ic,
            ),
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.textMdMedium.copyWith(
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventTabs extends StatelessWidget {
  const _EventTabs({required this.view});

  final GamebaseEventView view;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            labelColor: context.colors.textPrimary,
            unselectedLabelColor:
                context.colors.textPrimary.withValues(alpha: 0.5),
            indicatorColor: context.colors.textPrimary,
            labelStyle: AppTypography.textSmMedium,
            tabs: [
              const Tab(text: 'About'),
              const Tab(text: 'Games'),
              Tab(text: view.isTeam ? 'Teams' : 'Standings'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _AboutTab(view: view),
                _GamesTab(view: view),
                _StandingsTab(view: view),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- About -------------------------------------------------------------------

class _AboutTab extends StatelessWidget {
  const _AboutTab({required this.view});

  final GamebaseEventView view;

  String get _formatLabel {
    switch (view.format) {
      case 'team':
        return 'Team event';
      case 'knockout':
        return 'Knockout';
      default:
        return 'Tournament';
    }
  }

  @override
  Widget build(BuildContext context) {
    final about = view.about;
    final rows = <(String, String)>[
      ('Format', _formatLabel),
      if (about.startDate != null)
        ('Dates', TimeUtils.formatDateRange(about.startDate, about.endDate)),
      ('Games', '${about.gameCount}${view.truncated ? '+' : ''}'),
      ('Players', '${about.playerCount}'),
      if (about.teamCount != null) ('Teams', '${about.teamCount}'),
      if (about.roundCount > 0) ('Rounds', '${about.roundCount}'),
      if (about.avgElo != null) ('Avg rating', '${about.avgElo}'),
      if (about.maxElo != null) ('Top rating', '${about.maxElo}'),
      if (about.timeControl != null)
        ('Time control', _titleCase(about.timeControl!)),
      if ((about.site ?? '').isNotEmpty) ('Location', about.site!),
    ];

    return ListView(
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 24.h),
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(12.br),
          ),
          child: Column(
            children: [
              for (final row in rows) _AboutRow(label: row.$1, value: row.$2),
            ],
          ),
        ),
        if (view.truncated) ...[
          SizedBox(height: 12.h),
          Text(
            'This event is very large — only the most recent games are shown.',
            style: AppTypography.textXsRegular.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.5),
            ),
          ),
        ],
      ],
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110.w,
            child: Text(
              label,
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textPrimary.withValues(alpha: 0.5),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTypography.textSmMedium.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Games (format-aware, render-paginated) ----------------------------------

/// A single rendered row of the Games tab. Either a round header, a
/// team/knockout match header, or one game (referenced by its global index in
/// [_GamesTabState._orderedGames]).
class _GamesRow {
  const _GamesRow.header(this.header)
      : match = null,
        gameIndex = -1;
  const _GamesRow.match(this.match)
      : header = null,
        gameIndex = -1;
  const _GamesRow.game(this.gameIndex)
      : header = null,
        match = null;

  final String? header;
  final _MatchData? match;
  final int gameIndex;

  bool get isGame => gameIndex >= 0;
}

/// Aggregated header for a team-vs-team or player-vs-player match.
class _MatchData {
  const _MatchData({
    required this.leftLabel,
    required this.rightLabel,
    required this.leftScore,
    required this.rightScore,
    required this.isTeam,
    this.leftFed,
    this.rightFed,
  });

  final String leftLabel;
  final String rightLabel;
  final double leftScore;
  final double rightScore;
  final bool isTeam;
  final String? leftFed;
  final String? rightFed;
}

class _GamesTab extends StatefulWidget {
  const _GamesTab({required this.view});

  final GamebaseEventView view;

  @override
  State<_GamesTab> createState() => _GamesTabState();
}

class _GamesTabState extends State<_GamesTab> {
  // Reveal games in chunks so a huge event never builds thousands of cards (or
  // header-only PGNs) up front. The list grows on scroll / "Show more".
  static const int _pageSize = 60;

  final ScrollController _controller = ScrollController();

  /// Games in display order — the swipe order for the board.
  final List<GamebaseEventGame> _orderedGames = [];

  /// Header / match / game rows, computed once (no model building here).
  final List<_GamesRow> _layout = [];

  /// Lazily built, memoized board models. Index aligns with [_orderedGames].
  final List<GamesTourModel> _models = [];

  int _visibleGames = _pageSize;

  @override
  void initState() {
    super.initState();
    _buildLayout();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    if (_visibleGames >= _orderedGames.length) return;
    final pos = _controller.position;
    if (pos.pixels >= pos.maxScrollExtent - 600) {
      setState(() => _visibleGames += _pageSize);
    }
  }

  void _buildLayout() {
    final view = widget.view;
    final grouped = view.isTeam || view.isKnockout;

    for (final round in view.rounds) {
      if (round.games.isEmpty) continue;

      if (!grouped) {
        _layout.add(_GamesRow.header(round.displayLabel));
        for (final game in round.games) {
          _layout.add(_GamesRow.game(_orderedGames.length));
          _orderedGames.add(game);
        }
        continue;
      }

      _layout.add(_GamesRow.header(round.displayLabel));
      for (final group in _groupMatches(round.games, team: view.isTeam)) {
        _layout.add(_GamesRow.match(_matchData(group, team: view.isTeam)));
        for (final game in group) {
          _layout.add(_GamesRow.game(_orderedGames.length));
          _orderedGames.add(game);
        }
      }
    }
  }

  /// Group a round's games into matches: by team-pair for team events, by
  /// player-pair for knockouts. Insertion order is preserved.
  List<List<GamebaseEventGame>> _groupMatches(
    List<GamebaseEventGame> games, {
    required bool team,
  }) {
    final byKey = <String, List<GamebaseEventGame>>{};
    for (final game in games) {
      final a = team ? game.white.team : _playerKey(game.white);
      final b = team ? game.black.team : _playerKey(game.black);
      final key = ([(a ?? '').toLowerCase(), (b ?? '').toLowerCase()]..sort())
          .join('|');
      byKey.putIfAbsent(key, () => <GamebaseEventGame>[]).add(game);
    }
    return byKey.values.toList(growable: false);
  }

  String _playerKey(GamebaseEventPlayerRef p) {
    final fide = (p.fideId ?? '').trim();
    if (fide.isNotEmpty) return 'fide:$fide';
    return 'name:${(p.name ?? '').trim().toLowerCase()}';
  }

  _MatchData _matchData(List<GamebaseEventGame> group, {required bool team}) {
    final first = group.first;
    final leftId = team ? (first.white.team ?? '') : _playerKey(first.white);
    final leftLabel = team
        ? (first.white.team ?? 'Team')
        : _playerLabel(first.white);
    final rightLabel = team
        ? (first.black.team ?? 'Team')
        : _playerLabel(first.black);

    var left = 0.0;
    var right = 0.0;
    for (final g in group) {
      final (w, b) = _points(g.result);
      final whiteId = team ? (g.white.team ?? '') : _playerKey(g.white);
      if (whiteId.toLowerCase() == leftId.toLowerCase()) {
        left += w;
        right += b;
      } else {
        left += b;
        right += w;
      }
    }

    return _MatchData(
      leftLabel: leftLabel,
      rightLabel: rightLabel,
      leftScore: left,
      rightScore: right,
      isTeam: team,
      leftFed: team ? null : first.white.fed,
      rightFed: team ? null : first.black.fed,
    );
  }

  String _playerLabel(GamebaseEventPlayerRef p) {
    final title = (p.title ?? '').trim();
    final name = (p.name ?? 'Unknown').trim();
    return title.isNotEmpty ? '$title $name' : name;
  }

  /// (whitePoints, blackPoints) for a "1-0" | "0-1" | "1/2-1/2" | "*" result.
  (double, double) _points(String result) {
    switch (result) {
      case '1-0':
        return (1, 0);
      case '0-1':
        return (0, 1);
      case '1/2-1/2':
        return (0.5, 0.5);
      default:
        return (0, 0);
    }
  }

  GamesTourModel _modelFor(int index) {
    while (_models.length <= index) {
      _models.add(
        _orderedGames[_models.length].toGamesTourModel(
          eventName: widget.view.event,
          site: widget.view.site,
        ),
      );
    }
    return _models[index];
  }

  @override
  Widget build(BuildContext context) {
    if (_orderedGames.isEmpty) {
      return Center(
        child: Text(
          'No games',
          style: AppTypography.textSmRegular.copyWith(
            color: context.colors.textPrimary.withValues(alpha: 0.5),
          ),
        ),
      );
    }

    final revealed = math.min(_visibleGames, _orderedGames.length);
    // Pre-build models for revealed games so the board can swipe across them.
    _modelFor(revealed - 1);
    final allGames = _models.sublist(0, revealed);

    // Slice the layout to the revealed games; drop any trailing orphan headers.
    final rows = <_GamesRow>[];
    var shown = 0;
    for (final row in _layout) {
      if (row.isGame) {
        if (shown >= revealed) break;
        rows.add(row);
        shown++;
      } else {
        rows.add(row);
      }
    }
    while (rows.isNotEmpty && !rows.last.isGame) {
      rows.removeLast();
    }

    final hasMore = revealed < _orderedGames.length;
    final itemCount = rows.length + (hasMore ? 1 : 0);

    return ListView.builder(
      controller: _controller,
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
      itemCount: itemCount,
      itemBuilder: (context, i) {
        if (hasMore && i == rows.length) {
          return _ShowMoreButton(
            remaining: _orderedGames.length - revealed,
            onTap: () => setState(() => _visibleGames += _pageSize),
          );
        }

        final row = rows[i];
        if (row.header != null) {
          return _RoundHeader(label: row.header!);
        }
        if (row.match != null) {
          return _MatchHeader(data: row.match!);
        }

        return GamebaseSearchGameCard(
          game: _modelFor(row.gameIndex),
          allGames: allGames,
          gameIndex: row.gameIndex,
          animationIndex: row.gameIndex,
          onAdd: () => showAddToFolderSheet(
            context: context,
            game: _modelFor(row.gameIndex),
          ),
          showRound: false,
          hideEventInfo: false,
          playerProfileDataSource: PlayerProfileDataSource.twic,
        );
      },
    );
  }
}

class _RoundHeader extends StatelessWidget {
  const _RoundHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: 16.h, bottom: 8.h),
      child: Text(
        label,
        style: AppTypography.textSmBold.copyWith(
          color: context.colors.textPrimary.withValues(alpha: 0.8),
        ),
      ),
    );
  }
}

/// Team-vs-team / player-vs-player match header used for team & knockout events.
class _MatchHeader extends StatelessWidget {
  const _MatchHeader({required this.data});

  final _MatchData data;

  @override
  Widget build(BuildContext context) {
    final leftWins = data.leftScore > data.rightScore;
    final rightWins = data.rightScore > data.leftScore;
    final neutral = context.colors.textPrimary;
    final win = kGreenColor;
    final lose = context.colors.textPrimary.withValues(alpha: 0.5);

    Color sideColor(bool wins, bool otherWins) {
      if (!wins && !otherWins) return neutral;
      return wins ? win : lose;
    }

    return Container(
      margin: EdgeInsets.only(top: 6.h, bottom: 6.h),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(10.br),
      ),
      child: Row(
        children: [
          Expanded(
            child: _MatchSide(
              label: data.leftLabel,
              fed: data.leftFed,
              alignEnd: true,
              color: sideColor(leftWins, rightWins),
              bold: leftWins,
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 10.w),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
              decoration: BoxDecoration(
                color: kPrimaryColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6.br),
              ),
              child: Text(
                '${_trimDouble(data.leftScore)} – ${_trimDouble(data.rightScore)}',
                style: AppTypography.textSmBold.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          ),
          Expanded(
            child: _MatchSide(
              label: data.rightLabel,
              fed: data.rightFed,
              alignEnd: false,
              color: sideColor(rightWins, leftWins),
              bold: rightWins,
            ),
          ),
        ],
      ),
    );
  }
}

class _MatchSide extends StatelessWidget {
  const _MatchSide({
    required this.label,
    required this.fed,
    required this.alignEnd,
    required this.color,
    required this.bold,
  });

  final String label;
  final String? fed;
  final bool alignEnd;
  final Color color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final text = Flexible(
      child: Text(
        label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: alignEnd ? TextAlign.right : TextAlign.left,
        style: AppTypography.textXsMedium.copyWith(
          color: color,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
    final flag = (fed != null && fed!.trim().isNotEmpty)
        ? Padding(
            padding: EdgeInsets.symmetric(horizontal: 4.w),
            child: _FedFlag(countryCode: fed!),
          )
        : const SizedBox.shrink();

    return Row(
      mainAxisAlignment:
          alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: alignEnd ? [text, flag] : [flag, text],
    );
  }
}

class _ShowMoreButton extends StatelessWidget {
  const _ShowMoreButton({required this.remaining, required this.onTap});

  final int remaining;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 16.h),
      child: Center(
        child: GestureDetector(
          onTap: () {
            HapticFeedbackService.light();
            onTap();
          },
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(8.br),
            ),
            child: Text(
              'Show more ($remaining)',
              style: AppTypography.textSmMedium.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --- Standings ---------------------------------------------------------------

class _StandingsTab extends StatelessWidget {
  const _StandingsTab({required this.view});

  final GamebaseEventView view;

  @override
  Widget build(BuildContext context) {
    final standings = view.standings;

    if (standings.isTeam) {
      if (standings.teams.isEmpty) return _noStandings(context);
      return ListView.builder(
        padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
        itemCount: standings.teams.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return const _StandingsHeaderRow(
              columns: ['#', 'Team', 'MP', 'GP'],
            );
          }
          return _TeamStandingRow(team: standings.teams[i - 1]);
        },
      );
    }

    if (standings.players.isEmpty) return _noStandings(context);
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
      itemCount: standings.players.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return const _StandingsHeaderRow(
            columns: ['#', 'Player', 'Pts', 'Pld'],
          );
        }
        return _PlayerStandingRow(player: standings.players[i - 1]);
      },
    );
  }

  Widget _noStandings(BuildContext context) => Center(
        child: Text(
          'Standings unavailable',
          style: AppTypography.textSmRegular.copyWith(
            color: context.colors.textPrimary.withValues(alpha: 0.5),
          ),
        ),
      );
}

class _StandingsHeaderRow extends StatelessWidget {
  const _StandingsHeaderRow({required this.columns});

  final List<String> columns;

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.textXsRegular.copyWith(
      color: context.colors.textPrimary.withValues(alpha: 0.45),
    );
    return Padding(
      padding: EdgeInsets.only(left: 4.w, right: 4.w, bottom: 8.h),
      child: Row(
        children: [
          SizedBox(width: 28.w, child: Text(columns[0], style: style)),
          Expanded(child: Text(columns[1], style: style)),
          SizedBox(
            width: 48.w,
            child: Text(columns[2], style: style, textAlign: TextAlign.right),
          ),
          SizedBox(
            width: 44.w,
            child: Text(columns[3], style: style, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

class _PlayerStandingRow extends StatelessWidget {
  const _PlayerStandingRow({required this.player});

  final GamebaseEventPlayerStanding player;

  @override
  Widget build(BuildContext context) {
    final title = (player.title ?? '').trim();
    final name = (player.name ?? 'Unknown').trim();
    final record = '${player.wins}W · ${player.draws}D · ${player.losses}L'
        '${player.elo != null ? '  ·  ${player.elo}' : ''}';

    return Container(
      margin: EdgeInsets.only(bottom: 6.h),
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(8.br),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28.w,
            child: Text(
              '${player.rank}',
              style: AppTypography.textSmMedium.copyWith(
                color: context.colors.textPrimary.withValues(alpha: 0.55),
              ),
            ),
          ),
          if ((player.fed ?? '').trim().isNotEmpty) ...[
            _FedFlag(countryCode: player.fed!),
            SizedBox(width: 8.w),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    children: [
                      if (title.isNotEmpty)
                        TextSpan(
                          text: '$title ',
                          style: AppTypography.textSmMedium.copyWith(
                            color: kLightYellowColor,
                          ),
                        ),
                      TextSpan(
                        text: name,
                        style: AppTypography.textSmMedium.copyWith(
                          color: context.colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  record,
                  style: AppTypography.textXsRegular.copyWith(
                    color: context.colors.textPrimary.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 48.w,
            child: Text(
              _trimDouble(player.points),
              textAlign: TextAlign.right,
              style: AppTypography.textSmBold.copyWith(color: kGreenColor),
            ),
          ),
          SizedBox(
            width: 44.w,
            child: Text(
              '${player.played}',
              textAlign: TextAlign.right,
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textPrimary.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamStandingRow extends StatelessWidget {
  const _TeamStandingRow({required this.team});

  final GamebaseEventTeamStanding team;

  @override
  Widget build(BuildContext context) {
    final record = '${team.wins}W · ${team.draws}D · ${team.losses}L'
        '  ·  ${team.played} matches';

    return Container(
      margin: EdgeInsets.only(bottom: 6.h),
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(8.br),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28.w,
            child: Text(
              '${team.rank}',
              style: AppTypography.textSmMedium.copyWith(
                color: context.colors.textPrimary.withValues(alpha: 0.55),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  team.team,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.textSmMedium.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  record,
                  style: AppTypography.textXsRegular.copyWith(
                    color: context.colors.textPrimary.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 48.w,
            child: Text(
              _trimDouble(team.matchPoints),
              textAlign: TextAlign.right,
              style: AppTypography.textSmBold.copyWith(color: kGreenColor),
            ),
          ),
          SizedBox(
            width: 44.w,
            child: Text(
              _trimDouble(team.gamePoints),
              textAlign: TextAlign.right,
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textPrimary.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small federation flag that no-ops when the federation isn't a valid country
/// code (gamebase `fed` can be a country name or be missing).
class _FedFlag extends ConsumerWidget {
  const _FedFlag({required this.countryCode});

  final String countryCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final valid =
        ref.read(locationServiceProvider).getValidCountryCode(countryCode);
    if (valid.isEmpty) return SizedBox(width: 20.w, height: 14.h);
    return SizedBox(
      width: 20.w,
      height: 14.h,
      child: CountryFlag.fromCountryCode(
        valid,
        theme: ImageTheme(height: 14.h, width: 20.w),
      ),
    );
  }
}

// --- Empty / error -----------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.eventName});

  final String eventName;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 48.ic,
              color: context.colors.textPrimary.withValues(alpha: 0.4),
            ),
            SizedBox(height: 16.h),
            Text(
              "Couldn't build this event",
              style: AppTypography.textMdMedium.copyWith(
                color: context.colors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8.h),
            Text(
              'Open the ChessEver Database to search its games instead.',
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textPrimary.withValues(alpha: 0.5),
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 20.h),
            TextButton(
              onPressed: () {
                HapticFeedbackService.light();
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => TwicContentsScreen(initialEvent: eventName),
                  ),
                );
              },
              child: const Text('Search Database'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 40.ic,
              color: Colors.redAccent,
            ),
            SizedBox(height: 12.h),
            Text(
              message,
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textPrimary.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16.h),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

String _trimDouble(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}

String _titleCase(String value) {
  final lower = value.toLowerCase();
  if (lower.isEmpty) return value;
  return lower[0].toUpperCase() + lower.substring(1);
}
