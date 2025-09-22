import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';

abstract class ITourDetailProvider {
  Future<void> loadTourDetails();
  void updateSelection(String tourId);
  Future<void> refreshTourDetails();
}

abstract class ITourProcessor {
  Future<List<TourModel>> processTours(
    List<Tour> tours,
    List<String> liveTourIds,
  );
  TourModel? processSingleTour(
    Tour tour,
    DateTime now,
    List<String> liveTourIds,
  );
  RoundStatus calculateRoundStatus(
    String tourId,
    DateTime now,
    DateTime startDate,
    DateTime endDate,
    List<String> liveTourIds,
  );
}

abstract class ITourSelector {
  Tour determineSelectedTour(
    List<TourModel> tourModels,
    TourDetailViewModel? currentState,
    List<String> liveTourIds,
  );
  TourModel findBestTour(List<TourModel> tourModels, List<String> liveTourIds);
  TourModel? findTourModel(List<TourModel> tourModels, String tourId);
}

abstract class IViewModelFactory {
  TourDetailViewModel createViewModel(
    Tour selectedTour,
    List<TourModel> tourModels,
    List<String> liveTourIds,
  );
  TourDetailViewModel createViewModelFromExisting(
    TourDetailViewModel currentState,
    Tour selectedTour,
    List<String> liveTourIds,
  );
}

abstract class IStateManager {
  void setDataState(TourDetailViewModel viewModel);
  void setErrorState(Object error, [StackTrace? stackTrace]);
  void logWarning(String message);
}

abstract class ILiveTourListener {
  void setupLiveTourIdListener();
  void updateStateWithNewLiveTourIds(
    TourDetailViewModel currentState,
    List<String> newLiveTourIds,
  );
  bool listsAreEqual(List<String> list1, List<String> list2);
}
