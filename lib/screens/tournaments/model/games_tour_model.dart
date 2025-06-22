import 'package:chessever2/repository/supabase/game/game.dart';

class GamesTourModel {
  final String id;
  final String name;
  final String description;
  final String imageUrl;
  final String gameType;
  final int maxPlayers;
  final DateTime startDate;
  final DateTime endDate;

  GamesTourModel({
    required this.id,
    required this.name,
    required this.description,
    required this.imageUrl,
    required this.gameType,
    required this.maxPlayers,
    required this.startDate,
    required this.endDate,
  });


  factory GamesTourModel.fromGames(Game game){
    return GamesTourModel(
      id: game.id,
      name: 'Chess Tournament',
      description: 'A thrilling chess tournament for all levels.',
      imageUrl: 'https://example.com/image.png',
      gameType: 'Standard',
      maxPlayers: 100,
      startDate: DateTime.now(),
      endDate: DateTime.now().add(Duration(days: 7)),
    );
  }
}
