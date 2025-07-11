import 'package:chessever2/screens/tournaments/model/tour_event_card_model.dart';
import 'package:chessever2/utils/location_service_provider.dart';
import 'package:chessever2/widgets/event_card/starred_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final tournamentSortingServiceProvider = Provider<TournamentSortingService>((
  ref,
) {
  return TournamentSortingService(ref);
});

class TournamentSortingService {
  final Ref ref;

  TournamentSortingService(this.ref);

  List<TourEventCardModel> sortUpcomingTours(
    List<TourEventCardModel> tours,
    String dropDownSelectedCountry,
  ) {
    final currentLocation = _getCurrentLocation(tours);
    final favorites = ref.watch(
      starredProvider,
    ); // Get the list of favorited ids
    final hasFavorites = favorites.isNotEmpty;

    final filteredList =
        tours
            .where((t) => t.tourEventCategory == TourEventCategory.upcoming)
            .toList();

    filteredList.sort((a, b) {
      final isCountrymanA = _isCountryman(
        a,
        currentLocation,
        dropDownSelectedCountry,
      );
      final isCountrymanB = _isCountryman(
        b,
        currentLocation,
        dropDownSelectedCountry,
      );

      if (isCountrymanA && !isCountrymanB) return -1;
      if (!isCountrymanA && isCountrymanB) return 1;

      final isFavoriteA = favorites.contains(a.id);
      final isFavoriteB = favorites.contains(b.id);

      if (hasFavorites) {
        if (isFavoriteA && !isFavoriteB) return -1;
        if (!isFavoriteA && isFavoriteB) return 1;
      }

      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    return filteredList;
  }

  List<TourEventCardModel> sortAllTours(
    List<TourEventCardModel> tours,
    String dropDownSelectedCountry,
  ) {
    final currentLocation = _getCurrentLocation(tours);
    final favorites = ref.watch(
      starredProvider,
    ); // Get the list of favorited ids
    final hasFavorites = favorites.isNotEmpty;

    final filteredList =
        tours
            .where((t) => t.tourEventCategory != TourEventCategory.upcoming)
            .toList();

    filteredList.sort((a, b) {
      final isCountrymanA = _isCountryman(
        a,
        currentLocation,
        dropDownSelectedCountry,
      );
      final isCountrymanB = _isCountryman(
        b,
        currentLocation,
        dropDownSelectedCountry,
      );

      if (isCountrymanA && !isCountrymanB) return -1;
      if (!isCountrymanA && isCountrymanB) return 1;

      final isFavoriteA = favorites.contains(a.id);
      final isFavoriteB = favorites.contains(b.id);

      if (hasFavorites) {
        if (isFavoriteA && !isFavoriteB) return -1;
        if (!isFavoriteA && isFavoriteB) return 1;
      }

      final statusPriorityA = _getTournamentStatusPriority(a.tourEventCategory);
      final statusPriorityB = _getTournamentStatusPriority(b.tourEventCategory);

      final statusComparison = statusPriorityA.compareTo(statusPriorityB);
      if (statusComparison != 0) return statusComparison;

      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    return filteredList;
  }

  bool _isCountryman(
    TourEventCardModel tournament,
    String currentLocation,
    String dropDownSelectedCountry,
  ) {
    if (currentLocation.isEmpty || dropDownSelectedCountry.isEmpty) {
      print(
        'Empty location data - Current: "$currentLocation", Dropdown: "$dropDownSelectedCountry"',
      );
      return false;
    }

    final tournamentLocation =
        ref
            .read(locationServiceProvider)
            .getCountryName(tournament.location)
            .toLowerCase();

    // Use exact match now, trim spaces just in case
    final tournamentLocTrimmed = tournamentLocation.trim();
    final dropDownTrimmed = dropDownSelectedCountry.trim();

    final isCountryman = tournamentLocTrimmed == dropDownTrimmed;

    print('Checking countryman: ${tournament.title}');
    print(' Tournament location: "$tournamentLocTrimmed"');
    print(' Dropdown country: "$dropDownTrimmed"');
    print(' Is countryman: $isCountryman');

    return isCountryman;
  }

  int _getTournamentStatusPriority(TourEventCategory category) {
    switch (category) {
      case TourEventCategory.live:
        return 1;
      case TourEventCategory.completed:
        return 2;
      default:
        return 3;
    }
  }

  // Helper methods to safely get location data
  String _getCurrentLocation(List<TourEventCardModel> tours) {
    try {
      if (tours.isEmpty) return '';

      final location = ref
          .read(locationServiceProvider)
          .getCountryName(tours.first.location);
      return location.toLowerCase();
    } catch (e) {
      print('Error getting current location: $e');
      return '';
    }
  }
}
