import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/library/widgets/library_game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/screens/library/widgets/bulk_add_to_folder_sheet.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/number_format_utils.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

import '../providers/gamebase_explorer_state.dart';
import '../providers/gamebase_providers.dart';

class PositionGamesSheet extends ConsumerStatefulWidget {
  const PositionGamesSheet({
    super.key,
    required this.fen,
    required this.title,
    this.uci,
    this.moves = const <String>[],
    this.filters = const GamebaseFilters(),
  });

  final String fen;
  final String title;
  final String? uci;
  final List<String> moves;
  final GamebaseFilters filters;

  @override
  ConsumerState<PositionGamesSheet> createState() => _PositionGamesSheetState();
}

class _PositionGamesSheetState extends ConsumerState<PositionGamesSheet> {
  static const int _pageSize = 50;
  static const double _scrollPrefetchExtent = 640;
  final ScrollController _scrollController = ScrollController();

  final List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  final List<GamesTourModel> _games = <GamesTourModel>[];
  bool _isInitialLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _nextPageNumber = 0;
  int _requestToken = 0;
  int? _totalCount;
  String? _error;

  bool _isSelectionMode = false;
  final Set<String> _selectedGameIds = <String>{};
  bool _isLoadingAllForSave = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _fetchPage(reset: true);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        _isInitialLoading ||
        _isLoadingMore ||
        !_hasMore) {
      return;
    }
    final position = _scrollController.position;
    if (position.extentAfter > _scrollPrefetchExtent) return;
    _fetchPage();
  }

  GamebasePositionGamesQuery _buildQuery(int pageNumber) {
    final timeControlFilter =
        widget.filters.timeControls.isNotEmpty
            ? widget.filters.timeControls.first
            : null;
    final playerIdFilter =
        widget.filters.playerIds.isNotEmpty
            ? widget.filters.playerIds.first
            : null;

    return GamebasePositionGamesQuery(
      fen: widget.fen,
      moves: widget.moves,
      uci: widget.uci,
      timeControl: timeControlFilter,
      playerId: playerIdFilter,
      color: widget.filters.playerColor?.name,
      result: widget.filters.gameResult?.apiValue,
      minRating: widget.filters.minRating,
      maxRating: widget.filters.maxRating,
      pageNumber: pageNumber,
      pageSize: _pageSize,
    );
  }

  Future<void> _fetchPage({bool reset = false}) async {
    if (reset) {
      setState(() {
        _rows.clear();
        _games.clear();
        _isInitialLoading = true;
        _isLoadingMore = false;
        _hasMore = true;
        _nextPageNumber = 0;
        _totalCount = null;
        _error = null;
      });
    } else {
      if (_isInitialLoading || _isLoadingMore || !_hasMore) return;
      setState(() {
        _isLoadingMore = true;
        _error = null;
      });
    }

    final requestToken = ++_requestToken;
    try {
      final response = await ref.read(
        positionGamesProvider(_buildQuery(_nextPageNumber)).future,
      );
      if (!mounted || requestToken != _requestToken) return;

      final mergedRows = List<Map<String, dynamic>>.from(_rows);
      final mergedGames = List<GamesTourModel>.from(_games);
      final existingIds = <String>{};
      for (final row in _rows) {
        final id = row['id']?.toString().trim();
        if (id != null && id.isNotEmpty) {
          existingIds.add(id);
        }
      }

      for (final row in response.data) {
        final id = row['id']?.toString().trim();
        if (id != null && id.isNotEmpty) {
          if (existingIds.add(id)) {
            mergedRows.add(row);
            mergedGames.add(_mapPreviewToTourModel(row));
          }
        } else {
          mergedRows.add(row);
          mergedGames.add(_mapPreviewToTourModel(row));
        }
      }

      final addedCount = mergedRows.length - _rows.length;
      final hasMoreRows = response.metadata.hasMore && addedCount > 0;

      setState(() {
        _rows
          ..clear()
          ..addAll(mergedRows);
        _games
          ..clear()
          ..addAll(mergedGames);
        _hasMore = hasMoreRows;
        _nextPageNumber += 1;
        _totalCount = response.metadata.totalCount;
        _isInitialLoading = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted || requestToken != _requestToken) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isInitialLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Save-to-library helpers
  // ---------------------------------------------------------------------------

  Future<void> _loadAllRemainingPages() async {
    while (_hasMore && mounted) {
      await _fetchPage();
    }
  }

  Future<void> _handleSaveAll() async {
    if (_games.length > 1) {
      final hasPremium = await requirePremiumGuard(context, ref);
      if (!hasPremium || !mounted) return;
    }

    setState(() => _isLoadingAllForSave = true);
    try {
      await _loadAllRemainingPages();
      if (!mounted) return;
      await showBulkAddToFolderSheet(
        context: context,
        games: _games,
        sourceLabel: widget.title,
      );
    } finally {
      if (mounted) {
        setState(() => _isLoadingAllForSave = false);
      }
    }
  }

  void _enterSelectionMode() {
    HapticFeedback.lightImpact();
    setState(() {
      _isSelectionMode = true;
      _selectedGameIds.clear();
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedGameIds.clear();
      _isLoadingAllForSave = false;
    });
  }

  void _toggleGameSelection(String gameId) {
    HapticFeedback.lightImpact();
    setState(() {
      if (_selectedGameIds.contains(gameId)) {
        _selectedGameIds.remove(gameId);
      } else {
        _selectedGameIds.add(gameId);
      }
    });
  }

  void _selectAllLoaded() {
    setState(() {
      _selectedGameIds
        ..clear()
        ..addAll(_games.map((g) => g.gameId));
    });
  }

  Future<void> _addSelectedToLibrary() async {
    final selectedGames = _games
        .where((g) => _selectedGameIds.contains(g.gameId))
        .toList(growable: false);
    if (selectedGames.isEmpty) return;

    await showBulkAddToFolderSheet(
      context: context,
      games: selectedGames,
      sourceLabel: widget.title,
    );
  }

  void _showSaveToLibraryOptions() {
    final count = _totalCount ?? _games.length;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (ctx) => Container(
            decoration: BoxDecoration(
              color: kBlack3Color,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16.br)),
            ),
            padding: EdgeInsets.fromLTRB(
              16.w,
              20.h,
              16.w,
              MediaQuery.of(ctx).padding.bottom + 16.h,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Save to Library',
                  style: TextStyle(
                    color: kWhiteColor,
                    fontSize: 16.f,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 16.h),
                _SaveOptionTile(
                  icon: Icons.library_add_rounded,
                  title: 'Save all games',
                  subtitle:
                      '${formatCompactCount(count)} ${count == 1 ? 'game' : 'games'}',
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _handleSaveAll();
                  },
                ),
                SizedBox(height: 10.h),
                _SaveOptionTile(
                  icon: Icons.checklist_rounded,
                  title: 'Choose games manually',
                  subtitle: 'Select specific games to save',
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _enterSelectionMode();
                  },
                ),
              ],
            ),
          ),
    );
  }

  // ---------------------------------------------------------------------------
  // Selection toolbar
  // ---------------------------------------------------------------------------

  Widget _buildSelectionToolbar() {
    final selectedCount = _selectedGameIds.length;
    final title =
        selectedCount == 0 ? 'Choose games to save' : '$selectedCount selected';
    final subtitle =
        _isLoadingAllForSave
            ? 'Loading all games...'
            : 'Tap games manually or use quick select';

    return SingleMotionBuilder(
      motion: const CupertinoMotion.bouncy(),
      value: 1.0,
      builder: (context, progress, child) {
        return Opacity(
          opacity: progress.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1.0 - progress) * -10),
            child: Padding(
              padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 8.h),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
                decoration: BoxDecoration(
                  color: kBlack2Color,
                  borderRadius: BorderRadius.circular(16.br),
                  border: Border.all(
                    color: kPrimaryColor.withValues(alpha: 0.3),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: kPrimaryColor.withValues(alpha: 0.1),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                style: AppTypography.textSmMedium.copyWith(
                                  color: kWhiteColor,
                                ),
                              ),
                              SizedBox(height: 2.h),
                              Text(
                                subtitle,
                                style: AppTypography.textXsRegular.copyWith(
                                  color: kWhiteColor.withValues(alpha: 0.55),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: 8.w),
                        GestureDetector(
                          onTap: _exitSelectionMode,
                          child: Container(
                            width: 28.w,
                            height: 28.h,
                            decoration: BoxDecoration(
                              color: kWhiteColor.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              size: 16.sp,
                              color: kWhiteColor.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 10.h),
                    Row(
                      children: [
                        Expanded(
                          child: _SelectionActionButton(
                            label:
                                'Select all (${formatCompactCount(_games.length)})',
                            icon: Icons.select_all_rounded,
                            onTap: _selectAllLoaded,
                          ),
                        ),
                        SizedBox(width: 8.w),
                        Expanded(
                          child: _SelectionActionButton(
                            label:
                                selectedCount > 0
                                    ? 'Add selected'
                                    : 'Select first',
                            icon: Icons.library_add_rounded,
                            emphasized: selectedCount > 0,
                            onTap:
                                selectedCount > 0
                                    ? _addSelectedToLibrary
                                    : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSelectableCardWrapper(Widget child, {required bool isSelected}) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14.br),
            border: Border.all(
              color:
                  isSelected
                      ? kPrimaryColor.withValues(alpha: 0.85)
                      : Colors.transparent,
              width: 1.6,
            ),
            boxShadow:
                isSelected
                    ? [
                      BoxShadow(
                        color: kPrimaryColor.withValues(alpha: 0.22),
                        blurRadius: 18,
                        spreadRadius: 0.5,
                        offset: const Offset(0, 2),
                      ),
                    ]
                    : null,
          ),
          child: child,
        ),
        Positioned(
          top: -6.h,
          right: -6.w,
          child: Container(
            width: 24.w,
            height: 24.h,
            decoration: BoxDecoration(
              color:
                  isSelected
                      ? kPrimaryColor
                      : kBlack2Color.withValues(alpha: 0.95),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: kBackgroundColor.withValues(alpha: 0.55),
                  blurRadius: 8,
                  spreadRadius: 0.5,
                  offset: const Offset(0, 2),
                ),
              ],
              border: Border.all(
                color:
                    isSelected
                        ? kWhiteColor
                        : kWhiteColor.withValues(alpha: 0.24),
                width: 1.2,
              ),
            ),
            child: Icon(
              isSelected
                  ? Icons.check_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 14.5.sp,
              color: kWhiteColor,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: kBlack3Color,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.br)),
      ),
      child: ConstrainedBox(
        constraints:
            ResponsiveHelper.bottomSheetConstraints ?? const BoxConstraints(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(
              title: widget.title,
              onSaveToLibrary:
                  _games.isNotEmpty &&
                          !_isSelectionMode &&
                          !_isLoadingAllForSave
                      ? _showSaveToLibraryOptions
                      : null,
            ),
            if (_isSelectionMode) _buildSelectionToolbar(),
            Divider(color: kDividerColor, height: 1),
            Expanded(
              child:
                  _isInitialLoading && _games.isEmpty
                      ? const Center(
                        child: CircularProgressIndicator(
                          color: kWhiteColor,
                          strokeWidth: 2,
                        ),
                      )
                      : (_error != null && _games.isEmpty)
                      ? _Empty(message: 'Failed to load games.\n$_error')
                      : (_games.isEmpty)
                      ? const _Empty(
                        message: 'No games found for this position.',
                      )
                      : ListView.separated(
                        controller: _scrollController,
                        padding: EdgeInsets.only(
                          top: 8.sp,
                          bottom: 8.sp + bottomPadding,
                          left: 12.sp,
                          right: 12.sp,
                        ),
                        itemCount: _games.length + 1,
                        separatorBuilder: (_, __) => SizedBox(height: 8.sp),
                        itemBuilder: (context, index) {
                          if (index == _games.length) {
                            return _PositionGamesFooter(
                              isLoadingMore: _isLoadingMore,
                              hasMore: _hasMore,
                              loadedCount: _games.length,
                              totalCount: _totalCount,
                              onLoadMore: _fetchPage,
                            );
                          }

                          final game = _games[index];
                          final eventName =
                              (game.tourId.trim().isNotEmpty)
                                  ? game.tourId
                                  : 'Gamebase';

                          Widget gameCard = LibraryGameCard(
                            game: game,
                            eventName: eventName,
                            eco: game.roundSlug,
                            date: game.lastMoveTime,
                            showRound: true,
                            onTap:
                                _isSelectionMode
                                    ? () => _toggleGameSelection(game.gameId)
                                    : () => _openGame(
                                      context,
                                      ref,
                                      game,
                                      _games,
                                      index,
                                    ),
                            onLongPress: null,
                          );

                          if (_isSelectionMode) {
                            gameCard = _buildSelectableCardWrapper(
                              gameCard,
                              isSelected: _selectedGameIds.contains(
                                game.gameId,
                              ),
                            );
                          }

                          return gameCard;
                        },
                      ),
            ),
          ],
        ),
      ),
    );
  }

  static GamesTourModel _mapPreviewToTourModel(Map<String, dynamic> row) {
    final id = (row['id']?.toString() ?? '').trim();
    final safeId = id.isNotEmpty ? id : 'unknown';

    DateTime? date;
    final rawDate = row['date'];
    if (rawDate != null) {
      date = DateTime.tryParse(rawDate.toString());
    }

    final resultStr = row['result']?.toString() ?? '*';
    final timeControl = row['timeControl']?.toString();
    final eco = row['eco']?.toString() ?? '';
    final opening = row['opening']?.toString() ?? '';
    final variation = row['variation']?.toString() ?? '';
    final event = (row['event']?.toString() ?? '').trim();
    final tourId = (row['tour_id']?.toString() ??
            row['tournament_id']?.toString() ??
            event)
        .trim();

    final whiteName = (row['white']?.toString() ?? '').trim();
    final blackName = (row['black']?.toString() ?? '').trim();
    final whiteElo = (row['whiteElo'] as num?)?.toInt() ?? 0;
    final blackElo = (row['blackElo'] as num?)?.toInt() ?? 0;
    final whiteFed = row['whiteFed']?.toString() ?? '';
    final blackFed = row['blackFed']?.toString() ?? '';
    final whitePlayerId = row['whitePlayerId']?.toString().trim();
    final blackPlayerId = row['blackPlayerId']?.toString().trim();

    final formatCode =
        (eco.trim().isNotEmpty) ? eco.trim() : (timeControl ?? '');
    final openingName =
        (variation.trim().isNotEmpty)
            ? '$opening: $variation'
            : (opening.trim().isNotEmpty ? opening : null);

    return GamesTourModel(
      gameId: safeId,
      source: GameSource.gamebase,
      whitePlayer: PlayerCard(
        name: whiteName.isNotEmpty ? whiteName : 'White',
        federation: '',
        title: '',
        rating: whiteElo,
        countryCode: whiteFed,
        team: null,
        fideId: null,
        gamebasePlayerId:
            (whitePlayerId != null && whitePlayerId.isNotEmpty)
                ? whitePlayerId
                : null,
      ),
      blackPlayer: PlayerCard(
        name: blackName.isNotEmpty ? blackName : 'Black',
        federation: '',
        title: '',
        rating: blackElo,
        countryCode: blackFed,
        team: null,
        fideId: null,
        gamebasePlayerId:
            (blackPlayerId != null && blackPlayerId.isNotEmpty)
                ? blackPlayerId
                : null,
      ),
      whiteTimeDisplay: '--:--',
      blackTimeDisplay: '--:--',
      whiteClockCentiseconds: 0,
      blackClockCentiseconds: 0,
      gameStatus: GameStatus.fromString(resultStr),
      roundId: 'opening_explorer',
      roundSlug: formatCode.isNotEmpty ? formatCode : null,
      tourId: tourId.isNotEmpty ? tourId : 'Gamebase',
      tourSlug: null,
      lastMoveTime: date,
      eco: eco.trim().isNotEmpty ? eco.trim() : null,
      openingName: openingName,
      timeControl: timeControl,
    );
  }

  static Future<void> _openGame(
    BuildContext context,
    WidgetRef ref,
    GamesTourModel game,
    List<GamesTourModel> allGames,
    int currentIndex,
  ) async {
    // Premium guard - show paywall if not subscribed
    final hasPremium = await requirePremiumGuard(context, ref);
    if (!hasPremium) return;
    if (!context.mounted) return;

    // Ensure the chessboard screen renders as a "tour game" view.
    ref.read(chessboardViewFromProviderNew.notifier).state =
        ChessboardView.tour;

    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => const Center(
            child: CircularProgressIndicator(color: kWhiteColor),
          ),
    );

    try {
      final repo = ref.read(gamebaseRepositoryProvider);
      final gameWithPgn = await repo.getGameWithPgn(game.gameId);

      String? pgn;
      if (gameWithPgn != null) {
        if (gameWithPgn.pgn != null && gameWithPgn.pgn!.trim().isNotEmpty) {
          if (pgnHasMoves(gameWithPgn.pgn)) {
            pgn = gameWithPgn.pgn;
          }
        }
        if (pgn == null && gameWithPgn.data != null) {
          final built = buildPgnFromGamebaseData(gameWithPgn.data);
          if (built != null && pgnHasMoves(built)) pgn = built;
        }
      }

      // Header-only fallback (still lets users open the viewer without hard failing).
      pgn ??= buildHeaderOnlyPgn(
        whiteName: game.whitePlayer.name,
        blackName: game.blackPlayer.name,
        result: game.gameStatus.displayText,
        event: game.tourId,
        eco: game.roundSlug,
        date: game.lastMoveTime,
      );

      if (!context.mounted) return;
      Navigator.of(context).pop(); // loading

      final boardGames = allGames
          .map((g) => g.gameId == game.gameId ? g.copyWith(pgn: pgn) : g)
          .toList(growable: false);
      final safeIndex = currentIndex.clamp(0, boardGames.length - 1);

      Navigator.of(context).push(
        MaterialPageRoute(
          builder:
              (_) => ChessBoardScreenNew(
                games: boardGames,
                currentIndex: safeIndex,
                disableGamebaseOverlayByDefault: true,
              ),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      Navigator.of(context).pop(); // loading
      // Keep errors non-fatal; user can continue exploring.
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to open game')));
    }
  }
}

class _PositionGamesFooter extends StatelessWidget {
  const _PositionGamesFooter({
    required this.isLoadingMore,
    required this.hasMore,
    required this.loadedCount,
    required this.totalCount,
    required this.onLoadMore,
  });

  final bool isLoadingMore;
  final bool hasMore;
  final int loadedCount;
  final int? totalCount;
  final Future<void> Function({bool reset}) onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (isLoadingMore) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 14.h),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16.w,
              height: 16.h,
              child: const CircularProgressIndicator(
                color: kWhiteColor70,
                strokeWidth: 2,
              ),
            ),
            SizedBox(width: 10.w),
            Text(
              'Loading more games...',
              style: TextStyle(color: kWhiteColor70, fontSize: 12.f),
            ),
          ],
        ),
      );
    }

    if (hasMore) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 12.h),
        child: Center(
          child: TextButton(
            onPressed: () => onLoadMore(),
            style: TextButton.styleFrom(
              foregroundColor: kWhiteColor70,
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
            ),
            child: Text(
              totalCount != null
                  ? 'Load more ($loadedCount / $totalCount)'
                  : 'Load more',
              style: TextStyle(fontSize: 12.f, fontWeight: FontWeight.w500),
            ),
          ),
        ),
      );
    }

    if (totalCount != null) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 12.h),
        child: Center(
          child: Text(
            'Loaded all $totalCount games',
            style: TextStyle(color: kSecondaryTextColor, fontSize: 12.f),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12.h),
      child: Center(
        child: Text(
          'Loaded $loadedCount games',
          style: TextStyle(color: kSecondaryTextColor, fontSize: 12.f),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, this.onSaveToLibrary});

  final String title;
  final VoidCallback? onSaveToLibrary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.sp, 16.sp, 16.sp, 12.sp),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: kWhiteColor,
                fontSize: 14.f,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onSaveToLibrary != null) ...[
            GestureDetector(
              onTap: onSaveToLibrary,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: kPrimaryColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8.br),
                  border: Border.all(
                    color: kPrimaryColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.library_add_rounded,
                      color: kPrimaryColor,
                      size: 15.sp,
                    ),
                    SizedBox(width: 5.w),
                    Text(
                      'Save',
                      style: AppTypography.textXsRegular.copyWith(
                        color: kPrimaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(width: 6.w),
          ],
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.close, color: kSecondaryTextColor, size: 22.ic),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(16.sp),
        child: Text(
          message,
          style: TextStyle(color: kSecondaryTextColor, fontSize: 14.f),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _SaveOptionTile extends StatelessWidget {
  const _SaveOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        decoration: BoxDecoration(
          color: kWhiteColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(color: kWhiteColor.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            Container(
              width: 40.w,
              height: 40.h,
              decoration: BoxDecoration(
                color: kPrimaryColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: kPrimaryColor, size: 20.sp),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.textSmMedium.copyWith(
                      color: kWhiteColor,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    subtitle,
                    style: AppTypography.textXsRegular.copyWith(
                      color: kWhiteColor.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: kWhiteColor.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionActionButton extends StatelessWidget {
  const _SelectionActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.emphasized = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 9.h),
        decoration: BoxDecoration(
          color:
              enabled
                  ? (emphasized
                      ? kPrimaryColor
                      : kWhiteColor.withValues(alpha: 0.1))
                  : kWhiteColor.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10.br),
          border: Border.all(
            color:
                enabled
                    ? (emphasized
                        ? kPrimaryColor.withValues(alpha: 0.8)
                        : kWhiteColor.withValues(alpha: 0.18))
                    : kWhiteColor.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16.sp,
              color:
                  enabled ? kWhiteColor : kWhiteColor.withValues(alpha: 0.45),
            ),
            SizedBox(width: 6.w),
            Flexible(
              child: Text(
                label,
                style: AppTypography.textSmBold.copyWith(
                  color:
                      enabled
                          ? kWhiteColor
                          : kWhiteColor.withValues(alpha: 0.45),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
