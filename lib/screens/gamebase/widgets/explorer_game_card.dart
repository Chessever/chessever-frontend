import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/screens/gamebase/providers/explorer_game_focus_provider.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_explorer_state.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:chessever2/screens/gamebase/utils/continuation_line.dart';
import 'package:chessever2/screens/gamebase/widgets/position_games_sheet.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/chess_title_utils.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/backfilled_federation_flag.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Inline games list rendered under the explorer's move table when 10 or
/// fewer games remain in the current position (Trello #984).
///
/// Fetches the remaining games with `notationPlies: 20` so every row carries
/// a `continuation` UCI slice, then renders one [ExplorerGameCard] per game.
class ExplorerGamesSection extends ConsumerStatefulWidget {
  const ExplorerGamesSection({
    super.key,
    required this.fen,
    required this.moves,
    required this.filters,
  });

  /// Current explored position (the continuation anchor).
  final String fen;

  /// Explored UCI move path leading to [fen].
  final List<String> moves;

  final GamebaseFilters filters;

  @override
  ConsumerState<ExplorerGamesSection> createState() =>
      _ExplorerGamesSectionState();
}

class _ExplorerGamesSectionState extends ConsumerState<ExplorerGamesSection> {
  static const int _maxGames = 10;

  /// Full continuation slice per row (API maximum).
  static const int _notationPlies = 20;

  ExplorerFocusedGameNotifier? _focusNotifier;

  @override
  void dispose() {
    // Leaving the tree (panel closed / swiped away / position pruned the
    // section) must hand the bottom-nav arrows back to the main board.
    final focusNotifier = _focusNotifier;
    if (focusNotifier != null) {
      Future.microtask(focusNotifier.clearIfActive);
    }
    super.dispose();
  }

  GamebasePositionGamesQuery get _query => GamebasePositionGamesQuery(
    fen: widget.fen,
    moves: widget.moves,
    timeControl:
        widget.filters.timeControls.isNotEmpty
            ? widget.filters.timeControls.first
            : null,
    playerId:
        widget.filters.playerIds.isNotEmpty
            ? widget.filters.playerIds.first
            : null,
    color: widget.filters.playerColor?.name,
    result: widget.filters.gameResult?.apiValue,
    isOnline: widget.filters.isOnline,
    minRating: widget.filters.minRating,
    maxRating: widget.filters.maxRating,
    yearFrom: widget.filters.yearFrom,
    yearTo: widget.filters.yearTo,
    sortBy: widget.filters.sortBy,
    sortDirection: widget.filters.sortDirection,
    pageNumber: 0,
    pageSize: _maxGames,
    notationPlies: _notationPlies,
  );

  @override
  Widget build(BuildContext context) {
    _focusNotifier = ref.read(explorerFocusedGameProvider.notifier);
    final gamesAsync = ref.watch(positionGamesProvider(_query));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(12.sp, 10.sp, 12.sp, 6.sp),
          child: Text(
            'Games',
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 11.f,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        gamesAsync.when(
          loading: () => const _ExplorerGamesStatusRow.loading(),
          error: (_, __) => const _ExplorerGamesStatusRow(
            message: 'Couldn’t load games for this position',
          ),
          data: (response) {
            final rows = response.data.take(_maxGames).toList(growable: false);
            if (rows.isEmpty) {
              return const _ExplorerGamesStatusRow(message: 'No games found');
            }

            final games = <GamesTourModel>[];
            final lines = <ContinuationLine>[];
            for (final row in rows) {
              games.add(mapGamebasePreviewToTourModel(row));
              final ucis =
                  (row['continuation'] as List?)
                      ?.map((e) => e.toString())
                      .toList(growable: false) ??
                  const <String>[];
              lines.add(buildContinuationLine(widget.fen, ucis));
            }

            return Column(
              children: [
                for (var i = 0; i < games.length; i++)
                  Padding(
                    padding: EdgeInsets.fromLTRB(12.sp, 0, 12.sp, 8.sp),
                    child: ExplorerGameCard(
                      game: games[i],
                      anchorFen: widget.fen,
                      line: lines[i],
                      allGames: games,
                      index: i,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Compact, quiet status row for the inline games fetch.
class _ExplorerGamesStatusRow extends StatelessWidget {
  const _ExplorerGamesStatusRow({required this.message}) : isLoading = false;

  const _ExplorerGamesStatusRow.loading() : message = null, isLoading = true;

  final String? message;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 14.sp),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isLoading) ...[
            SizedBox(
              width: 14.w,
              height: 14.h,
              child: CircularProgressIndicator(
                color: context.colors.textPrimaryMuted,
                strokeWidth: 2,
              ),
            ),
            SizedBox(width: 10.w),
            Text(
              'Loading games...',
              style: TextStyle(
                color: context.colors.textPrimaryMuted,
                fontSize: 12.f,
              ),
            ),
          ] else
            Text(
              message ?? '',
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 12.f,
              ),
            ),
        ],
      ),
    );
  }
}

/// One game remaining in the explored position: mini board on the left, player
/// metadata on the right, and the game's continuation from this position as a
/// horizontally scrollable SAN chip strip at the bottom.
///
/// Interaction mapping (Trello #984):
/// - Tap the notation strip / a chip → premium-gated FOCUS; while focused the
///   screen's bottom-nav arrows walk the continuation on the miniboard.
/// - Tap anywhere else on the card → open the full game (existing premium
///   gate inside [openGamebaseGame]).
/// - While focused: X icon or tapping the card body again releases focus.
class ExplorerGameCard extends ConsumerStatefulWidget {
  const ExplorerGameCard({
    super.key,
    required this.game,
    required this.anchorFen,
    required this.line,
    required this.allGames,
    required this.index,
  });

  final GamesTourModel game;
  final String anchorFen;
  final ContinuationLine line;
  final List<GamesTourModel> allGames;
  final int index;

  @override
  ConsumerState<ExplorerGameCard> createState() => _ExplorerGameCardState();
}

class _ExplorerGameCardState extends ConsumerState<ExplorerGameCard> {
  final GlobalKey _currentChipKey = GlobalKey();
  final ScrollController _chipScrollController = ScrollController();
  int? _lastEnsuredPly;

  @override
  void dispose() {
    _chipScrollController.dispose();
    super.dispose();
  }

  bool _isThisCardFocused(ExplorerGameFocus? focus) =>
      focus != null && focus.gameId == widget.game.gameId;

  Future<void> _handleFocusRequest(int ply) async {
    final focusNotifier = ref.read(explorerFocusedGameProvider.notifier);
    if (_isThisCardFocused(ref.read(explorerFocusedGameProvider))) {
      focusNotifier.jumpTo(ply);
      return;
    }
    // Walking a game's moves is Premium — even inside the free window.
    final unlocked = await requirePremiumGuard(context, ref);
    if (!unlocked || !mounted) return;
    focusNotifier.focus(
      gameId: widget.game.gameId,
      anchorFen: widget.anchorFen,
      sans: widget.line.sans,
      fens: widget.line.fens,
      ply: ply,
    );
  }

  Future<void> _handleBodyTap() async {
    final focusNotifier = ref.read(explorerFocusedGameProvider.notifier);
    if (_isThisCardFocused(ref.read(explorerFocusedGameProvider))) {
      // Tapping the focused card's body toggles focus off.
      focusNotifier.clear();
      return;
    }
    // Hand the arrows back to the board before pushing a new board screen so
    // the pushed screen's nav bar can't inherit a stale focus.
    focusNotifier.clear();
    await openGamebaseGame(
      context,
      ref,
      widget.game,
      widget.allGames,
      widget.index,
      widget.anchorFen,
    );
  }

  void _scheduleEnsureChipVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final chipContext = _currentChipKey.currentContext;
      if (chipContext == null) return;
      Scrollable.ensureVisible(
        chipContext,
        alignment: 0.5,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
      );
    });
  }

  (String, String) _scores(GameStatus status) => switch (status) {
    GameStatus.whiteWins => ('1', '0'),
    GameStatus.blackWins => ('0', '1'),
    GameStatus.draw => ('½', '½'),
    _ => ('', ''),
  };

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String get _metaLine {
    final rawEvent = widget.game.tourId.trim();
    final event =
        (rawEvent.isEmpty || rawEvent.toLowerCase() == 'gamebase')
            ? 'Gamebase'
            : rawEvent;
    final parts = <String>[
      event,
      if ((widget.game.eco ?? '').trim().isNotEmpty) widget.game.eco!.trim(),
      if (_formatDate(widget.game.lastMoveTime).isNotEmpty)
        _formatDate(widget.game.lastMoveTime),
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final focus = ref.watch(
      explorerFocusedGameProvider.select(
        (f) => (f != null && f.gameId == widget.game.gameId) ? f : null,
      ),
    );
    final isFocused = focus != null;

    if (isFocused && _lastEnsuredPly != focus.ply) {
      _lastEnsuredPly = focus.ply;
      _scheduleEnsureChipVisible();
    } else if (!isFocused) {
      _lastEnsuredPly = null;
    }

    final boardSettings =
        ref.watch(boardSettingsProviderNew).valueOrNull ??
        const BoardSettingsNew();
    final boardFen = isFocused ? focus.boardFen : widget.anchorFen;
    final boardSize = 96.sp;
    final (whiteScore, blackScore) = _scores(widget.game.gameStatus);

    return Container(
      decoration: BoxDecoration(
        color:
            isFocused
                ? kPrimaryColor.withValues(alpha: 0.08)
                : context.colors.surfaceRecessed,
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(
          color:
              isFocused
                  ? kPrimaryColor.withValues(alpha: 0.45)
                  : context.colors.textPrimary.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleBodyTap,
            child: Padding(
              padding: EdgeInsets.all(10.sp),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4.br),
                    child: StaticChessboard(
                      size: boardSize,
                      settings: StaticChessboardSettings(
                        enableCoordinates: false,
                        colorScheme: boardSettings.colorScheme,
                        pieceAssets: boardSettings.pieceAssets,
                      ),
                      orientation: Side.white,
                      fen: boardFen,
                    ),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ExplorerCardPlayerRow(
                          player: widget.game.whitePlayer,
                          score: whiteScore,
                        ),
                        SizedBox(height: 6.h),
                        _ExplorerCardPlayerRow(
                          player: widget.game.blackPlayer,
                          score: blackScore,
                        ),
                        SizedBox(height: 8.h),
                        Text(
                          _metaLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.textXsRegular.copyWith(
                            color: context.colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isFocused) ...[
                    SizedBox(width: 6.w),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap:
                          () =>
                              ref
                                  .read(explorerFocusedGameProvider.notifier)
                                  .clear(),
                      child: Padding(
                        padding: EdgeInsets.all(2.sp),
                        child: Icon(
                          Icons.close_rounded,
                          color: context.colors.textSecondary,
                          size: 18.ic,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (widget.line.isNotEmpty)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (isFocused) {
                  ref.read(explorerFocusedGameProvider.notifier).clear();
                } else {
                  _handleFocusRequest(0);
                }
              },
              child: Padding(
                padding: EdgeInsets.fromLTRB(10.sp, 0, 10.sp, 10.sp),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SingleChildScrollView(
                    controller: _chipScrollController,
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < widget.line.sans.length; i++) ...[
                          if (i > 0) SizedBox(width: 4.w),
                          _buildChip(
                            context,
                            index: i,
                            currentPly: isFocused ? focus.ply : null,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChip(
    BuildContext context, {
    required int index,
    required int? currentPly,
  }) {
    final isCurrent = currentPly != null && currentPly == index;
    final label = continuationChipLabel(
      widget.anchorFen,
      index,
      widget.line.sans[index],
    );
    return GestureDetector(
      key: isCurrent ? _currentChipKey : null,
      behavior: HitTestBehavior.opaque,
      onTap: () => _handleFocusRequest(index),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 4.h),
        decoration: BoxDecoration(
          color:
              isCurrent
                  ? kPrimaryColor.withValues(alpha: 0.2)
                  : context.colors.textPrimary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6.br),
          border: Border.all(
            color:
                isCurrent
                    ? kPrimaryColor.withValues(alpha: 0.5)
                    : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isCurrent ? kPrimaryColor : context.colors.textPrimary,
            fontSize: 12.f,
            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _ExplorerCardPlayerRow extends StatelessWidget {
  const _ExplorerCardPlayerRow({required this.player, required this.score});

  final PlayerCard player;

  /// Per-side result figure ('1', '0', '½'), empty when unknown/ongoing.
  final String score;

  @override
  Widget build(BuildContext context) {
    final title = ChessTitleUtils.normalize(player.title);
    return Row(
      children: [
        BackfilledFederationFlag(
          federation: player.countryCode,
          fideId: player.fideId,
          width: 14.sp,
          height: 10.sp,
          borderRadius: BorderRadius.circular(2.br),
        ),
        SizedBox(width: 6.w),
        if (title.isNotEmpty) ...[
          Text(
            title,
            style: AppTypography.textXsMedium.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          SizedBox(width: 4.w),
        ],
        Flexible(
          child: Text(
            player.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
        ),
        if (player.rating > 0) ...[
          SizedBox(width: 6.w),
          Text(
            player.displayRating,
            style: AppTypography.textXsRegular.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ],
        const Spacer(),
        if (score.isNotEmpty)
          Text(
            score,
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}
