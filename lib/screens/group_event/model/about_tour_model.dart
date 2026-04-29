import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:equatable/equatable.dart';

class AboutTourModel extends Equatable {
  final String id;
  final String slug;
  final String name;
  final String description;
  final String imageUrl;
  final List<TournamentPlayer> players;
  final String timeControl;
  final String date;
  final String location;
  final String websiteUrl;
  final String standingsUrl;
  final String tourUrl;
  final String? groupBroadcastId;

  const AboutTourModel({
    required this.id,
    required this.slug,
    required this.name,
    required this.description,
    required this.imageUrl,
    required this.players,
    required this.timeControl,
    required this.date,
    required this.location,
    required this.websiteUrl,
    required this.standingsUrl,
    required this.tourUrl,
    this.groupBroadcastId,
  });

  factory AboutTourModel.fromTour(Tour tour) {
    return AboutTourModel(
      id: tour.id,
      slug: tour.slug,
      name: tour.name,
      imageUrl: tour.image ?? '',
      //todo: This field needs to be added in the Tour Model
      description: '',
      players: tour.players,
      timeControl: tour.info.tc ?? '',
      date: tour.dateRangeFormatted,
      location: tour.info.location ?? '',
      websiteUrl: tour.info.website ?? '',
      standingsUrl: tour.info.standings ?? '',
      tourUrl: tour.url,
      groupBroadcastId: tour.groupBroadcastId,
    );
  }
  factory AboutTourModel.empty() {
    return const AboutTourModel(
      id: '',
      slug: '',
      name: 'No Tournament',
      description: 'Currently no tournaments available',
      imageUrl: '',
      players: [],
      timeControl: '',
      date: '',
      location: '',
      websiteUrl: '',
      standingsUrl: '',
      tourUrl: '',
    );
  }

  String extractDomain() {
    try {
      // Trim the URL to remove leading/trailing whitespace
      final trimmedUrl = websiteUrl.trim();

      // Parse the URL
      Uri uri = Uri.parse(trimmedUrl);

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
    slug,
    name,
    description,
    imageUrl,
    players,
    timeControl,
    date,
    location,
    websiteUrl,
    standingsUrl,
    tourUrl,
    groupBroadcastId,
  ];
}
