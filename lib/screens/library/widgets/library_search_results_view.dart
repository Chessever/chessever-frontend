import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/library/providers/library_combined_search_provider.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/library/widgets/add_to_folder_sheet.dart';
import 'package:chessever2/screens/library/widgets/book_saved_game_card.dart';
import 'package:chessever2/screens/library/widgets/folder_card.dart';
import 'package:chessever2/screens/library/widgets/gamebase_search_game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class LibrarySearchResultsView extends ConsumerWidget {
  final LibrarySearchResult results;
  final AsyncValue<List<GamesTourModel>>? databaseGamesAsync;
  final Function(LibraryFolder) onFolderTap;
  final Function(GamebasePlayer) onPlayerTap; // Maybe open profile
  final Function(SavedAnalysis) onAnalysisTap;
  final Function(GamesTourModel) onGameTap;

  const LibrarySearchResultsView({
    super.key,
    required this.results,
    this.databaseGamesAsync,
    required this.onFolderTap,
    required this.onPlayerTap,
    required this.onAnalysisTap,
    required this.onGameTap,
  });

  void _showAddToFolderSheet(BuildContext context, GamesTourModel game) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddToFolderSheet(game: game),
    );
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

    final builtPgn = data is Map ? buildPgnFromGamebaseData(Map<String, dynamic>.from(data)) : null;
    final pgn = row['pgn']?.toString() ?? builtPgn;
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

    final whitePlayer = PlayerCard(
      name: whiteName,
      federation: '',
      title: (md['WhiteTitle'] as String?)?.trim() ?? '',
      rating:
          md['WhiteElo'] != null
              ? parseRating(md['WhiteElo'])
              : parseRating(row['whiteRating']),
      countryCode: '',
      team: null,
      fideId: null,
    );
    final blackPlayer = PlayerCard(
      name: blackName,
      federation: '',
      title: (md['BlackTitle'] as String?)?.trim() ?? '',
      rating:
          md['BlackElo'] != null
              ? parseRating(md['BlackElo'])
              : parseRating(row['blackRating']),
      countryCode: '',
      team: null,
      fideId: null,
    );

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
          SizedBox(
            height: 88.h,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: results.players.length,
              separatorBuilder: (_, __) => SizedBox(width: 10.w),
              itemBuilder: (context, index) {
                final p = results.players[index];
                final title = p.title;
                final hasTitle = title != null && title.isNotEmpty;
                return GestureDetector(
                  onTap: () => onPlayerTap(p),
                  child: Container(
                    width: 140.w,
                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                    decoration: BoxDecoration(
                      color: const Color(0xFF18181B), // Zinc 900
                      borderRadius: BorderRadius.circular(10.br),
                      border: Border.all(color: const Color(0xFF27272A)), // Zinc 800
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20.sp,
                          backgroundColor: const Color(0xFF27272A), // Zinc 800
                          child: Text(
                            p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                            style: AppTypography.textSmBold.copyWith(
                              color: const Color(0xFFFAFAFA), // Zinc 50
                            ),
                          ),
                        ),
                        SizedBox(width: 10.w),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.textXsMedium.copyWith(
                                  color: const Color(0xFFFAFAFA), // Zinc 50
                                  height: 1.2,
                                ),
                              ),
                              if (hasTitle) ...[
                                SizedBox(height: 2.h),
                                Text(
                                  title,
                                  style: AppTypography.textXsRegular.copyWith(
                                    color: const Color(0xFFA1A1AA), // Zinc 400
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SizedBox(height: 24.h),
        ],

        // Saved Analysis Section
        if (results.analyses.isNotEmpty) ...[
          _SectionHeader(title: 'Saved Games'),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
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
          databaseGamesAsync: databaseGamesAsync,
          fallbackGames: fallbackGameModels,
        ),
      ],
    );
  }

  List<Widget> _buildDatabaseGamesSection({
    required BuildContext context,
    required AsyncValue<List<GamesTourModel>>? databaseGamesAsync,
    required List<GamesTourModel> fallbackGames,
  }) {
    if (databaseGamesAsync == null) {
      if (fallbackGames.isEmpty) return const [];
      return [
        _SectionHeader(title: 'Database Games'),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: fallbackGames.length,
          separatorBuilder: (_, __) => SizedBox(height: 12.h),
          itemBuilder: (context, index) {
            return GamebaseSearchGameCard(
              game: fallbackGames[index],
              allGames: fallbackGames,
              gameIndex: index,
              animationIndex: index,
              onAdd: () => _showAddToFolderSheet(context, fallbackGames[index]),
            );
          },
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

          return ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: games.length,
            separatorBuilder: (_, __) => SizedBox(height: 12.h),
            itemBuilder: (context, index) {
              return GamebaseSearchGameCard(
                game: games[index],
                allGames: games,
                gameIndex: index,
                animationIndex: index,
                onAdd: () => _showAddToFolderSheet(context, games[index]),
              );
            },
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
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Text(
        title,
        style: AppTypography.textSmBold.copyWith(color: kWhiteColor),
      ),
    );
  }
}
