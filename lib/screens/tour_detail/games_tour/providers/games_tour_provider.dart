

import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final gamesTourProvider = FutureProvider.family< List<Games>, String>((ref ,id )async { 
  final gamesLocalStorageProvider = ref.read(gamesLocalStorage);
  return await gamesLocalStorageProvider.fetchAndSaveGames(
    id,
  );
});