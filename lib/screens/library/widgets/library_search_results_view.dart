import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/library/providers/library_combined_search_provider.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/library/widgets/add_to_folder_sheet.dart';
import 'package:chessever2/screens/library/widgets/book_saved_game_card.dart';
import 'package:chessever2/screens/library/widgets/folder_card.dart';
import 'package:chessever2/screens/library/widgets/gamebase_search_game_card.dart';
import 'package:chessever2/screens/library/widgets/gamebase_search_player_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/chess_title_utils.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class LibrarySearchResultsView extends ConsumerWidget {
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
        mdRaw is Map ? Map<String, dynamic>.from(mdRaw) : const <String, dynamic>{};

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
        (md['Event'] as String?)?.trim().isNotEmpty == true
            ? md['Event'].toString()
            : (row['event']?.toString() ??
                row['Event']?.toString() ??
                row['tournament']?.toString() ??
                'Gamebase');

    DateTime? _parseMdDate(String? raw) {
      if (raw == null) return null;
      final value = raw.trim();
      if (value.isEmpty || value.startsWith('????')) return null;
      final normalized = value.replaceAll('.', '-');
      return DateTime.tryParse(normalized);
    }

    final date =
        row['date'] != null ? DateTime.tryParse(row['date'].toString()) : null;

    final dateFromMd = _parseMdDate(md['Date'] as String?);

    final timeControl =
        row['timeControl']?.toString() ?? md['TimeControl']?.toString();
    final eco =
        (md['ECO'] as String?)?.trim().isNotEmpty == true
            ? md['ECO'].toString()
            : (row['eco']?.toString() ?? row['ECO']?.toString());
    final formatCode = (eco != null && eco.isNotEmpty) ? eco : (timeControl ?? '');

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
  Widget build(BuildContext context, WidgetRef ref) {
    final fallbackGameModels = results.games.map(_mapToGameModel).toList();

    final hasDatabaseSection =
        databaseGamesAsync?.maybeWhen(
          data: (games) => games.isNotEmpty,
          loading: () => true,
          error: (_, __) => true,
          orElse: () => false,
        ) ??
        fallbackGameModels.isNotEmpty;

    final hasAnyResults =
        results.folders.isNotEmpty ||
        results.analyses.isNotEmpty ||
        results.players.isNotEmpty ||
        hasDatabaseSection;

    if (!hasAnyResults) {
      return Center(
        child: Text(
          'No results found',
          style: AppTypography.textSmRegular.copyWith(
            color: const Color(0xFFA1A1AA),
          ),
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      children: [
        // Folders Section
        if (results.folders.isNotEmpty) ...[
          _SectionHeader(title: 'Books'),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: results.folders.length,
            separatorBuilder: (_, __) => SizedBox(height: 12.h),
            itemBuilder: (context, index) {
              final folder = results.folders[index];
              return FolderCard(
                folder: folder,
                isExpanded: true,
                onTap: () => onFolderTap(folder),
              );
            },
          ),
          SizedBox(height: 24.h),
        ],

        // Players Section
        if (results.players.isNotEmpty) ...[
          _SectionHeader(title: 'Players'),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: results.players.length,
            separatorBuilder: (_, __) => SizedBox(height: 8.h),
            itemBuilder: (context, index) {
              final player = results.players[index];
              return GamebaseSearchPlayerCard(
                player: player,
                onTap: () => onPlayerTap(player),
                onAdd: () => onPlayerFilter(player),
                animationIndex: index,
              );
            },
          ),
          SizedBox(height: 24.h),
        ],

        // Saved Analysis Section
        if (results.analyses.isNotEmpty) ...[
          _SectionHeader(title: 'Saved Games'),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: results.analyses.length,
            separatorBuilder: (_, __) => SizedBox(height: 12.h),
            itemBuilder: (context, index) {
              final analysis = results.analyses[index];
              return BookSavedGameCard(analysis: analysis);
            },
          ),
          SizedBox(height: 24.h),
        ],

        // Database Games Section
        ..._buildDatabaseGamesSection(
          context: context,
          ref: ref,
          databaseGamesAsync: databaseGamesAsync,
          fallbackGames: fallbackGameModels,
          viewMode: viewMode,
        ),
      ],
    );
  }

  List<Widget> _buildDatabaseGamesSection({
    required BuildContext context,
    required WidgetRef ref,
    required AsyncValue<List<GamesTourModel>>? databaseGamesAsync,
    required List<GamesTourModel> fallbackGames,
    required GamesListViewMode viewMode,
  }) {
    if (databaseGamesAsync == null) {
      if (fallbackGames.isEmpty) return const [];
      return [
        _SectionHeader(title: 'Database Games'),
        _buildGamesList(
          context: context,
          ref: ref,
          games: fallbackGames,
          viewMode: viewMode,
        ),
      ];
    }

    return [
      _SectionHeader(title: 'Database Games'),
      databaseGamesAsync.when(
        data: (games) {
          if (games.isEmpty) {
            return Padding(
              padding: EdgeInsets.only(top: 4.h, bottom: 12.h),
              child: Text(
                'No database games found',
                style: AppTypography.textSmRegular.copyWith(
                  color: const Color(0xFFA1A1AA),
                ),
              ),
            );
          }

          return _buildGamesList(
            context: context,
            ref: ref,
            games: games,
            viewMode: viewMode,
          );
        },
        loading:
            () => Padding(
              padding: EdgeInsets.symmetric(vertical: 24.h),
              child: const Center(
                child: CircularProgressIndicator(color: kWhiteColor),
              ),
            ),
        error:
            (e, _) => Padding(
              padding: EdgeInsets.only(top: 4.h, bottom: 12.h),
              child: Text(
                'Failed to load database games: $e',
                style: AppTypography.textSmRegular.copyWith(color: kRedColor),
              ),
            ),
      ),
    ];
  }

  Widget _buildGamesList({
    required BuildContext context,
    required WidgetRef ref,
    required List<GamesTourModel> games,
    required GamesListViewMode viewMode,
  }) {
    final isGrid = viewMode == GamesListViewMode.chessBoardGrid;
    final isBoard = viewMode == GamesListViewMode.chessBoard;

    if (isGrid) {
      // Grid mode: 2 games per row
      final items = <Widget>[];
      for (int i = 0; i < games.length; i += 2) {
        final game1 = games[i];
        final game2 = i + 1 < games.length ? games[i + 1] : null;
        final isLast = i + 2 >= games.length;

        items.add(
          Padding(
            padding: EdgeInsets.only(bottom: isLast ? 16.h : 12.h),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _LibraryGridGame(
                  game: game1,
                  gameIndex: i,
                  allGames: games,
                ),
                if (game2 != null)
                  _LibraryGridGame(
                    game: game2,
                    gameIndex: i + 1,
                    allGames: games,
                  ),
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
            builder: (_) => ChessBoardScreenNew(
              games: allGames,
              currentIndex: gameIndex,
              hideEventInfo: true,
              showGamebaseButton: false,
              disableGamebaseOverlayByDefault: true,
              showClock: false,
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
            builder: (_) => ChessBoardScreenNew(
              games: allGames,
              currentIndex: gameIndex,
              hideEventInfo: true,
              showGamebaseButton: false,
              disableGamebaseOverlayByDefault: true,
              showClock: false,
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
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: AppTypography.textSmBold.copyWith(color: kWhiteColor),
    );
  }
}
