import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:dartchess/dartchess.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/library/widgets/library_game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../providers/gamebase_explorer_state.dart';
import '../providers/gamebase_providers.dart';

typedef GamebaseSortChanged =
    void Function(GamebaseSortField field, GamebaseSortDirection direction);

Future<void> showGamebaseSortOptions({
  required BuildContext context,
  required GamebaseSortField sortBy,
  required GamebaseSortDirection sortDirection,
  required GamebaseSortChanged onChanged,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder:
        (ctx) => StatefulBuilder(
          builder: (context, setModalState) {
            final bottomPadding = MediaQuery.of(ctx).padding.bottom;
            void handleTap(GamebaseSortField field) {
              final nextDirection =
                  sortBy == field
                      ? (sortDirection == GamebaseSortDirection.desc
                          ? GamebaseSortDirection.asc
                          : GamebaseSortDirection.desc)
                      : GamebaseSortDirection.desc;
              setModalState(() {});
              Navigator.pop(ctx);
              onChanged(field, nextDirection);
            }

            return Container(
              decoration: BoxDecoration(
                color: context.colors.surfaceRecessed,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(20.br),
                ),
              ),
              padding: EdgeInsets.fromLTRB(
                16.w,
                24.h,
                16.w,
                bottomPadding + 16.h,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Sort Games',
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 18.f,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      InkWell(
                        onTap: () => Navigator.pop(ctx),
                        borderRadius: BorderRadius.circular(20.br),
                        child: Container(
                          padding: EdgeInsets.all(4.w),
                          decoration: BoxDecoration(
                            color: context.colors.surface,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close,
                            color: Colors.grey,
                            size: 20.sp,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 24.h),
                  _SortOptionTile(
                    title: 'Average Rating',
                    isSelected: sortBy == GamebaseSortField.avgElo,
                    sortDirection: sortDirection,
                    onTap: () => handleTap(GamebaseSortField.avgElo),
                  ),
                  SizedBox(height: 8.h),
                  _SortOptionTile(
                    title: 'White Rating',
                    isSelected: sortBy == GamebaseSortField.whiteElo,
                    sortDirection: sortDirection,
                    onTap: () => handleTap(GamebaseSortField.whiteElo),
                  ),
                  SizedBox(height: 8.h),
                  _SortOptionTile(
                    title: 'Black Rating',
                    isSelected: sortBy == GamebaseSortField.blackElo,
                    sortDirection: sortDirection,
                    onTap: () => handleTap(GamebaseSortField.blackElo),
                  ),
                  SizedBox(height: 8.h),
                  _SortOptionTile(
                    title: 'Year / Date',
                    isSelected: sortBy == GamebaseSortField.date,
                    sortDirection: sortDirection,
                    onTap: () => handleTap(GamebaseSortField.date),
                  ),
                ],
              ),
            );
          },
        ),
  );
}

class PositionGamesSheet extends ConsumerStatefulWidget {
  const PositionGamesSheet({
    super.key,
    required this.fen,
    required this.title,
    this.uci,
    this.moves = const <String>[],
    this.filters = const GamebaseFilters(),
    this.useFenEndpoint = false,
  });

  final String fen;
  final String title;
  final String? uci;
  final List<String> moves;
  final GamebaseFilters filters;

  /// When true, fetch via `/api/game-position/fen/games` (exact-FEN match)
  /// instead of the move-aggregate endpoint. Used by the pasted-PGN /
  /// FEN-position flow where there is no selected move path.
  final bool useFenEndpoint;

  @override
  ConsumerState<PositionGamesSheet> createState() => _PositionGamesSheetState();
}

class _PositionGamesSheetState extends ConsumerState<PositionGamesSheet> {
  static const int _pageSize = 20;
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

  late GamebaseSortField _sortBy;
  late GamebaseSortDirection _sortDirection;

  @override
  void initState() {
    super.initState();
    _sortBy = widget.filters.sortBy;
    _sortDirection = widget.filters.sortDirection;
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
      isOnline: widget.filters.isOnline,
      minRating: widget.filters.minRating,
      maxRating: widget.filters.maxRating,
      yearFrom: widget.filters.yearFrom,
      yearTo: widget.filters.yearTo,
      sortBy: _sortBy,
      sortDirection: _sortDirection,
      pageNumber: pageNumber,
      pageSize: _pageSize,
    );
  }

  Future<GamebaseSearchQueryResponse> _fetchFenPage(int pageNumber) {
    final timeControlFilter =
        widget.filters.timeControls.isNotEmpty
            ? widget.filters.timeControls.first
            : null;
    final playerIdFilter =
        widget.filters.playerIds.isNotEmpty
            ? widget.filters.playerIds.first
            : null;
    return ref
        .read(gamebaseRepositoryProvider)
        .getFenPositionGames(
          fen: widget.fen,
          uci: widget.uci,
          timeControl: timeControlFilter,
          playerId: playerIdFilter,
          color: widget.filters.playerColor?.name,
          result: widget.filters.gameResult?.apiValue,
          isOnline: widget.filters.isOnline,
          minRating: widget.filters.minRating,
          maxRating: widget.filters.maxRating,
          yearFrom: widget.filters.yearFrom,
          yearTo: widget.filters.yearTo,
          sortBy: _sortBy,
          sortDirection: _sortDirection,
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
      final response =
          widget.useFenEndpoint
              ? await _fetchFenPage(_nextPageNumber)
              : await ref.read(
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
        _totalCount = response.metadata.totalCount ?? _totalCount;
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

  void _showSortOptions() {
    showGamebaseSortOptions(
      context: context,
      sortBy: _sortBy,
      sortDirection: _sortDirection,
      onChanged: (field, direction) {
        setState(() {
          _sortBy = field;
          _sortDirection = direction;
        });
        _fetchPage(reset: true);
      },
    );
  }

  String get _countText {
    if (_isInitialLoading && _games.isEmpty) return 'Searching';
    if (_totalCount != null) return '$_totalCount games';
    if (_games.isEmpty) return '0 games';
    return _hasMore ? '${_games.length}+ games' : '${_games.length} games';
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surfaceRecessed,
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
              countText: _countText,
              onSort: _showSortOptions,
            ),
            Divider(color: context.colors.divider, height: 1),
            Expanded(
              child:
                  _isInitialLoading && _games.isEmpty
                      ? Center(
                        child: CircularProgressIndicator(
                          color: context.colors.textPrimary,
                          strokeWidth: 2,
                        ),
                      )
                      : (_error != null && _games.isEmpty)
                      ? _Empty(message: 'Failed to load games.\n$_error')
                      : (_games.isEmpty)
                      ? const _Empty(message: 'No Games Found')
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

                          return LibraryGameCard(
                            game: game,
                            eventName: eventName,
                            eco: game.roundSlug,
                            date: game.lastMoveTime,
                            showRound: true,
                            onTap: () {
                              String? targetFen = widget.fen;
                              if (widget.uci != null) {
                                try {
                                  final position = Chess.fromSetup(
                                    Setup.parseFen(widget.fen),
                                  );
                                  final from = Square.fromName(
                                    widget.uci!.substring(0, 2),
                                  );
                                  final to = Square.fromName(
                                    widget.uci!.substring(2, 4),
                                  );
                                  Role? promotion;
                                  if (widget.uci!.length > 4) {
                                    promotion = Role.fromChar(widget.uci![4]);
                                  }
                                  final move = NormalMove(
                                    from: from,
                                    to: to,
                                    promotion: promotion,
                                  );
                                  targetFen = position.play(move).fen;
                                } catch (_) {
                                  // Fallback to widget.fen
                                }
                              }
                              _openGame(
                                context,
                                ref,
                                game,
                                _games,
                                index,
                                targetFen,
                              );
                            },
                            onLongPress: null,
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
    );
  }

  static GamesTourModel _mapPreviewToTourModel(Map<String, dynamic> row) {
    int parseInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    int? parsePositiveInt(dynamic value) {
      final parsed = parseInt(value);
      return parsed > 0 ? parsed : null;
    }

    String readString(String key) => (row[key]?.toString() ?? '').trim();

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
    final tourId =
        (row['tour_id']?.toString() ??
                row['tournament_id']?.toString() ??
                event)
            .trim();

    final whiteName =
        (readString('white').isNotEmpty
                ? readString('white')
                : readString('whiteName'))
            .trim();
    final blackName =
        (readString('black').isNotEmpty
                ? readString('black')
                : readString('blackName'))
            .trim();
    final whiteElo = parseInt(row['whiteElo']);
    final blackElo = parseInt(row['blackElo']);
    final whiteFed = readString('whiteFed');
    final blackFed = readString('blackFed');
    final whiteTitle = readString('whiteTitle');
    final blackTitle = readString('blackTitle');
    final whitePlayerId = readString('whitePlayerId');
    final blackPlayerId = readString('blackPlayerId');

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
        federation: whiteFed,
        title: whiteTitle,
        rating: whiteElo,
        countryCode: whiteFed,
        team: null,
        fideId: parsePositiveInt(row['whiteFideId']),
        gamebasePlayerId: whitePlayerId.isNotEmpty ? whitePlayerId : null,
      ),
      blackPlayer: PlayerCard(
        name: blackName.isNotEmpty ? blackName : 'Black',
        federation: blackFed,
        title: blackTitle,
        rating: blackElo,
        countryCode: blackFed,
        team: null,
        fideId: parsePositiveInt(row['blackFideId']),
        gamebasePlayerId: blackPlayerId.isNotEmpty ? blackPlayerId : null,
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
    String? initialFen,
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
          (ctx) => Center(
            child: CircularProgressIndicator(color: context.colors.textPrimary),
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
                initialFen: initialFen,
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
              child: CircularProgressIndicator(
                color: context.colors.textPrimaryMuted,
                strokeWidth: 2,
              ),
            ),
            SizedBox(width: 10.w),
            Text(
              'Loading more games...',
              style: TextStyle(
                color: context.colors.textPrimaryMuted,
                fontSize: 12.f,
              ),
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
              foregroundColor: context.colors.textPrimaryMuted,
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
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 12.f,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12.h),
      child: Center(
        child: Text(
          'Loaded $loadedCount games',
          style: TextStyle(color: context.colors.textSecondary, fontSize: 12.f),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.countText, this.onSort});

  final String title;
  final String countText;
  final VoidCallback? onSort;

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
                color: context.colors.textPrimary,
                fontSize: 14.f,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(width: 8.w),
          Text(
            countText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.textXsRegular.copyWith(
              color: context.colors.textPrimaryMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (onSort != null) ...[
            SizedBox(width: 10.w),
            GestureDetector(
              onTap: onSort,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: context.colors.textPrimary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8.br),
                  border: Border.all(
                    color: context.colors.textPrimary.withValues(alpha: 0.12),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.sort_rounded,
                      color: context.colors.textPrimaryMuted,
                      size: 15.sp,
                    ),
                    SizedBox(width: 5.w),
                    Text(
                      'Sort',
                      style: AppTypography.textXsRegular.copyWith(
                        color: context.colors.textPrimaryMuted,
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
            icon: Icon(
              Icons.close,
              color: context.colors.textSecondary,
              size: 22.ic,
            ),
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
          style: TextStyle(color: context.colors.textSecondary, fontSize: 14.f),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _SortOptionTile extends StatelessWidget {
  const _SortOptionTile({
    required this.title,
    required this.isSelected,
    this.sortDirection,
    required this.onTap,
  });

  final String title;
  final bool isSelected;
  final GamebaseSortDirection? sortDirection;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? kPrimaryColor.withValues(alpha: 0.15)
                  : context.colors.textPrimary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(
            color:
                isSelected
                    ? kPrimaryColor.withValues(alpha: 0.3)
                    : context.colors.textPrimary.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: AppTypography.textSmMedium.copyWith(
                  color:
                      isSelected ? kPrimaryColor : context.colors.textPrimary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            if (isSelected && sortDirection != null)
              Icon(
                sortDirection == GamebaseSortDirection.desc
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_upward_rounded,
                color: kPrimaryColor,
                size: 18.sp,
              ),
            if (!isSelected)
              Icon(
                Icons.arrow_downward_rounded,
                color: context.colors.textPrimary.withValues(alpha: 0.2),
                size: 18.sp,
              ),
          ],
        ),
      ),
    );
  }
}
