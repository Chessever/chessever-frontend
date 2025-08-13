import 'package:chessever2/screens/tournaments/model/tour_event_card_model.dart';

class SearchResult {
  final TourEventCardModel tournament;
  final double score;
  final String matchedText;
  final SearchResultType type;

  const SearchResult({
    required this.tournament,
    required this.score,
    required this.matchedText,
    required this.type,
  });
}

enum SearchResultType { tournament, player }