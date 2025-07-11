import 'package:chessever2/screens/tournaments/model/games_tour_model.dart';

class ChessBoardFenModel {
  ChessBoardFenModel({
    required this.fen,
    required this.gmName,
    required this.gmSecondName,
    required this.firstGmCountryCode,
    required this.secondGmCountryCode,
    required this.firstGmTime,
    required this.secondGmTime,
    required this.firstGmRank,
    required this.secondGmRank,
    required this.pgn,
    required this.status,
  });

  final String gmName;
  final String gmSecondName;
  final String fen;
  final String firstGmCountryCode;
  final String secondGmCountryCode;
  final String firstGmTime;
  final String secondGmTime;
  final String firstGmRank;
  final String secondGmRank;
  final String pgn;
  final String status;

  factory ChessBoardFenModel.fromGamesTourModel(GamesTourModel gamesTourModel) {
    return ChessBoardFenModel(
      fen: gamesTourModel.fen ?? '',
      gmName: gamesTourModel.whitePlayer.name,
      gmSecondName: gamesTourModel.blackPlayer.name,
      firstGmCountryCode: gamesTourModel.whitePlayer.countryCode,
      secondGmCountryCode: gamesTourModel.blackPlayer.countryCode,
      firstGmTime: gamesTourModel.whiteTimeDisplay,
      secondGmTime: gamesTourModel.blackTimeDisplay,
      firstGmRank: gamesTourModel.whitePlayer.displayTitle,
      secondGmRank: gamesTourModel.blackPlayer.displayTitle,
      pgn: gamesTourModel.pgn ?? "",
      status: gamesTourModel.gameStatus.displayText,
    );
  }
}
