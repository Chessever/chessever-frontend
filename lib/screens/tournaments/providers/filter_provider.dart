import 'package:chessever2/repository/local_storage/tournament/tour_local_storage.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final tourFormatRepositoryProvider = Provider<FilterController>((ref) {
  return FilterController(ref);
});

final tourFormatsProvider = FutureProvider.autoDispose<List<String>>((
  ref,
) async {
  return ref.read(tourFormatRepositoryProvider).getFormats();
});

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
}
