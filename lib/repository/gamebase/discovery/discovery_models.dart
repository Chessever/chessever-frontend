import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/chess_title_utils.dart';

/// Plain models for the Discovery surfaces (Lichess Studies + Miniatures).
/// Hand-written `fromJson` (no codegen) to keep the new endpoints lightweight.

DateTime? _parseDate(Object? raw) {
  if (raw == null) return null;
  final s = raw.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

int _parseInt(Object? raw, [int fallback = 0]) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw?.toString() ?? '') ?? fallback;
}

/// A single page of `{ items, total, limit, offset }` envelopes.
class PagedResult<T> {
  const PagedResult({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  final List<T> items;
  final int total;
  final int limit;
  final int offset;

  bool get hasMore => offset + items.length < total;

  static PagedResult<T> fromData<T>(
    Map<String, dynamic> data,
    T Function(Map<String, dynamic>) itemFromJson,
  ) {
    final rawItems = (data['items'] as List?) ?? const [];
    return PagedResult<T>(
      items: [
        for (final e in rawItems)
          itemFromJson(Map<String, dynamic>.from(e as Map)),
      ],
      total: _parseInt(data['total']),
      limit: _parseInt(data['limit']),
      offset: _parseInt(data['offset']),
    );
  }
}

class LichessStudy {
  const LichessStudy({
    required this.id,
    required this.name,
    required this.authorUsername,
    required this.views,
    required this.lichessCreatedAt,
    required this.lichessUpdatedAt,
    required this.chapterCount,
    required this.plyTotal,
    required this.hasAnnotations,
    required this.credibilityScore,
    required this.passedGate,
    required this.status,
    required this.syncedAt,
  });

  final String id;
  final String name;
  final String? authorUsername;
  final int views;
  final DateTime? lichessCreatedAt;
  final DateTime? lichessUpdatedAt;
  final int chapterCount;
  final int plyTotal;
  final bool hasAnnotations;
  final double credibilityScore;
  final bool passedGate;
  final String status;
  final DateTime? syncedAt;

  factory LichessStudy.fromJson(Map<String, dynamic> json) {
    return LichessStudy(
      id: json['id'].toString(),
      name: (json['name'] ?? 'Untitled study').toString(),
      authorUsername: json['authorUsername']?.toString(),
      views: _parseInt(json['views']),
      lichessCreatedAt: _parseDate(json['lichessCreatedAt']),
      lichessUpdatedAt: _parseDate(json['lichessUpdatedAt']),
      chapterCount: _parseInt(json['chapterCount']),
      plyTotal: _parseInt(json['plyTotal']),
      hasAnnotations: json['hasAnnotations'] == true,
      credibilityScore:
          (json['credibilityScore'] is num)
              ? (json['credibilityScore'] as num).toDouble()
              : double.tryParse(json['credibilityScore']?.toString() ?? '') ??
                  0,
      passedGate: json['passedGate'] == true,
      status: (json['status'] ?? 'active').toString(),
      syncedAt: _parseDate(json['syncedAt']),
    );
  }
}

class LichessStudyChapter {
  const LichessStudyChapter({
    required this.id,
    required this.chapterId,
    required this.name,
    required this.plyCount,
    required this.orderIndex,
  });

  final String id;
  final String chapterId;
  final String? name;
  final int plyCount;
  final int orderIndex;

  factory LichessStudyChapter.fromJson(Map<String, dynamic> json) {
    return LichessStudyChapter(
      id: json['id'].toString(),
      chapterId: json['chapterId'].toString(),
      name: json['name']?.toString(),
      plyCount: _parseInt(json['plyCount']),
      orderIndex: _parseInt(json['orderIndex']),
    );
  }
}

class LichessStudyDetail {
  const LichessStudyDetail({required this.study, required this.chapters});

  final LichessStudy study;
  final List<LichessStudyChapter> chapters;

  factory LichessStudyDetail.fromJson(Map<String, dynamic> json) {
    final rawChapters = (json['chapters'] as List?) ?? const [];
    return LichessStudyDetail(
      study: LichessStudy.fromJson(
        Map<String, dynamic>.from(json['study'] as Map),
      ),
      chapters: [
        for (final c in rawChapters)
          LichessStudyChapter.fromJson(Map<String, dynamic>.from(c as Map)),
      ]..sort((a, b) => a.orderIndex.compareTo(b.orderIndex)),
    );
  }
}

class Miniature {
  const Miniature({
    required this.gameId,
    required this.avgRating,
    required this.plyCount,
    required this.finalMoveNumber,
    required this.result,
    required this.timeControl,
    required this.isOnline,
    required this.date,
    required this.event,
    required this.eco,
    required this.whiteName,
    required this.blackName,
    required this.whiteElo,
    required this.blackElo,
  });

  final String gameId;
  final int? avgRating;
  final int plyCount;
  final int finalMoveNumber;

  /// Decisive result only: 'W' (white wins) or 'B' (black wins).
  final String result;
  final String timeControl; // CLASSICAL | RAPID | BLITZ
  final bool isOnline;
  final DateTime? date;
  final String? event;
  final String? eco;
  final String? whiteName;
  final String? blackName;
  final int? whiteElo;
  final int? blackElo;

  factory Miniature.fromJson(Map<String, dynamic> json) {
    return Miniature(
      gameId: json['gameId'].toString(),
      avgRating: json['avgRating'] == null ? null : _parseInt(json['avgRating']),
      plyCount: _parseInt(json['plyCount']),
      finalMoveNumber: _parseInt(json['finalMoveNumber']),
      result: (json['result'] ?? 'W').toString(),
      timeControl: (json['timeControl'] ?? 'CLASSICAL').toString(),
      isOnline: json['isOnline'] == true,
      date: _parseDate(json['date']),
      event: json['event']?.toString(),
      eco: json['eco']?.toString(),
      whiteName: json['whiteName']?.toString(),
      blackName: json['blackName']?.toString(),
      whiteElo: json['whiteElo'] == null ? null : _parseInt(json['whiteElo']),
      blackElo: json['blackElo'] == null ? null : _parseInt(json['blackElo']),
    );
  }

  GameStatus get status =>
      result == 'B' ? GameStatus.blackWins : GameStatus.whiteWins;

  /// Builds the board-ready model. Source is [GameSource.gamebase] so the board
  /// lazily fetches the full PGN by [gameId] (these are master-database games),
  /// mirroring [mapGamebaseGameToGamesTourModel].
  GamesTourModel toGamesTourModel() {
    final ecoClean = (eco ?? '').trim();
    final event0 = (event ?? '').trim();
    final fallbackPgn =
        buildPgnFromGamebaseData(<String, dynamic>{
          'md': {
            'White': whiteName ?? 'White',
            'Black': blackName ?? 'Black',
            'Result': result == 'B' ? '0-1' : '1-0',
            if (event0.isNotEmpty) 'Event': event0,
            if (ecoClean.isNotEmpty) 'ECO': ecoClean,
          },
        });

    return GamesTourModel(
      gameId: gameId,
      source: GameSource.gamebase,
      whitePlayer: PlayerCard(
        name: (whiteName ?? 'White').trim().isEmpty ? 'White' : whiteName!,
        federation: '',
        title: ChessTitleUtils.normalize(''),
        rating: whiteElo ?? 0,
        countryCode: '',
        team: null,
      ),
      blackPlayer: PlayerCard(
        name: (blackName ?? 'Black').trim().isEmpty ? 'Black' : blackName!,
        federation: '',
        title: ChessTitleUtils.normalize(''),
        rating: blackElo ?? 0,
        countryCode: '',
        team: null,
      ),
      whiteTimeDisplay: '--:--',
      blackTimeDisplay: '--:--',
      whiteClockCentiseconds: 0,
      blackClockCentiseconds: 0,
      gameStatus: status,
      roundId: 'miniature',
      roundSlug: ecoClean.isNotEmpty ? ecoClean : null,
      tourId: event0.isNotEmpty ? event0 : 'Miniatures',
      tourSlug: event0.isNotEmpty ? event0 : null,
      pgn: fallbackPgn,
      lastMoveTime: date,
      eco: ecoClean.isNotEmpty ? ecoClean : null,
      avgElo: avgRating,
      isOnline: isOnline,
    );
  }
}
