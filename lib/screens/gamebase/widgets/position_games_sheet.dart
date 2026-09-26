import 'dart:async';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:dartchess/dartchess.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/library/widgets/library_game_card.dart';
import 'package:chessever2/screens/my_space/actions/space_menu_action.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/player_profile/utils/twic_event_identity.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/game_space_shortcut.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/logger/logger.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../providers/explorer_game_focus_provider.dart';
import '../providers/explorer_games_cache.dart';
import '../providers/gamebase_explorer_state.dart';
import '../providers/gamebase_providers.dart';

typedef GamebaseSortChanged =
    void Function(GamebaseSortField field, GamebaseSortDirection direction);

/// The surface every Opening Explorer sheet and panel is painted on: the games
/// sheet, its sort sheet, the filter sheet and the panel under the board.
///
/// Dark keeps the historic recessed tone. Light cannot: the explorer's game
/// cards are built from `surfaceRecessed` (the player band) and `surface` (the
/// footer, chips and fields), so a `surfaceRecessed` sheet swallowed the whole
/// player band and left only loose footer strips floating on it. On the page
/// [AppColors.background] the band sits a step darker and the paper a step
/// lighter, the footing those cards have on every other light-mode list and
/// on the board screen's explorer page.
Color explorerSheetSurface(BuildContext context) =>
    context.isLightTheme
        ? context.colors.background
        : context.colors.surfaceRecessed;

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
                color: explorerSheetSurface(context),
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
                            color:
                                context.isLightTheme
                                    ? context.colors.iconSecondary
                                    : Colors.grey,
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
    @visibleForTesting this.openGame = openGamebaseGame,
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

  /// Opens a tapped game. Always [openGamebaseGame] outside tests.
  final GamebaseGameOpener openGame;

  @override
  ConsumerState<PositionGamesSheet> createState() => _PositionGamesSheetState();
}

class _PositionGamesSheetState extends ConsumerState<PositionGamesSheet> {
  static const double _scrollPrefetchExtent = 640;
  final ScrollController _scrollController = ScrollController();

  /// The rows on screen and their cards. Always replaced by a new list, never
  /// edited in place: a tap hands the list it saw to the board, and a first
  /// page refreshed underneath it must not change which game that tap opens.
  List<Map<String, dynamic>> _rows = const <Map<String, dynamic>>[];
  List<GamesTourModel> _games = const <GamesTourModel>[];
  bool _isInitialLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _nextPageNumber = 0;
  int? _totalCount;
  String? _error;

  /// Bumped on every reset (opening, a sort change). Work started for an
  /// older generation is dropped when it lands.
  int _generation = 0;

  /// Whether page 0 on screen is a current server answer. While it is not,
  /// the rows are a saved copy being checked and paging waits, so a later
  /// page is never stacked on the offsets of a first page that may shift.
  bool _firstPageCurrent = false;

  /// When the saved copy on screen was fetched; null once page 0 is current.
  DateTime? _savedAt;

  /// When the current page 0 was asked for. A later page asked for before it
  /// (an earlier open of this sheet, held or still on the wire) is asked for
  /// again rather than appended, so its offsets match the first page on
  /// screen.
  DateTime? _firstPageFetchedAt;

  /// The check of the saved copy on screen failed.
  bool _refreshFailed = false;

  /// This load has shown a saved copy, so the header's count slot keeps the
  /// width it had while the copy was checked.
  bool _savedCopyShown = false;

  /// The reader reached the end of the list while paging was held for the
  /// saved copy's check. Paging picks up as soon as page 0 is current.
  bool _pagingDeferred = false;

  final Stopwatch _openWatch = Stopwatch();
  bool _paintRecorded = false;

  late GamebaseSortField _sortBy;
  late GamebaseSortDirection _sortDirection;

  bool get _showingSaved => !_firstPageCurrent && _savedAt != null;

  @override
  void initState() {
    super.initState();
    _sortBy = widget.filters.sortBy;
    _sortDirection = widget.filters.sortDirection;
    _scrollController.addListener(_onScroll);
    _loadFirstPage();
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
    if (!_firstPageCurrent) {
      // Held until page 0 is current; resumed by [_resumeDeferredPaging].
      _pagingDeferred = true;
      return;
    }
    _loadMore();
  }

  /// Page 0 just became current. If the reader got to the end of the list
  /// while it was being checked, load the next page now rather than waiting
  /// for another scroll that may never come.
  void _resumeDeferredPaging() {
    if (!_pagingDeferred) return;
    _pagingDeferred = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onScroll();
    });
  }

  /// Built through the shared factory so every warm-up addresses the exact
  /// `positionGamesProvider` entry (and saved page) this sheet reads. The
  /// exact-FEN sheet goes through the same provider and cache as the rest.
  GamebasePositionGamesQuery _buildQuery(int pageNumber) {
    return GamebasePositionGamesQuery.sheetPage(
      fen: widget.fen,
      filters: widget.filters,
      moves: widget.moves,
      uci: widget.uci,
      sortBy: _sortBy,
      sortDirection: _sortDirection,
      pageNumber: pageNumber,
      useFenEndpoint: widget.useFenEndpoint,
    );
  }

  /// Opens (or re-sorts) the list at page 0.
  ///
  /// 1. A current server answer already held paints in the first frame and
  ///    is final.
  /// 2. Otherwise a first page held in memory, or read back from disk, paints
  ///    at once as a saved copy, and the server is asked again behind it.
  /// 3. With nothing held, the list waits for the server as it always has.
  void _loadFirstPage() {
    final generation = ++_generation;
    _openWatch
      ..reset()
      ..start();
    _paintRecorded = false;
    _rows = const <Map<String, dynamic>>[];
    _games = const <GamesTourModel>[];
    _isInitialLoading = true;
    _isLoadingMore = false;
    _hasMore = true;
    _nextPageNumber = 0;
    _totalCount = null;
    _error = null;
    _firstPageCurrent = false;
    _savedAt = null;
    _firstPageFetchedAt = null;
    _refreshFailed = false;
    _savedCopyShown = false;
    _pagingDeferred = false;

    final query = _buildQuery(0);
    final cache = ref.read(explorerGamesCacheProvider);
    final held = ref.read(positionGamesProvider(query));
    if (!held.isLoading && held.hasValue && cache.isFresh(held.requireValue)) {
      _applyFirstPage(held.requireValue, source: ExplorerGamesSource.memory);
      _refresh();
      return;
    }

    final saved =
        cache.peek(query) ??
        (held.hasValue
            ? ExplorerGamesSnapshot(
              response: held.requireValue,
              fetchedAt:
                  cache.fetchedAtOf(held.requireValue) ??
                  DateTime.fromMillisecondsSinceEpoch(0),
              source: ExplorerGamesSource.memory,
            )
            : null);
    if (saved != null) {
      _showSaved(saved);
    } else {
      // Nothing in memory: the disk usually answers well before the server.
      unawaited(
        cache.read(query).then((snapshot) {
          if (snapshot == null || !mounted || generation != _generation) {
            return;
          }
          if (_firstPageCurrent || _showingSaved) return;
          _showSaved(snapshot, afterFailure: _error != null);
        }),
      );
    }

    if (!held.isLoading && (held.hasValue || held.hasError)) {
      // A settled answer that is too old (or failed) is asked for again. Done
      // after this frame so no provider changes while the sheet builds.
      scheduleMicrotask(() {
        if (!mounted || generation != _generation) return;
        final current = ref.read(positionGamesProvider(query));
        if (!current.isLoading) ref.invalidate(positionGamesProvider(query));
        _revalidate(query, generation);
      });
    } else {
      _revalidate(query, generation);
    }
    _refresh();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  /// Paints [snapshot] as a saved copy while the server is asked again.
  void _showSaved(ExplorerGamesSnapshot snapshot, {bool afterFailure = false}) {
    // An empty saved page would flash "No games" before the real answer.
    if (snapshot.response.data.isEmpty) return;
    _applyFirstPage(snapshot.response, source: snapshot.source, current: false);
    _savedAt = snapshot.fetchedAt;
    _savedCopyShown = true;
    if (afterFailure) {
      _refreshFailed = true;
      _error = null;
    }
    _refresh();
  }

  Future<void> _revalidate(GamebasePositionGamesQuery query, int generation) async {
    try {
      final response = await ref.read(positionGamesProvider(query).future);
      if (!mounted || generation != _generation) return;
      setState(() {
        _applyFirstPage(response, source: ExplorerGamesSource.network);
      });
      _resumeDeferredPaging();
    } catch (e, st) {
      talker.handle(e, st);
      if (!mounted || generation != _generation) return;
      setState(() {
        if (_showingSaved) {
          // Keep the saved rows, marked as saved; paging stays held.
          _refreshFailed = true;
        } else {
          _error = userFacingError(e);
          _isInitialLoading = false;
        }
      });
    }
  }

  void _retryRefresh() {
    final generation = _generation;
    final query = _buildQuery(0);
    setState(() => _refreshFailed = false);
    final current = ref.read(positionGamesProvider(query));
    if (!current.isLoading && current.hasError) {
      ref.invalidate(positionGamesProvider(query));
    }
    _revalidate(query, generation);
  }

  /// Installs [response] as page 0. [current] is false for a saved copy.
  ///
  /// When a current answer replaces a saved copy with the very same rows,
  /// the lists on screen are kept as they are.
  void _applyFirstPage(
    GamebaseSearchQueryResponse response, {
    required ExplorerGamesSource source,
    bool current = true,
  }) {
    final rows = <Map<String, dynamic>>[];
    final existingIds = <String>{};
    for (final row in response.data) {
      final id = row['id']?.toString().trim();
      if (id != null && id.isNotEmpty && !existingIds.add(id)) continue;
      rows.add(row);
    }

    if (!_sameRows(rows)) {
      _rows = List<Map<String, dynamic>>.unmodifiable(rows);
      _games = List<GamesTourModel>.unmodifiable(
        rows.map(_mapPreviewToTourModel),
      );
    }
    _hasMore = response.metadata.hasMore && rows.isNotEmpty;
    _nextPageNumber = 1;
    _totalCount = response.metadata.totalCount;
    _isInitialLoading = false;
    _isLoadingMore = false;
    _error = null;
    _firstPageCurrent = current;
    if (current) {
      _savedAt = null;
      _refreshFailed = false;
      _firstPageFetchedAt = ref
          .read(explorerGamesCacheProvider)
          .fetchedAtOf(response);
    }
    if (!_paintRecorded) {
      _paintRecorded = true;
      _openWatch.stop();
      recordExplorerGamesPaint(
        surface: 'games sheet',
        source: source,
        elapsed: _openWatch.elapsed,
      );
    }
  }

  bool _sameRows(List<Map<String, dynamic>> rows) {
    if (rows.length != _rows.length) return false;
    return const DeepCollectionEquality().equals(rows, _rows);
  }

  /// The next page, appended after the rows on screen. Only ever asked on
  /// top of a current page 0.
  Future<void> _loadMore() async {
    if (!_firstPageCurrent ||
        _isInitialLoading ||
        _isLoadingMore ||
        !_hasMore) {
      return;
    }
    final generation = _generation;
    final pageNumber = _nextPageNumber;
    setState(() {
      _isLoadingMore = true;
      _error = null;
    });

    bool stillWanted() =>
        mounted && generation == _generation && pageNumber == _nextPageNumber;

    try {
      final query = _buildQuery(pageNumber);
      _dropHeldPageOlderThanFirst(query);
      var response = await ref.read(positionGamesProvider(query).future);
      if (!stillWanted()) return;
      if (_askedBeforeFirstPage(response)) {
        // It was still on the wire from before the page 0 on screen was
        // asked for (an earlier open of this sheet), so it may sit on
        // offsets that page 0 has moved since. Asked again, once: the new
        // request goes out after page 0's.
        ref.invalidate(positionGamesProvider(query));
        response = await ref.read(positionGamesProvider(query).future);
        if (!stillWanted()) return;
      }

      final mergedRows = List<Map<String, dynamic>>.of(_rows);
      final mergedGames = List<GamesTourModel>.of(_games);
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
        _rows = List<Map<String, dynamic>>.unmodifiable(mergedRows);
        _games = List<GamesTourModel>.unmodifiable(mergedGames);
        _hasMore = hasMoreRows;
        _nextPageNumber += 1;
        _totalCount = response.metadata.totalCount ?? _totalCount;
        _isLoadingMore = false;
      });
    } catch (e, st) {
      talker.handle(e, st);
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = userFacingError(e);
        _isLoadingMore = false;
      });
    }
  }

  /// A later page is only appended if it was asked for no earlier than the
  /// page 0 on screen. One held from before (an earlier open of this sheet,
  /// still retained) may sit on offsets that have since shifted, so it is
  /// asked for again; so is one that failed. One still on the wire is
  /// checked when it lands (see [_loadMore]).
  void _dropHeldPageOlderThanFirst(GamebasePositionGamesQuery query) {
    final provider = positionGamesProvider(query);
    if (!ref.exists(provider)) return;
    final held = ref.read(provider);
    if (held.isLoading) return;
    if (held.hasValue &&
        !held.hasError &&
        !_askedBeforeFirstPage(held.requireValue)) {
      return;
    }
    ref.invalidate(provider);
  }

  /// Whether [page] was asked for before the page 0 on screen was, compared
  /// by when each request went out, never by when it landed: a slow request
  /// sent earlier still answers for the earlier moment. Unknown counts as
  /// before.
  bool _askedBeforeFirstPage(GamebaseSearchQueryResponse page) {
    final askedAt = ref.read(explorerGamesCacheProvider).fetchedAtOf(page);
    final firstAt = _firstPageFetchedAt;
    return askedAt == null || firstAt == null || askedAt.isBefore(firstAt);
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
        _loadFirstPage();
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
        color: explorerSheetSurface(context),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.br)),
      ),
      child: ConstrainedBox(
        constraints:
            ResponsiveHelper.bottomSheetConstraints ?? const BoxConstraints(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // A saved copy's state lives in the header's count slot, which
            // keeps one size while the copy is checked, fails and is retried:
            // the title never re-wraps and the rows below never move.
            _Header(
              title: widget.title,
              countText: _countText,
              savedCopy:
                  _showingSaved
                      ? (_refreshFailed
                          ? _SavedCopyState.failed
                          : _SavedCopyState.checking)
                      : null,
              savedCopyShown: _savedCopyShown,
              onRetry: _retryRefresh,
              onSort: _showSortOptions,
              onClose: () => Navigator.of(context).pop(),
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
                      ? _Empty(
                        message:
                            widget.useFenEndpoint
                                ? 'No games match this position'
                                : 'No Games Found',
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
                              checkingSavedCopy:
                                  _showingSaved && !_refreshFailed,
                              refreshFailed: _showingSaved && _refreshFailed,
                              savedAt: _savedAt,
                              onLoadMore: _loadMore,
                              onRetry: _retryRefresh,
                            );
                          }

                          final game = _games[index];
                          final eventName =
                              (game.tourId.trim().isNotEmpty)
                                  ? game.tourId
                                  : 'Gamebase';

                          void openGame() {
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
                          }

                          Widget buildCard({VoidCallback? onLongPress}) =>
                              LibraryGameCard(
                                game: game,
                                eventName: eventName,
                                eco: game.roundSlug,
                                date: game.lastMoveTime,
                                showRound: true,
                                onTap: openGame,
                                onLongPress: onLongPress,
                              );

                          // The Builder hands the menu the card's own box to
                          // anchor to; the item context is the whole sliver.
                          return Builder(
                            builder:
                                (cardContext) => buildCard(
                                  onLongPress:
                                      () => _showGameActions(
                                        cardContext,
                                        game,
                                        openGame,
                                        buildCard,
                                      ),
                                ),
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
    );
  }

  /// Long-press menu for an explorer game: open it, or pin it to My Space.
  void _showGameActions(
    BuildContext cardContext,
    GamesTourModel game,
    VoidCallback onOpen,
    Widget Function({VoidCallback? onLongPress}) buildCard,
  ) {
    final spaceDraft = gameSpaceShortcutDraft(game);
    showLibraryContextMenu(
      context: cardContext,
      previewBuilder: (_) => buildCard(),
      onPreviewTap: onOpen,
      actions: [
        LibraryMenuAction(
          icon: Icons.open_in_new_rounded,
          label: 'Open game',
          onSelected: onOpen,
        ),
        if (spaceDraft != null)
          spaceMenuAction(context: cardContext, ref: ref, draft: spaceDraft),
      ],
    );
  }

  static GamesTourModel _mapPreviewToTourModel(Map<String, dynamic> row) =>
      mapGamebasePreviewToTourModel(row);

  Future<void> _openGame(
    BuildContext context,
    WidgetRef ref,
    GamesTourModel game,
    List<GamesTourModel> allGames,
    int currentIndex,
    String? initialFen,
  ) => widget.openGame(context, ref, game, allGames, currentIndex, initialFen);
}

/// Strips internal/opaque event identifiers so compact explorer cards never
/// show UUIDs, hash-like IDs, long numeric IDs, or private URLs as event names.
String sanitizeGamebaseEventLabel(Object? raw) {
  final normalized = (raw?.toString() ?? '').trim().replaceAll(
    RegExp(r'\s+'),
    ' ',
  );
  if (normalized.isEmpty) return '';
  final isOpaqueId =
      RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
      ).hasMatch(normalized) ||
      RegExp(r'^[0-9a-fA-F]{24}$|^[0-9a-fA-F]{32}$').hasMatch(normalized) ||
      RegExp(r'^\d{8,}$').hasMatch(normalized);
  final lower = normalized.toLowerCase();
  final isUrlLike =
      lower.contains('://') ||
      lower.startsWith('urn:') ||
      lower.startsWith('www.') ||
      RegExp(r'^[a-z0-9.-]+\.[a-z]{2,}(?::\d+)?(?:[/?#]|$)').hasMatch(lower);
  return isOpaqueId || isUrlLike ? '' : normalized;
}

/// Maps a gamebase `GameSearchPreview` row into the app's [GamesTourModel].
/// Shared by [PositionGamesSheet] and the explorer's inline games section.
GamesTourModel mapGamebasePreviewToTourModel(Map<String, dynamic> row) {
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
  final eventCandidates = [
        row['canonical_event_name'],
        row['canonicalEventName'],
        row['event_name'],
        row['eventName'],
        row['tournament_name'],
        row['tournamentName'],
        row['tour_name'],
        row['tourName'],
        row['event'],
      ]
      .map(sanitizeGamebaseEventLabel)
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
  // Lichess-broadcast rows carry a per-round pairing label in their PGN Event
  // header ("Round 9: Khripachenko, Alexander - Radovanovic, Mihajlo"), which
  // is not the tournament and only repeats the two names the card already
  // prints. For those rows the parent event survives solely in the `Site`
  // broadcast URL slug — see `twic_player_games_no_tour_fields`.
  final event = eventCandidates.firstWhere(
    isUsefulTwicEventTitle,
    orElse:
        () =>
            eventTitleFromBroadcastSite(readString('site')) ??
            (eventCandidates.isNotEmpty ? eventCandidates.first : ''),
  );
  final tourId =
      (row['tour_id']?.toString() ?? row['tournament_id']?.toString() ?? event)
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

  final formatCode = (eco.trim().isNotEmpty) ? eco.trim() : (timeControl ?? '');
  final openingName =
      (variation.trim().isNotEmpty)
          ? '$opening: $variation'
          : (opening.trim().isNotEmpty ? opening : null);

  final fen =
      (readString('fen').isNotEmpty
              ? readString('fen')
              : (readString('lastFen').isNotEmpty
                  ? readString('lastFen')
                  : readString('finalFen')))
          .trim();
  final lastMove =
      (readString('lastMove').isNotEmpty
              ? readString('lastMove')
              : readString('last_move'))
          .trim();

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
    // Keep the display event separate from tourId, which is commonly an
    // opaque Gamebase tournament UUID.
    tourSlug: event.isNotEmpty ? event : null,
    fen: fen.isNotEmpty ? fen : null,
    lastMove: lastMove.isNotEmpty ? lastMove : null,
    lastMoveTime: date,
    eco: eco.trim().isNotEmpty ? eco.trim() : null,
    openingName: openingName,
    timeControl: timeControl,
  );
}

/// The games the board opens with, and which one is current, for a tap on
/// [game] that the caller placed at [currentIndex] of [games].
///
/// The tapped game is found by identity, then by id, never by position
/// alone, so a list refreshed between the tap and the board can never open a
/// different game. Should it somehow be missing, it opens on its own. Only
/// the tapped entry carries [pgn].
(List<GamesTourModel>, int) resolveGamebaseBoardGames({
  required List<GamesTourModel> games,
  required GamesTourModel game,
  required int currentIndex,
  required String? pgn,
}) {
  var tappedIndex =
      currentIndex >= 0 &&
              currentIndex < games.length &&
              identical(games[currentIndex], game)
          ? currentIndex
          : games.indexWhere((g) => identical(g, game));
  if (tappedIndex < 0) {
    tappedIndex = games.indexWhere((g) => g.gameId == game.gameId);
  }
  if (tappedIndex < 0) {
    return (<GamesTourModel>[game.copyWith(pgn: pgn)], 0);
  }
  return (
    <GamesTourModel>[
      for (var i = 0; i < games.length; i++)
        i == tappedIndex ? games[i].copyWith(pgn: pgn) : games[i],
    ],
    tappedIndex,
  );
}

/// Signature of [openGamebaseGame].
typedef GamebaseGameOpener =
    Future<void> Function(
      BuildContext context,
      WidgetRef ref,
      GamesTourModel game,
      List<GamesTourModel> allGames,
      int currentIndex,
      String? initialFen,
    );

/// Opens a gamebase game into the full board screen: premium guard → loading
/// modal → PGN fetch → [ChessBoardScreenNew]. Shared by [PositionGamesSheet]
/// and the explorer's inline games section.
Future<void> openGamebaseGame(
  BuildContext context,
  WidgetRef ref,
  GamesTourModel game,
  List<GamesTourModel> allGames,
  int currentIndex,
  String? initialFen,
) async {
  // Copy the list before the first await. The paywall and the PGN request
  // below can take a while, and the list the caller showed may be refreshed
  // underneath them; the board must still open the game that was tapped.
  final games = List<GamesTourModel>.of(allGames);

  // Premium guard - show paywall if not subscribed
  final hasPremium = await requirePremiumGuard(context, ref);
  if (!hasPremium) return;
  if (!context.mounted) return;

  // Any lingering explorer-card focus must not hijack the pushed board
  // screen's arrows (Trello #984).
  ref.read(explorerFocusedGameProvider.notifier).clear();

  // Ensure the chessboard screen renders as a "tour game" view.
  ref.read(chessboardViewFromProviderNew.notifier).state = ChessboardView.tour;

  if (!context.mounted) return;
  showAlertModal<void>(
    context: context,
    barrierDismissible: false,
    child: Container(
      padding: EdgeInsets.all(20.sp),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16.br),
        border: Border.all(
          color: context.colors.textPrimary.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
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

    final (boardGames, safeIndex) = resolveGamebaseBoardGames(
      games: games,
      game: game,
      currentIndex: currentIndex,
      pgn: pgn,
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => ChessBoardScreenNew(
              games: boardGames,
              currentIndex: safeIndex,
              viewSource: ChessboardView.tour,
              playerProfileDataSource: PlayerProfileDataSource.twic,
              disableGamebaseOverlayByDefault: true,
              showClock: false,
              initialFen: initialFen,
            ),
      ),
    );
  } catch (_) {
    if (!context.mounted) return;
    Navigator.of(context).pop(); // loading
    // Keep errors non-fatal; user can continue exploring.
    showAppSnack(context, 'Failed to open game', tone: AppSnackTone.danger);
  }
}

class _PositionGamesFooter extends StatelessWidget {
  const _PositionGamesFooter({
    required this.isLoadingMore,
    required this.hasMore,
    required this.loadedCount,
    required this.totalCount,
    required this.checkingSavedCopy,
    required this.refreshFailed,
    required this.onLoadMore,
    required this.onRetry,
    this.savedAt,
  });

  final bool isLoadingMore;
  final bool hasMore;
  final int loadedCount;
  final int? totalCount;

  /// A saved first page is on screen and the server is being asked again;
  /// paging waits for the answer.
  final bool checkingSavedCopy;

  /// The server could not be reached for the saved first page on screen.
  final bool refreshFailed;
  final VoidCallback onLoadMore;
  final VoidCallback onRetry;

  /// When the saved copy on screen was fetched.
  final DateTime? savedAt;

  @override
  Widget build(BuildContext context) {
    // A saved copy being checked is never shown as the whole list, however
    // short it is.
    if (isLoadingMore || checkingSavedCopy) {
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
              isLoadingMore ? 'Loading more games...' : 'Updating games...',
              style: TextStyle(
                color: context.colors.textPrimaryMuted,
                fontSize: 12.f,
              ),
            ),
          ],
        ),
      );
    }

    if (refreshFailed) {
      // Never "Loaded all": the list is a saved copy.
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 12.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${_savedAgeLabel(savedAt, DateTime.now())}. '
              'Couldn’t refresh.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 12.f,
              ),
            ),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: context.colors.textPrimaryMuted,
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
              ),
              child: Text(
                hasMore ? 'Try again to load more' : 'Try again',
                style: TextStyle(fontSize: 12.f, fontWeight: FontWeight.w500),
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
            onPressed: onLoadMore,
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

/// Where a saved first page on screen stands with the server.
enum _SavedCopyState {
  /// Being asked for again; paging waits.
  checking,

  /// The server could not be reached for it.
  failed,
}

/// How old a saved copy is, for the footer: "Saved 3 days ago".
String _savedAgeLabel(DateTime? savedAt, DateTime now) {
  if (savedAt == null || savedAt.year < 2000) return 'Saved copy';
  final age = now.difference(savedAt);
  if (age.inMinutes < 1) return 'Saved just now';
  if (age.inHours < 1) return 'Saved ${age.inMinutes} min ago';
  if (age.inDays < 1) return 'Saved ${age.inHours} h ago';
  return age.inDays == 1 ? 'Saved yesterday' : 'Saved ${age.inDays} days ago';
}

/// The header's count slot once a load has shown a saved copy: "Updating"
/// with a small spinner while the server is asked, then, if that fails,
/// "Retry", which turns back into "Updating" in place, and finally the count
/// once the server's answer is on screen. What the rows are and how old they
/// are goes in the footer ("Saved 3 days ago. Couldn’t refresh.").
///
/// All three are laid out together and only the current one is shown, so
/// the slot keeps a single width from the saved copy to the answer that
/// replaces it: the title beside it never re-wraps and the rows under the
/// header never move, at any text size. Retry is the narrowest, so the slot
/// is as wide as "Updating" or the count, whichever is wider, and never
/// taller than the close button beside it.
class _SavedCopyStatus extends StatelessWidget {
  const _SavedCopyStatus({
    required this.state,
    required this.count,
    required this.onRetry,
    required this.style,
  });

  /// Null once the rows are the server's answer: [count] is shown.
  final _SavedCopyState? state;
  final Widget count;
  final VoidCallback? onRetry;
  final TextStyle style;

  /// Laid out either way; painted, hit-tested and read out only when
  /// [visible].
  static Widget _slot({required bool visible, required Widget child}) =>
      Visibility(
        visible: visible,
        maintainState: true,
        maintainAnimation: true,
        maintainSize: true,
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final checking = state == _SavedCopyState.checking;
    final failed = state == _SavedCopyState.failed;
    return Stack(
      alignment: AlignmentDirectional.centerEnd,
      children: [
        _slot(visible: state == null, child: count),
        _slot(
          visible: checking,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 10.sp,
                // Only spins while shown: a hidden spinner would keep the
                // sheet repainting for as long as the check stays failed.
                child:
                    checking
                        ? CircularProgressIndicator(
                          color: context.colors.textPrimaryMuted,
                          strokeWidth: 1.5,
                        )
                        : null,
              ),
              SizedBox(width: 6.w),
              Text('Updating', maxLines: 1, style: style),
            ],
          ),
        ),
        _slot(
          visible: failed,
          child: TextButton(
            onPressed: onRetry,
            // The close button's own sizing (40 high, padded to the theme's
            // tap target), so the header row keeps its height with Retry in
            // it.
            style: TextButton.styleFrom(
              foregroundColor: context.colors.textPrimary,
              padding: EdgeInsets.symmetric(horizontal: 8.w),
              minimumSize: const Size(44, 40),
            ),
            child: Text(
              'Retry',
              maxLines: 1,
              style: style.copyWith(
                color: context.colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.countText,
    this.savedCopy,
    this.savedCopyShown = false,
    this.onRetry,
    this.onSort,
    this.onClose,
  });

  final String title;
  final String countText;

  /// Set while the rows are a saved copy; the count slot then says so.
  final _SavedCopyState? savedCopy;

  /// This load showed a saved copy at some point, so the count slot keeps
  /// the width it had then (see [_SavedCopyStatus]). A load that never did
  /// shows the plain count.
  final bool savedCopyShown;
  final VoidCallback? onRetry;
  final VoidCallback? onSort;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final countStyle = AppTypography.textXsRegular.copyWith(
      color: context.colors.textPrimaryMuted,
      fontWeight: FontWeight.w500,
    );
    final count = Text(
      countText,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: countStyle,
    );
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
          if (savedCopy == null && !savedCopyShown)
            count
          else
            _SavedCopyStatus(
              state: savedCopy,
              count: count,
              onRetry: onRetry,
              style: countStyle,
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
          if (onClose != null)
            IconButton(
              onPressed: onClose,
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
                      isSelected ? context.colors.accentText : context.colors.textPrimary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            if (isSelected && sortDirection != null)
              Icon(
                sortDirection == GamebaseSortDirection.desc
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_upward_rounded,
                color: context.colors.accentText,
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
