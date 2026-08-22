// Comprehensive ECO (Encyclopaedia of Chess Openings) lookup utility.
//
// The ECO classification system divides chess openings into 5 main categories (A-E),
// each containing 100 codes (00-99). This utility provides detailed information
// about each category and individual opening codes.

part 'eco_opening_catalog_data.g.dart';

/// Represents detailed information about an ECO opening
class EcoOpening {
  const EcoOpening({
    required this.code,
    required this.name,
    this.moves,
    this.isMainLine = false,
  });

  final String code;
  final String name;
  final String? moves;
  final bool isMainLine;
}

/// One source row from the 365Chess catalog. Range rows (for example
/// `B20-B99`) are selectable parents; exact rows provide every searchable
/// named subvariant and its move path.
class EcoOpeningRecord {
  const EcoOpeningRecord({
    required this.code,
    required this.name,
    required this.moves,
  });

  final String code;
  final String name;
  final String moves;

  bool get isRange => code.contains('-');
}

/// A validated, inclusive range within one ECO category.
class EcoCodeRange {
  const EcoCodeRange({required this.start, required this.end});

  final String start;
  final String end;

  int get startNumber => int.parse(start.substring(1));
  int get endNumber => int.parse(end.substring(1));
  int get codeCount => endNumber - startNumber + 1;
  String get label => '$start-$end';

  bool contains(String code) {
    final normalized = code.trim().toUpperCase();
    if (!RegExp(r'^[A-E][0-9]{2}$').hasMatch(normalized) ||
        normalized[0] != start[0]) {
      return false;
    }
    final number = int.parse(normalized.substring(1));
    return number >= startNumber && number <= endNumber;
  }

  /// Smallest exact prefix cover understood by all existing PostgREST query
  /// paths. Whole decades become `B2`; partial edges stay exact (`D40`).
  List<String> get codePrefixes {
    final prefixes = <String>[];
    var number = startNumber;
    while (number <= endNumber) {
      if (number % 10 == 0 && number + 9 <= endNumber) {
        prefixes.add('${start[0]}${number ~/ 10}');
        number += 10;
      } else {
        prefixes.add('${start[0]}${number.toString().padLeft(2, '0')}');
        number++;
      }
    }
    return List<String>.unmodifiable(prefixes);
  }

  static EcoCodeRange? tryParse(String raw) {
    final normalized = raw.trim().toUpperCase().replaceAll('–', '-');
    final match = RegExp(
      r'^([A-E][0-9]{2})-([A-E][0-9]{2})$',
    ).firstMatch(normalized);
    if (match == null) return null;
    final start = match.group(1)!;
    final end = match.group(2)!;
    if (start[0] != end[0] ||
        int.parse(start.substring(1)) > int.parse(end.substring(1))) {
      return null;
    }
    return EcoCodeRange(start: start, end: end);
  }
}

/// Represents an ECO category (A, B, C, D, or E)
class EcoCategory {
  const EcoCategory({
    required this.letter,
    required this.name,
    required this.description,
    required this.keyOpenings,
    required this.characteristics,
  });

  final String letter;
  final String name;
  final String description;
  final List<String> keyOpenings;
  final String characteristics;
}

/// A selectable parent opening backed by an exact inclusive ECO range.
///
/// [codePrefixes] is the minimal query-safe cover of that range. This keeps
/// the existing prefix contract while allowing source ranges such as D30-D42,
/// not just decade-aligned parents such as B90-B99.
class EcoOpeningFamily {
  const EcoOpeningFamily({
    required this.id,
    required this.name,
    required this.rangeStart,
    required this.rangeEnd,
    required this.codePrefixes,
    required this.codeCount,
    this.moves,
  });

  final String id;
  final String name;
  final String rangeStart;
  final String rangeEnd;
  final List<String> codePrefixes;
  final int codeCount;
  final String? moves;

  String get rangeLabel => '$rangeStart-$rangeEnd';

  /// Retained for category-color callers and legacy two-character families.
  String get codePrefix => codePrefixes.first;

  bool containsCode(String code) =>
      EcoCodeRange(start: rangeStart, end: rangeEnd).contains(code);
}

/// ECO Categories with comprehensive descriptions
class EcoOpenings {
  EcoOpenings._();

  /// The five main ECO categories with detailed information
  static const Map<String, EcoCategory> categories = {
    'A': EcoCategory(
      letter: 'A',
      name: 'Flank Openings',
      description:
          'Openings that don\'t begin with 1.e4 or 1.d4, plus Queen\'s Pawn openings without an early c4.',
      keyOpenings: [
        'English Opening (1.c4)',
        'Réti Opening (1.Nf3)',
        'Bird\'s Opening (1.f4)',
        'Dutch Defense',
        'Benoni Defense',
        'Budapest Gambit',
      ],
      characteristics:
          'Hypermodern and flexible setups, fianchettoed bishops, delayed central tension',
    ),
    'B': EcoCategory(
      letter: 'B',
      name: 'Semi-Open Games',
      description:
          'Black responds to 1.e4 with moves other than 1...e5. Asymmetrical pawn structures.',
      keyOpenings: [
        'Sicilian Defense (1.e4 c5)',
        'Caro-Kann Defense (1.e4 c6)',
        'Pirc Defense (1.e4 d6)',
        'Alekhine\'s Defense (1.e4 Nf6)',
        'Scandinavian Defense (1.e4 d5)',
        'Modern Defense (1.e4 g6)',
      ],
      characteristics:
          'Dynamic imbalances, complex middlegames, fighting chess',
    ),
    'C': EcoCategory(
      letter: 'C',
      name: 'Open Games',
      description:
          'Classical openings beginning with 1.e4 e5, including the French Defense.',
      keyOpenings: [
        'French Defense (1.e4 e6)',
        'Ruy López / Spanish Game',
        'Italian Game (Giuoco Piano)',
        'Scotch Game',
        'King\'s Gambit',
        'Petrov\'s Defense',
      ],
      characteristics:
          'Classical pawn center, rapid piece development, tactical play',
    ),
    'D': EcoCategory(
      letter: 'D',
      name: 'Closed Games',
      description:
          'Queen\'s Pawn openings with 1.d4 d5, featuring the Queen\'s Gambit complex.',
      keyOpenings: [
        'Queen\'s Gambit Declined',
        'Queen\'s Gambit Accepted',
        'Slav Defense',
        'Semi-Slav Defense',
        'Grünfeld Defense',
        'Catalan Opening',
      ],
      characteristics:
          'Solid pawn structures, strategic maneuvering, positional play',
    ),
    'E': EcoCategory(
      letter: 'E',
      name: 'Indian Defenses',
      description:
          'Openings where Black plays 1...Nf6 against 1.d4, declining to occupy the center early.',
      keyOpenings: [
        'Nimzo-Indian Defense',
        'Queen\'s Indian Defense',
        'King\'s Indian Defense',
        'Bogo-Indian Defense',
        'Catalan Opening (with Nf6)',
        'Old Indian Defense',
      ],
      characteristics:
          'Hypermodern approach, flexible pawn structures, complex strategic battles',
    ),
  };

  /// Get category info by letter
  static EcoCategory? getCategory(String letter) {
    return categories[letter.toUpperCase()];
  }

  /// Get category for an ECO code (e.g., "B42" returns category B)
  static EcoCategory? getCategoryForCode(String ecoCode) {
    if (ecoCode.isEmpty) return null;
    return categories[ecoCode[0].toUpperCase()];
  }

  /// Curated one-label-per-code display fallback for all 500 exact ECO codes.
  static const Map<String, String> codeToName = {
    // A00-A09: Irregular & Flank Openings
    'A00': 'Irregular Openings',
    'A01': 'Nimzowitsch-Larsen Attack',
    'A02': 'Bird\'s Opening',
    'A03': 'Bird\'s Opening',
    'A04': 'Réti Opening',
    'A05': 'Réti Opening',
    'A06': 'Réti Opening',
    'A07': 'Réti Opening: Barcza System',
    'A08': 'Réti Opening: Barcza System',
    'A09': 'Réti Opening',

    // A10-A39: English Opening
    'A10': 'English Opening',
    'A11': 'English: Caro-Kann System',
    'A12': 'English: Réti-Caro-Kann',
    'A13': 'English: Agincourt Defense',
    'A14': 'English: Agincourt, Neo-Catalan',
    'A15': 'English Opening',
    'A16': 'English: Anglo-Indian',
    'A17': 'English: Hedgehog',
    'A18': 'English: Mikenas-Flohr',
    'A19': 'English: Mikenas-Flohr',
    'A20': 'English: King\'s English',
    'A21': 'English: King\'s English',
    'A22': 'English: Two Knights',
    'A23': 'English: Two Knights, Keres',
    'A24': 'English: Three Knights',
    'A25': 'English: Closed System',
    'A26': 'English: Closed System',
    'A27': 'English: Three Knights',
    'A28': 'English: Four Knights',
    'A29': 'English: Four Knights',
    'A30': 'English: Symmetrical',
    'A31': 'English: Symmetrical, Anti-Benoni',
    'A32': 'English: Symmetrical',
    'A33': 'English: Symmetrical',
    'A34': 'English: Symmetrical',
    'A35': 'English: Symmetrical, Four Knights',
    'A36': 'English: Symmetrical',
    'A37': 'English: Symmetrical',
    'A38': 'English: Symmetrical',
    'A39': 'English: Maróczy Bind',

    // A40-A55: Queen's Pawn & Indian Systems
    'A40': 'Queen\'s Pawn Opening',
    'A41': 'Queen\'s Pawn',
    'A42': 'Modern Defense: Averbakh',
    'A43': 'Old Benoni Defense',
    'A44': 'Old Benoni: Czech Benoni',
    'A45': 'Indian Defense',
    'A46': 'Queen\'s Pawn: Indian Systems',
    'A47': 'Queen\'s Indian (without c4)',
    'A48': 'King\'s Indian: East Indian',
    'A49': 'King\'s Indian: Fianchetto',
    'A50': 'Queen\'s Pawn Game',
    'A51': 'Budapest Gambit',
    'A52': 'Budapest Gambit',
    'A53': 'Old Indian Defense',
    'A54': 'Old Indian: Ukrainian',
    'A55': 'Old Indian: Main Line',

    // A56-A79: Benoni Defenses
    'A56': 'Benoni Defense',
    'A57': 'Benko Gambit',
    'A58': 'Benko Gambit Accepted',
    'A59': 'Benko Gambit: Modern',
    'A60': 'Modern Benoni',
    'A61': 'Modern Benoni',
    'A62': 'Modern Benoni: Fianchetto',
    'A63': 'Modern Benoni: Fianchetto',
    'A64': 'Modern Benoni: Fianchetto',
    'A65': 'Modern Benoni: Classical',
    'A66': 'Modern Benoni: Four Pawns',
    'A67': 'Modern Benoni: Taimanov',
    'A68': 'Modern Benoni: Four Pawns',
    'A69': 'Modern Benoni: Four Pawns',
    'A70': 'Modern Benoni: Classical',
    'A71': 'Modern Benoni: Classical',
    'A72': 'Modern Benoni: Classical',
    'A73': 'Modern Benoni: Classical',
    'A74': 'Modern Benoni: Classical',
    'A75': 'Modern Benoni: Classical',
    'A76': 'Modern Benoni: Classical',
    'A77': 'Modern Benoni: Classical',
    'A78': 'Modern Benoni: Classical',
    'A79': 'Modern Benoni: Classical',

    // A80-A99: Dutch Defense
    'A80': 'Dutch Defense',
    'A81': 'Dutch Defense',
    'A82': 'Dutch: Staunton Gambit',
    'A83': 'Dutch: Staunton Gambit',
    'A84': 'Dutch Defense',
    'A85': 'Dutch Defense',
    'A86': 'Dutch Defense',
    'A87': 'Dutch: Leningrad',
    'A88': 'Dutch: Leningrad',
    'A89': 'Dutch: Leningrad',
    'A90': 'Dutch: Classical',
    'A91': 'Dutch: Classical',
    'A92': 'Dutch: Classical',
    'A93': 'Dutch: Stonewall',
    'A94': 'Dutch: Stonewall',
    'A95': 'Dutch: Stonewall, Botvinnik',
    'A96': 'Dutch: Ilyin-Zhenevsky',
    'A97': 'Dutch: Ilyin-Zhenevsky',
    'A98': 'Dutch: Ilyin-Zhenevsky',
    'A99': 'Dutch: Ilyin-Zhenevsky',

    // B00-B09: Uncommon King's Pawn Defenses
    'B00': 'King\'s Pawn Opening',
    'B01': 'Scandinavian Defense',
    'B02': 'Alekhine\'s Defense',
    'B03': 'Alekhine\'s Defense: Exchange',
    'B04': 'Alekhine\'s Defense: Modern',
    'B05': 'Alekhine\'s Defense: Modern',
    'B06': 'Modern Defense',
    'B07': 'Pirc Defense',
    'B08': 'Pirc: Classical',
    'B09': 'Pirc: Austrian Attack',

    // B10-B19: Caro-Kann Defense
    'B10': 'Caro-Kann Defense',
    'B11': 'Caro-Kann: Two Knights',
    'B12': 'Caro-Kann Defense',
    'B13': 'Caro-Kann: Exchange',
    'B14': 'Caro-Kann: Panov-Botvinnik',
    'B15': 'Caro-Kann: Classical',
    'B16': 'Caro-Kann: Bronstein-Larsen',
    'B17': 'Caro-Kann: Steinitz',
    'B18': 'Caro-Kann: Classical',
    'B19': 'Caro-Kann: Classical',

    // B20-B99: Sicilian Defense
    'B20': 'Sicilian Defense',
    'B21': 'Sicilian: Grand Prix / Morra',
    'B22': 'Sicilian: Alapin',
    'B23': 'Sicilian: Closed',
    'B24': 'Sicilian: Closed',
    'B25': 'Sicilian: Closed',
    'B26': 'Sicilian: Closed',
    'B27': 'Sicilian Defense',
    'B28': 'Sicilian: O\'Kelly',
    'B29': 'Sicilian: Nimzowitsch',
    'B30': 'Sicilian: Rossolimo',
    'B31': 'Sicilian: Rossolimo',
    'B32': 'Sicilian: Flohr',
    'B33': 'Sicilian: Sveshnikov',
    'B34': 'Sicilian: Accelerated Dragon',
    'B35': 'Sicilian: Dragon',
    'B36': 'Sicilian: Maróczy Bind',
    'B37': 'Sicilian: Dragon',
    'B38': 'Sicilian: Dragon',
    'B39': 'Sicilian: Dragon',
    'B40': 'Sicilian: Kan',
    'B41': 'Sicilian: Kan',
    'B42': 'Sicilian: Kan',
    'B43': 'Sicilian: Kan',
    'B44': 'Sicilian: Taimanov',
    'B45': 'Sicilian: Taimanov',
    'B46': 'Sicilian: Taimanov',
    'B47': 'Sicilian: Taimanov',
    'B48': 'Sicilian: Taimanov',
    'B49': 'Sicilian: Taimanov',
    'B50': 'Sicilian Defense',
    'B51': 'Sicilian: Moscow',
    'B52': 'Sicilian: Canal-Sokolsky',
    'B53': 'Sicilian: Chekhover',
    'B54': 'Sicilian Defense',
    'B55': 'Sicilian: Prins',
    'B56': 'Sicilian: Classical',
    'B57': 'Sicilian: Sozin',
    'B58': 'Sicilian: Classical',
    'B59': 'Sicilian: Boleslavsky',
    'B60': 'Sicilian: Richter-Rauzer',
    'B61': 'Sicilian: Richter-Rauzer',
    'B62': 'Sicilian: Richter-Rauzer',
    'B63': 'Sicilian: Richter-Rauzer',
    'B64': 'Sicilian: Richter-Rauzer',
    'B65': 'Sicilian: Richter-Rauzer',
    'B66': 'Sicilian: Richter-Rauzer',
    'B67': 'Sicilian: Richter-Rauzer',
    'B68': 'Sicilian: Velimirović',
    'B69': 'Sicilian: Velimirović',
    'B70': 'Sicilian: Dragon',
    'B71': 'Sicilian: Dragon, Levenfish',
    'B72': 'Sicilian: Dragon, Classical',
    'B73': 'Sicilian: Dragon, Classical',
    'B74': 'Sicilian: Dragon, Classical',
    'B75': 'Sicilian: Dragon, Yugoslav',
    'B76': 'Sicilian: Dragon, Yugoslav',
    'B77': 'Sicilian: Dragon, Yugoslav',
    'B78': 'Sicilian: Dragon, Yugoslav',
    'B79': 'Sicilian: Dragon, Yugoslav',
    'B80': 'Sicilian: Scheveningen',
    'B81': 'Sicilian: Keres Attack',
    'B82': 'Sicilian: Scheveningen',
    'B83': 'Sicilian: Scheveningen',
    'B84': 'Sicilian: Scheveningen',
    'B85': 'Sicilian: Scheveningen',
    'B86': 'Sicilian: Sozin',
    'B87': 'Sicilian: Sozin',
    'B88': 'Sicilian: Sozin',
    'B89': 'Sicilian: Sozin',
    'B90': 'Sicilian: Najdorf',
    'B91': 'Sicilian: Najdorf',
    'B92': 'Sicilian: Najdorf',
    'B93': 'Sicilian: Najdorf',
    'B94': 'Sicilian: Najdorf',
    'B95': 'Sicilian: Najdorf',
    'B96': 'Sicilian: Najdorf',
    'B97': 'Sicilian: Najdorf, Poisoned Pawn',
    'B98': 'Sicilian: Najdorf',
    'B99': 'Sicilian: Najdorf',

    // C00-C19: French Defense
    'C00': 'French Defense',
    'C01': 'French: Exchange',
    'C02': 'French: Advance',
    'C03': 'French: Tarrasch',
    'C04': 'French: Tarrasch, Guimard',
    'C05': 'French: Tarrasch, Closed',
    'C06': 'French: Tarrasch, Closed',
    'C07': 'French: Tarrasch, Open',
    'C08': 'French: Tarrasch, Open',
    'C09': 'French: Tarrasch, Open',
    'C10': 'French Defense',
    'C11': 'French: Classical',
    'C12': 'French: MacCutcheon',
    'C13': 'French: Classical',
    'C14': 'French: Classical, Steinitz',
    'C15': 'French: Winawer',
    'C16': 'French: Winawer, Advance',
    'C17': 'French: Winawer, Advance',
    'C18': 'French: Winawer, Advance',
    'C19': 'French: Winawer, Advance',

    // C20-C59: Open Games (1.e4 e5)
    'C20': 'King\'s Pawn Game',
    'C21': 'Center Game',
    'C22': 'Center Game',
    'C23': 'Bishop\'s Opening',
    'C24': 'Bishop\'s Opening: Berlin',
    'C25': 'Vienna Game',
    'C26': 'Vienna Game',
    'C27': 'Vienna: Frankenstein-Dracula',
    'C28': 'Vienna Game',
    'C29': 'Vienna Gambit',
    'C30': 'King\'s Gambit',
    'C31': 'King\'s Gambit Declined',
    'C32': 'King\'s Gambit: Falkbeer',
    'C33': 'King\'s Gambit Accepted',
    'C34': 'King\'s Gambit Accepted',
    'C35': 'King\'s Gambit: Cunningham',
    'C36': 'King\'s Gambit: Modern',
    'C37': 'King\'s Gambit: Bishop\'s Gambit',
    'C38': 'King\'s Gambit: Philidor',
    'C39': 'King\'s Gambit: Allgaier',
    'C40': 'King\'s Knight Opening',
    'C41': 'Philidor Defense',
    'C42': 'Petrov\'s Defense',
    'C43': 'Petrov\'s Defense',
    'C44': 'Scotch Gambit',
    'C45': 'Scotch Game',
    'C46': 'Three Knights Game',
    'C47': 'Four Knights Game',
    'C48': 'Four Knights: Spanish',
    'C49': 'Four Knights: Double Spanish',
    'C50': 'Italian Game',
    'C51': 'Italian: Evans Gambit',
    'C52': 'Italian: Evans Gambit',
    'C53': 'Italian: Giuoco Piano',
    'C54': 'Italian: Giuoco Piano',
    'C55': 'Italian: Two Knights',
    'C56': 'Italian: Two Knights',
    'C57': 'Italian: Fegatello Attack',
    'C58': 'Italian: Two Knights',
    'C59': 'Italian: Two Knights',

    // C60-C99: Spanish/Ruy López
    'C60': 'Ruy López',
    'C61': 'Ruy López: Bird\'s Defense',
    'C62': 'Ruy López: Old Steinitz',
    'C63': 'Ruy López: Schliemann',
    'C64': 'Ruy López: Classical',
    'C65': 'Ruy López: Berlin',
    'C66': 'Ruy López: Berlin',
    'C67': 'Ruy López: Berlin',
    'C68': 'Ruy López: Exchange',
    'C69': 'Ruy López: Exchange',
    'C70': 'Ruy López: Morphy Defense',
    'C71': 'Ruy López: Modern Steinitz',
    'C72': 'Ruy López: Modern Steinitz',
    'C73': 'Ruy López: Modern Steinitz',
    'C74': 'Ruy López: Modern Steinitz',
    'C75': 'Ruy López: Modern Steinitz',
    'C76': 'Ruy López: Modern Steinitz',
    'C77': 'Ruy López: Anderssen',
    'C78': 'Ruy López: Archangelsk',
    'C79': 'Ruy López: Steinitz Deferred',
    'C80': 'Ruy López: Open',
    'C81': 'Ruy López: Open, Howell',
    'C82': 'Ruy López: Open',
    'C83': 'Ruy López: Open, Classical',
    'C84': 'Ruy López: Closed',
    'C85': 'Ruy López: Exchange, Bronstein',
    'C86': 'Ruy López: Worrall',
    'C87': 'Ruy López: Closed, Averbakh',
    'C88': 'Ruy López: Closed, Anti-Marshall',
    'C89': 'Ruy López: Marshall Attack',
    'C90': 'Ruy López: Closed',
    'C91': 'Ruy López: Closed',
    'C92': 'Ruy López: Zaitsev',
    'C93': 'Ruy López: Smyslov',
    'C94': 'Ruy López: Breyer',
    'C95': 'Ruy López: Breyer',
    'C96': 'Ruy López: Chigorin',
    'C97': 'Ruy López: Chigorin',
    'C98': 'Ruy López: Chigorin',
    'C99': 'Ruy López: Chigorin',

    // D00-D69: Queen's Gambit & Related
    'D00': 'Queen\'s Pawn Game',
    'D01': 'Richter-Veresov Attack',
    'D02': 'Queen\'s Pawn: London System',
    'D03': 'Queen\'s Pawn: Torre Attack',
    'D04': 'Queen\'s Pawn: Colle System',
    'D05': 'Queen\'s Pawn: Colle System',
    'D06': 'Queen\'s Gambit',
    'D07': 'Queen\'s Gambit: Chigorin',
    'D08': 'Queen\'s Gambit: Albin Counter-Gambit',
    'D09': 'Queen\'s Gambit: Albin Counter-Gambit',
    'D10': 'Slav Defense',
    'D11': 'Slav Defense',
    'D12': 'Slav Defense',
    'D13': 'Slav: Exchange',
    'D14': 'Slav: Exchange',
    'D15': 'Slav: Three Knights',
    'D16': 'Slav: Bronstein',
    'D17': 'Slav: Czech',
    'D18': 'Slav: Dutch',
    'D19': 'Slav: Dutch',
    'D20': 'Queen\'s Gambit Accepted',
    'D21': 'Queen\'s Gambit Accepted',
    'D22': 'Queen\'s Gambit Accepted',
    'D23': 'Queen\'s Gambit Accepted',
    'D24': 'Queen\'s Gambit Accepted',
    'D25': 'Queen\'s Gambit Accepted',
    'D26': 'Queen\'s Gambit Accepted',
    'D27': 'Queen\'s Gambit Accepted: Classical',
    'D28': 'Queen\'s Gambit Accepted',
    'D29': 'Queen\'s Gambit Accepted',
    'D30': 'Queen\'s Gambit Declined',
    'D31': 'Queen\'s Gambit Declined',
    'D32': 'Queen\'s Gambit Declined: Tarrasch',
    'D33': 'Queen\'s Gambit Declined: Tarrasch',
    'D34': 'Queen\'s Gambit Declined: Tarrasch',
    'D35': 'Queen\'s Gambit Declined: Exchange',
    'D36': 'Queen\'s Gambit Declined: Exchange',
    'D37': 'Queen\'s Gambit Declined',
    'D38': 'Queen\'s Gambit Declined: Ragozin',
    'D39': 'Queen\'s Gambit Declined: Ragozin',
    'D40': 'Queen\'s Gambit Declined: Semi-Tarrasch',
    'D41': 'Queen\'s Gambit Declined: Semi-Tarrasch',
    'D42': 'Queen\'s Gambit Declined: Semi-Tarrasch',
    'D43': 'Semi-Slav Defense',
    'D44': 'Semi-Slav: Botvinnik',
    'D45': 'Semi-Slav: Main Line',
    'D46': 'Semi-Slav: Chigorin',
    'D47': 'Semi-Slav: Meran',
    'D48': 'Semi-Slav: Meran',
    'D49': 'Semi-Slav: Meran',
    'D50': 'Queen\'s Gambit Declined',
    'D51': 'Queen\'s Gambit Declined',
    'D52': 'Queen\'s Gambit Declined: Cambridge Springs',
    'D53': 'Queen\'s Gambit Declined',
    'D54': 'Queen\'s Gambit Declined: Anti-Tartakower',
    'D55': 'Queen\'s Gambit Declined',
    'D56': 'Queen\'s Gambit Declined: Lasker Defense',
    'D57': 'Queen\'s Gambit Declined: Lasker Defense',
    'D58': 'Queen\'s Gambit Declined: Tartakower',
    'D59': 'Queen\'s Gambit Declined: Tartakower',
    'D60': 'Queen\'s Gambit Declined: Orthodox',
    'D61': 'Queen\'s Gambit Declined: Orthodox',
    'D62': 'Queen\'s Gambit Declined: Orthodox',
    'D63': 'Queen\'s Gambit Declined: Orthodox',
    'D64': 'Queen\'s Gambit Declined: Orthodox',
    'D65': 'Queen\'s Gambit Declined: Orthodox',
    'D66': 'Queen\'s Gambit Declined: Orthodox',
    'D67': 'Queen\'s Gambit Declined: Orthodox',
    'D68': 'Queen\'s Gambit Declined: Orthodox',
    'D69': 'Queen\'s Gambit Declined: Orthodox',

    // D70-D99: Grünfeld Defense
    'D70': 'Neo-Grünfeld Defense',
    'D71': 'Neo-Grünfeld Defense',
    'D72': 'Neo-Grünfeld Defense',
    'D73': 'Neo-Grünfeld Defense',
    'D74': 'Neo-Grünfeld Defense',
    'D75': 'Neo-Grünfeld Defense',
    'D76': 'Neo-Grünfeld Defense',
    'D77': 'Neo-Grünfeld: Fianchetto',
    'D78': 'Neo-Grünfeld: Fianchetto',
    'D79': 'Neo-Grünfeld: Fianchetto',
    'D80': 'Grünfeld Defense',
    'D81': 'Grünfeld: Russian',
    'D82': 'Grünfeld: Brinckmann',
    'D83': 'Grünfeld: Brinckmann',
    'D84': 'Grünfeld Defense',
    'D85': 'Grünfeld Defense',
    'D86': 'Grünfeld: Exchange',
    'D87': 'Grünfeld: Exchange',
    'D88': 'Grünfeld: Exchange',
    'D89': 'Grünfeld: Exchange',
    'D90': 'Grünfeld Defense',
    'D91': 'Grünfeld: Three Knights',
    'D92': 'Grünfeld: Hungarian',
    'D93': 'Grünfeld: Hungarian',
    'D94': 'Grünfeld: Makogonov',
    'D95': 'Grünfeld: Makogonov',
    'D96': 'Grünfeld: Russian',
    'D97': 'Grünfeld: Russian',
    'D98': 'Grünfeld: Russian',
    'D99': 'Grünfeld: Russian',

    // E00-E09: Catalan Opening
    'E00': 'Queen\'s Pawn: Neo-Indian',
    'E01': 'Catalan Opening',
    'E02': 'Catalan Opening',
    'E03': 'Catalan Opening',
    'E04': 'Catalan: Open',
    'E05': 'Catalan: Open',
    'E06': 'Catalan: Closed',
    'E07': 'Catalan: Closed',
    'E08': 'Catalan: Closed',
    'E09': 'Catalan: Closed',

    // E10-E19: Queen's Indian & Related
    'E10': 'Queen\'s Pawn: Neo-Indian',
    'E11': 'Bogo-Indian Defense',
    'E12': 'Queen\'s Indian Defense',
    'E13': 'Queen\'s Indian Defense',
    'E14': 'Queen\'s Indian Defense',
    'E15': 'Queen\'s Indian Defense',
    'E16': 'Queen\'s Indian Defense',
    'E17': 'Queen\'s Indian Defense',
    'E18': 'Queen\'s Indian Defense',
    'E19': 'Queen\'s Indian Defense',

    // E20-E59: Nimzo-Indian Defense
    'E20': 'Nimzo-Indian Defense',
    'E21': 'Nimzo-Indian: Three Knights',
    'E22': 'Nimzo-Indian: Spielmann',
    'E23': 'Nimzo-Indian: Spielmann',
    'E24': 'Nimzo-Indian: Sämisch',
    'E25': 'Nimzo-Indian: Sämisch',
    'E26': 'Nimzo-Indian: Sämisch',
    'E27': 'Nimzo-Indian: Sämisch',
    'E28': 'Nimzo-Indian: Sämisch',
    'E29': 'Nimzo-Indian: Sämisch',
    'E30': 'Nimzo-Indian: Leningrad',
    'E31': 'Nimzo-Indian: Leningrad',
    'E32': 'Nimzo-Indian: Classical',
    'E33': 'Nimzo-Indian: Classical',
    'E34': 'Nimzo-Indian: Classical',
    'E35': 'Nimzo-Indian: Classical',
    'E36': 'Nimzo-Indian: Classical',
    'E37': 'Nimzo-Indian: Classical',
    'E38': 'Nimzo-Indian: Classical',
    'E39': 'Nimzo-Indian: Classical',
    'E40': 'Nimzo-Indian Defense',
    'E41': 'Nimzo-Indian: Hübner',
    'E42': 'Nimzo-Indian: Taimanov',
    'E43': 'Nimzo-Indian: Fischer',
    'E44': 'Nimzo-Indian: Fischer',
    'E45': 'Nimzo-Indian: Fischer',
    'E46': 'Nimzo-Indian: Reshevsky',
    'E47': 'Nimzo-Indian: Four Pawns',
    'E48': 'Nimzo-Indian: Four Pawns',
    'E49': 'Nimzo-Indian: Four Pawns',
    'E50': 'Nimzo-Indian Defense',
    'E51': 'Nimzo-Indian: Four Pawns',
    'E52': 'Nimzo-Indian: Main Line',
    'E53': 'Nimzo-Indian: Main Line',
    'E54': 'Nimzo-Indian: Main Line',
    'E55': 'Nimzo-Indian: Main Line',
    'E56': 'Nimzo-Indian: Main Line',
    'E57': 'Nimzo-Indian: Main Line',
    'E58': 'Nimzo-Indian: Main Line',
    'E59': 'Nimzo-Indian: Main Line',

    // E60-E99: King's Indian Defense
    'E60': 'King\'s Indian Defense',
    'E61': 'King\'s Indian Defense',
    'E62': 'King\'s Indian: Fianchetto',
    'E63': 'King\'s Indian: Fianchetto',
    'E64': 'King\'s Indian: Fianchetto',
    'E65': 'King\'s Indian: Fianchetto',
    'E66': 'King\'s Indian: Fianchetto',
    'E67': 'King\'s Indian: Fianchetto',
    'E68': 'King\'s Indian: Fianchetto',
    'E69': 'King\'s Indian: Fianchetto',
    'E70': 'King\'s Indian Defense',
    'E71': 'King\'s Indian: Makogonov',
    'E72': 'King\'s Indian: Averbakh',
    'E73': 'King\'s Indian: Averbakh',
    'E74': 'King\'s Indian: Averbakh',
    'E75': 'King\'s Indian: Averbakh',
    'E76': 'King\'s Indian: Four Pawns',
    'E77': 'King\'s Indian: Four Pawns',
    'E78': 'King\'s Indian: Four Pawns',
    'E79': 'King\'s Indian: Four Pawns',
    'E80': 'King\'s Indian: Sämisch',
    'E81': 'King\'s Indian: Sämisch',
    'E82': 'King\'s Indian: Sämisch',
    'E83': 'King\'s Indian: Sämisch',
    'E84': 'King\'s Indian: Sämisch',
    'E85': 'King\'s Indian: Sämisch',
    'E86': 'King\'s Indian: Sämisch',
    'E87': 'King\'s Indian: Sämisch',
    'E88': 'King\'s Indian: Sämisch',
    'E89': 'King\'s Indian: Sämisch',
    'E90': 'King\'s Indian: Classical',
    'E91': 'King\'s Indian: Classical',
    'E92': 'King\'s Indian: Classical',
    'E93': 'King\'s Indian: Petrosian',
    'E94': 'King\'s Indian: Classical',
    'E95': 'King\'s Indian: Classical',
    'E96': 'King\'s Indian: Classical',
    'E97': 'King\'s Indian: Mar del Plata',
    'E98': 'King\'s Indian: Mar del Plata',
    'E99': 'King\'s Indian: Mar del Plata',
  };

  /// Every source row, including all named move-level variants and the
  /// explicit parent ranges supplied by the catalog.
  static const List<EcoOpeningRecord> catalog = _ecoOpeningCatalog;

  static final List<EcoOpeningRecord> exactCatalog = List.unmodifiable(
    catalog.where((record) => !record.isRange),
  );

  static final List<EcoOpeningRecord> rangeCatalog = List.unmodifiable(
    catalog.where((record) => record.isRange),
  );

  static final Map<String, List<EcoOpeningRecord>> recordsByCode =
      _buildRecordsByCode();

  static final Map<String, List<EcoOpeningRecord>> _recordsByMovePath =
      _buildRecordsByMovePath();

  /// Selectable parents from both sources of truth:
  ///
  /// * explicit CSV ranges such as B20-B99 and D30-D42;
  /// * safe decade parents derived from the curated 500-code display map,
  ///   such as B9 / B90-B99 for the Najdorf family.
  static final List<EcoOpeningFamily> families = _buildFamilies();

  static Map<String, List<EcoOpeningRecord>> _buildRecordsByCode() {
    final result = <String, List<EcoOpeningRecord>>{};
    for (final record in exactCatalog) {
      result.putIfAbsent(record.code, () => []).add(record);
    }
    return Map.unmodifiable({
      for (final entry in result.entries)
        entry.key: List<EcoOpeningRecord>.unmodifiable(entry.value),
    });
  }

  static Map<String, List<EcoOpeningRecord>> _buildRecordsByMovePath() {
    final result = <String, List<EcoOpeningRecord>>{};
    for (final record in exactCatalog) {
      final key = movePathKey(moveTokens(record.moves));
      result.putIfAbsent(key, () => []).add(record);
    }
    return Map.unmodifiable({
      for (final entry in result.entries)
        entry.key: List<EcoOpeningRecord>.unmodifiable(entry.value),
    });
  }

  static List<EcoOpeningFamily> _buildFamilies() {
    final byPrefix = <String, List<MapEntry<String, String>>>{};
    for (final entry in codeToName.entries) {
      if (entry.key.length < 3) continue;
      final prefix = entry.key.substring(0, 2);
      byPrefix.putIfAbsent(prefix, () => []).add(entry);
    }

    final result = <EcoOpeningFamily>[];
    for (final group in byPrefix.entries) {
      final parentNames =
          group.value.map((entry) {
            // Comma suffixes are child variations inside the same parent, e.g.
            // "Sicilian: Najdorf, Poisoned Pawn".
            return entry.value.split(',').first.trim();
          }).toSet();
      if (group.value.length < 2 || parentNames.length != 1) continue;
      final range = EcoCodeRange(start: '${group.key}0', end: '${group.key}9');
      result.add(
        EcoOpeningFamily(
          id: group.key,
          name: parentNames.single,
          rangeStart: range.start,
          rangeEnd: range.end,
          codePrefixes: List.unmodifiable([group.key]),
          codeCount: group.value.length,
          moves: _representativeMoves(range, parentNames.single),
        ),
      );
    }

    // Preserve this shipped ID for recent searches and saved smart events.
    // The matching CSV range below enriches it with the authoritative move
    // path rather than creating a duplicate E60-E99 destination.
    const kingIndianRange = EcoCodeRange(start: 'E60', end: 'E99');
    result.add(
      EcoOpeningFamily(
        id: 'E6+E7+E8+E9',
        name: "King's Indian",
        rangeStart: kingIndianRange.start,
        rangeEnd: kingIndianRange.end,
        codePrefixes: kingIndianRange.codePrefixes,
        codeCount: kingIndianRange.codeCount,
        moves: _representativeMoves(kingIndianRange, "King's Indian"),
      ),
    );

    for (final record in rangeCatalog) {
      final range = EcoCodeRange.tryParse(record.code);
      if (range == null) continue;
      final existingIndex = result.indexWhere(
        (family) =>
            family.rangeStart == range.start && family.rangeEnd == range.end,
      );
      if (existingIndex >= 0) {
        final existing = result[existingIndex];
        result[existingIndex] = EcoOpeningFamily(
          id: existing.id,
          name: existing.name,
          rangeStart: range.start,
          rangeEnd: range.end,
          codePrefixes: range.codePrefixes,
          codeCount: range.codeCount,
          moves: record.moves,
        );
      } else {
        result.add(
          EcoOpeningFamily(
            id: range.label,
            name: record.name,
            rangeStart: range.start,
            rangeEnd: range.end,
            codePrefixes: range.codePrefixes,
            codeCount: range.codeCount,
            moves: record.moves,
          ),
        );
      }
    }

    result.sort(compareFamiliesParentFirst);
    return List<EcoOpeningFamily>.unmodifiable(result);
  }

  static String? _representativeMoves(EcoCodeRange range, String familyName) {
    final normalizedFamily = _simpleNameTokens(familyName);
    EcoOpeningRecord? best;
    var bestNameScore = -1;
    for (final record in exactCatalog) {
      if (!range.contains(record.code)) continue;
      final recordName = _simpleNameTokens(record.name);
      final nameScore = _commonPrefixLength(normalizedFamily, recordName);
      if (best == null ||
          nameScore > bestNameScore ||
          (nameScore == bestNameScore &&
              moveTokens(record.moves).length <
                  moveTokens(best.moves).length)) {
        best = record;
        bestNameScore = nameScore;
      }
    }
    return best?.moves;
  }

  static List<String> _simpleNameTokens(String value) => value
      .toLowerCase()
      .replaceAll('defence', 'defense')
      .split(RegExp(r'[^a-z0-9]+'))
      .where((token) => token.isNotEmpty)
      .toList(growable: false);

  static int _commonPrefixLength(List<String> left, List<String> right) {
    final limit = left.length < right.length ? left.length : right.length;
    var count = 0;
    while (count < limit && left[count] == right[count]) {
      count++;
    }
    return count;
  }

  static int compareFamiliesParentFirst(
    EcoOpeningFamily left,
    EcoOpeningFamily right,
  ) {
    final category = left.rangeStart[0].compareTo(right.rangeStart[0]);
    if (category != 0) return category;
    final start = int.parse(
      left.rangeStart.substring(1),
    ).compareTo(int.parse(right.rangeStart.substring(1)));
    if (start != 0) return start;
    final widerFirst = right.codeCount.compareTo(left.codeCount);
    if (widerFirst != 0) return widerFirst;
    return left.name.compareTo(right.name);
  }

  /// Finds a safe range-backed family by its persisted ID or visible range.
  static EcoOpeningFamily? getFamily(String? familyId) {
    final normalized = familyId?.trim().toUpperCase().replaceAll('–', '-');
    if (normalized == null || normalized.isEmpty) return null;
    for (final family in families) {
      if (family.id == normalized || family.rangeLabel == normalized) {
        return family;
      }
    }
    return null;
  }

  static int variantCountForCode(String code) =>
      recordsByCode[code.trim().toUpperCase()]?.length ?? 0;

  static EcoOpeningRecord? canonicalRecordForCode(String code) {
    final records = recordsByCode[code.trim().toUpperCase()];
    if (records == null || records.isEmpty) return null;
    return records.reduce((left, right) {
      final leftDepth = moveTokens(left.moves).length;
      final rightDepth = moveTokens(right.moves).length;
      if (leftDepth != rightDepth) return leftDepth < rightDepth ? left : right;
      return left.name.length <= right.name.length ? left : right;
    });
  }

  static List<EcoOpeningFamily> familiesForCode(String code, {String? moves}) {
    final movePath = moves == null ? null : moveTokens(moves);
    final result = families
        .where((family) {
          if (!family.containsCode(code)) return false;
          if (movePath == null || family.moves == null) return true;
          return isMovePrefix(moveTokens(family.moves!), movePath);
        })
        .toList(growable: false);
    result.sort((left, right) {
      final depth = moveTokens(
        left.moves ?? '',
      ).length.compareTo(moveTokens(right.moves ?? '').length);
      if (depth != 0) return depth;
      return right.codeCount.compareTo(left.codeCount);
    });
    return result;
  }

  /// The most specific canonical move ancestors of [record], one per ECO
  /// destination and ordered root-first. This is the programmatic tree used
  /// by both the horizontal home results and the vertical filter browser.
  static List<EcoOpeningRecord> ancestorRecords(EcoOpeningRecord record) {
    final descendantMoves = moveTokens(record.moves);
    final descendantName = _simpleNameTokens(record.name);
    final byCode = <String, EcoOpeningRecord>{};
    final scores = <String, int>{};
    for (var depth = 1; depth < descendantMoves.length; depth++) {
      final candidates =
          _recordsByMovePath[movePathKey(descendantMoves.take(depth))];
      if (candidates == null) continue;
      for (final candidate in candidates) {
        final nameScore = _commonPrefixLength(
          _simpleNameTokens(candidate.name),
          descendantName,
        );
        if (nameScore == 0) continue;
        final existing = byCode[candidate.code];
        final existingDepth =
            existing == null ? -1 : moveTokens(existing.moves).length;
        final candidateDepth = moveTokens(candidate.moves).length;
        if (nameScore > (scores[candidate.code] ?? -1) ||
            (nameScore == scores[candidate.code] &&
                candidateDepth > existingDepth)) {
          scores[candidate.code] = nameScore;
          byCode[candidate.code] = candidate;
        }
      }
    }
    final result = byCode.values.toList(growable: false);
    result.sort(
      (left, right) =>
          compareMovePaths(moveTokens(left.moves), moveTokens(right.moves)),
    );
    return result;
  }

  static List<String> moveTokens(String moves) => moves
      .trim()
      .split(RegExp(r'\s+'))
      .where(
        (token) => token.isNotEmpty && !RegExp(r'^\d+\.{1,3}$').hasMatch(token),
      )
      .toList(growable: false);

  static String movePathKey(Iterable<String> tokens) => tokens.join('\u0001');

  static bool isMovePrefix(List<String> prefix, List<String> path) {
    if (prefix.length > path.length) return false;
    for (var index = 0; index < prefix.length; index++) {
      if (prefix[index] != path[index]) return false;
    }
    return true;
  }

  static int compareMovePaths(List<String> left, List<String> right) {
    final limit = left.length < right.length ? left.length : right.length;
    for (var index = 0; index < limit; index++) {
      final order = left[index].toLowerCase().compareTo(
        right[index].toLowerCase(),
      );
      if (order != 0) return order;
    }
    return left.length.compareTo(right.length);
  }

  /// Human label for either an individual code or a safe parent family.
  static String? getFilterName(String? ecoCode) {
    if (ecoCode == null || ecoCode.trim().isEmpty) return null;
    final normalized = ecoCode.trim().toUpperCase();
    return getFamily(normalized)?.name ?? getOpeningName(normalized);
  }

  /// Get opening name for an ECO code
  static String? getOpeningName(String? ecoCode) {
    if (ecoCode == null || ecoCode.isEmpty) return null;
    final normalized = ecoCode.toUpperCase().trim();
    // Try exact match first
    if (codeToName.containsKey(normalized)) {
      return codeToName[normalized];
    }
    // Try with just first 3 characters (in case of extended codes)
    if (normalized.length >= 3) {
      final shortCode = normalized.substring(0, 3);
      return codeToName[shortCode];
    }
    return null;
  }

  /// Get a formatted display string combining ECO code and opening name
  static String getDisplayString(String? ecoCode, {String? fallbackName}) {
    if (ecoCode == null || ecoCode.isEmpty) {
      return fallbackName ?? 'Unknown Opening';
    }
    final name = getOpeningName(ecoCode) ?? fallbackName;
    if (name != null) {
      return '$ecoCode · $name';
    }
    return ecoCode;
  }
}
