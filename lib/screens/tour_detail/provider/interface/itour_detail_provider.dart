abstract class ITourDetailProvider {
  Future<void> loadTourDetails();

  void updateSelection(String tourId);

  Future<void> refreshTourDetails();
}
