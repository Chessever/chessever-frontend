import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:flutter/foundation.dart';

/// A famous player's public online accounts, offered on the Favorites tab.
@immutable
class PrepFavorite {
  const PrepFavorite({
    required this.id,
    required this.name,
    required this.title,
    required this.country,
    this.fideId,
    this.chesscom,
    this.lichess,
  });

  final String id;
  final String name;
  final String title;

  /// ISO 3166 alpha-2.
  final String country;
  final String? fideId;
  final String? chesscom;
  final String? lichess;

  List<(PrepSource, String)> get accounts => [
    if (chesscom != null) (PrepSource.chesscom, chesscom!),
    if (lichess != null) (PrepSource.lichess, lichess!),
  ];
}

/// Every account here was checked against the Lichess and Chess.com public
/// APIs on 2026-10-06: open, not flagged, and carrying the player's title or
/// real name. Lichess handles that were untitled or anonymous were left out
/// rather than guessed.
const List<PrepFavorite> kPrepFavorites = [
  PrepFavorite(id: 'carlsen', name: 'Magnus Carlsen', title: 'GM', country: 'NO', fideId: '1503014', chesscom: 'MagnusCarlsen', lichess: 'DrNykterstein'),
  PrepFavorite(id: 'nakamura', name: 'Hikaru Nakamura', title: 'GM', country: 'US', fideId: '2016192', chesscom: 'Hikaru'),
  PrepFavorite(id: 'caruana', name: 'Fabiano Caruana', title: 'GM', country: 'US', fideId: '2020009', chesscom: 'FabianoCaruana'),
  PrepFavorite(id: 'firouzja', name: 'Alireza Firouzja', title: 'GM', country: 'FR', fideId: '12573981', chesscom: 'Firouzja2003', lichess: 'alireza2003'),
  PrepFavorite(id: 'gukesh', name: 'Gukesh Dommaraju', title: 'GM', country: 'IN', fideId: '46616543', chesscom: 'GukeshDommaraju'),
  PrepFavorite(id: 'ding', name: 'Ding Liren', title: 'GM', country: 'CN', fideId: '8603677', chesscom: 'Chefshouse'),
  PrepFavorite(id: 'nepomniachtchi', name: 'Ian Nepomniachtchi', title: 'GM', country: 'RU', fideId: '4168119', chesscom: 'lachesisQ'),
  PrepFavorite(id: 'praggnanandhaa', name: 'Praggnanandhaa R', title: 'GM', country: 'IN', fideId: '25059530', chesscom: 'rpragchess'),
  PrepFavorite(id: 'erigaisi', name: 'Arjun Erigaisi', title: 'GM', country: 'IN', fideId: '35009192', chesscom: 'GHANDEEVAM2003'),
  PrepFavorite(id: 'so', name: 'Wesley So', title: 'GM', country: 'US', fideId: '5202213', chesscom: 'GMWSO'),
  PrepFavorite(id: 'giri', name: 'Anish Giri', title: 'GM', country: 'NL', fideId: '24116068', chesscom: 'AnishGiri', lichess: 'AnishGiri'),
  PrepFavorite(id: 'abdusattorov', name: 'Nodirbek Abdusattorov', title: 'GM', country: 'UZ', fideId: '14204118', chesscom: 'ChessWarrior7197'),
  PrepFavorite(id: 'aronian', name: 'Levon Aronian', title: 'GM', country: 'US', fideId: '13300474', chesscom: 'LevonAronian'),
  PrepFavorite(id: 'vachier-lagrave', name: 'Maxime Vachier-Lagrave', title: 'GM', country: 'FR', fideId: '623539', chesscom: 'LyonBeast'),
  PrepFavorite(id: 'anand', name: 'Viswanathan Anand', title: 'GM', country: 'IN', fideId: '5000017', chesscom: 'TheVish'),
  PrepFavorite(id: 'duda', name: 'Jan-Krzysztof Duda', title: 'GM', country: 'PL', fideId: '1170546', chesscom: 'Polish_fighter3000'),
  PrepFavorite(id: 'gujrathi', name: 'Vidit Gujrathi', title: 'GM', country: 'IN', fideId: '5029465', chesscom: 'viditchess'),
  PrepFavorite(id: 'mamedyarov', name: 'Shakhriyar Mamedyarov', title: 'GM', country: 'AZ', fideId: '13401319', chesscom: 'Azerichess'),
  PrepFavorite(id: 'wei-yi', name: 'Wei Yi', title: 'GM', country: 'CN', fideId: '8603820', chesscom: 'LOVEVAE'),
  PrepFavorite(id: 'keymer', name: 'Vincent Keymer', title: 'GM', country: 'DE', fideId: '12940690', chesscom: 'VincentKeymer'),
  PrepFavorite(id: 'grischuk', name: 'Alexander Grischuk', title: 'GM', country: 'RU', fideId: '4126025', chesscom: 'Grischuk'),
  PrepFavorite(id: 'niemann', name: 'Hans Niemann', title: 'GM', country: 'US', fideId: '2093596', chesscom: 'HansOnTwitch'),
  PrepFavorite(id: 'sarin', name: 'Nihal Sarin', title: 'GM', country: 'IN', fideId: '25089022', chesscom: 'nihalsarin'),
  PrepFavorite(id: 'artemiev', name: 'Vladislav Artemiev', title: 'GM', country: 'RU', fideId: '24101605', chesscom: 'Sibelephant', lichess: 'Konevlad'),
  PrepFavorite(id: 'andreikin', name: 'Dmitry Andreikin', title: 'GM', country: 'RU', fideId: '4158814', chesscom: 'FairChess_on_YouTube', lichess: 'Vladimirovich9000'),
  PrepFavorite(id: 'maghsoodloo', name: 'Parham Maghsoodloo', title: 'GM', country: 'IR', fideId: '12529832', chesscom: 'Parhamov'),
  PrepFavorite(id: 'bortnyk', name: 'Oleksandr Bortnyk', title: 'GM', country: 'US', fideId: '14117459', chesscom: 'Oleksandr_Bortnyk', lichess: 'Night-King96'),
  PrepFavorite(id: 'tang', name: 'Andrew Tang', title: 'GM', country: 'US', fideId: '2063408', chesscom: 'penguingm1', lichess: 'penguingm1'),
  PrepFavorite(id: 'navara', name: 'David Navara', title: 'GM', country: 'CZ', fideId: '309095', lichess: 'RealDavidNavara'),
  PrepFavorite(id: 'le-tuan-minh', name: 'Le Tuan Minh', title: 'GM', country: 'VN', fideId: '12401137', chesscom: 'wonderfultime'),
  PrepFavorite(id: 'bluebaum', name: 'Matthias Bluebaum', title: 'GM', country: 'DE', fideId: '12940836', chesscom: 'Msb2'),
  PrepFavorite(id: 'kollars', name: 'Dmitrij Kollars', title: 'GM', country: 'DE', fideId: '12938653', chesscom: 'GM_dmitrij'),
  PrepFavorite(id: 'hou-yifan', name: 'Hou Yifan', title: 'GM', country: 'CN', fideId: '8602980', chesscom: 'houyifan'),
  PrepFavorite(id: 'ju-wenjun', name: 'Ju Wenjun', title: 'GM', country: 'CN', fideId: '8603006', chesscom: 'juwenjun'),
  PrepFavorite(id: 'rozman', name: 'Levy Rozman', title: 'IM', country: 'US', fideId: '2089026', chesscom: 'GothamChess'),
  PrepFavorite(id: 'rosen', name: 'Eric Rosen', title: 'IM', country: 'US', fideId: '2046256', chesscom: 'IMRosen', lichess: 'EricRosen'),
  PrepFavorite(id: 'rudolf', name: 'Anna Rudolf', title: 'IM', country: 'HU', fideId: '720941', chesscom: 'Anna_Chess'),
  PrepFavorite(id: 'botez', name: 'Alexandra Botez', title: 'WFM', country: 'US', fideId: '2041513', chesscom: 'AlexandraBotez'),
];
