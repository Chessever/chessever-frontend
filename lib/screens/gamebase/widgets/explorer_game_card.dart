import 'dart:async';

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart';
import 'package:chessever2/screens/chessboard/widgets/evaluation_bar_widget.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/screens/gamebase/providers/explorer_game_focus_provider.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_explorer_state.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:chessever2/screens/gamebase/utils/continuation_line.dart';
import 'package:chessever2/screens/gamebase/utils/explorer_games_paging.dart';
import 'package:chessever2/screens/gamebase/widgets/position_games_sheet.dart';
import 'package:chessever2/screens/player_profile/utils/twic_event_identity.dart';
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
    this.boardSize,
    this.onCardCountChanged,
    this.evalWindow,
  });

  /// Current explored position (the continuation anchor).
  final String fen;

  /// Explored UCI move path leading to [fen].
  final List<String> moves;

  final GamebaseFilters filters;

  /// Mini-board edge for every card. Supplied by the panel when it pages the
  /// strip one card at a time, so a whole card fits the space under the
  /// board's bottom player row. Null keeps the natural size.
  final double? boardSize;

  /// Reports how many cards are actually rendered, so the hosting panel can
  /// size its page grid to the strip rather than to the requested count.
  final ValueChanged<int>? onCardCountChanged;

  /// Which cards the reader can see, kept measured by the hosting panel. Only
  /// those cards evaluate their position; the rest reserve the bar's width and
  /// draw nothing. Null means no host is tracking visibility, so no card
  /// evaluates — the bar slot is reserved and left empty.
  final ValueListenable<ExplorerGamesEvalWindow>? evalWindow;

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

  /// Last card count handed to [ExplorerGamesSection.onCardCountChanged].
  int? _reportedCardCount;

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

  /// Publishes the rendered card count after the frame that rendered it —
  /// the panel turns this into its page grid, and a grid built mid-build would
  /// describe a layout that does not exist yet.
  void _reportCardCount(int count) {
    if (_reportedCardCount == count) return;
    _reportedCardCount = count;
    final callback = widget.onCardCountChanged;
    if (callback == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      callback(count);
    });
  }

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
          loading: () {
            _reportCardCount(0);
            return const _ExplorerGamesStatusRow.loading();
          },
          error: (_, __) {
            _reportCardCount(0);
            return const _ExplorerGamesStatusRow(
              message: 'Couldn’t load games for this position',
            );
          },
          data: (response) {
            final rows = response.data.take(_maxGames).toList(growable: false);
            if (rows.isEmpty) {
              _reportCardCount(0);
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
            _reportCardCount(games.length);

            return Column(
              children: [
                for (var i = 0; i < games.length; i++)
                  Padding(
                    // Bottom gap is part of the page pitch — keep it equal to
                    // `ExplorerGameCardGeometry.gap` or the grid drifts.
                    padding: EdgeInsets.fromLTRB(
                      12.sp,
                      0,
                      12.sp,
                      ExplorerGameCardGeometry.gap,
                    ),
                    child: ExplorerGameCard(
                      game: games[i],
                      anchorFen: widget.fen,
                      line: lines[i],
                      allGames: games,
                      index: i,
                      boardSize: widget.boardSize,
                      evalWindow: widget.evalWindow,
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

/// Year the game was played, or empty when the row carried no usable date.
///
/// Gamebase preview rows put the PGN `Date` in `lastMoveTime`; a live clock
/// never reaches these cards.
@visibleForTesting
String explorerGameYearLabel(GamesTourModel game) {
  final year = game.lastMoveTime?.year;
  if (year == null || year < 1500) return '';
  return year.toString();
}

/// Human-readable event for the center slot. `tourId` may be an opaque UUID.
///
/// Two things never reach the card:
/// - a round or pairing label ("Round 9: Carlsen - Nakamura"), which is not the
///   tournament and only repeats the two names printed above and below it. The
///   preview mapper resolves the parent event from the broadcast `Site` slug;
///   when even that is unavailable the slot stays empty rather than lie.
/// - the year, when the name already carries the game's own year. The card
///   prints the year on its own line, so "Serbia Open 2026 Masters · 2026"
///   would stutter — it reads "Serbia Open Masters" over "2026" instead.
@visibleForTesting
String explorerGameEventLabel(GamesTourModel game) {
  final label = sanitizeGamebaseEventLabel(game.tourSlug);
  if (label.isEmpty || isTwicRoundDisplayTitle(label)) return '';
  return _withoutRedundantYear(label, explorerGameYearLabel(game));
}

/// Drops [year] from [label] when it stands alone as its own token, then tidies
/// the punctuation the removal leaves behind.
///
/// A year welded into a longer number or a date is left alone — "Friday Night
/// Quads 05.29.2026" and "Open 2026/27" are real gamebase event names, and
/// cutting the year out of either leaves a wreck. Keeps [label] whenever the
/// removal would leave nothing meaningful (an event literally named "2026").
String _withoutRedundantYear(String label, String year) {
  if (year.isEmpty) return label;
  final token = RegExp('(?<![0-9./-])$year(?![0-9./-])');
  if (!token.hasMatch(label)) return label;
  final stripped =
      label
          .replaceAll(token, ' ')
          // "Open (2026)" must not leave an empty bracket pair behind.
          .replaceAll(RegExp(r'\(\s*\)|\[\s*\]'), ' ')
          .replaceAllMapped(RegExp(r'\s+([,;:.])'), (m) => m.group(1)!)
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll(RegExp(r'^[\s,;:.\-–—/|]+'), '')
          .replaceAll(RegExp(r'[\s,;:\-–—/|]+$'), '')
          .trim();
  return RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(stripped)
      ? stripped
      : label;
}

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
    this.boardSize,
    this.evalWindow,
    this.playMoveSound,
  });

  final GamesTourModel game;
  final String anchorFen;
  final ContinuationLine line;
  final List<GamesTourModel> allGames;
  final int index;

  /// Mini-board edge. Every card in a strip shares one value so the strip can
  /// page card by card; null falls back to the natural size.
  final double? boardSize;

  /// On-screen window kept measured by the hosting panel — see
  /// [ExplorerGamesSection.evalWindow].
  final ValueListenable<ExplorerGamesEvalWindow>? evalWindow;

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
      final chipBox = chipContext.findRenderObject();
      if (chipBox == null) return;
      if (!_chipScrollController.hasClients) return;
      // Only the chip strip may move. `Scrollable.ensureVisible` walks up
      // *every* enclosing scrollable, so it would also re-centre the card
      // inside the explorer list and undo its card-by-card alignment.
      _chipScrollController.position.ensureVisible(
        chipBox,
        alignment: 0.5,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
      );
    });
  }

  String get _eventLine => explorerGameEventLabel(widget.game);

  String get _yearLine => explorerGameYearLabel(widget.game);

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

    // Larger mini-board so cards stay readable when games fill the panel. The
    // strip may hand down a smaller edge when the panel is short — every card
    // in one strip shares it, which is what keeps the paging grid uniform.
    final boardSize =
        widget.boardSize ?? ExplorerGameCardGeometry.preferredBoardSize;
    // Same engine-gauge setting the grid game cards honour. The bar's width is
    // reserved whenever the gauge is on, so a card entering or leaving the
    // viewport swaps only the bar's contents — the board never resizes.
    final showEvalBar =
        ref.watch(engineSettingsProviderNew).valueOrNull?.showEngineGauge ??
        true;
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
    final closeIconColor = context.colors.textSecondary;

    // Reader's text size is part of the card's height, so the continuation
    // band can never crop a chip.
    final textScaler = MediaQuery.textScalerOf(context);
    final stripHeight = ExplorerGameCardGeometry.stripHeight(textScaler);
    final cardHeight = ExplorerGameCardGeometry.cardHeight(
      boardSize,
      textScaler,
    );

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
        // Expanded, not sized: the card's total height is pinned below, and
        // this row absorbs any sub-pixel drift so the board's own padding
        // never overflows.
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleBodyTap,
            child: Container(
              decoration: BoxDecoration(
                color:
                    isFocused
                        ? Color.alphaBlend(
                          kPrimaryColor.withValues(
                            alpha: isLight ? 0.06 : 0.10,
                          ),
                          topSurface,
                        )
                        : topSurface,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12.br),
                  topRight: Radius.circular(12.br),
                ),
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
                        // Eval bar flush against the board's left edge, exactly
                        // as the grid game cards draw it. Its width is taken
                        // from the metadata column on the right (which has room
                        // to spare), so the board keeps its size and the card
                        // its height.
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (showEvalBar)
                              _ExplorerCardEvalBar(
                                width: ExplorerGameCardGeometry.evalBarWidth,
                                height: boardSize,
                                fen: boardFen,
                                index: widget.index,
                                isFocused: isFocused,
                                window: widget.evalWindow,
                              ),
                            GameCardChessboard(
                              fen: boardFen,
                              lastMove: lastMove,
                              boardSize: boardSize,
                              orientation: Side.white,
                              showCoordinates: false,
                              gameStatus: boardStatus,
                            ),
                          ],
                        ),
                      ),
                      // Black top · meta middle (centered) · white bottom, so
                      // the names read in the same order as the mini-board
                      // beside them (drawn `orientation: Side.white`, black
                      // back rank at the top) and as the main board's own
                      // player rows. Height matches the mini-board so scores
                      // and names track its edges.
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
                                  isWhite: false,
                                ),
                                Expanded(
                                  child: _ExplorerCardMetaSlot(
                                    event: _eventLine,
                                    year: _yearLine,
                                  ),
                                ),
                                _ExplorerCardPlayerRow(
                                  game: widget.game,
                                  isWhite: true,
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
                                      .read(
                                        explorerFocusedGameProvider.notifier,
                                      )
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
        ),
        // The continuation band is always drawn, at one constant height: cards
        // that page one at a time may not be taller or shorter than each other
        // because of the line they happen to carry.
        _ContinuationStrip(
          height: stripHeight,
          surface: bottomSurface,
          onTap:
              widget.line.isEmpty
                  ? null
                  : () {
                    if (isFocused) {
                      ref.read(explorerFocusedGameProvider.notifier).clear();
                    } else {
                      _handleFocusRequest(0);
                    }
                  },
          child:
              widget.line.isEmpty
                  ? Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10.sp),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Game ends at this position',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.textXsRegular.copyWith(
                          color: context.colors.textSecondary,
                        ),
                      ),
                    ),
                  )
                  : SingleChildScrollView(
                    controller: _chipScrollController,
                    scrollDirection: Axis.horizontal,
                    // Horizontal inset lives INSIDE the scroll view so chips
                    // are not clipped at the left/right edges of the card.
                    padding: EdgeInsets.symmetric(horizontal: 10.sp),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
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
    if (_freeUserLocked && isFocused) {
      // Drop stale focus if subscription lapsed while a card was focused.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(explorerFocusedGameProvider.notifier).clear();
      });
    }

    final Widget body =
        _freeUserLocked
            ? Stack(
              children: [
                IgnorePointer(child: shell),
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => requirePremiumGuard(context, ref),
                  ),
                ),
              ],
            )
            : shell;

    // One exact height for every card — the contract the inline strip's
    // card-by-card paging rests on.
    return SizedBox(height: cardHeight, child: body);
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

/// Event identity in the gap between the two player rows: the tournament, with
/// the year of the game beneath it in a quieter step.
///
/// The year sits on its own line rather than trailing the event so a long
/// tournament name can fade out without taking the year with it, and so every
/// card in the strip carries it in the same place.
///
/// Two guards keep it inside the slot the mini-board fixes, because the card's
/// height is a hard constant (see [ExplorerGameCardGeometry]): the reader's text
/// size is capped for these two dense lines only, and the year is dropped
/// outright when the slot cannot hold both. Neither line is ever cropped.
class _ExplorerCardMetaSlot extends StatelessWidget {
  const _ExplorerCardMetaSlot({required this.event, required this.year});

  final String event;
  final String year;

  static const double _maxTextScale = 1.2;

  @override
  Widget build(BuildContext context) {
    if (event.isEmpty && year.isEmpty) return const SizedBox.shrink();

    final scaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: _maxTextScale);
    final eventStyle = AppTypography.textXsRegular.copyWith(
      color: context.colors.textPrimaryMuted,
    );
    final yearStyle = AppTypography.textXxsRegular.copyWith(
      color: context.colors.textSecondary,
      letterSpacing: 0.3,
    );
    // Same expressions AppTypography builds these two styles from.
    final eventHeight = scaler.scale(12.f) * (20.h / 12.h);
    final yearHeight = scaler.scale(11.f) * (18.h / 11.h);

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: _maxTextScale,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final room = constraints.maxHeight;
          final showYear =
              year.isNotEmpty &&
              (event.isEmpty ||
                  !room.isFinite ||
                  room >= eventHeight + yearHeight);
          return Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 2.w),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (event.isNotEmpty)
                    _FadingOverflowText(
                      text: event,
                      textAlign: TextAlign.center,
                      style: eventStyle,
                    ),
                  if (showYear)
                    Text(
                      year,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      style: yearStyle,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Constant-height band under the mini-board holding the continuation chips.
///
/// Height never follows its contents: a long line, a short line and a game
/// that ends on the explored position all occupy the same band, which is what
/// lets the strip above page one card at a time.
class _ContinuationStrip extends StatelessWidget {
  const _ContinuationStrip({
    required this.height,
    required this.surface,
    required this.child,
    this.onTap,
  });

  final double height;
  final Color surface;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final band = SizedBox(
      height: height,
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(12.br),
            bottomRight: Radius.circular(12.br),
          ),
        ),
        child: child,
      ),
    );
    if (onTap == null) return band;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: band,
    );
  }
}

/// Shortest gap between two evaluations of the same card.
///
/// The first ply of a walk is rated at once; plies the reader steps through
/// inside this window collapse into one request. Without it, walking a
/// continuation would spend a Gamebase lookup and an engine job on every ply
/// the reader passes over on the way to the one they stop at.
const Duration _kExplorerCardEvalInterval = Duration(milliseconds: 250);

/// Evaluation bar for one inline explorer card.
///
/// Mounts the shared game-card eval widget — the same one the For You feed and
/// every other game card uses, so a position rated here lands in the same cache
/// and comes back from it instantly — but only while this card is on screen.
/// Off screen the slot stays reserved and empty: a strip of ten cards must
/// never queue ten engine jobs behind the one the reader is actually walking.
class _ExplorerCardEvalBar extends StatefulWidget {
  const _ExplorerCardEvalBar({
    required this.width,
    required this.height,
    required this.fen,
    required this.index,
    required this.isFocused,
    required this.window,
  });

  final double width;
  final double height;
  final String fen;
  final int index;
  final bool isFocused;
  final ValueListenable<ExplorerGamesEvalWindow>? window;

  @override
  State<_ExplorerCardEvalBar> createState() => _ExplorerCardEvalBarState();
}

class _ExplorerCardEvalBarState extends State<_ExplorerCardEvalBar> {
  /// Position currently handed to the eval widget. Trails [widget.fen] only
  /// while the reader is stepping faster than [_kExplorerCardEvalInterval], and
  /// always catches up on the ply they stop at.
  late String _ratedFen = widget.fen;
  DateTime? _lastRequest;
  Timer? _pending;

  @override
  void didUpdateWidget(covariant _ExplorerCardEvalBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fen == oldWidget.fen || widget.fen == _ratedFen) return;
    final last = _lastRequest;
    final waited =
        last == null
            ? _kExplorerCardEvalInterval
            : DateTime.now().difference(last);
    if (waited >= _kExplorerCardEvalInterval) {
      _request(widget.fen);
      return;
    }
    // Inside the window: hold, and rate wherever the walk has reached by the
    // time it closes.
    _pending?.cancel();
    _pending = Timer(_kExplorerCardEvalInterval - waited, () {
      if (mounted) _request(widget.fen);
    });
  }

  void _request(String fen) {
    _pending?.cancel();
    _pending = null;
    _lastRequest = DateTime.now();
    setState(() => _ratedFen = fen);
  }

  @override
  void dispose() {
    _pending?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final window = widget.window;
    // No host tracking visibility ⇒ nobody can say this card is on screen, so
    // it does not evaluate. Reserving the slot keeps the card's geometry
    // identical either way.
    if (window == null) return _slot();
    return ValueListenableBuilder<ExplorerGamesEvalWindow>(
      valueListenable: window,
      builder: (context, value, _) {
        // The focused card always evaluates: it is the one being traversed, and
        // waiting on a measurement to catch up would strand it on '...'.
        if (!value.contains(widget.index) && !widget.isFocused) return _slot();
        // Mid-scroll stay on cache and server evals. Starting the engine for a
        // card that is about to leave the viewport only costs the next one time.
        return EvaluationBarWidgetForGames(
          width: widget.width,
          height: widget.height,
          fen: _ratedFen,
          // Cards this small use the grid game card's compact bar treatment.
          playerView: PlayerView.gridView,
          allowStockfishFallback: value.settled,
        );
      },
    );
  }

  Widget _slot() => SizedBox(width: widget.width, height: widget.height);
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
