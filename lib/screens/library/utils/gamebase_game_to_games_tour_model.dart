import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/chess_title_utils.dart';

GamesTourModel mapGamebaseGameToGamesTourModel(GamebaseGame game) {
  final data = game.data ?? const <String, dynamic>{};
  final mdRaw = data['md'] ?? data['metadata'];
  final md =
      mdRaw is Map
          ? Map<String, dynamic>.from(mdRaw)
          : const <String, dynamic>{};

  String countryCodeFromMetadata({required bool isWhite}) {
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

  String pickName(String key, String fallback) {
    final raw = md[key];
    final value = (raw?.toString() ?? '').trim();
    return value.isNotEmpty ? value : fallback;
  }

  final whiteName = pickName('White', 'White');
  final blackName = pickName('Black', 'Black');

  final rawResult = (md['Result']?.toString() ?? '').trim();
  final resultValue = rawResult.isNotEmpty ? rawResult : game.resultDisplay;
  final status = GameStatus.fromString(resultValue);
  final pgnResult = _toPgnResult(status);

  int parseRating(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int? parseFideId(Object? raw) {
    if (raw == null) return null;
    return int.tryParse(raw.toString());
  }

  final whitePlayer = PlayerCard(
    name: whiteName,
    federation: '',
    title: ChessTitleUtils.normalize((md['WhiteTitle']?.toString() ?? '').trim()),
    rating: parseRating(md['WhiteElo']),
    countryCode: countryCodeFromMetadata(isWhite: true),
    team: null,
    fideId: parseFideId(md['WhiteFideId']),
  );

  final blackPlayer = PlayerCard(
    name: blackName,
    federation: '',
    title: ChessTitleUtils.normalize((md['BlackTitle']?.toString() ?? '').trim()),
    rating: parseRating(md['BlackElo']),
    countryCode: countryCodeFromMetadata(isWhite: false),
    team: null,
    fideId: parseFideId(md['BlackFideId']),
  );

  final eventRaw = (md['Event']?.toString() ?? '').trim();
  final tourId = eventRaw.isNotEmpty ? eventRaw : 'Gamebase';

  final ecoRaw = (md['ECO']?.toString() ?? '').trim();
  final roundSlug = ecoRaw.isNotEmpty ? ecoRaw : game.timeControlDisplay;

  final pgn =
      buildPgnFromGamebaseData(data) ??
      _buildFallbackPgn(
        whiteName: whiteName,
        blackName: blackName,
        result: pgnResult,
        event: tourId,
      );

  return GamesTourModel(
    gameId: game.id,
    whitePlayer: whitePlayer,
    blackPlayer: blackPlayer,
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: status,
    roundId: 'gamebase',
    roundSlug: roundSlug.isNotEmpty ? roundSlug : null,
    tourId: tourId,
    pgn: pgn,
    lastMoveTime: game.date,
  );
}

String _buildFallbackPgn({
  required String whiteName,
  required String blackName,
  required String result,
  required String event,
}) {
  final safeResult =
      (result == '1-0' ||
              result == '0-1' ||
              result == '1/2-1/2' ||
              result == '*')
          ? result
          : '*';

  final sb =
      StringBuffer()
        ..writeln('[Event "$event"]')
        ..writeln('[White "$whiteName"]')
        ..writeln('[Black "$blackName"]')
        ..writeln('[Result "$safeResult"]')
        ..writeln()
        ..write(safeResult);

  return sb.toString();
}

String _toPgnResult(GameStatus status) {
  switch (status) {
    case GameStatus.whiteWins:
      return '1-0';
    case GameStatus.blackWins:
      return '0-1';
    case GameStatus.draw:
      return '1/2-1/2';
    case GameStatus.ongoing:
      return '*';
    case GameStatus.unknown:
      return '*';
  }
}
