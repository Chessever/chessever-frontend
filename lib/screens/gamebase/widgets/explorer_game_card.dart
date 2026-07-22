import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart';
import 'package:chessever2/screens/gamebase/providers/explorer_game_focus_provider.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_explorer_state.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:chessever2/screens/gamebase/utils/continuation_line.dart';
import 'package:chessever2/screens/gamebase/widgets/position_games_sheet.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/audio_player_service.dart';
import 'package:chessever2/utils/broadcast_custom_scoring.dart';
import 'package:chessever2/utils/chess_title_utils.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/backfilled_federation_flag.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:dartchess/dartchess.dart' show Move, NormalMove, Side, Square;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Inline games list rendered under the explorer's move table when 10 or
/// fewer games remain in the current position (Trello #984).
///
/// Fetches a short `notationPlies` preview for instant chips, then upgrades
/// each strip to the full remaining game via `getGameWithPgn` (API cap is 20).
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

  /// Preview length from position-games API (OpenAPI max is 20 plies).
  static const int _notationPlies = 20;

  ExplorerFocusedGameNotifier? _focusNotifier;

  /// Full mainline continuations keyed by game id (past the API 20-ply cap).
  final Map<String, ContinuationLine> _fullLinesByGameId = {};

  /// In-flight upgrade jobs so we don't re-fetch on every rebuild.
  final Set<String> _upgradingGameIds = {};

  /// Last fen we upgraded for — drop cache when the explorer position moves.
  String? _upgradeFenKey;

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

  void _resetUpgradeCacheIfNeeded() {
    final key = continuationFenKey(widget.fen);
    if (_upgradeFenKey == key) return;
    _upgradeFenKey = key;
    _fullLinesByGameId.clear();
    _upgradingGameIds.clear();
  }

  /// Fetch full PGN/data for each preview row and replace the 20-ply strip
  /// with the remainder of the real game through the terminal position.
  void _scheduleFullLineUpgrade(List<GamesTourModel> games) {
    _resetUpgradeCacheIfNeeded();
    final repo = ref.read(gamebaseRepositoryProvider);
    final anchorFen = widget.fen;

    for (final game in games) {
      final id = game.gameId;
      if (id.isEmpty || id == 'unknown') continue;
      if (_fullLinesByGameId.containsKey(id)) continue;
      if (_upgradingGameIds.contains(id)) continue;
      _upgradingGameIds.add(id);

      () async {
        try {
          final withPgn = await repo.getGameWithPgn(id);
          if (!mounted) return;
          if (continuationFenKey(widget.fen) != continuationFenKey(anchorFen)) {
            return; // position moved while we were fetching
          }
          final full = buildFullContinuationLine(
            anchorFen: anchorFen,
            gameId: id,
            data: withPgn?.data,
            pgn: withPgn?.pgn,
          );
          if (full == null || full.isEmpty) return;
          if (!mounted) return;
          setState(() {
            _fullLinesByGameId[id] = full;
            _upgradingGameIds.remove(id);
          });
        } catch (_) {
          if (mounted) {
            setState(() => _upgradingGameIds.remove(id));
          } else {
            _upgradingGameIds.remove(id);
          }
        }
      }();
    }
  }

  @override
  Widget build(BuildContext context) {
    _focusNotifier = ref.read(explorerFocusedGameProvider.notifier);
    final gamesAsync = ref.watch(positionGamesProvider(_query));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        gamesAsync.when(
          loading: () => const _ExplorerGamesStatusRow.loading(),
          error:
              (_, __) => const _ExplorerGamesStatusRow(
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
              final game = mapGamebasePreviewToTourModel(row);
              games.add(game);
              final ucis =
                  (row['continuation'] as List?)
                      ?.map((e) => e.toString())
                      .toList(growable: false) ??
                  const <String>[];
              final preview = buildContinuationLine(widget.fen, ucis);
              final full = _fullLinesByGameId[game.gameId];
              // Prefer full mainline when it actually extends past the API cap.
              lines.add(
                (full != null && full.sans.length > preview.sans.length)
                    ? full
                    : (full ?? preview),
              );
            }

            // Fire-and-forget full-game upgrade after this frame.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _scheduleFullLineUpgrade(games);
            });

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

/// Outcome of a body tap on an [ExplorerGameCard] (after premium allows).
///
/// Always [openGame]: body never clear-focus-only. Clear-only left the mini-board
/// on the terminal fen without navigation — the broken first-tap feel.
enum ExplorerCardBodyAction {
  /// Navigate into [openGamebaseGame] / the chess board screen.
  openGame,
}

/// Shipped body-tap branch for explorer game cards.
///
/// [isThisCardFocused] is accepted so call sites stay explicit, but it does
/// **not** change the outcome: focused and unfocused body taps both open.
@visibleForTesting
ExplorerCardBodyAction resolveExplorerCardBodyAction({
  required bool isThisCardFocused,
}) {
  // Ignore focus: X / strip clear focus; body is open-only.
  return ExplorerCardBodyAction.openGame;
}

/// FEN passed to [openGamebaseGame] / the chess board when opening from a card.
///
/// When this card is focused after continuation traversal, use [focus.boardFen]
/// so the board continues from that ply. Unfocused open uses the explorer
/// [anchorFen] (position being explored).
@visibleForTesting
String resolveExplorerCardOpenInitialFen({
  required String gameId,
  required String anchorFen,
  required ExplorerGameFocus? focus,
}) {
  if (focus != null && focus.gameId == gameId) {
    return focus.boardFen;
  }
  return anchorFen;
}

/// SAN to sonify when a focused explorer card changes its displayed ply.
/// Forward/jump plays the reached move; backward plays the move being undone.
@visibleForTesting
String? resolveExplorerFocusSoundSan(
  ExplorerGameFocus? previous,
  ExplorerGameFocus? next,
) {
  if (next == null) return null;
  final sameGame = previous?.gameId == next.gameId;
  if (sameGame && previous!.ply == next.ply) return null;

  final soundPly =
      sameGame && next.ply < previous!.ply ? previous.ply : next.ply;
  if (soundPly < 0 || soundPly >= next.sans.length) return null;
  return next.sans[soundPly];
}

/// Human-readable event for the center slot. `tourId` may be an opaque UUID.
@visibleForTesting
String explorerGameEventLabel(GamesTourModel game) =>
    sanitizeGamebaseEventLabel(game.tourSlug);

/// One game remaining in the explored position: mini board on the left, player
/// metadata on the right, and the game's continuation from this position as a
/// horizontally scrollable SAN chip strip at the bottom.
///
/// Interaction mapping (Trello #984):
/// - Free users: any tap/scroll interaction on the card shows the paywall
///   (cards stay visible as a teaser under the free move window).
/// - Premium: tap notation strip / chip → FOCUS; bottom-nav arrows walk the
///   continuation on the miniboard. **Body tap always opens the full game**
///   (never clear-focus-only — that only snapped the mini-board fen). When
///   focused, open continues from the focused ply (`boardFen`).
/// - While focused: X icon (or re-tapping the notation strip) releases focus.
class ExplorerGameCard extends ConsumerStatefulWidget {
  const ExplorerGameCard({
    super.key,
    required this.game,
    required this.anchorFen,
    required this.line,
    required this.allGames,
    required this.index,
    this.playMoveSound,
  });

  final GamesTourModel game;
  final String anchorFen;
  final ContinuationLine line;
  final List<GamesTourModel> allGames;
  final int index;

  /// Test seam for the native audio plugin. Production uses AudioPlayerService.
  final ValueChanged<String>? playMoveSound;

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

  @override
  void didUpdateWidget(covariant ExplorerGameCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When the section upgrades the strip past the API 20-ply cap, rebind
    // focus with the longer mainline so arrows can walk the full game.
    if (oldWidget.line.sans.length >= widget.line.sans.length) return;
    final focus = ref.read(explorerFocusedGameProvider);
    if (!_isThisCardFocused(focus)) return;
    final ply = focus!.ply;
    ref
        .read(explorerFocusedGameProvider.notifier)
        .focus(
          gameId: widget.game.gameId,
          anchorFen: widget.anchorFen,
          sans: widget.line.sans,
          fens: widget.line.fens,
          ply: ply.clamp(-1, widget.line.sans.length - 1),
        );
  }

  bool _isThisCardFocused(ExplorerGameFocus? focus) =>
      focus != null && focus.gameId == widget.game.gameId;

  /// True when this card must reject interaction and surface the paywall.
  /// Mirrors [requirePremiumGuard] / explorer free-window: debug bypass.
  bool get _freeUserLocked {
    if (kDebugMode) return false;
    return !ref.watch(subscriptionProvider.select((s) => s.isSubscribed));
  }

  /// Premium gate for every interactive path on this card.
  Future<bool> _requirePremium() async {
    final unlocked = await requirePremiumGuard(context, ref);
    if (!unlocked && mounted) {
      // Never leave free users mid-focus with arrow ownership.
      ref.read(explorerFocusedGameProvider.notifier).clear();
    }
    return unlocked && mounted;
  }

  Future<void> _handleFocusRequest(int ply) async {
    final focusNotifier = ref.read(explorerFocusedGameProvider.notifier);
    if (_isThisCardFocused(ref.read(explorerFocusedGameProvider))) {
      // Already focused ⇒ already passed premium; allow chip jumps.
      focusNotifier.jumpTo(ply);
      return;
    }
    // Focus / walk / open are Premium — even inside the free move window.
    if (!await _requirePremium()) return;
    focusNotifier.focus(
      gameId: widget.game.gameId,
      anchorFen: widget.anchorFen,
      sans: widget.line.sans,
      fens: widget.line.fens,
      ply: ply,
    );
  }

  Future<void> _handleBodyTap() async {
    // Body always opens the chess board after premium. Do NOT clear-focus-only
    // when already focused — that only jumped the mini-board to the terminal
    // fen and left the user on the explorer (felt like a broken first tap).
    // Unfocus is X / strip re-tap; openGamebaseGame also clears focus.
    final focus = ref.read(explorerFocusedGameProvider);
    final action = resolveExplorerCardBodyAction(
      isThisCardFocused: _isThisCardFocused(focus),
    );
    assert(
      action == ExplorerCardBodyAction.openGame,
      'body tap must open the board',
    );
    // Read open fen BEFORE openGamebaseGame clears focus so mid-traversal
    // opens land on the focused ply, not only the explorer anchor.
    final openFen = resolveExplorerCardOpenInitialFen(
      gameId: widget.game.gameId,
      anchorFen: widget.anchorFen,
      focus: focus,
    );
    if (!await _requirePremium()) return;
    if (!mounted) return;
    await openGamebaseGame(
      context,
      ref,
      widget.game,
      widget.allGames,
      widget.index,
      openFen,
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

  String get _eventLine => explorerGameEventLabel(widget.game);

  Move? _uciToMove(String? uci) {
    final raw = (uci ?? '').trim().toLowerCase();
    if (raw.length < 4) return null;
    try {
      final from = Square.fromName(raw.substring(0, 2));
      final to = Square.fromName(raw.substring(2, 4));
      return NormalMove(from: from, to: to);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ExplorerGameFocus?>(explorerFocusedGameProvider, (
      previous,
      next,
    ) {
      if (next?.gameId != widget.game.gameId) return;
      final san = resolveExplorerFocusSoundSan(previous, next);
      if (san == null) return;
      final soundEnabled =
          ref.read(boardSettingsProviderNew).valueOrNull?.soundEnabled == true;
      if (!soundEnabled) return;
      final playMoveSound = widget.playMoveSound;
      if (playMoveSound != null) {
        playMoveSound(san);
      } else {
        AudioPlayerService.instance.playSfxForSan(san);
      }
    });

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

    // Larger mini-board so cards stay readable when games fill the panel.
    final boardSize = 124.sp;
    final status = widget.game.gameStatus;
    final finished = status.isFinished;

    // Same board pipeline as grid game cards (last-move, fallen king, doves).
    // Prefer the game's own end FEN; else the last continuation ply so
    // terminal overlays land on the displayed position.
    final gameFen = (widget.game.fen ?? '').trim();
    final continuationEndFen =
        widget.line.fens.isNotEmpty ? widget.line.fens.last : null;
    final String boardFen;
    final Move? lastMove;
    final GameStatus boardStatus;
    if (isFocused) {
      boardFen = focus.boardFen;
      lastMove = null;
      // Terminal king/dove animations only when focus is at the strip end.
      boardStatus =
          (!focus.canGoForward && finished) ? status : GameStatus.ongoing;
    } else if (gameFen.isNotEmpty) {
      boardFen = gameFen;
      lastMove = _uciToMove(widget.game.lastMove);
      boardStatus = finished ? status : GameStatus.ongoing;
    } else if (continuationEndFen != null &&
        continuationEndFen != widget.anchorFen) {
      boardFen = continuationEndFen;
      lastMove = null;
      boardStatus = finished ? status : GameStatus.ongoing;
    } else {
      boardFen = widget.anchorFen;
      lastMove = null;
      boardStatus = GameStatus.ongoing;
    }

    // Explorer sits on near-black board chrome (kBackground). Cards must lift
    // as dark elevated surfaces — NOT GameCard's light chip-strip (that only
    // works on the tournament list). Tokens still come from AppColors.
    final isLight = context.isLightTheme;
    // Dark: surface (#1A) on background (#0C); footer one step recessed.
    // Light: same white GameCard treatment.
    final topSurface =
        isLight ? context.colors.surface : context.colors.surface;
    final bottomSurface =
        isLight
            ? context.colors.surfaceRecessed
            : context.colors.surfaceRecessed;
    final metaColor = context.colors.textSecondary;
    final closeIconColor = context.colors.textSecondary;

    final radius = BorderRadius.circular(12.br);
    final outerBorder =
        isFocused
            ? Border.all(color: kPrimaryColor.withValues(alpha: 0.4))
            : Border.all(
              color:
                  isLight
                      ? context.colors.divider.withValues(alpha: 0.5)
                      : context.colors.divider,
            );

    final card = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleBodyTap,
          child: Container(
            decoration: BoxDecoration(
              color:
                  isFocused
                      ? Color.alphaBlend(
                        kPrimaryColor.withValues(alpha: isLight ? 0.06 : 0.10),
                        topSurface,
                      )
                      : topSurface,
              borderRadius:
                  widget.line.isNotEmpty
                      ? BorderRadius.only(
                        topLeft: Radius.circular(12.br),
                        topRight: Radius.circular(12.br),
                      )
                      : radius,
              border: Border(
                bottom: BorderSide(
                  color: context.colors.divider.withValues(
                    alpha: isLight ? 0.6 : 1.0,
                  ),
                ),
              ),
            ),
            // Stack so the unfocus "x" floats top-right without taking row
            // width (no layout shift when focus begins).
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // No ClipRRect — fallen-king / dove overlays must not be cut.
                    Padding(
                      padding: EdgeInsets.only(
                        left: 10.sp,
                        top: 10.sp,
                        bottom: 10.sp,
                      ),
                      child: GameCardChessboard(
                        fen: boardFen,
                        lastMove: lastMove,
                        boardSize: boardSize,
                        orientation: Side.white,
                        showCoordinates: false,
                        gameStatus: boardStatus,
                      ),
                    ),
                    // White top · meta middle (centered) · black bottom —
                    // height matches the mini-board so scores/names track
                    // the board edge.
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          10.sp,
                          10.sp,
                          10.sp,
                          10.sp,
                        ),
                        child: SizedBox(
                          height: boardSize,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _ExplorerCardPlayerRow(
                                game: widget.game,
                                isWhite: true,
                              ),
                              Expanded(
                                child: Center(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 2.w,
                                    ),
                                    child:
                                        _eventLine.isEmpty
                                            ? const SizedBox.shrink()
                                            : _FadingOverflowText(
                                              text: _eventLine,
                                              textAlign: TextAlign.center,
                                              style: AppTypography.textXsRegular
                                                  .copyWith(color: metaColor),
                                            ),
                                  ),
                                ),
                              ),
                              _ExplorerCardPlayerRow(
                                game: widget.game,
                                isWhite: false,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (isFocused)
                  Positioned(
                    top: 4.sp,
                    right: 4.sp,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap:
                            () =>
                                ref
                                    .read(explorerFocusedGameProvider.notifier)
                                    .clear(),
                        customBorder: const CircleBorder(),
                        child: Container(
                          width: 28.sp,
                          height: 28.sp,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: topSurface.withValues(alpha: 0.92),
                            border: Border.all(
                              color: context.colors.divider.withValues(
                                alpha: isLight ? 0.6 : 1.0,
                              ),
                            ),
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            color: closeIconColor,
                            size: 16.ic,
                          ),
                        ),
                      ),
                    ),
                  ),
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
            child: Container(
              decoration: BoxDecoration(
                color: bottomSurface,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(12.br),
                  bottomRight: Radius.circular(12.br),
                ),
              ),
              // Horizontal inset lives INSIDE the scroll view so chips are
              // not clipped at the left/right edges of the card.
              child: SingleChildScrollView(
                controller: _chipScrollController,
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.fromLTRB(10.sp, 8.sp, 10.sp, 10.sp),
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
      ],
    );

    final shell = Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        border: outerBorder,
        boxShadow:
            isLight
                ? [
                  BoxShadow(
                    color: context.colors.shadow,
                    blurRadius: 10,
                    offset: const Offset(0, 1),
                  ),
                ]
                : null,
      ),
      child: ClipRRect(borderRadius: radius, child: card),
    );

    // Free users may *see* the teaser cards, but any interaction hits paywall.
    // Full-card barrier so chip scrolls / nested gestures can't slip through.
    if (!_freeUserLocked) return shell;

    if (isFocused) {
      // Drop stale focus if subscription lapsed while a card was focused.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(explorerFocusedGameProvider.notifier).clear();
      });
    }

    return Stack(
      children: [
        IgnorePointer(child: shell),
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => requirePremiumGuard(context, ref),
          ),
        ),
      ],
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
    final isLight = context.isLightTheme;
    // Tonal chips on recessed footer — brand only on the active ply.
    final idleFill =
        isLight
            ? context.colors.surface
            : context.colors.surface.withValues(alpha: 0.55);
    return GestureDetector(
      key: isCurrent ? _currentChipKey : null,
      behavior: HitTestBehavior.opaque,
      onTap: () => _handleFocusRequest(index),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 4.h),
        decoration: BoxDecoration(
          color:
              isCurrent
                  ? kPrimaryColor.withValues(alpha: isLight ? 0.12 : 0.18)
                  : idleFill,
          borderRadius: BorderRadius.circular(6.br),
        ),
        child: Text(
          label,
          style: AppTypography.textXsMedium.copyWith(
            color: isCurrent ? kPrimaryColor : context.colors.textPrimary,
            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _ExplorerCardPlayerRow extends StatelessWidget {
  const _ExplorerCardPlayerRow({required this.game, required this.isWhite});

  final GamesTourModel game;
  final bool isWhite;

  @override
  Widget build(BuildContext context) {
    final player = isWhite ? game.whitePlayer : game.blackPlayer;
    final title = ChessTitleUtils.normalize(player.title);
    final status = game.gameStatus;
    final scoreLabel = boardResultLabelForSide(game, isWhite: isWhite) ?? '';
    final isDraw = status == GameStatus.draw;
    final isWin =
        (status == GameStatus.whiteWins && isWhite) ||
        (status == GameStatus.blackWins && !isWhite);
    // Result colors match board/player rows; names use normal app text tokens
    // (dark elevated card on black chrome — not GameCard's inverted strip).
    final resultColor =
        !status.isFinished
            ? context.colors.textPrimary
            : isWin
            ? kPrimaryColor
            : isDraw
            ? context.colors.textPrimaryMuted
            : context.colors.danger;

    // Title + name share the same size/family so "GM" sits level with the
    // surname (board chrome pattern). Title stays light-yellow; name primary.
    final nameStyle = AppTypography.textSmMedium.copyWith(
      color: context.colors.textPrimary,
      height: 1.15,
    );
    final titleStyle = nameStyle.copyWith(
      color: kLightYellowColor,
      fontWeight: FontWeight.w700,
    );
    final ratingStyle = AppTypography.textXsRegular.copyWith(
      color: context.colors.textPrimaryMuted,
      height: 1.15,
    );

    // Same size as name so "1"/"0"/"½" don't read as a smaller caption.
    final scoreStyle = nameStyle.copyWith(
      color: resultColor,
      fontWeight: FontWeight.w600,
    );
    // Fixed-width trailing score slot so white/black share the same right edge.
    // Wide enough for "½" at textSm without clipping.
    final scoreSlotWidth = 22.sp;

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
        Expanded(
          child: _FadingOverflowRichText(
            span: TextSpan(
              children: [
                if (title.isNotEmpty)
                  TextSpan(text: '$title ', style: titleStyle),
                TextSpan(text: player.name, style: nameStyle),
                if (player.rating > 0)
                  TextSpan(
                    text: ' ${player.displayRating}',
                    style: ratingStyle,
                  ),
              ],
            ),
          ),
        ),
        SizedBox(width: 8.w),
        SizedBox(
          width: scoreSlotWidth,
          child: Text(
            scoreLabel,
            textAlign: TextAlign.right,
            style: scoreStyle,
          ),
        ),
      ],
    );
  }
}

/// Soft trailing fade when text is wider than the slot — never "…".
class _FadingOverflowText extends StatelessWidget {
  const _FadingOverflowText({
    required this.text,
    required this.style,
    this.textAlign = TextAlign.start,
  });

  final String text;
  final TextStyle style;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final textDir = Directionality.of(context);
        final child = Text(
          text,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
          textAlign: textAlign,
          style: style,
        );
        if (!maxW.isFinite || maxW <= 0) return child;

        // Full-width box so TextAlign.center actually centers in the meta slot.
        Widget sized = SizedBox(width: maxW, child: child);

        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: 1,
          textDirection: textDir,
        )..layout(maxWidth: maxW);

        final overflows =
            painter.didExceedMaxLines || painter.width > maxW + 0.5;
        if (!overflows) return sized;

        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) {
            return const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)],
              // Soft dissolve over the last ~28% of the line.
              stops: [0.0, 0.72, 1.0],
            ).createShader(bounds);
          },
          child: sized,
        );
      },
    );
  }
}

/// Same overflow fade for title + name + rating RichText.
class _FadingOverflowRichText extends StatelessWidget {
  const _FadingOverflowRichText({required this.span});

  final InlineSpan span;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final textDir = Directionality.of(context);
        final child = Text.rich(
          span,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
        );
        if (!maxW.isFinite || maxW <= 0) return child;

        final painter = TextPainter(
          text: span,
          maxLines: 1,
          textDirection: textDir,
        )..layout(maxWidth: maxW);

        final overflows =
            painter.didExceedMaxLines || painter.width > maxW + 0.5;
        if (!overflows) return child;

        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) {
            return const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)],
              stops: [0.0, 0.72, 1.0],
            ).createShader(bounds);
          },
          child: child,
        );
      },
    );
  }
}
