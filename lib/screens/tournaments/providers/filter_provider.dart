import 'package:chessever2/repository/local_storage/group_broadcast/group_broadcast_local_storage.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/screens/tournaments/tournament_screen.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// Filter controller provider
final tourFormatRepositoryProvider =
    AutoDisposeProvider.family<FilterController, TournamentCategory>((
      ref,
      tournamentCategory,
    ) {
      return FilterController(ref: ref, tournamentCategory: tournamentCategory);
    });

// Formats provider
final tourFormatsProvider =
    AutoDisposeFutureProvider.family<List<String>, TournamentCategory>((
      ref,
      tournamentCategory,
    ) async {
      return ref
          .read(tourFormatRepositoryProvider(tournamentCategory))
          .getFormats();
    });

// Filter controller
class FilterController {
  FilterController({required this.ref, required this.tournamentCategory});

  final Ref ref;
  final TournamentCategory tournamentCategory;

  Future<List<String>> getFormats() async {
    final groupBroadcast =
        await ref
            .read(groupBroadcastLocalStorage(tournamentCategory))
            .getGroupBroadcasts();
    final formats =
        groupBroadcast
            .map((tour) => tour.timeControl?.trim())
            .whereType<String>()
            .where((format) => format.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return ['All Formats', ...formats];
  }

  Future<List<GroupBroadcast>> applyFilter(String selectedFormat) async {
    print(' applyFilter called with format: $selectedFormat');
    final groupBroadcast = await ref.read(groupBroadcastLocalStorage(tournamentCategory)).getGroupBroadcasts();
    final filteredTours =
        selectedFormat == 'All Formats'
            ? groupBroadcast
            : groupBroadcast.where((tour) {
              final format = tour.timeControl?.trim().toLowerCase();
              final selected = selectedFormat.trim().toLowerCase();
              return format == selected;
            }).toList();

    return filteredTours;
  }
}
