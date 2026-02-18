import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/library/widgets/library_game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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
  static const int _eagerPrefetchCap = 1000;
  final ScrollController _scrollController = ScrollController();

  final List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  bool _isInitialLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _nextPageNumber = 0;
  int _requestToken = 0;
  int? _totalCount;
  String? _error;

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
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels < position.maxScrollExtent - 420) return;
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
          }
        } else {
          mergedRows.add(row);
        }
      }

      final addedCount = mergedRows.length - _rows.length;
      final hasMoreRows = response.metadata.hasMore && addedCount > 0;

      setState(() {
        _rows
          ..clear()
          ..addAll(mergedRows);
        _hasMore = hasMoreRows;
        _nextPageNumber += 1;
        _totalCount = response.metadata.totalCount;
        _isInitialLoading = false;
        _isLoadingMore = false;
      });

      final eagerTarget =
          (_totalCount != null && _totalCount! < _eagerPrefetchCap)
              ? _totalCount!
              : _eagerPrefetchCap;
      final shouldEagerPrefetch = _hasMore && _rows.length < eagerTarget;
      if (shouldEagerPrefetch) {
        Future<void>.microtask(() => _fetchPage());
      }
    } catch (e) {
      if (!mounted || requestToken != _requestToken) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isInitialLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final games = _rows.map(_mapPreviewToTourModel).toList(growable: false);

    return SafeArea(
      top: false,
      child: Container(
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
              _Header(title: widget.title),
              Divider(color: kDividerColor, height: 1),
              Expanded(
                child:
                    _isInitialLoading && games.isEmpty
                        ? const Center(
                          child: CircularProgressIndicator(
                            color: kWhiteColor,
                            strokeWidth: 2,
                          ),
                        )
                        : (_error != null && games.isEmpty)
                        ? _Empty(message: 'Failed to load games.\n$_error')
                        : (games.isEmpty)
                        ? const _Empty(message: 'No games found for this position.')
                        : ListView.separated(
                          controller: _scrollController,
                          padding: EdgeInsets.symmetric(
                            vertical: 8.sp,
                            horizontal: 12.sp,
                          ),
                          itemCount: games.length + 1,
                          separatorBuilder: (_, __) => SizedBox(height: 8.sp),
                          itemBuilder: (context, index) {
                            if (index == games.length) {
                              return _PositionGamesFooter(
                                isLoadingMore: _isLoadingMore,
                                hasMore: _hasMore,
                                loadedCount: games.length,
                                totalCount: _totalCount,
                                onLoadMore: _fetchPage,
                              );
                            }

                            final game = games[index];
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
                              onTap: () => _openGame(context, ref, game),
                              onLongPress: null,
                            );
                          },
                        ),
              ),
            ],
          ),
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
    final event = row['event']?.toString() ?? '';

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
      tourId: event.trim().isNotEmpty ? event.trim() : 'Gamebase',
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
  ) async {
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

      Navigator.of(context).push(
        MaterialPageRoute(
          builder:
              (_) => ChessBoardScreenNew(
                games: [game.copyWith(pgn: pgn)],
                currentIndex: 0,
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
  const _Header({required this.title});

  final String title;

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
