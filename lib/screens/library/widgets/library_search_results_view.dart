import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/library/providers/gamebase_database_games_provider.dart';
import 'package:chessever2/screens/library/providers/library_combined_search_provider.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/library/widgets/add_to_folder_sheet.dart';
import 'package:chessever2/screens/library/widgets/book_saved_game_card.dart';
import 'package:chessever2/screens/library/widgets/folder_card.dart';
import 'package:chessever2/screens/library/widgets/gamebase_search_game_card.dart';
import 'package:chessever2/screens/library/widgets/gamebase_search_player_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/chess_title_utils.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/number_format_utils.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class LibrarySearchResultsView extends ConsumerStatefulWidget {
  final LibrarySearchResult results;
  final AsyncValue<List<GamesTourModel>>? databaseGamesAsync;
  final GamesListViewMode viewMode;
  final Function(LibraryFolder) onFolderTap;
  final Function(GamebasePlayer) onPlayerTap;
  final Function(GamebasePlayer) onPlayerFilter;
  final Function(SavedAnalysis) onAnalysisTap;
  final Function(GamesTourModel) onGameTap;

  const LibrarySearchResultsView({
    super.key,
    required this.results,
    this.databaseGamesAsync,
    this.viewMode = GamesListViewMode.gamesCard,
    required this.onFolderTap,
    required this.onPlayerTap,
    required this.onPlayerFilter,
    required this.onAnalysisTap,
    required this.onGameTap,
  });

  @override
  ConsumerState<LibrarySearchResultsView> createState() =>
      _LibrarySearchResultsViewState();
}

class _LibrarySearchResultsViewState
    extends ConsumerState<LibrarySearchResultsView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Load more when approaching the end of the list
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreGames();
    }
  }

  void _loadMoreGames() {
    final paginationState = ref.read(gamebaseDatabaseGamesPaginatedProvider);
    if (!paginationState.isLoading && paginationState.hasMore) {
      ref.read(gamebaseDatabaseGamesPaginatedProvider.notifier).loadNextPage();
    }
  }

  void _showAddToFolderSheet(BuildContext context, GamesTourModel game) {
    showAddToFolderSheet(context: context, game: game);
  }

  GamesTourModel _mapToGameModel(Map<String, dynamic> row) {
    final id = row['id']?.toString() ?? 'unknown';
    // Logic similar to _toGamesTourModel in LibraryScreen
    // Ideally this logic should be centralized but duplicating for now to keep it self-contained or move to utils

    final data = row['data'];
    final mdRaw = data is Map ? (data['md'] ?? data['metadata']) : null;
    final md =
        mdRaw is Map
            ? Map<String, dynamic>.from(mdRaw)
            : const <String, dynamic>{};

    // Headers fallback
    final whiteName =
        (md['White'] as String?)?.trim().isNotEmpty == true
            ? md['White'].toString()
            : (row['white']?.toString() ??
                row['whiteName']?.toString() ??
                row['white_player']?['name']?.toString() ??
                'White');
    final blackName =
        (md['Black'] as String?)?.trim().isNotEmpty == true
            ? md['Black'].toString()
            : (row['black']?.toString() ??
                row['blackName']?.toString() ??
                row['black_player']?['name']?.toString() ??
                'Black');

    final result =
        (md['Result'] as String?)?.trim().isNotEmpty == true
            ? md['Result'].toString()
            : (row['result']?.toString() ?? '*');

    final builtPgn =
        data is Map
            ? buildPgnFromGamebaseData(Map<String, dynamic>.from(data))
            : null;
    var pgn = row['pgn']?.toString() ?? builtPgn;
    final tourId =
        (row['tour_id']?.toString() ??
                row['tournament_id']?.toString() ??
                ((md['Event'] as String?)?.trim().isNotEmpty == true
                    ? md['Event'].toString()
                    : (row['event']?.toString() ??
                        row['Event']?.toString() ??
                        row['tournament']?.toString() ??
                        'Gamebase')))
            .trim();

    DateTime? parseMdDate(String? raw) {
      if (raw == null) return null;
      final value = raw.trim();
      if (value.isEmpty || value.startsWith('????')) return null;
      final normalized = value.replaceAll('.', '-');
      return DateTime.tryParse(normalized);
    }

    final date =
        row['date'] != null ? DateTime.tryParse(row['date'].toString()) : null;

    final dateFromMd = parseMdDate(md['Date'] as String?);

    final timeControl =
        row['timeControl']?.toString() ?? md['TimeControl']?.toString();
    final eco =
        (md['ECO'] as String?)?.trim().isNotEmpty == true
            ? md['ECO'].toString()
            : (row['eco']?.toString() ?? row['ECO']?.toString());
    final formatCode =
        (eco != null && eco.isNotEmpty) ? eco : (timeControl ?? '');

    int parseRating(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    final whiteTitleRaw =
        (md['WhiteTitle'] as String?) ??
        row['whiteTitle']?.toString() ??
        row['white_player']?['title']?.toString() ??
        '';
    final blackTitleRaw =
        (md['BlackTitle'] as String?) ??
        row['blackTitle']?.toString() ??
        row['black_player']?['title']?.toString() ??
        '';

    final whitePlayer = PlayerCard(
      name: whiteName,
      federation: '',
      title: ChessTitleUtils.normalize(whiteTitleRaw),
      rating:
          md['WhiteElo'] != null
              ? parseRating(md['WhiteElo'])
              : parseRating(row['whiteRating']),
      countryCode:
          row['whiteFed']?.toString().trim() ??
          row['white_player']?['fed']?.toString().trim() ??
          '',
      team: null,
      fideId: null,
    );
    final blackPlayer = PlayerCard(
      name: blackName,
      federation: '',
      title: ChessTitleUtils.normalize(blackTitleRaw),
      rating:
          md['BlackElo'] != null
              ? parseRating(md['BlackElo'])
              : parseRating(row['blackRating']),
      countryCode:
          row['blackFed']?.toString().trim() ??
          row['black_player']?['fed']?.toString().trim() ??
          '',
      team: null,
      fideId: null,
    );

    if (pgn == null || pgn.trim().isEmpty) {
      pgn = buildHeaderOnlyPgn(
        whiteName: whiteName,
        blackName: blackName,
        result: result,
        event: tourId,
        site: row['site']?.toString() ?? md['Site']?.toString(),
        date: date ?? dateFromMd,
        eco: eco,
        opening: row['opening']?.toString() ?? md['Opening']?.toString(),
        variation: row['variation']?.toString() ?? md['Variation']?.toString(),
      );
    }

    return GamesTourModel(
      gameId: id,
      source: GameSource.gamebase,
      whitePlayer: whitePlayer,
      blackPlayer: blackPlayer,
      whiteTimeDisplay: '--:--',
      blackTimeDisplay: '--:--',
      whiteClockCentiseconds: 0,
      blackClockCentiseconds: 0,
      gameStatus: GameStatus.fromString(result),
      roundId: 'search',
      roundSlug: formatCode.isNotEmpty ? formatCode : null,
      tourId: tourId,
      pgn: pgn,
      lastMoveTime: date ?? dateFromMd,
    );
  }

  @override
  Widget build(BuildContext context) {
    final fallbackGameModels =
        widget.results.games.map(_mapToGameModel).toList();

    // Watch the paginated provider for database games
    final paginationState = ref.watch(gamebaseDatabaseGamesPaginatedProvider);

    final hasDatabaseSection =
        widget.databaseGamesAsync?.maybeWhen(
          data: (games) => games.isNotEmpty,
          loading: () => true,
          error: (_, __) => true,
          orElse: () => false,
        ) ??
        paginationState.games.isNotEmpty || fallbackGameModels.isNotEmpty;

    final hasAnyResults =
        widget.results.folders.isNotEmpty ||
        widget.results.analyses.isNotEmpty ||
        widget.results.players.isNotEmpty ||
        hasDatabaseSection;

    if (!hasAnyResults) {
      return Center(
        child: Text(
          'No results found',
          style: AppTypography.textSmRegular.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
      );
    }

    return ListView(
      controller: _scrollController,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      children: [
        // Folders Section
        if (widget.results.folders.isNotEmpty) ...[
          _SectionHeader(title: 'Folders'),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: widget.results.folders.length,
            separatorBuilder: (_, __) => SizedBox(height: 12.h),
            itemBuilder: (context, index) {
              final folder = widget.results.folders[index];
              return FolderCard(
                folder: folder,
                isExpanded: true,
                onTap: () => widget.onFolderTap(folder),
              );
            },
          ),
          SizedBox(height: 24.h),
        ],

        // Players Section
        if (widget.results.players.isNotEmpty) ...[
          _SectionHeader(
            title: 'Players',
            count:
                widget.results.playerTotalCount > 0
                    ? widget.results.playerTotalCount
                    : widget.results.players.length,
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: widget.results.players.length,
            separatorBuilder: (_, __) => SizedBox(height: 8.h),
            itemBuilder: (context, index) {
              final player = widget.results.players[index];
              return GamebaseSearchPlayerCard(
                player: player,
                onTap: () => widget.onPlayerTap(player),
                onAdd: () => widget.onPlayerFilter(player),
                animationIndex: index,
              );
            },
          ),
          SizedBox(height: 24.h),
        ],

        // Saved Analysis Section
        if (widget.results.analyses.isNotEmpty) ...[
          _SectionHeader(title: 'Saved Games'),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: widget.results.analyses.length,
            separatorBuilder: (_, __) => SizedBox(height: 12.h),
            itemBuilder: (context, index) {
              final analysis = widget.results.analyses[index];
              return BookSavedGameCard(analysis: analysis);
            },
          ),
          SizedBox(height: 24.h),
        ],

        // Database Games Section with pagination
        ..._buildDatabaseGamesSection(
          context: context,
          paginationState: paginationState,
          databaseGamesAsync: widget.databaseGamesAsync,
          fallbackGames: fallbackGameModels,
          viewMode: widget.viewMode,
        ),
      ],
    );
  }

  List<Widget> _buildDatabaseGamesSection({
    required BuildContext context,
    required DatabaseGamesPaginationState paginationState,
    required AsyncValue<List<GamesTourModel>>? databaseGamesAsync,
    required List<GamesTourModel> fallbackGames,
    required GamesListViewMode viewMode,
  }) {
    // Use paginated games if available, otherwise fall back to legacy
    final games =
        paginationState.games.isNotEmpty
            ? paginationState.games
            : (databaseGamesAsync?.valueOrNull ?? fallbackGames);

    if (games.isEmpty &&
        !paginationState.isLoading &&
        databaseGamesAsync == null) {
      return const [];
    }

    return [
      _SectionHeader(
        title: 'Database Games',
        count:
            paginationState.totalCount > 0 ? paginationState.totalCount : null,
      ),
      if (games.isEmpty && paginationState.isLoading)
        Padding(
          padding: EdgeInsets.symmetric(vertical: 24.h),
          child:  Center(
            child: CircularProgressIndicator(color: context.colors.textPrimary),
          ),
        )
      else if (paginationState.error != null && games.isEmpty)
        Padding(
          padding: EdgeInsets.only(top: 4.h, bottom: 12.h),
          child: Text(
            'Failed to load games',
            style: AppTypography.textSmRegular.copyWith(color: kRedColor),
          ),
        )
      else
        _buildGamesList(context: context, games: games, viewMode: viewMode),

      // Load more indicator
      if (paginationState.hasMore && games.isNotEmpty) ...[
        SizedBox(height: 16.h),
        _LoadMoreButton(
          isLoading: paginationState.isLoading,
          onTap: _loadMoreGames,
          remainingCount:
              paginationState.totalCount > 0
                  ? paginationState.totalCount - games.length
                  : null,
        ),
      ],

      // Loading indicator at bottom when loading more
      if (paginationState.isLoading && games.isNotEmpty)
        Padding(
          padding: EdgeInsets.symmetric(vertical: 16.h),
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                color: context.colors.textPrimary,
                strokeWidth: 2,
              ),
            ),
          ),
        ),

      SizedBox(height: 24.h),
    ];
  }

  Widget _buildGamesList({
    required BuildContext context,
    required List<GamesTourModel> games,
    required GamesListViewMode viewMode,
  }) {
    final isGrid = viewMode == GamesListViewMode.chessBoardGrid;
    final isBoard = viewMode == GamesListViewMode.chessBoard;

    if (isGrid) {
      // Grid mode: dynamic columns based on device/orientation
      // Tablet landscape: 4 columns, Tablet portrait: 2 columns, Phone: 2 columns
      final int gridColumns =
          ResponsiveHelper.isTablet && ResponsiveHelper.isLandscape ? 4 : 2;
      final items = <Widget>[];

      for (int i = 0; i < games.length; i += gridColumns) {
        final isLast = i + gridColumns >= games.length;

        // Gather games for this row
        final rowGames = <GamesTourModel>[];
        for (int j = 0; j < gridColumns && i + j < games.length; j++) {
          rowGames.add(games[i + j]);
        }

        items.add(
          Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 12.h),
            child: Row(
              children: [
                for (int j = 0; j < gridColumns; j++) ...[
                  if (j > 0) SizedBox(width: 12.sp),
                  Expanded(
                    child:
                        j < rowGames.length
                            ? _LibraryGridGame(
                              game: rowGames[j],
                              gameIndex: i + j,
                              allGames: games,
                            )
                            : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        );
      }

      return Column(children: items);
    }

    if (isBoard) {
      // Board mode: full-width board cards
      return ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: games.length,
        separatorBuilder: (_, __) => SizedBox(height: 12.h),
        itemBuilder: (context, index) {
          return _LibraryBoardGame(
            game: games[index],
            gameIndex: index,
            allGames: games,
          );
        },
      );
    }

    // Card mode (default): use GamebaseSearchGameCard
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: games.length,
      separatorBuilder: (_, __) => SizedBox(height: 12.h),
      itemBuilder: (context, index) {
        return GamebaseSearchGameCard(
          game: games[index],
          allGames: games,
          gameIndex: index,
          animationIndex: index,
          onAdd: () => _showAddToFolderSheet(context, games[index]),
          showSwipeHint: index == 0,
          hideEventInfo: true,
        );
      },
    );
  }
}

/// Load more button widget
class _LoadMoreButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onTap;
  final int? remainingCount;

  const _LoadMoreButton({
    required this.isLoading,
    required this.onTap,
    this.remainingCount,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap:
          isLoading
              ? null
              : () {
                HapticFeedbackService.light();
                onTap();
              },
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 14.h, horizontal: 20.w),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(color: context.colors.surfaceRecessed),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading) ...[
              SizedBox(
                width: 16.sp,
                height: 16.sp,
                child: CircularProgressIndicator(
                  color: context.colors.textPrimary,
                  strokeWidth: 2,
                ),
              ),
              SizedBox(width: 10.w),
            ],
            Text(
              isLoading
                  ? 'Loading...'
                  : remainingCount != null
                  ? 'Load more (${formatCompactCount(remainingCount!)} remaining)'
                  : 'Load more games',
              style: AppTypography.textSmMedium.copyWith(
                color: context.colors.textPrimary.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Grid game widget with premium guard
class _LibraryGridGame extends ConsumerWidget {
  final GamesTourModel game;
  final int gameIndex;
  final List<GamesTourModel> allGames;

  const _LibraryGridGame({
    required this.game,
    required this.gameIndex,
    required this.allGames,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GridChessBoardFromFENNew(
      key: ValueKey('lib_grid_game_${game.gameId}'),
      gamesTourModel: game,
      onChanged: () async {
        // Premium guard - show paywall if not subscribed
        final hasPremium = await requirePremiumGuard(context, ref);
        if (!hasPremium) return;
        if (!context.mounted) return;

        // Navigate directly with Library-specific params (no gamebase button)
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) => ChessBoardScreenNew(
                  games: allGames,
                  currentIndex: gameIndex,
                  showGamebaseButton: false,
                ),
          ),
        );
      },
      pinnedIds: const [],
      onPinToggle: (_) {},
    );
  }
}

/// Board game widget with premium guard
class _LibraryBoardGame extends ConsumerWidget {
  final GamesTourModel game;
  final int gameIndex;
  final List<GamesTourModel> allGames;

  const _LibraryBoardGame({
    required this.game,
    required this.gameIndex,
    required this.allGames,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ChessBoardFromFENNew(
      key: ValueKey('lib_board_game_${game.gameId}'),
      gamesTourModel: game,
      onChanged: () async {
        // Premium guard - show paywall if not subscribed
        final hasPremium = await requirePremiumGuard(context, ref);
        if (!hasPremium) return;
        if (!context.mounted) return;

        // Navigate directly with Library-specific params (no gamebase button)
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) => ChessBoardScreenNew(
                  games: allGames,
                  currentIndex: gameIndex,
                  showGamebaseButton: false,
                ),
          ),
        );
      },
      pinnedIds: const [],
      onPinToggle: (_) {},
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int? count;

  const _SectionHeader({required this.title, this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Row(
        children: [
          Text(
            title,
            style: AppTypography.textSmBold.copyWith(color: context.colors.textPrimary),
          ),
          if (count != null && count! > 0) ...[
            SizedBox(width: 8.w),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
              decoration: BoxDecoration(
                color: context.colors.surfaceRecessed,
                borderRadius: BorderRadius.circular(10.br),
              ),
              child: Text(
                formatCompactCount(count!),
                style: AppTypography.textXsRegular.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
