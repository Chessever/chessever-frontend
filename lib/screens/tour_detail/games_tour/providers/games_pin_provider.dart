import 'package:chessever2/repository/local_storage/tournament/games/pin_games_local_storage.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final gamesPinprovider = FutureProvider<List<String>>((ref) async {
  final pinnedIds = await ref.read(pinGameLocalStorage).getPinnedGameIds();
  return pinnedIds;
});
