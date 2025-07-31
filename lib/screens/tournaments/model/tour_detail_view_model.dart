import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/tournaments/model/about_tour_model.dart';
import 'package:equatable/equatable.dart';

class TourDetailViewModel extends Equatable {
  const TourDetailViewModel({
    required this.aboutTourModel,
    required this.selectedTourId,
    required this.tours,
  });

  final AboutTourModel aboutTourModel;
  final String selectedTourId;
  final List<Tour> tours;

  @override
  List<Object?> get props => [
    this.aboutTourModel,
    this.selectedTourId,
    this.tours,
  ];
}
