import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/library/utils/load_saved_analysis.dart';
import 'package:chessever2/screens/library/widgets/library_game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:flutter/material.dart';

class BookSavedGameCard extends StatelessWidget {
  const BookSavedGameCard({super.key, required this.analysis, this.onTap});

  final SavedAnalysis analysis;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final game = _bookAnalysisToGamesTourModel(analysis);
    final eventName = _eventNameFromMetadata(analysis.chessGame.metadata);

    return LibraryGameCard(
      game: game,
      eventName: eventName,
      onTap: onTap ?? () => loadSavedAnalysis(context, analysis),
    );
  }

  GamesTourModel _bookAnalysisToGamesTourModel(SavedAnalysis analysis) {
    final md = analysis.chessGame.metadata;
    final whiteName = md['White'] as String? ?? 'White';
    final blackName = md['Black'] as String? ?? 'Black';
    final whiteTitle = (md['WhiteTitle'] ?? '').toString().trim();
    final blackTitle = (md['BlackTitle'] ?? '').toString().trim();
    final whiteCountryCode = _countryCodeFromMetadata(md, isWhite: true);
    final blackCountryCode = _countryCodeFromMetadata(md, isWhite: false);
    final whiteElo = _parseRating(md['WhiteElo']);
    final blackElo = _parseRating(md['BlackElo']);

    final result = (md['Result'] as String? ?? '*').trim();
    final status = GameStatus.fromString(result);

    final mainline = analysis.chessGame.mainline;
    final last = mainline.isNotEmpty ? mainline.last : null;

    final (whiteClockSeconds, blackClockSeconds) = _extractClockSeconds(
      mainline,
    );

    final eco = md['ECO']?.toString() ?? '';
    final openingName = md['Opening']?.toString() ?? '';
    final event =
        md['Event']?.toString() ?? md['Site']?.toString() ?? 'library';
    final round = md['Round']?.toString() ?? 'saved_analysis';
    final timeControl = md['TimeControl']?.toString();
    final dateStr = md['Date']?.toString();

    DateTime? parsedDate;
    if (dateStr != null && dateStr.isNotEmpty) {
      try {
        if (dateStr.contains('.')) {
          final parts = dateStr.split('.');
          if (parts.length == 3) {
            final year = int.tryParse(parts[0]);
            final month = int.tryParse(parts[1]);
            final day = int.tryParse(parts[2]);
            if (year != null && month != null && day != null) {
              parsedDate = DateTime(year, month, day);
            }
          }
        } else {
          parsedDate = DateTime.tryParse(dateStr);
        }
      } catch (_) {}
    }

    return GamesTourModel(
      gameId: analysis.id,
      source: GameSource.savedAnalysis,
      whitePlayer: PlayerCard(
        name: whiteName,
        federation: whiteCountryCode,
        title: whiteTitle,
        rating: whiteElo,
        countryCode: whiteCountryCode,
        team: null,
      ),
      blackPlayer: PlayerCard(
        name: blackName,
        federation: blackCountryCode,
        title: blackTitle,
        rating: blackElo,
        countryCode: blackCountryCode,
        team: null,
      ),
      whiteTimeDisplay: '--:--',
      blackTimeDisplay: '--:--',
      whiteClockCentiseconds: (whiteClockSeconds ?? 0) * 100,
      blackClockCentiseconds: (blackClockSeconds ?? 0) * 100,
      whiteClockSeconds: whiteClockSeconds,
      blackClockSeconds: blackClockSeconds,
      gameStatus: status,
      roundId: round,
      tourId: event,
      timeControl: timeControl,
      lastMoveTime: parsedDate,
      lastMove: last?.uci,
      fen: last?.fen ?? analysis.chessGame.startingFen,
      eco: eco.isNotEmpty ? eco : null,
      openingName: openingName.isNotEmpty ? openingName : null,
    );
  }

  String _eventNameFromMetadata(Map<String, dynamic> md) {
    final eventRaw = md['Event'] as String? ?? md['Site'] as String? ?? '';
    return _formatEventName(eventRaw);
  }

  int _parseRating(Object? raw) {
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty) return 0;
    return int.tryParse(value) ?? 0;
  }

  String _formatEventName(String raw) {
    final cleaned = raw.replaceAll('-', ' ').replaceAll('_', ' ').trim();
    if (cleaned.isEmpty) return 'Unknown event';
    return cleaned;
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

  (int?, int?) _extractClockSeconds(List<ChessMove> mainline) {
    String? lastWhiteClock;
    String? lastBlackClock;

    for (final move in mainline) {
      final clock = move.clockTime;
      if (clock == null || clock.isEmpty) continue;

      // `ChessMove.turn` is the side to move AFTER the move.
      // If it's black to move, white just moved (white clock).
      if (move.turn == ChessColor.black) {
        lastWhiteClock = clock;
      } else if (move.turn == ChessColor.white) {
        lastBlackClock = clock;
      }
    }

    return (
      _parseClockToSeconds(lastWhiteClock),
      _parseClockToSeconds(lastBlackClock),
    );
  }

  int? _parseClockToSeconds(String? clock) {
    if (clock == null || clock.trim().isEmpty) return null;

    final parts = clock.trim().split(':').map((p) => p.trim()).toList();
    if (parts.length == 2) {
      final m = int.tryParse(parts[0]);
      final s = int.tryParse(parts[1]);
      if (m == null || s == null) return null;
      return m * 60 + s;
    }
    if (parts.length == 3) {
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final s = int.tryParse(parts[2]);
      if (h == null || m == null || s == null) return null;
      return h * 3600 + m * 60 + s;
    }
    return null;
  }
}
