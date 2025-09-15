import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';

abstract class IGroupEventScreenController {
  Ref get ref;
  GroupEventCategory get tourEventCategory;

  Future<void> loadTours({
    List<GroupBroadcast>? inputBroadcast,
    List<String>? liveIds,
  });

  Future<void> setFilteredModels(List<GroupBroadcast> filterBroadcast);

  Future<void> resetFilters();

  Future<void> onRefresh();

  void onSelectTournament({required BuildContext context, required String id});

  void onSelectPlayer({
    required BuildContext context,
    required SearchPlayer player,
  });

  Future<void> searchForTournament(
    String query,
    GroupEventCategory tourEventCategory,
  );

  Future<void> loadTournaments(GroupEventCategory tourEventCategory);

  Future<List<SearchPlayer>> getAllPlayersFromCurrentTournaments();

  Future<List<SearchPlayer>> searchPlayersOnly(String query);
}
