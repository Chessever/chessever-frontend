import 'package:chessever2/repository/supabase/tour/tour.dart';

final RegExp _combinedLabel = RegExp(r'(^|[^a-z0-9])combined([^a-z0-9]|$)');

/// Organizer-published Combined sections repeat the real source groups.
bool isCombinedSectionLabel({String? name, String? slug}) =>
    _combinedLabel.hasMatch('${name ?? ''} ${slug ?? ''}'.toLowerCase());

bool isCombinedSourceTour(Tour tour) =>
    !tour.isMirror && !isCombinedSectionLabel(name: tour.name, slug: tour.slug);

/// Hide organizer Combined groups wherever real categories are available.
/// A standalone feed keeps its title and remains reachable.
List<TourModel> visibleEventCategories(List<TourModel> tours) {
  final real = tours
      .where((model) => isCombinedSourceTour(model.tour))
      .toList();
  return real.isEmpty ? tours : real;
}
