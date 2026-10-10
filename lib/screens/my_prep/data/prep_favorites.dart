import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:flutter/foundation.dart';

/// The public online accounts known for a FIDE player. The Favorites tab
/// lists players from the ChessEver ranking, so ChessEver is always a
/// source; these add the player's Lichess and Chess.com games to it.
@immutable
class PrepFavorite {
  const PrepFavorite({
    required this.fideId,
    required this.name,
    this.legacyId,
    this.chesscom,
    this.lichess,
  });

  final String fideId;
  final String name;

  /// The id favorites were saved under before they were keyed by FIDE id.
  final String? legacyId;
  final String? chesscom;
  final String? lichess;

  /// What a profile opened from this player stores as its `favoriteId`.
  String get id => legacyId ?? fideId;

  List<(PrepSource, String)> get accounts => [
    if (chesscom != null) (PrepSource.chesscom, chesscom!),
    if (lichess != null) (PrepSource.lichess, lichess!),
  ];

  /// Whether [query] names one of the handles, which the ranking's own name
  /// search cannot see.
  bool matches(String query) {
    final clean = query.trim().toLowerCase();
    return clean.length >= 2 &&
        ((chesscom?.toLowerCase().contains(clean) ?? false) ||
            (lichess?.toLowerCase().contains(clean) ?? false));
  }
}

final Map<String, PrepFavorite> kPrepFavoritesByFide = {
  for (final favorite in kPrepFavorites) favorite.fideId: favorite,
};

/// The FIDE id [profile] stands for: its own, or the one its saved favorite
/// names.
String? prepFavoriteFide(PrepProfile profile) {
  if (profile.fideId case final fide?) return fide;
  final id = profile.favoriteId;
  if (id == null) return null;
  for (final favorite in kPrepFavorites) {
    if (favorite.id == id) return favorite.fideId;
  }
  return null;
}

/// FIDE's active players rated 2560 and above on the October 2026 list, and
/// the streamers Favorites has always carried. A Chess.com account is listed
/// when it is open, carries the GM title Chess.com verifies, and gives the
/// player's own name; a Lichess account when it is open, titled and names
/// the player. Anonymous or untitled handles were left out rather than
/// guessed. Checked against both public APIs on 2026-10-09.
const List<PrepFavorite> kPrepFavorites = [
  PrepFavorite(
    fideId: '1503014',
    name: 'Magnus Carlsen',
    legacyId: 'carlsen',
    chesscom: 'MagnusCarlsen',
    lichess: 'DrNykterstein',
  ),
  PrepFavorite(
    fideId: '2016192',
    name: 'Hikaru Nakamura',
    legacyId: 'nakamura',
    chesscom: 'Hikaru',
  ),
  PrepFavorite(
    fideId: '2020009',
    name: 'Fabiano Caruana',
    legacyId: 'caruana',
    chesscom: 'FabianoCaruana',
  ),
  PrepFavorite(
    fideId: '14205483',
    name: 'Javokhir Sindarov',
    chesscom: 'Javokhir_Sindarov05',
  ),
  PrepFavorite(
    fideId: '14204118',
    name: 'Nodirbek Abdusattorov',
    legacyId: 'abdusattorov',
    chesscom: 'ChessWarrior7197',
  ),
  PrepFavorite(
    fideId: '5202213',
    name: 'Wesley So',
    legacyId: 'so',
    chesscom: 'GMWSO',
  ),
  PrepFavorite(
    fideId: '25059530',
    name: 'Praggnanandhaa R',
    legacyId: 'praggnanandhaa',
    chesscom: 'rpragchess',
  ),
  PrepFavorite(
    fideId: '12940690',
    name: 'Vincent Keymer',
    legacyId: 'keymer',
    chesscom: 'VincentKeymer',
    lichess: 'VincentKeymer2004',
  ),
  PrepFavorite(
    fideId: '8603405',
    name: 'Wei Yi',
    legacyId: 'wei-yi',
    chesscom: 'LOVEVAE',
  ),
  PrepFavorite(
    fideId: '12573981',
    name: 'Alireza Firouzja',
    legacyId: 'firouzja',
    chesscom: 'Firouzja2003',
    lichess: 'alireza2003',
  ),
  PrepFavorite(
    fideId: '24116068',
    name: 'Anish Giri',
    legacyId: 'giri',
    chesscom: 'AnishGiri',
    lichess: 'AnishGiri',
  ),
  PrepFavorite(
    fideId: '35009192',
    name: 'Arjun Erigaisi',
    legacyId: 'erigaisi',
    chesscom: 'GHANDEEVAM2003',
  ),
  PrepFavorite(
    fideId: '1170546',
    name: 'Jan-Krzysztof Duda',
    legacyId: 'duda',
    chesscom: 'Polish_fighter3000',
  ),
  PrepFavorite(
    fideId: '5000017',
    name: 'Viswanathan Anand',
    legacyId: 'anand',
    chesscom: 'TheVish',
  ),
  PrepFavorite(
    fideId: '3503240',
    name: 'Leinier Dominguez Perez',
    chesscom: 'DominguezOnYoutube',
  ),
  PrepFavorite(fideId: '12401137', name: 'Quang Liem Le', chesscom: 'LiemLe'),
  PrepFavorite(
    fideId: '44599790',
    name: 'Yagiz Kaan Erdogmus',
    chesscom: 'legendisback1',
  ),
  PrepFavorite(
    fideId: '12521213',
    name: 'M. Amin Tabatabaei',
    chesscom: 'amintabatabaei',
  ),
  PrepFavorite(
    fideId: '13300474',
    name: 'Levon Aronian',
    legacyId: 'aronian',
    chesscom: 'LevonAronian',
  ),
  PrepFavorite(
    fideId: '8603677',
    name: 'Ding Liren',
    legacyId: 'ding',
    chesscom: 'Chefshouse',
  ),
  PrepFavorite(
    fideId: '4168119',
    name: 'Ian Nepomniachtchi',
    legacyId: 'nepomniachtchi',
    chesscom: 'lachesisQ',
  ),
  PrepFavorite(
    fideId: '2093596',
    name: 'Hans Niemann',
    legacyId: 'niemann',
    chesscom: 'HansOnTwitch',
  ),
  PrepFavorite(
    fideId: '623539',
    name: 'Maxime Vachier-Lagrave',
    legacyId: 'vachier-lagrave',
    chesscom: 'LyonBeast',
  ),
  PrepFavorite(
    fideId: '1039784',
    name: 'Jorden Van Foreest',
    chesscom: 'joppie2',
  ),
  PrepFavorite(
    fideId: '4158814',
    name: 'Dmitry Andreikin',
    legacyId: 'andreikin',
    chesscom: 'FairChess_on_YouTube',
    lichess: 'Vladimirovich9000',
  ),
  PrepFavorite(
    fideId: '14203987',
    name: 'Nodirbek Yakubboev',
    chesscom: 'hanzo_hasashi1',
    lichess: 'yackobaby',
  ),
  PrepFavorite(
    fideId: '738590',
    name: 'Richard Rapport',
    chesscom: 'Lordillidan',
  ),
  PrepFavorite(
    fideId: '46616543',
    name: 'Gukesh Dommaraju',
    legacyId: 'gukesh',
    chesscom: 'GukeshDommaraju',
  ),
  PrepFavorite(
    fideId: '13401319',
    name: 'Shakhriyar Mamedyarov',
    legacyId: 'mamedyarov',
    chesscom: 'Azerichess',
  ),
  PrepFavorite(
    fideId: '25092340',
    name: 'Nihal Sarin',
    legacyId: 'sarin',
    chesscom: 'nihalsarin',
    lichess: 'nihalsarin2004',
  ),
  PrepFavorite(
    fideId: '12539929',
    name: 'Parham Maghsoodloo',
    legacyId: 'maghsoodloo',
    chesscom: 'Parhamov',
  ),
  PrepFavorite(fideId: '8603820', name: 'Yangyi Yu', chesscom: 'chesspanda123'),
  PrepFavorite(
    fideId: '2900084',
    name: 'Veselin Topalov',
    chesscom: 'VESELINTOPALOV359',
  ),
  PrepFavorite(
    fideId: '8602883',
    name: 'Hao Wang',
    chesscom: 'Aoitsukibluemoon',
  ),
  PrepFavorite(
    fideId: '5029465',
    name: 'Vidit Gujrathi',
    legacyId: 'gujrathi',
    chesscom: 'viditchess',
  ),
  PrepFavorite(
    fideId: '24130737',
    name: 'Vladimir Fedoseev',
    chesscom: 'Fedoseev-Vladimir',
    lichess: 'Feokl1995',
  ),
  PrepFavorite(
    fideId: '13400924',
    name: 'Teimour Radjabov',
    chesscom: 'TRadjabov',
  ),
  PrepFavorite(
    fideId: '2056437',
    name: 'Awonder Liang',
    chesscom: 'rednova1729',
  ),
  PrepFavorite(
    fideId: '24175439',
    name: 'Andrey Esipenko',
    chesscom: 'Andreikka',
  ),
  PrepFavorite(
    fideId: '13413937',
    name: 'Aydin Suleymanli',
    chesscom: 'LastGladiator1',
    lichess: 'LastGladiator2',
  ),
  PrepFavorite(
    fideId: '5072786',
    name: 'Chithambaram VR. Aravindh',
    chesscom: 'Vaathi_Coming',
  ),
  PrepFavorite(fideId: '25060783', name: 'V Pranav', chesscom: 'vi_pranav'),
  PrepFavorite(fideId: '35028600', name: 'Pranesh M', chesscom: 'artooon'),
  PrepFavorite(
    fideId: '24651516',
    name: 'Matthias Bluebaum',
    legacyId: 'bluebaum',
    chesscom: 'Msb2',
  ),
  PrepFavorite(
    fideId: '410608',
    name: 'David W L Howell',
    chesscom: 'howitzer14',
  ),
  PrepFavorite(
    fideId: '14200244',
    name: 'Rustam Kasimdzhanov',
    chesscom: 'solingen2020',
  ),
  PrepFavorite(fideId: '14102951', name: 'Pavel Eljanov', chesscom: 'eljanov'),
  PrepFavorite(fideId: '703303', name: 'Peter Leko', chesscom: 'PeterLeko'),
  PrepFavorite(
    fideId: '4152956',
    name: 'Nikita Vitiugov',
    chesscom: 'Colchonero64',
  ),
  PrepFavorite(
    fideId: '13409301',
    name: 'Mahammad Muradli',
    chesscom: 'ChessLover0108',
    lichess: 'MahammadMuradli2003',
  ),
  PrepFavorite(
    fideId: '12923044',
    name: 'Frederik Svane',
    chesscom: 'frederiksvane',
    lichess: 'Chessfis',
  ),
  PrepFavorite(
    fideId: '13306553',
    name: 'Haik M. Martirosyan',
    chesscom: 'Micki-taryan',
    lichess: 'ARM-777777',
  ),
  PrepFavorite(
    fideId: '2023970',
    name: 'Ray Robson',
    chesscom: 'spicycaterpillar',
  ),
  PrepFavorite(
    fideId: '1118358',
    name: 'Radoslaw Wojtaszek',
    chesscom: 'Radzio1987',
  ),
  PrepFavorite(
    fideId: '44155573',
    name: 'Volodar Murzin',
    chesscom: 'Volodar_Murzin',
    lichess: 'V_M',
  ),
  PrepFavorite(fideId: '2047640', name: 'Jeffery Xiong', chesscom: 'jefferyx'),
  PrepFavorite(
    fideId: '1226380',
    name: 'Bogdan-Daniel Deac',
    chesscom: 'BogdanDeac',
  ),
  PrepFavorite(fideId: '24126055', name: 'Daniil Dubov', chesscom: 'Duhless'),
  PrepFavorite(
    fideId: '3805662',
    name: 'Jose Eduardo Martinez Alcantara',
    chesscom: 'Jospem',
  ),
  PrepFavorite(
    fideId: '4116992',
    name: 'Alexander Morozevich',
    chesscom: 'EgorGeroev',
  ),
  PrepFavorite(
    fideId: '24101605',
    name: 'Vladislav Artemiev',
    legacyId: 'artemiev',
    chesscom: 'Sibelephant',
    lichess: 'Konevlad',
  ),
  PrepFavorite(
    fideId: '8601445',
    name: 'Xiangzhi Bu',
    chesscom: 'chesswolf1210',
  ),
  PrepFavorite(
    fideId: '14117908',
    name: 'Igor Kovalenko',
    chesscom: 'igorkovalenko',
  ),
  PrepFavorite(
    fideId: '2285525',
    name: 'David Anton Guijarro',
    chesscom: 'tptagain',
  ),
  PrepFavorite(
    fideId: '14204223',
    name: 'Shamsiddin Vokhidov',
    chesscom: 'Shield12',
  ),
  PrepFavorite(
    fideId: '5007003',
    name: 'Pentala Harikrishna',
    chesscom: 'GMharikrishna',
  ),
  PrepFavorite(
    fideId: '13306766',
    name: 'Shant Sargsyan',
    chesscom: 'Sargsyan_Shant',
  ),
  PrepFavorite(
    fideId: '5074452',
    name: 'Murali Karthikeyan',
    chesscom: 'youngKID',
  ),
  PrepFavorite(fideId: '1510045', name: 'Aryan Tari', chesscom: 'AryanTari'),
  PrepFavorite(fideId: '5084423', name: 'Aryan Chopra', chesscom: 'Deadeye10'),
  PrepFavorite(fideId: '2004887', name: 'Sam Shankland', chesscom: 'Shankland'),
  PrepFavorite(
    fideId: '35093487',
    name: 'Raunak Sadhwani',
    chesscom: 'RaunakSadhwani2005',
  ),
  PrepFavorite(fideId: '44507356', name: 'Ediz Gurel', chesscom: 'gurelediz'),
  PrepFavorite(
    fideId: '13302507',
    name: 'Robert Hovhannisyan',
    chesscom: 'Robert_Chessmood',
  ),
  PrepFavorite(
    fideId: '2805677',
    name: 'Boris Gelfand',
    chesscom: 'Remontada2017',
  ),
  PrepFavorite(
    fideId: '4135539',
    name: 'Kirill Alekseenko',
    chesscom: 'BilodeauA',
  ),
  PrepFavorite(
    fideId: '14101025',
    name: 'Alexander Onischuk',
    chesscom: 'AlexOnischuk',
  ),
  PrepFavorite(
    fideId: '4262875',
    name: 'Nikolas Theodorou',
    chesscom: 'NikoTheodorou',
  ),
  PrepFavorite(fideId: '13306677', name: 'Aram Hakobyan', chesscom: 'Njal28'),
  PrepFavorite(
    fideId: '24125890',
    name: 'Grigoriy Oparin',
    chesscom: 'OparinGrigoriy',
  ),
  PrepFavorite(
    fideId: '4162722',
    name: 'Ernesto Inarkiev',
    chesscom: 'Vorenus_Lucius',
  ),
  PrepFavorite(fideId: '8603332', name: 'Shanglei Lu', chesscom: 'wudileige'),
  PrepFavorite(fideId: '13515110', name: 'Denis Lazavik', chesscom: 'DenLaz'),
  PrepFavorite(
    fideId: '30920019',
    name: 'Abhimanyu Mishra',
    chesscom: 'PursuitOfHappyness2',
  ),
  PrepFavorite(
    fideId: '4107012',
    name: 'Mikhail Al. Antipov',
    chesscom: 'Antipov_Mikhail_Al',
  ),
  PrepFavorite(
    fideId: '1512668',
    name: 'Johan-Sebastian Christiansen',
    chesscom: 'JSPrepz',
  ),
  PrepFavorite(
    fideId: '13401653',
    name: 'Rauf Mamedov',
    chesscom: 'Baku_Boulevard',
    lichess: 'muisback',
  ),
  PrepFavorite(
    fideId: '14103320',
    name: 'Ruslan Ponomariov',
    chesscom: 'MashaPutina1985',
  ),
  PrepFavorite(
    fideId: '2905540',
    name: 'Ivan Cheparinov',
    chesscom: 'GMCheparinov',
  ),
  PrepFavorite(
    fideId: '409561',
    name: 'Gawain C B Maroroa Jones',
    chesscom: 'VerdeNotte',
  ),
  PrepFavorite(
    fideId: '35028561',
    name: 'Leon Luke Mendonca',
    chesscom: 'LionTheLeon_06',
    lichess: 'LeonMendonca_YT',
  ),
  PrepFavorite(
    fideId: '4126025',
    name: 'Alexander Grischuk',
    legacyId: 'grischuk',
    chesscom: 'Grischuk',
  ),
  PrepFavorite(
    fideId: '14100010',
    name: 'Vasyl Ivanchuk',
    chesscom: 'viviania',
  ),
  PrepFavorite(fideId: '8608288', name: 'Xiangyu Xu', chesscom: 'xxysoul6'),
  PrepFavorite(
    fideId: '1444948',
    name: 'Jonas Buhl Bjerre',
    chesscom: 'lilleper1',
  ),
  PrepFavorite(
    fideId: '30901561',
    name: 'Brandon Jacobson',
    chesscom: 'BrandonJacobson',
    lichess: 'iamstraw',
  ),
  PrepFavorite(fideId: '1000268', name: 'Loek Van Wely', chesscom: 'KingLoek'),
  PrepFavorite(
    fideId: '2293307',
    name: 'Jaime Santos Latasa',
    chesscom: 'h4parah5',
  ),
  PrepFavorite(
    fideId: '12909572',
    name: 'Dmitrij Kollars',
    legacyId: 'kollars',
    chesscom: 'GM_dmitrij',
    lichess: 'dmitrij_IM',
  ),
  PrepFavorite(
    fideId: '358878',
    name: 'Thai Dai Van Nguyen',
    chesscom: 'NTDVAN12',
    lichess: 'NTDVAN',
  ),
  PrepFavorite(
    fideId: '5061245',
    name: 'Abhimanyu Puranik',
    chesscom: 'abhidabhi',
  ),
  PrepFavorite(
    fideId: '35042025',
    name: 'Aditya Mittal',
    chesscom: 'vinniethepooh',
    lichess: 'Thunderbolt1909',
  ),
  PrepFavorite(
    fideId: '4108116',
    name: 'Maksim Chigaev',
    chesscom: 'Fandorine',
    lichess: 'Fandorine96',
  ),
  PrepFavorite(
    fideId: '14508150',
    name: 'Ivan Saric',
    chesscom: 'dalmatinac101',
  ),
  PrepFavorite(
    fideId: '4657101',
    name: 'Rasmus Svane',
    chesscom: 'rasmussvane',
    lichess: 'sumsar42',
  ),
  PrepFavorite(fideId: '14105730', name: 'Anton Korobov', chesscom: 'GOGIEFF'),
  PrepFavorite(fideId: '4675789', name: 'Georg Meier', chesscom: 'GeorgMeier'),
  PrepFavorite(fideId: '642908', name: 'Jules Moussard', chesscom: 'Annawel'),
  PrepFavorite(fideId: '8601429', name: 'Yue Wang', chesscom: 'chesswy'),
  PrepFavorite(
    fideId: '30953499',
    name: 'Andy Woodward',
    chesscom: 'Philippians46',
  ),
  PrepFavorite(
    fideId: '14107090',
    name: 'Andrei Volokitin',
    chesscom: 'GMvolokitin',
  ),
  PrepFavorite(
    fideId: '14114038',
    name: 'Volodymyr Onyshchuk',
    chesscom: 'onyshchuk_v',
  ),
  PrepFavorite(
    fideId: '9301348',
    name: 'A.R. Saleh Salem',
    chesscom: 'Salem-AR',
  ),
  PrepFavorite(
    fideId: '12510130',
    name: 'Pouya Idani',
    chesscom: 'pouya21',
    lichess: 'Poudini',
  ),
  PrepFavorite(fideId: '8604436', name: 'Chao b Li', chesscom: 'chessawp'),
  PrepFavorite(
    fideId: '34189030',
    name: 'Aleksey Grebnev',
    chesscom: 'Grebnev_A',
  ),
  PrepFavorite(
    fideId: '14109182',
    name: 'Yuriy Kryvoruchko',
    chesscom: 'Y_Kryvoruchko',
  ),
  PrepFavorite(
    fideId: '1400355',
    name: 'Peter Heine Nielsen',
    chesscom: 'PeterHeineNielsen',
  ),
  PrepFavorite(
    fideId: '13300881',
    name: 'Gabriel Sargissian',
    chesscom: 'Arm-Akiba',
  ),
  PrepFavorite(
    fideId: '712779',
    name: 'Benjamin Gledura',
    chesscom: 'promen1999',
    lichess: 'stumpspice',
  ),
  PrepFavorite(fideId: '605506', name: 'Etienne Bacrot', chesscom: 'baki83'),
  PrepFavorite(fideId: '718572', name: 'Ferenc Berkes', chesscom: 'BerkesFeri'),
  PrepFavorite(
    fideId: '240990',
    name: 'Daniel Dardha',
    chesscom: 'DanielDardha2005',
  ),
  PrepFavorite(
    fideId: '14210703',
    name: 'Mukhiddin Madaminov',
    chesscom: 'Macho_2006',
    lichess: 'Player_06',
  ),
  PrepFavorite(
    fideId: '24107581',
    name: 'Alexandr Predke',
    chesscom: 'Alexandr_Predke',
  ),
  PrepFavorite(
    fideId: '13402935',
    name: 'Vasif Durarbayli',
    chesscom: 'Durarbayli',
  ),
  PrepFavorite(
    fideId: '24603295',
    name: 'Alexander Donchenko',
    chesscom: 'Alexander_Donchenko',
    lichess: 'Alexander_Donchenko',
  ),
  PrepFavorite(
    fideId: '608742',
    name: 'Laurent Fressinet',
    chesscom: 'Zlatan56',
  ),
  PrepFavorite(
    fideId: '13402129',
    name: 'Eltaj Safarli',
    chesscom: 'Eltaj_Safarli',
  ),
  PrepFavorite(
    fideId: '1188062',
    name: 'Szymon Gumularz',
    chesscom: 'SGchess01',
    lichess: 'SGchess01',
  ),
  PrepFavorite(
    fideId: '2099438',
    name: 'Andrew Hong',
    chesscom: 'SpeedofLight0',
  ),
  PrepFavorite(fideId: '10601457', name: 'Bassem Amin', chesscom: 'Dr-Bassem'),
  PrepFavorite(fideId: '404853', name: 'Luke J McShane', chesscom: 'LMcShane'),
  PrepFavorite(
    fideId: '309095',
    name: 'David Navara',
    legacyId: 'navara',
    chesscom: 'FormerProdigy',
    lichess: 'RealDavidNavara',
  ),
  PrepFavorite(
    fideId: '14187086',
    name: 'Ihor Samunenkov',
    chesscom: 'sokidze',
    lichess: 'Ujevxejv',
  ),
  PrepFavorite(
    fideId: '14506688',
    name: 'Ante Brkic',
    chesscom: 'Slavonac1988',
  ),
  PrepFavorite(
    fideId: '3800024',
    name: 'Julio E Granda Zuniga',
    chesscom: 'GMJulioGranda',
  ),
  PrepFavorite(fideId: '911925', name: 'Aleksandar Indjic', chesscom: 'Beca95'),
  PrepFavorite(fideId: '46626786', name: 'Pranav Anand', chesscom: 'adotand'),
  PrepFavorite(
    fideId: '3518736',
    name: 'Carlos Daniel Albornoz Cabrera',
    chesscom: 'CarlosAlbornoz',
  ),
  PrepFavorite(
    fideId: '14120828',
    name: 'Oleksandr Bortnyk',
    legacyId: 'bortnyk',
    chesscom: 'Oleksandr_Bortnyk',
    lichess: 'Night-King96',
  ),
  PrepFavorite(
    fideId: '46634827',
    name: 'Bharath Subramaniyam H',
    chesscom: 'FGHSMN',
  ),
  PrepFavorite(
    fideId: '1710400',
    name: 'Nils Grandelius',
    chesscom: 'Grandelicious',
    lichess: 'Grandelicious',
  ),
  PrepFavorite(fideId: '5804418', name: 'Jingyao Tin', chesscom: 'tjychess'),
  PrepFavorite(fideId: '8602280', name: 'Jinshi Bai', chesscom: 'kaka666'),
  PrepFavorite(
    fideId: '22291482',
    name: 'Miguel Santos Ruiz',
    chesscom: 'Miguelito',
  ),
  PrepFavorite(
    fideId: '14109530',
    name: 'Alexander Areshchenko',
    chesscom: 'CopperBrain',
  ),
  PrepFavorite(
    fideId: '4111990',
    name: 'Semen Khanin',
    chesscom: 'Semyon_Khanin',
  ),
  PrepFavorite(fideId: '8622388', name: 'Tong Xiao', chesscom: 'xiaotong2008'),
  PrepFavorite(
    fideId: '400041',
    name: 'Michael Adams',
    chesscom: 'GMMickeyAdams',
  ),
  PrepFavorite(
    fideId: '662399',
    name: 'Maxime Lagarde',
    chesscom: 'Rikikits',
    lichess: 'Rikikits',
  ),
  PrepFavorite(
    fideId: '4120787',
    name: 'Vladimir Malakhov',
    chesscom: 'Vladimir_2020',
  ),
  PrepFavorite(
    fideId: '4173708',
    name: 'Aleksandr Rakhmanov',
    chesscom: 'Rakhmanov_Aleksandr',
    lichess: 'Rakhmanov_Aleksandr',
  ),
  PrepFavorite(
    fideId: '8602980',
    name: 'Hou Yifan',
    legacyId: 'hou-yifan',
    chesscom: 'houyifan',
  ),
  PrepFavorite(fideId: '8603154', name: 'Qun Ma', chesscom: 'defenceboy'),
  PrepFavorite(fideId: '21864080', name: 'Jan Malek', chesscom: 'forevery0ung'),
  PrepFavorite(
    fideId: '4168003',
    name: 'Maxim Matlakov',
    chesscom: 'BillieKimbah',
    lichess: 'Matlakov',
  ),
  PrepFavorite(fideId: '4170350', name: 'Ivan Popov', chesscom: 'POPOV_IVAN'),
  PrepFavorite(fideId: '310204', name: 'Sergei Movsesian', chesscom: 'Tesla37'),
  PrepFavorite(fideId: '400025', name: 'Nigel D Short', chesscom: 'NigelShort'),
  PrepFavorite(fideId: '4627253', name: 'Fabian Doettling', chesscom: 'Fabsid'),
  PrepFavorite(
    fideId: '12961523',
    name: 'Luis Engel',
    chesscom: 'hoffentlichreichts',
  ),
  PrepFavorite(
    fideId: '2000024',
    name: 'Gata Kamsky',
    chesscom: 'TigrVShlyape',
  ),
  PrepFavorite(
    fideId: '2209390',
    name: 'Alexei Shirov',
    chesscom: 'AlexeiShirov',
  ),
  PrepFavorite(fideId: '2802007', name: 'Emil Sutovsky', chesscom: 'VZMZ'),
  PrepFavorite(
    fideId: '2257327',
    name: 'Ivan Salgado Lopez',
    chesscom: 'SalgadoChess91',
  ),
  PrepFavorite(
    fideId: '13900048',
    name: 'Victor Bologan',
    chesscom: 'NewBornNow',
    lichess: 'VictorAntonBologan',
  ),
  PrepFavorite(
    fideId: '24198455',
    name: 'Arseniy Nesterov',
    chesscom: 'Arseniy_Nesterov',
    lichess: 'Arseniii_Nesterov',
  ),
  PrepFavorite(
    fideId: '4125029',
    name: 'Alexander Riazantsev',
    chesscom: 'Riazantsev',
  ),
  PrepFavorite(
    fideId: '916811',
    name: 'Dragan Solak',
    chesscom: 'DraganSolak',
    lichess: 'DraganSolak',
  ),
  PrepFavorite(
    fideId: '30909694',
    name: 'Christopher Woojin Yoo',
    chesscom: 'ChristopherYoo',
  ),
  PrepFavorite(
    fideId: '3700488',
    name: 'Axel Bachmann',
    chesscom: 'chito89',
    lichess: 'ABachmann',
  ),
  PrepFavorite(fideId: '4663527', name: 'Arik Braun', chesscom: 'Baby_Legs'),
  PrepFavorite(fideId: '23718293', name: 'Vaclav Finek', chesscom: 'vasblesk'),
  PrepFavorite(
    fideId: '2200015',
    name: 'Miguel Illescas Cordoba',
    chesscom: 'DEARMIKE',
  ),
  PrepFavorite(
    fideId: '4194985',
    name: 'David Paravyan',
    chesscom: 'dropstoneDP',
    lichess: 'drop_stone',
  ),
  PrepFavorite(
    fideId: '12401153',
    name: 'Le Tuan Minh',
    legacyId: 'le-tuan-minh',
    chesscom: 'wonderfultime',
  ),
  PrepFavorite(fideId: '2101246', name: 'Rafael Leitao', chesscom: 'GMRafpig'),
  PrepFavorite(
    fideId: '24131423',
    name: 'Daniil Yuffa',
    chesscom: 'danyuffa',
    lichess: 'CrazySage',
  ),
  PrepFavorite(
    fideId: '34184934',
    name: 'Gleb Dudin',
    chesscom: 'WoodlandMagic',
    lichess: 'AylorSnow',
  ),
  PrepFavorite(fideId: '2106388', name: 'Luis Paulo Supi', chesscom: 'LPSupi'),
  PrepFavorite(
    fideId: '10601619',
    name: 'Ahmed Adly',
    chesscom: 'A-Adly',
    lichess: 'GMadly',
  ),
  PrepFavorite(
    fideId: '1202758',
    name: 'Liviu-Dieter Nisipeanu',
    chesscom: 'LiviuDieterNisipeanu',
  ),
  PrepFavorite(
    fideId: '2806851',
    name: 'Maxim Rodshtein',
    chesscom: 'ColErranMorad',
  ),
  PrepFavorite(fideId: '950122', name: 'Velimir Ivic', chesscom: 'DrVelja'),
  PrepFavorite(
    fideId: '13707647',
    name: 'Denis Makhnev',
    chesscom: 'Denis_Makhnyov',
  ),
  PrepFavorite(
    fideId: '13402960',
    name: 'Nijat Abasov',
    chesscom: 'AbasovN',
    lichess: 'AbasovN',
  ),
  PrepFavorite(
    fideId: '4625498',
    name: 'Jan Gustafsson',
    chesscom: 'JanistanTV',
    lichess: 'JanistanTV',
  ),
  PrepFavorite(
    fideId: '3901211',
    name: 'Eduardo Iturrizaga Bonelli',
    chesscom: 'iturrizaga',
  ),
  PrepFavorite(
    fideId: '4650891',
    name: 'Arkadij Naiditsch',
    chesscom: 'CaptainJames',
  ),
  PrepFavorite(fideId: '4118987', name: 'Evgeniy Najer', chesscom: 'ENajer77'),
  PrepFavorite(
    fideId: '24650684',
    name: 'Dennis Wagner',
    chesscom: 'chessdjw',
    lichess: 'chessdjw',
  ),
  PrepFavorite(
    fideId: '4160258',
    name: 'Anton Demchenko',
    chesscom: 'Anton_Demchenko',
  ),
  PrepFavorite(
    fideId: '1007998',
    name: 'Erwin L\'Ami',
    chesscom: 'erwinlami',
    lichess: 'erwinlami',
  ),
  PrepFavorite(
    fideId: '1126881',
    name: 'Dariusz Swiercz',
    chesscom: 'daro94',
    lichess: 'daro94',
  ),
  PrepFavorite(
    fideId: '4198603',
    name: 'Aleksandr Shimanov',
    chesscom: 'shimastream',
    lichess: 'Multibrendovyi',
  ),
  PrepFavorite(
    fideId: '42520835',
    name: 'Sina Movahed',
    chesscom: 'Sina-Movahed',
    lichess: 'sina_iran',
  ),
  PrepFavorite(
    fideId: '13300857',
    name: 'Manuel Petrosyan',
    chesscom: 'Manuel_Petrosyan',
  ),
  PrepFavorite(fideId: '728446', name: 'Imre Balog', chesscom: 'Imre91'),
  PrepFavorite(
    fideId: '24604747',
    name: 'Niclas Huschenbeth',
    chesscom: 'GM_Huschenbeth',
    lichess: 'Niclas',
  ),
  PrepFavorite(
    fideId: '1001302',
    name: 'Dimitri Reinderman',
    chesscom: 'KingOfConvenience',
  ),
  PrepFavorite(fideId: '8602956', name: 'Yang Wen', chesscom: 'BabeGroot'),
  PrepFavorite(
    fideId: '4212312',
    name: 'Antonios Pavlidis',
    chesscom: 'Faqade',
  ),
  PrepFavorite(
    fideId: '4300033',
    name: 'Bobby Cheng',
    chesscom: 'slackadaisacal',
  ),
  PrepFavorite(fideId: '1503707', name: 'Jon Ludvig Hammer', chesscom: 'gmjlh'),
  PrepFavorite(
    fideId: '1610856',
    name: 'Markus Ragger',
    chesscom: 'MarkusRagger',
    lichess: 'Markus_Ragger',
  ),
  PrepFavorite(
    fideId: '3507416',
    name: 'Yusnel Bacallao Alonso',
    chesscom: 'Bacallao2019',
  ),
  PrepFavorite(fideId: '3802272', name: 'Jorge Cori', chesscom: 'machupichu10'),
  PrepFavorite(
    fideId: '14112906',
    name: 'Yuriy Kuzubov',
    chesscom: 'KuzubovYuriy',
  ),
  PrepFavorite(
    fideId: '4101286',
    name: 'Nikita Petrov',
    chesscom: 'zvonokchess1996',
  ),
  PrepFavorite(
    fideId: '13402390',
    name: 'Vugar Rasulov',
    chesscom: 'vugarrasulov',
  ),
  PrepFavorite(
    fideId: '722413',
    name: 'Tamas Banusz',
    chesscom: 'bancsoo',
    lichess: 'bancsoo',
  ),
  PrepFavorite(
    fideId: '12576468',
    name: 'Bardiya Daneshvar',
    chesscom: 'Bardiya06',
  ),
  PrepFavorite(fideId: '503142', name: 'Tomi Nyback', chesscom: 'sumopork'),
  PrepFavorite(
    fideId: '3409350',
    name: 'Cristobal Henriquez Villagra',
    chesscom: 'Kurufzugun',
  ),
  PrepFavorite(
    fideId: '1207822',
    name: 'Constantin Lupulescu',
    chesscom: 'LupulescuC',
  ),
  PrepFavorite(
    fideId: '1438832',
    name: 'Jesper Sondergaard Thybo',
    chesscom: 'JTCoach',
  ),
  PrepFavorite(
    fideId: '5045185',
    name: 'Suri Vaibhav',
    chesscom: 'obliviate12',
  ),
  PrepFavorite(fideId: '884189', name: 'Lorenzo Lodici', chesscom: 'Didici'),
  PrepFavorite(
    fideId: '1533533',
    name: 'Elham Amar',
    chesscom: 'Twitch_ElhamBlitz05',
  ),
  PrepFavorite(fideId: '11600454', name: 'Daniel Fridman', chesscom: 'Tormoz'),
  PrepFavorite(
    fideId: '13504398',
    name: 'Vladislav Kovalev',
    chesscom: 'vladislavkovalev',
    lichess: 'Esssquire',
  ),
  PrepFavorite(
    fideId: '110973',
    name: 'Alan Pichot',
    chesscom: 'platy3',
    lichess: 'Platy2',
  ),
  PrepFavorite(fideId: '13702661', name: 'Rinat Jumabayev', chesscom: 'Jumbo'),
  PrepFavorite(
    fideId: '1046730',
    name: 'Casper Schoppen',
    chesscom: 'Casper_Schoppen',
  ),
  PrepFavorite(fideId: '1007246', name: 'Jan Smeets', chesscom: 'JanSmeets'),
  PrepFavorite(
    fideId: '24249971',
    name: 'Ivan Zemlyanskii',
    chesscom: 'Prizant_academy',
  ),
  PrepFavorite(
    fideId: '14206323',
    name: 'Abdimalik Abdisalimov',
    chesscom: 'Abdimalik_Abdisalimov',
  ),
  PrepFavorite(
    fideId: '4667719',
    name: 'David Baramidze',
    chesscom: 'DavidBaramidze',
  ),
  PrepFavorite(
    fideId: '5002150',
    name: 'Surya Shekhar Ganguly',
    chesscom: 'suryaganguly',
  ),
  PrepFavorite(fideId: '813192', name: 'Daniele Vocaturo', chesscom: 'Diwi89'),
  PrepFavorite(
    fideId: '8603847',
    name: 'Chongsheng Zeng',
    chesscom: 'lonelyzeng',
  ),
  PrepFavorite(
    fideId: '2270544',
    name: 'Alvar Alonso Rosell',
    chesscom: 'iwanyu',
  ),
  PrepFavorite(
    fideId: '1017063',
    name: 'Benjamin Bok',
    chesscom: 'GMBenjaminBok',
    lichess: 'BenjaminBokTwitch',
  ),
  PrepFavorite(
    fideId: '14507927',
    name: 'Marin Bosiocic',
    chesscom: 'Bosiocic',
  ),
  PrepFavorite(fideId: '6383742', name: 'Isik Can', chesscom: 'IsikCan05'),
  PrepFavorite(
    fideId: '20000197',
    name: 'Faustino Oro',
    chesscom: 'FaustinoOro',
    lichess: 'FaustiOro',
  ),
  PrepFavorite(
    fideId: '14112620',
    name: 'Li Min Peng',
    chesscom: 'Peng_Li-Min',
    lichess: 'Peng_Li_Min',
  ),
  PrepFavorite(
    fideId: '4148843',
    name: 'Evgeny Romanov',
    chesscom: 'EvgenyRomanov',
  ),
  PrepFavorite(
    fideId: '2801795',
    name: 'Nitzan Steinberg',
    chesscom: 'Nitzan_Steinberg',
  ),
  PrepFavorite(
    fideId: '2059630',
    name: 'Andrew Tang',
    legacyId: 'tang',
    chesscom: 'penguingm1',
    lichess: 'penguingm1',
  ),
  PrepFavorite(
    fideId: '8603006',
    name: 'Ju Wenjun',
    legacyId: 'ju-wenjun',
    chesscom: 'juwenjun',
  ),
  PrepFavorite(
    fideId: '2039877',
    name: 'Levy Rozman',
    legacyId: 'rozman',
    chesscom: 'GothamChess',
  ),
  PrepFavorite(
    fideId: '2032562',
    name: 'Eric Rosen',
    legacyId: 'rosen',
    chesscom: 'IMRosen',
    lichess: 'EricRosen',
  ),
  PrepFavorite(
    fideId: '722855',
    name: 'Anna Rudolf',
    legacyId: 'rudolf',
    chesscom: 'Anna_Chess',
  ),
  PrepFavorite(
    fideId: '2603365',
    name: 'Alexandra Botez',
    legacyId: 'botez',
    chesscom: 'AlexandraBotez',
  ),
];
