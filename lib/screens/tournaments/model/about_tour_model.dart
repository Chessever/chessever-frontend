import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:equatable/equatable.dart';

class AboutTourModel extends Equatable{
  final String id;
  final String name;
  final String description;
  final String imageUrl;
  final List<String> players;
  final String timeControl;
  final String date;
  final String location;
  final String websiteUrl;

  const AboutTourModel({
    required this.id,
    required this.name,
    required this.description,
    required this.imageUrl,
    required this.players,
    required this.timeControl,
    required this.date,
    required this.location,
    required this.websiteUrl,
  });

  factory AboutTourModel.fromTour(Tour tour) {
    return AboutTourModel(
      id: tour.id,
      name: tour.name,
      //todo: add a fallback
      imageUrl: tour.image ?? '',
      //todo: This field needs to be added in the Tour Model
      description: '',
      players: tour.info.playersList,
      //todo: add a fallback
      timeControl: tour.info.tc ?? '',
      date: tour.dateRangeFormatted,
      //todo: add a fallback
      location: tour.info.location ?? '',
      //todo: add a fallback
      websiteUrl: tour.info.website ?? '',
    );
  }

  String extractDomain() {
    try {
      // Parse the URL
      Uri uri = Uri.parse(websiteUrl);

      // Get the host (domain)
      String host = uri.host;

      // Remove 'www.' prefix if it exists
      if (host.startsWith('www.')) {
        host = host.substring(4);
      }

      return host;
    } catch (e) {
      // Return empty string or handle error as needed
      return '';
    }
  }

  @override
  List<Object?> get props => [
    id,
    name,
    description,
    imageUrl,
    players,
    timeControl,
    date,
    location,
    websiteUrl,
  ];
}
