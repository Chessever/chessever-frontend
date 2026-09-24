import 'package:flutter/foundation.dart';

/// Streaks, exactly as the cloud ledger counts them (see
/// chessever_cloudflare/apps/streaks/sql/time-classes.sql): consecutive
/// DECISIVE over-the-board wins since the most recent loss in the same FIDE
/// time class. Draws neither extend nor break a run, there is no run before a
/// first loss, and online games never count.
///
/// Source rows: `player_streak_class_leaderboard` (the wall, one row per
/// player per class with a live run) and `player_streak_class` (one player's
/// three classes with their latest decisive games). Both are world-readable.
enum StreakTimeClass { standard, rapid, blitz }

extension StreakTimeClassX on StreakTimeClass {
  /// Wire value in `time_class`.
  String get wire => name;

  String get label => switch (this) {
    StreakTimeClass.standard => 'Classical',
    StreakTimeClass.rapid => 'Rapid',
    StreakTimeClass.blitz => 'Blitz',
  };

  static StreakTimeClass? tryParse(Object? raw) => switch (raw) {
    'standard' || 'classical' => StreakTimeClass.standard,
    'rapid' => StreakTimeClass.rapid,
    'blitz' => StreakTimeClass.blitz,
    _ => null,
  };
}

/// The wall starts at three wins; below that it is just Tuesday.
const int kStreakWallMin = 3;

/// Featured (top-of-wall) flames only show familiar, highly rated players.
///
/// Also the default floor of every streak list (the wall, Discovery, the
/// Feed): below it a run is rarely interesting. Explicit wall filters (a
/// search, a federation, a title, an age group, women only) look past it.
const int kStreakFeaturedMinRating = 2650;

/// Whether [row] clears the default streak floor: rated at least
/// [kStreakFeaturedMinRating] in its own time class.
bool passesStreakFloor(StreakRow row) =>
    (row.rating ?? 0) >= kStreakFeaturedMinRating;

enum StreakLevel { ember, flame, blaze, inferno }

/// ember 3–4 · flame 5–9 · blaze 10–19 · inferno 20+
StreakLevel streakLevel(int streak) {
  if (streak >= 20) return StreakLevel.inferno;
  if (streak >= 10) return StreakLevel.blaze;
  if (streak >= 5) return StreakLevel.flame;
  return StreakLevel.ember;
}

extension StreakLevelX on StreakLevel {
  String get word => switch (this) {
    StreakLevel.ember => 'Warming up',
    StreakLevel.flame => 'On fire',
    StreakLevel.blaze => 'Blazing',
    StreakLevel.inferno => 'Untouchable',
  };
}

/// FIDE age categories by birth year, like FIDE's own: U12 is everyone under
/// 12 on 1 January, i.e. 12 or younger in calendar-year terms. Senior groups
/// count whoever reaches 50 or 65 this year.
enum StreakAgeGroup { all, u10, u12, u14, u16, u18, u20, s50, s65 }

extension StreakAgeGroupX on StreakAgeGroup {
  String get label => switch (this) {
    StreakAgeGroup.all => 'All ages',
    StreakAgeGroup.u10 => 'Under 10',
    StreakAgeGroup.u12 => 'Under 12',
    StreakAgeGroup.u14 => 'Under 14',
    StreakAgeGroup.u16 => 'Under 16',
    StreakAgeGroup.u18 => 'Under 18',
    StreakAgeGroup.u20 => 'Under 20',
    StreakAgeGroup.s50 => 'Seniors 50+',
    StreakAgeGroup.s65 => 'Seniors 65+',
  };

  /// Calendar-year age test, identical to the site's `inAgeGroup`.
  bool contains(int? age) {
    if (this == StreakAgeGroup.all) return true;
    if (age == null) return false;
    final n = int.parse(name.substring(1));
    return name.startsWith('u') ? age <= n : age >= n;
  }
}

/// Calendar-year age from a birth year (the view's `age` column does the same).
int? streakAgeFromBirthYear(int? birthYear, {DateTime? now}) {
  if (birthYear == null) return null;
  final year = (now ?? DateTime.now().toUtc()).year;
  if (birthYear < 1900 || birthYear > year) return null;
  return year - birthYear;
}

int? _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.isFinite ? v.toInt() : null;
  if (v is String && v.trim().isNotEmpty) return num.tryParse(v)?.toInt();
  return null;
}

String? _text(Object? v) {
  if (v == null) return null;
  final t = v.toString().trim();
  return t.isEmpty ? null : t;
}

String? _upper(Object? v) => _text(v)?.toUpperCase();

bool _flag(Object? v) => v == true || v == 'true';

/// One row of the wall: a player's live run in one time class.
@immutable
class StreakRow {
  const StreakRow({
    required this.fideId,
    required this.timeClass,
    required this.name,
    this.title,
    this.fed,
    this.sex,
    this.rating,
    this.birthYear,
    this.age,
    required this.currentStreak,
    required this.bestStreak,
    this.bestStreakAt,
    this.wins = 0,
    this.losses = 0,
    this.anchorLossGameDay,
    this.streakStartGameDay,
    this.lastGameDay,
    this.lastResult,
    this.runOppAvg,
    this.runOppBest,
    this.runOppBestName,
    this.runOppBestTitle,
    this.trackedCurrent = false,
    this.trackedTop500 = false,
    this.updatedAt,
  });

  final int fideId;
  final StreakTimeClass timeClass;

  /// As stored ("Surname, First"); use [displayName] for UI.
  final String name;
  final String? title;

  /// FIDE federation code, e.g. "IND".
  final String? fed;
  final String? sex;

  /// FIDE rating in THIS time class.
  final int? rating;
  final int? birthYear;
  final int? age;
  final int currentStreak;
  final int bestStreak;
  final DateTime? bestStreakAt;
  final int wins;
  final int losses;
  final String? anchorLossGameDay;
  final String? streakStartGameDay;
  final String? lastGameDay;
  final String? lastResult;

  /// Average rating of the rated opponents beaten in the current run.
  final int? runOppAvg;

  /// Strongest opponent beaten in the current run.
  final int? runOppBest;
  final String? runOppBestName;
  final String? runOppBestTitle;

  /// Playing in a broadcast right now.
  final bool trackedCurrent;
  final bool trackedTop500;
  final DateTime? updatedAt;

  StreakLevel get level => streakLevel(currentStreak);

  /// "Carlsen, Magnus" → "Magnus Carlsen".
  String get displayName => streakDisplayName(name);

  /// Surname only, for tight tiles.
  String get shortName => name.split(',').first.trim();

  static const selectColumns =
      'fide_id,time_class,name,title,fed,sex,rating,birth_year,age,'
      'current_streak,best_streak,best_streak_at,wins,losses,'
      'anchor_loss_game_day,streak_start_game_day,last_game_day,last_result,'
      'run_opp_avg,run_opp_best,run_opp_best_name,run_opp_best_title,'
      'tracked_current,tracked_top500,updated_at';

  /// Rows are untrusted: a bad field becomes null, never a thrown render.
  static StreakRow? fromJson(Map<String, dynamic> raw) {
    final fideId = _int(raw['fide_id']);
    final name = _text(raw['name']);
    final tc = StreakTimeClassX.tryParse(raw['time_class']);
    if (fideId == null || fideId <= 0 || name == null || tc == null) {
      return null;
    }
    final birthYear = _int(raw['birth_year']);
    final listedAge = _int(raw['age']);
    return StreakRow(
      fideId: fideId,
      timeClass: tc,
      name: name,
      title: _upper(raw['title']),
      fed: _upper(raw['fed']),
      sex: _upper(raw['sex']),
      rating: _int(raw['rating']),
      birthYear: birthYear,
      age: (listedAge != null && listedAge > 0 && listedAge < 120)
          ? listedAge
          : streakAgeFromBirthYear(birthYear),
      currentStreak: (_int(raw['current_streak']) ?? 0).clamp(0, 1 << 20),
      bestStreak: (_int(raw['best_streak']) ?? 0).clamp(0, 1 << 20),
      bestStreakAt: DateTime.tryParse(_text(raw['best_streak_at']) ?? ''),
      wins: _int(raw['wins']) ?? 0,
      losses: _int(raw['losses']) ?? 0,
      anchorLossGameDay: _text(raw['anchor_loss_game_day']),
      streakStartGameDay: _text(raw['streak_start_game_day']),
      lastGameDay: _text(raw['last_game_day']),
      lastResult: _text(raw['last_result']),
      runOppAvg: _int(raw['run_opp_avg']),
      runOppBest: _int(raw['run_opp_best']),
      runOppBestName: _text(raw['run_opp_best_name']),
      runOppBestTitle: _upper(raw['run_opp_best_title']),
      trackedCurrent: _flag(raw['tracked_current']),
      trackedTop500: _flag(raw['tracked_top500']),
      updatedAt: DateTime.tryParse(_text(raw['updated_at']) ?? ''),
    );
  }
}

/// One decisive game in a class history (the `games` jsonb array).
@immutable
class StreakGame {
  const StreakGame({
    required this.gameId,
    required this.result,
    this.gameDay,
    this.color,
    this.opponentName,
    this.opponentTitle,
    this.opponentFed,
    this.opponentRating,
    this.tourId,
    this.tourName,
    this.roundId,
    this.roundName,
    this.sortAt,
    this.streakAfter = 0,
  });

  final String gameId;

  /// 'win' or 'loss' (only decisive games are stored).
  final String result;
  final String? gameDay;
  final String? color;
  final String? opponentName;
  final String? opponentTitle;
  final String? opponentFed;
  final int? opponentRating;
  final String? tourId;
  final String? tourName;
  final String? roundId;
  final String? roundName;
  final String? sortAt;
  final int streakAfter;

  bool get isWin => result == 'win';

  static StreakGame? fromJson(Map<String, dynamic> raw) {
    final id = _text(raw['game_id']);
    final r = _text(raw['result'])?.toLowerCase();
    if (id == null || (r != 'win' && r != 'loss')) return null;
    final c = _text(raw['color'])?.toLowerCase();
    return StreakGame(
      gameId: id,
      result: r!,
      gameDay: _text(raw['game_day']),
      color: (c == 'white' || c == 'black') ? c : null,
      opponentName: _text(raw['opponent_name']),
      opponentTitle: _upper(raw['opponent_title']),
      opponentFed: _upper(raw['opponent_fed']),
      opponentRating: _int(raw['opponent_rating']),
      tourId: _text(raw['tour_id']),
      tourName: _text(raw['tour_name']),
      roundId: _text(raw['round_id']),
      roundName: _text(raw['round_name']),
      sortAt: _text(raw['sort_at']),
      streakAfter: (_int(raw['streak_after']) ?? 0).clamp(0, 1 << 20),
    );
  }
}

/// One player's run in one time class, with its latest decisive games.
@immutable
class StreakClassRun {
  const StreakClassRun({
    required this.timeClass,
    required this.currentStreak,
    required this.bestStreak,
    this.bestStreakAt,
    this.wins = 0,
    this.losses = 0,
    this.anchorLossGameDay,
    this.streakStartGameDay,
    this.lastGameDay,
    this.lastResult,
    this.runOppAvg,
    this.runOppBest,
    this.runOppBestName,
    this.runOppBestTitle,
    this.games = const [],
  });

  final StreakTimeClass timeClass;
  final int currentStreak;
  final int bestStreak;
  final DateTime? bestStreakAt;
  final int wins;
  final int losses;
  final String? anchorLossGameDay;
  final String? streakStartGameDay;
  final String? lastGameDay;
  final String? lastResult;
  final int? runOppAvg;
  final int? runOppBest;
  final String? runOppBestName;
  final String? runOppBestTitle;

  /// Oldest first, at most the latest 400.
  final List<StreakGame> games;

  StreakLevel get level => streakLevel(currentStreak);

  static const selectColumns =
      'time_class,current_streak,best_streak,best_streak_at,wins,losses,'
      'anchor_loss_game_day,streak_start_game_day,last_game_day,last_result,'
      'run_opp_avg,run_opp_best,run_opp_best_name,run_opp_best_title,games';

  /// The current run as the site draws it: from the anchor loss on (the loss
  /// included), or the last [currentStreak] games when no loss is stored.
  List<StreakGame> get currentRunGames {
    final lastLoss = games.lastIndexWhere((g) => !g.isWin);
    if (lastLoss >= 0) return games.sublist(lastLoss);
    if (currentStreak <= 0) return const [];
    return games.sublist((games.length - currentStreak).clamp(0, games.length));
  }

  /// Latest win in the current run, if any.
  StreakGame? get latestWin {
    for (final g in currentRunGames.reversed) {
      if (g.isWin) return g;
    }
    return null;
  }

  static StreakClassRun? fromJson(Map<String, dynamic> raw) {
    final tc = StreakTimeClassX.tryParse(raw['time_class']);
    if (tc == null) return null;
    final rawGames = raw['games'];
    final games = <StreakGame>[];
    if (rawGames is List) {
      for (final g in rawGames) {
        if (g is Map) {
          final parsed = StreakGame.fromJson(Map<String, dynamic>.from(g));
          if (parsed != null) games.add(parsed);
        }
      }
    }
    return StreakClassRun(
      timeClass: tc,
      currentStreak: (_int(raw['current_streak']) ?? 0).clamp(0, 1 << 20),
      bestStreak: (_int(raw['best_streak']) ?? 0).clamp(0, 1 << 20),
      bestStreakAt: DateTime.tryParse(_text(raw['best_streak_at']) ?? ''),
      wins: _int(raw['wins']) ?? 0,
      losses: _int(raw['losses']) ?? 0,
      anchorLossGameDay: _text(raw['anchor_loss_game_day']),
      streakStartGameDay: _text(raw['streak_start_game_day']),
      lastGameDay: _text(raw['last_game_day']),
      lastResult: _text(raw['last_result']),
      runOppAvg: _int(raw['run_opp_avg']),
      runOppBest: _int(raw['run_opp_best']),
      runOppBestName: _text(raw['run_opp_best_name']),
      runOppBestTitle: _upper(raw['run_opp_best_title']),
      games: games,
    );
  }
}

/// A player's streak card: profile plus all three classes.
@immutable
class PlayerStreaks {
  const PlayerStreaks({
    required this.fideId,
    required this.name,
    this.title,
    this.fed,
    this.sex,
    this.birthYear,
    this.age,
    this.ratings = const {},
    this.trackedCurrent = false,
    this.runs = const {},
  });

  final int fideId;
  final String name;
  final String? title;
  final String? fed;
  final String? sex;
  final int? birthYear;
  final int? age;
  final Map<StreakTimeClass, int?> ratings;
  final bool trackedCurrent;
  final Map<StreakTimeClass, StreakClassRun> runs;

  String get displayName => streakDisplayName(name);

  StreakClassRun? run(StreakTimeClass tc) => runs[tc];

  /// The class to open on: [asked] when present, else the hottest live run,
  /// else the best-ever, else classical (the site's `pickClass`).
  StreakTimeClass pickClass([StreakTimeClass? asked]) {
    if (asked != null && runs.containsKey(asked)) return asked;
    final list = runs.values.toList()
      ..sort((a, b) {
        final c = b.currentStreak.compareTo(a.currentStreak);
        if (c != 0) return c;
        final bst = b.bestStreak.compareTo(a.bestStreak);
        if (bst != 0) return bst;
        return a.timeClass.index.compareTo(b.timeClass.index);
      });
    return list.isEmpty
        ? (asked ?? StreakTimeClass.standard)
        : list.first.timeClass;
  }

  static const profileColumns =
      'fide_id,name,title,fed,sex,birth_year,rating,rapid_rating,blitz_rating,'
      'tracked_current,tracked_top500';

  static PlayerStreaks? fromJson(
    Map<String, dynamic> profile,
    List<Map<String, dynamic>> classes,
  ) {
    final fideId = _int(profile['fide_id']);
    final name = _text(profile['name']);
    if (fideId == null || fideId <= 0 || name == null) return null;
    final birthYear = _int(profile['birth_year']);
    final runs = <StreakTimeClass, StreakClassRun>{};
    for (final c in classes) {
      final run = StreakClassRun.fromJson(c);
      if (run != null) runs[run.timeClass] = run;
    }
    return PlayerStreaks(
      fideId: fideId,
      name: name,
      title: _upper(profile['title']),
      fed: _upper(profile['fed']),
      sex: _upper(profile['sex']),
      birthYear: birthYear,
      age: streakAgeFromBirthYear(birthYear),
      ratings: {
        StreakTimeClass.standard: _int(profile['rating']),
        StreakTimeClass.rapid: _int(profile['rapid_rating']),
        StreakTimeClass.blitz: _int(profile['blitz_rating']),
      },
      trackedCurrent: _flag(profile['tracked_current']),
      runs: runs,
    );
  }
}

/// "Carlsen, Magnus" → "Magnus Carlsen"; names without a comma pass through.
String streakDisplayName(String raw) {
  final parts = raw.split(',');
  if (parts.length < 2) return raw.trim();
  final first = parts.sublist(1).join(',').trim();
  final last = parts.first.trim();
  return first.isEmpty ? last : '$first $last';
}

/// Wall filter. The time class is which wall you are on, not a filter.
@immutable
class StreakWallFilter {
  const StreakWallFilter({
    this.age = StreakAgeGroup.all,
    this.womenOnly = false,
    this.fed,
    this.title,
    this.playingNow = false,
    this.query = '',
  });

  final StreakAgeGroup age;
  final bool womenOnly;
  final String? fed;
  final String? title;
  final bool playingNow;
  final String query;

  bool get isDefault =>
      age == StreakAgeGroup.all &&
      !womenOnly &&
      fed == null &&
      title == null &&
      !playingNow &&
      query.trim().isEmpty;

  /// The user is looking for someone in particular (a name, a federation, a
  /// title, an age group, women), so the wall searches every player instead
  /// of only those above [kStreakFeaturedMinRating]. "Playing now" alone
  /// keeps the floor: it narrows by time, not by who.
  bool get looksPastFloor =>
      age != StreakAgeGroup.all ||
      womenOnly ||
      fed != null ||
      title != null ||
      query.trim().isNotEmpty;

  bool matches(StreakRow r) {
    if (!age.contains(r.age)) return false;
    if (womenOnly && r.sex != 'F') return false;
    if (fed != null && r.fed != fed) return false;
    if (title != null && r.title != title) return false;
    if (playingNow && !r.trackedCurrent) return false;
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty &&
        !'${r.fideId} ${r.name} ${r.displayName} ${r.fed ?? ''} ${r.title ?? ''}'
            .toLowerCase()
            .contains(q)) {
      return false;
    }
    return true;
  }

  StreakWallFilter copyWith({
    StreakAgeGroup? age,
    bool? womenOnly,
    String? fed,
    bool clearFed = false,
    String? title,
    bool clearTitle = false,
    bool? playingNow,
    String? query,
  }) {
    return StreakWallFilter(
      age: age ?? this.age,
      womenOnly: womenOnly ?? this.womenOnly,
      fed: clearFed ? null : (fed ?? this.fed),
      title: clearTitle ? null : (title ?? this.title),
      playingNow: playingNow ?? this.playingNow,
      query: query ?? this.query,
    );
  }
}
