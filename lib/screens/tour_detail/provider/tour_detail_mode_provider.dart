import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final selectedBroadcastModelProvider = StateProvider<GroupBroadcast?>(
  (ref) => null,
);

final selectedTourModeProvider =
    AutoDisposeStateProvider<TournamentDetailScreenMode>(
      (ref) => TournamentDetailScreenMode.games,
    );

/// For Tabs
enum TournamentDetailScreenMode {
  about,
  games,
  standings,
}
