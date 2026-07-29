import 'package:chessever2/services/lichess_move_annotations_service.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class LichessMoveAnnotationsParams {
  final String? lichessGameId;
  final String? siteUrl;
  final String signature;
  final List<String> moveSans;
  final bool isLiveGame;

  const LichessMoveAnnotationsParams({
    required this.lichessGameId,
    this.siteUrl,
    required this.signature,
    required this.moveSans,
    required this.isLiveGame,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LichessMoveAnnotationsParams &&
          lichessGameId == other.lichessGameId &&
          siteUrl == other.siteUrl &&
          signature == other.signature &&
          isLiveGame == other.isLiveGame;

  @override
  int get hashCode =>
      Object.hash(lichessGameId, siteUrl, signature, isLiveGame);
}

final lichessMoveAnnotationsProvider = FutureProvider.family.autoDispose<
  Map<int, LichessMoveAnnotation>?,
  LichessMoveAnnotationsParams
>((ref, params) async {
  final gameId = params.lichessGameId;
  debugPrint(
    '🔍 [AnnotationsProvider] gameId=$gameId, isLiveGame=${params.isLiveGame}, moveSans.length=${params.moveSans.length}, siteUrl=${params.siteUrl}',
  );

  if (gameId == null ||
      gameId.isEmpty ||
      params.isLiveGame ||
      params.moveSans.isEmpty) {
    debugPrint(
      '🔍 [AnnotationsProvider] Skipping: gameId=${gameId == null ? 'null' : (gameId.isEmpty ? 'empty' : 'ok')}, isLive=${params.isLiveGame}, hasMoves=${params.moveSans.isNotEmpty}',
    );
    return null;
  }

  debugPrint('🔍 [AnnotationsProvider] Fetching annotations for $gameId...');
  final result = await LichessMoveAnnotationsService.getAnnotations(
    lichessGameId: gameId,
    moveSans: params.moveSans,
    signature: params.signature,
    siteUrl: params.siteUrl,
  );
  debugPrint(
    '🔍 [AnnotationsProvider] Result: ${result?.length ?? 0} annotations',
  );
  if (result != null && result.isNotEmpty) {
    debugPrint(
      '🔍 [AnnotationsProvider] Annotation indices: ${result.keys.toList()}',
    );
  }
  return result;
});
