import 'package:chessever2/repository/local_storage/tournament/tour_local_storage.dart';
import 'package:chessever2/screens/tournaments/model/tour_event_card_model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../repository/supabase/tour/tour.dart';

// Filter controller provider
final tourFormatRepositoryProvider = Provider<FilterController>((ref) {
  return FilterController(ref);
});

// Formats provider
final tourFormatsProvider = FutureProvider.autoDispose<List<String>>((
  ref,
) async {
  return ref.read(tourFormatRepositoryProvider).getFormats();
});

// Filter controller
class FilterController {
  FilterController(this.ref);
  final Ref ref;

  Future<List<String>> getFormats() async {
    final tours = await ref.read(tourLocalStorageProvider).getTours();
    final formats =
        tours
            .map((tour) => tour.info.format?.trim())
            .whereType<String>()
            .where((format) => format.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return ['All Formats', ...formats];
  }

  Future<List<Tour>> applyFilter(String selectedFormat) async {
    print(' applyFilter called with format: $selectedFormat');
    final tours = await ref.read(tourLocalStorageProvider).getTours();
    final filteredTours =
        selectedFormat == 'All Formats'
            ? tours
            : tours.where((tour) {
              final format = tour.info.format?.trim().toLowerCase();
              final selected = selectedFormat.trim().toLowerCase();
              return format == selected && tour.info.players != null;
            }).toList();

    print(' Selected format: $selectedFormat');
    print(' Total tours: ${tours.length}');
    print('Filtered tours: ${filteredTours.length}');
    for (final tour in filteredTours) {
      print('Tour: ${tour.info.players}, Format: ${tour.info.format}');
    }

    return filteredTours;
  }
}
