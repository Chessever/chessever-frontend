import 'package:chessever2/repository/lichess/fide/fide_player.dart';
import 'package:chessever2/repository/lichess/fide/lichess_fide_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Provider to get FIDE player ratings from Lichess API
final fidePlayerProvider = FutureProvider.family.autoDispose<
  FidePlayer?,
  int
>((ref, fideId) async {
  final repo = ref.read(lichessFideRepoProvider);
  
  try {
    final player = await repo.getPlayerById(fideId);
    return player;
  } catch (e) {
    print('Error fetching FIDE player $fideId: $e');
    return null;
  }
});

/// Provider to search FIDE players by name
final fidePlayerSearchProvider = FutureProvider.family.autoDispose<
  List<FidePlayer>,
  String
>((ref, name) async {
  final repo = ref.read(lichessFideRepoProvider);
  
  try {
    final players = await repo.searchPlayersByName(name);
    return players;
  } catch (e) {
    print('Error searching FIDE players with name "$name": $e');
    return [];
  }
});

/// Request model for FIDE rating lookup
class FideRatingRequest {
  final int? fideId;
  final String? playerName;
  final String timeControlType; // "standard", "rapid", "blitz"

  const FideRatingRequest({
    this.fideId,
    this.playerName,
    required this.timeControlType,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FideRatingRequest &&
          runtimeType == other.runtimeType &&
          fideId == other.fideId &&
          playerName == other.playerName &&
          timeControlType == other.timeControlType;

  @override
  int get hashCode =>
      fideId.hashCode ^ playerName.hashCode ^ timeControlType.hashCode;
}

/// Provider to get specific time control rating for a player
final fideRatingProvider = FutureProvider.family.autoDispose<
  int?,
  FideRatingRequest
>((ref, request) async {
  // Prefer FIDE ID if available
  if (request.fideId != null) {
    final playerAsync = await ref.watch(fidePlayerProvider(request.fideId!).future);
    return playerAsync?.getRating(request.timeControlType);
  }

  // Fallback to name search
  if (request.playerName != null && request.playerName!.isNotEmpty) {
    final players = await ref.watch(
      fidePlayerSearchProvider(request.playerName!).future,
    );
    
    if (players.isNotEmpty) {
      // Return first match rating
      return players.first.getRating(request.timeControlType);
    }
  }

  return null;
});
