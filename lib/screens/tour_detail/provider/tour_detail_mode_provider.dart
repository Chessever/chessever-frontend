import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final selectedBroadcastModelProvider = StateProvider<GroupBroadcast?>(
  (ref) => null,
);

/// Re-reads the canonical base-table row while an event is open.
///
/// Home and discovery surfaces intentionally keep using the existing SQL
/// views. Those views predate `broadcast_writer`, so their row may not carry
/// the source attribution even after the additive column is deployed. A
/// detail-only lookup keeps those proven list queries untouched while making
/// the source label accurate. Network failures retain the already-selected
/// event instead of affecting navigation.
final canonicalSelectedBroadcastProvider =
    FutureProvider.autoDispose<GroupBroadcast?>((ref) async {
      final selected = ref.watch(selectedBroadcastModelProvider);
      if (selected == null || selected.id.trim().isEmpty) return selected;

      try {
        return await ref
            .read(groupBroadcastRepositoryProvider)
            .getGroupBroadcastById(selected.id);
      } catch (_) {
        return selected;
      }
    });

final selectedBroadcastWriterAttributionProvider = Provider<String>((ref) {
  final selected = ref.watch(selectedBroadcastModelProvider);
  final canonical = ref.watch(canonicalSelectedBroadcastProvider).valueOrNull;
  return (canonical ?? selected)?.writerAttributionLabel ??
      'Powered by Lichess';
});

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
