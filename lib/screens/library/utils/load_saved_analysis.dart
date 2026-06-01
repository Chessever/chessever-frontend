import 'dart:async';

import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/notation/notation_tree.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Navigates to chess board screen with a loaded saved analysis (single game, no swiping)
///
/// This creates a SavedAnalysisData from the SavedAnalysis and passes it
/// to ChessBoardScreenNew for full state restoration including:
/// - All variations from the ChessGame tree
/// - variationComments restoration
/// - movePointer navigation position (via lastViewedPosition)
/// - isBoardFlipped preference (from analysisState)
Future<void> loadSavedAnalysis(
  BuildContext context,
  SavedAnalysis analysis,
) async {
  var resolvedAnalysis = analysis;

  // Update last opened timestamp but don't block navigation on errors
  try {
    final container = ProviderScope.containerOf(context, listen: false);
    final repository = container.read(libraryRepositoryProvider);
    final latest = await repository.getSavedAnalysis(analysis.id);
    if (latest != null) {
      resolvedAnalysis = latest;
    }
    await repository.updateLastOpened(analysis.id);
  } catch (_) {
    // Best-effort update; proceed even if we cannot write
  }

  if (!context.mounted) return;

  // Convert SavedAnalysis to GamesTourModel format
  final game = convertSavedAnalysisToGame(resolvedAnalysis);

  // Create SavedAnalysisData for full state restoration
  final savedAnalysisData = createSavedAnalysisData(resolvedAnalysis);

  // Navigate to chess board with saved analysis data
  Navigator.of(context).push(
    MaterialPageRoute(
      builder:
          (_) => ChessBoardScreenNew(
            currentIndex: 0,
            games: [game],
            savedAnalysisData: savedAnalysisData,
            showGamebaseButton: false,
          ),
    ),
  );
}

/// Navigates to chess board screen with swiping support across multiple saved analyses.
///
/// Converts all analyses to GamesTourModel (with PGN for swiped-to games)
/// and passes the tapped game's SavedAnalysisData for full state restoration.
Future<void> loadSavedAnalysisWithSwiping(
  BuildContext context,
  List<SavedAnalysis> allAnalyses,
  int tappedIndex, {
  bool readOnly = false,
}) async {
  final analysesForNavigation = List<SavedAnalysis>.from(allAnalyses);
  var tappedAnalysis = analysesForNavigation[tappedIndex];

  // Update last opened timestamp but don't block navigation on errors
  if (!readOnly) {
    try {
      final container = ProviderScope.containerOf(context, listen: false);
      final repository = container.read(libraryRepositoryProvider);
      final latest = await repository.getSavedAnalysis(tappedAnalysis.id);
      if (latest != null) {
        tappedAnalysis = latest;
        analysesForNavigation[tappedIndex] = latest;
      }
      await repository.updateLastOpened(tappedAnalysis.id);
    } catch (_) {
      // Best-effort update; proceed even if we cannot write
    }
  }

  if (!context.mounted) return;

  // Convert all analyses to GamesTourModel with PGN populated for swiping
  final games = analysesForNavigation.map(convertSavedAnalysisToGame).toList();
  final savedAnalysesDataByIndex = analysesForNavigation
      .map(
        (analysis) =>
            readOnly
                ? createReadOnlySavedAnalysisData(analysis)
                : createSavedAnalysisData(analysis),
      )
      .toList(growable: false);

  // Create SavedAnalysisData for the tapped game only
  final savedAnalysisData = savedAnalysesDataByIndex[tappedIndex];

  Navigator.of(context).push(
    MaterialPageRoute(
      builder:
          (_) => ChessBoardScreenNew(
            currentIndex: tappedIndex,
            games: games,
            savedAnalysisData: savedAnalysisData,
            savedAnalysesDataByIndex: savedAnalysesDataByIndex,
            showGamebaseButton: false,
          ),
    ),
  );
}

/// Creates SavedAnalysisData from SavedAnalysis for state restoration
SavedAnalysisData createSavedAnalysisData(SavedAnalysis analysis) {
  // Extract board flip preference from analysisState (snake_case from DB)
  final isBoardFlipped =
      analysis.analysisState['is_board_flipped'] as bool? ?? false;

  // Extract movePointer from analysisState if saved (snake_case from DB)
  List<int>? movePointer;
  final savedPointer = analysis.analysisState['move_pointer'];
  if (savedPointer is List) {
    movePointer = savedPointer.cast<int>();
  }

  return SavedAnalysisData(
    analysisId: analysis.id,
    sourceGameId: analysis.sourceGameId,
    chessGame: analysis.chessGame,
    variationComments: analysis.variationComments,
    moveNags: analysis.moveNags,
    movePointer: movePointer,
    isBoardFlipped: isBoardFlipped,
    lastViewedPosition: analysis.lastViewedPosition,
    title: analysis.title,
    folderId: analysis.folderId,
    tags: analysis.tags,
  );
}

/// Creates a read-only SavedAnalysisData (no analysisId, so board won't save back).
/// Used for shared/subscribed database games.
SavedAnalysisData createReadOnlySavedAnalysisData(SavedAnalysis analysis) {
  return SavedAnalysisData(
    analysisId: null,
    sourceGameId: analysis.sourceGameId,
    chessGame: analysis.chessGame,
    variationComments: analysis.variationComments,
    moveNags: analysis.moveNags,
    movePointer: null,
    isBoardFlipped: false,
    lastViewedPosition: analysis.lastViewedPosition,
  );
}

/// Converts a SavedAnalysis to GamesTourModel format
///
/// This creates a minimal GamesTourModel that the chess board can display.
/// Uses analysis.id as gameId to avoid conflicts with live games.
/// PGN is populated via exportGameToPgn so swiped-to games can load moves.
GamesTourModel convertSavedAnalysisToGame(SavedAnalysis analysis) {
  final chessGame = analysis.chessGame;

  // Extract player info from metadata
  final md = chessGame.metadata;
  final whiteName = md['White'] as String? ?? 'White';
  final blackName = md['Black'] as String? ?? 'Black';
  final result = md['Result'] as String? ?? '*';
  final whiteTitle = (md['WhiteTitle'] ?? '').toString().trim();
  final blackTitle = (md['BlackTitle'] ?? '').toString().trim();
  final whiteRating = _parseRating(md['WhiteElo']);
  final blackRating = _parseRating(md['BlackElo']);
  final whiteCountryCode = _countryCodeFromMetadata(md, isWhite: true);
  final blackCountryCode = _countryCodeFromMetadata(md, isWhite: false);

  // Create player cards with minimal info
  final whitePlayer = PlayerCard(
    name: whiteName,
    federation: whiteCountryCode,
    title: whiteTitle,
    rating: whiteRating,
    countryCode: whiteCountryCode,
    team: null,
    fideId: null,
  );

  final blackPlayer = PlayerCard(
    name: blackName,
    federation: blackCountryCode,
    title: blackTitle,
    rating: blackRating,
    countryCode: blackCountryCode,
    team: null,
    fideId: null,
  );

  final eco = md['ECO']?.toString();
  final openingName = md['Opening']?.toString();
  final event = md['Event']?.toString() ?? 'library';
  final round = md['Round']?.toString() ?? 'saved_analysis';
  final date = md['Date']?.toString();
  final timeControl = md['TimeControl']?.toString();

  DateTime? parsedDate;
  if (date != null && date.isNotEmpty) {
    // Attempt to parse PGN date format (YYYY.MM.DD) or standard ISO format
    try {
      if (date.contains('.')) {
        final parts = date.split('.');
        if (parts.length == 3) {
          final year = int.tryParse(parts[0]);
          final month = int.tryParse(parts[1]);
          final day = int.tryParse(parts[2]);
          if (year != null && month != null && day != null) {
            parsedDate = DateTime(year, month, day);
          }
        }
      } else {
        parsedDate = DateTime.tryParse(date);
      }
    } catch (_) {}
  }

  final whiteTimeDisplay = md['WhiteTimeDisplay']?.toString() ?? '--:--';
  final blackTimeDisplay = md['BlackTimeDisplay']?.toString() ?? '--:--';
  final whiteClockSeconds =
      md['WhiteClockSeconds'] != null
          ? int.tryParse(md['WhiteClockSeconds'].toString())
          : null;
  final blackClockSeconds =
      md['BlackClockSeconds'] != null
          ? int.tryParse(md['BlackClockSeconds'].toString())
          : null;
  final boardNr =
      md['BoardNr'] != null ? int.tryParse(md['BoardNr'].toString()) : null;
  final tourSlug = md['TourSlug']?.toString();
  final roundSlug = md['RoundSlug']?.toString();

  // Determine tournament ID: prefer the saved UUID from sourceTournamentId
  // which allows fetching full event info (images, website, etc.)
  final tourId =
      (analysis.sourceTournamentId?.isNotEmpty == true)
          ? analysis.sourceTournamentId!
          : event;

  // Use analysis.id as gameId to avoid conflicts with live games
  // The original source game ID is preserved in analysis.sourceGameId
  return GamesTourModel(
    gameId: 'saved_analysis_${analysis.id}',
    source: GameSource.savedAnalysis,
    whitePlayer: whitePlayer,
    blackPlayer: blackPlayer,
    whiteTimeDisplay: whiteTimeDisplay,
    blackTimeDisplay: blackTimeDisplay,
    whiteClockCentiseconds: (whiteClockSeconds ?? 0) * 100,
    blackClockCentiseconds: (blackClockSeconds ?? 0) * 100,
    whiteClockSeconds: whiteClockSeconds,
    blackClockSeconds: blackClockSeconds,
    boardNr: boardNr,
    tourSlug: tourSlug,
    roundSlug: roundSlug,
    gameStatus: GameStatus.fromString(result),
    roundId: round,
    tourId: tourId,
    timeControl: timeControl,
    // PGN populated for swiped-to games (the tapped game uses savedAnalysisData instead)
    pgn: exportGameToPgn(chessGame),
    eco: eco,
    openingName: openingName,
    lastMoveTime: parsedDate,
  );
}

int _parseRating(Object? raw) {
  final value = raw?.toString().trim() ?? '';
  if (value.isEmpty) return 0;
  return int.tryParse(value) ?? 0;
}

String _countryCodeFromMetadata(
  Map<String, dynamic> md, {
  required bool isWhite,
}) {
  final prefix = isWhite ? 'White' : 'Black';

  final candidates = <Object?>[
    md['${prefix}Fed'],
    md['${prefix}Federation'],
    md['${prefix}Country'],
    md['${prefix}FideFederation'],
    md['${prefix}Nationality'],
  ];

  for (final value in candidates) {
    final s = value?.toString().trim() ?? '';
    if (s.isNotEmpty) return s;
  }

  return '';
}
