import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';

RoundStatus calculateTourRoundStatus({
  required String tourId,
  required DateTime now,
  required DateTime startDate,
  required DateTime endDate,
  required List<String> liveTourIds,
}) {
  if (now.isBefore(startDate)) {
    return RoundStatus.upcoming;
  } else if (now.isAfter(endDate)) {
    return RoundStatus.completed;
  } else if (liveTourIds.contains(tourId)) {
    return RoundStatus.live;
  } else {
    return RoundStatus.ongoing;
  }
}

Tour? findTourById(List<TourModel> tourModels, String? tourId) {
  if (tourId == null || tourId.isEmpty) {
    return null;
  }

  for (final tourModel in tourModels) {
    if (tourModel.tour.id == tourId) {
      return tourModel.tour;
    }
  }

  return null;
}

Tour selectDefaultTour({
  required List<TourModel> tourModels,
  required List<String> liveTourIds,
  String? currentSelectedId,
  String? savedTourId,
  String? activityTourId,
}) {
  final hasStartedTours = tourModels.any(
    (model) => model.roundStatus != RoundStatus.upcoming,
  );

  bool canUseSelection(TourModel model) {
    if (!hasStartedTours) {
      return true;
    }
    return model.roundStatus != RoundStatus.upcoming;
  }

  Tour? findSelectableTour(String? tourId) {
    if (tourId == null || tourId.isEmpty) {
      return null;
    }

    for (final model in tourModels) {
      if (model.tour.id == tourId && canUseSelection(model)) {
        return model.tour;
      }
    }

    return null;
  }

  final currentTour = findSelectableTour(currentSelectedId);
  if (currentTour != null) {
    return currentTour;
  }

  final savedTour = findSelectableTour(savedTourId);
  if (savedTour != null) {
    return savedTour;
  }

  final liveModels =
      tourModels
          .where((model) => model.roundStatus == RoundStatus.live)
          .toList()
        ..sort((a, b) {
          final aDate =
              a.tour.dates.isNotEmpty ? a.tour.dates.first : DateTime(1970);
          final bDate =
              b.tour.dates.isNotEmpty ? b.tour.dates.first : DateTime(1970);
          return bDate.compareTo(aDate);
        });
  if (liveModels.isNotEmpty) {
    return liveModels.first.tour;
  }

  final selectableModels =
      hasStartedTours
          ? tourModels
              .where((model) => model.roundStatus != RoundStatus.upcoming)
              .toList()
          : List<TourModel>.from(tourModels);

  if (selectableModels.isNotEmpty) {
    final toursWithDates =
        selectableModels.where((model) => model.tour.dates.isNotEmpty).toList();

    if (toursWithDates.isNotEmpty) {
      final firstStart = toursWithDates.first.tour.dates.first;
      final allSameStart = toursWithDates.every(
        (model) =>
            model.tour.dates.first.year == firstStart.year &&
            model.tour.dates.first.month == firstStart.month &&
            model.tour.dates.first.day == firstStart.day,
      );

      if (allSameStart) {
        final withElo =
            toursWithDates.where((model) => model.tour.avgElo != null).toList()
              ..sort((a, b) => b.tour.avgElo!.compareTo(a.tour.avgElo!));
        if (withElo.isNotEmpty) {
          return withElo.first.tour;
        }
      } else {
        toursWithDates.sort((a, b) {
          final dateCompare = b.tour.dates.first.compareTo(a.tour.dates.first);
          if (dateCompare != 0) {
            return dateCompare;
          }
          final aElo = a.tour.avgElo ?? 0;
          final bElo = b.tour.avgElo ?? 0;
          return bElo.compareTo(aElo);
        });
        return toursWithDates.first.tour;
      }
    }

    final withElo =
        selectableModels.where((model) => model.tour.avgElo != null).toList()
          ..sort((a, b) => b.tour.avgElo!.compareTo(a.tour.avgElo!));
    if (withElo.isNotEmpty) {
      return withElo.first.tour;
    }
  }

  final activityTour = findSelectableTour(activityTourId);
  if (activityTour != null) {
    return activityTour;
  }

  final ongoingTours =
      tourModels
          .where((model) => model.roundStatus == RoundStatus.ongoing)
          .toList()
        ..sort((a, b) {
          final aDate =
              a.tour.dates.isNotEmpty ? a.tour.dates.first : DateTime(1970);
          final bDate =
              b.tour.dates.isNotEmpty ? b.tour.dates.first : DateTime(1970);
          return bDate.compareTo(aDate);
        });
  if (ongoingTours.isNotEmpty) {
    return ongoingTours.first.tour;
  }

  final completedTours =
      tourModels
          .where((model) => model.roundStatus == RoundStatus.completed)
          .toList()
        ..sort((a, b) {
          final aDate =
              a.tour.dates.isNotEmpty ? a.tour.dates.last : DateTime(1970);
          final bDate =
              b.tour.dates.isNotEmpty ? b.tour.dates.last : DateTime(1970);
          return bDate.compareTo(aDate);
        });
  if (completedTours.isNotEmpty) {
    return completedTours.first.tour;
  }

  final upcomingTours =
      tourModels
          .where((model) => model.roundStatus == RoundStatus.upcoming)
          .toList()
        ..sort((a, b) {
          final aDate =
              a.tour.dates.isNotEmpty ? a.tour.dates.first : DateTime(1970);
          final bDate =
              b.tour.dates.isNotEmpty ? b.tour.dates.first : DateTime(1970);
          return aDate.compareTo(bDate);
        });
  if (upcomingTours.isNotEmpty) {
    return upcomingTours.first.tour;
  }

  return tourModels.first.tour;
}
