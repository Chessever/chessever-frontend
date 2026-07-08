import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final selectedBroadcastModelProvider = StateProvider<GroupBroadcast?>(
  (ref) => null,
);

final selectedTourModeProvider = StateProvider<TournamentDetailScreenMode>(
  (ref) => TournamentDetailScreenMode.games,
);

/// For Tabs. `players` is appended so the first three indices stay stable —
/// each visible tab list (3-tab regular/knockout, 4-tab team) is a prefix of
/// these values, keeping `values[index]` valid for both layouts.
enum TournamentDetailScreenMode { about, games, standings, players }
