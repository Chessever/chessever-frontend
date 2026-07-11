import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final selectedBroadcastModelProvider = StateProvider<GroupBroadcast?>(
  (ref) => null,
);

final selectedTourModeProvider = StateProvider<TournamentDetailScreenMode>(
  (ref) => TournamentDetailScreenMode.games,
);

/// The logical pages available to tournament detail layouts.
///
/// A mode's enum index is deliberately not its page index: regular, knockout,
/// and team events expose different ordered subsets. Use the explicit mapping
/// helpers in `tour_detail_tabs.dart` whenever converting between a page and a
/// mode.
enum TournamentDetailScreenMode { about, games, bracket, standings, players }
