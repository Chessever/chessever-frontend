import 'dart:typed_data';

import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/services/prep_analysis.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_common.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_button.dart' show TappableScale;
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:flutter/material.dart';

/// Which side the prepared player had.
enum PrepSide { both, white, black }

/// Desktop's date windows anchor to the latest downloaded game, so historical
/// players can be studied without an empty window relative to today's date.
enum PrepStatsWindow {
  all('All dates', null),
  year('1 year', 365),
  sixMonths('6 months', 180),
  ninetyDays('90 days', 90),
  thirtyDays('30 days', 30);

  const PrepStatsWindow(this.label, this.days);
  final String label;
  final int? days;
}

/// The slice of games every tab of a profile shows.
@immutable
class PrepFilter {
  const PrepFilter({
    this.source,
    this.speed,
    this.side = PrepSide.both,
    this.accountKey,
    this.accountFile,
    this.outcome,
    this.year,
    this.eco,
    this.opening,
    this.opponent,
    this.length,
    this.window = PrepStatsWindow.all,
    this.base,
  });

  final PrepSource? source;
  final PrepTimeControl? speed;
  final PrepSide side;
  final String? accountKey;
  final String? accountFile;
  final PrepOutcome? outcome;
  final int? year;
  final String? eco;
  final String? opening;
  final String? opponent;

  /// Games of one length: an index into [PrepStats.lengthLabels].
  final int? length;
  final PrepStatsWindow window;
  final GameFilter? base;

  bool get isActive => source != null || accountKey != null || narrows;

  /// Whether anything but the choice of source narrows the games. A source
  /// read alone is the whole of what About shows, not a slice of it.
  bool get narrows =>
      speed != null ||
      side != PrepSide.both ||
      window != PrepStatsWindow.all ||
      hasFacets;

  /// How many narrowings are on, for the filter button's badge.
  int get activeCount =>
      [
        source != null || accountKey != null,
        speed != null,
        side != PrepSide.both,
        window != PrepStatsWindow.all,
        outcome != null,
        year != null,
        eco != null,
        opening != null,
        opponent != null,
        length != null,
        base?.hasActiveSorts ?? false,
      ].where((on) => on).length +
      (base?.activeFilterCount ?? 0);

  /// Context for the current slice, without keeping its controls on screen.
  String get summary =>
      [if (source != null) source!.label, ...labels].join(' · ');

  /// What narrows the games within their source, one name a narrowing.
  List<String> get labels => [
    if (speed != null) speed!.label,
    if (side != PrepSide.both) side == PrepSide.white ? 'White' : 'Black',
    if (window != PrepStatsWindow.all) window.label,
    if (outcome != null)
      switch (outcome!) {
        PrepOutcome.win => 'Wins',
        PrepOutcome.draw => 'Draws',
        PrepOutcome.loss => 'Losses',
        PrepOutcome.unknown => 'Unfinished',
      },
    if (year != null) '$year',
    if (eco != null) eco!,
    if (opening != null) opening!,
    if (opponent != null) opponent!,
    if (length != null) '${PrepStats.lengthLabels[length!]} moves',
    if (base?.hasActiveFilters ?? false)
      '${base!.activeFilterCount} game filters',
    if (base?.hasActiveSorts ?? false) '${base!.activeSortCount} sort keys',
  ];

  bool get hasFacets =>
      outcome != null ||
      year != null ||
      eco != null ||
      opening != null ||
      opponent != null ||
      length != null ||
      (base?.hasActiveFilters ?? false) ||
      (base?.hasActiveSorts ?? false);

  GameFilter get dialogFilter => (base ?? GameFilter()).copyWith(
    color: switch (side) {
      PrepSide.both => GameColorFilter.all,
      PrepSide.white => GameColorFilter.white,
      PrepSide.black => GameColorFilter.black,
    },
    timeControl: speed == null
        ? base?.timeControl
        : switch (speed!) {
            PrepTimeControl.ultrabullet ||
            PrepTimeControl.bullet ||
            PrepTimeControl.blitz => GameTimeControlFilter.blitz,
            PrepTimeControl.rapid => GameTimeControlFilter.rapid,
            _ => GameTimeControlFilter.classical,
          },
    eco: eco == null ? base?.eco : GameEcoFilter.forCode(eco!),
    minYear: year ?? base?.minYear,
    maxYear: year ?? base?.maxYear,
  );

  PrepFilter withGameFilter(GameFilter value) => copyWith(
    base: value.copyWith(color: GameColorFilter.all),
    side: switch (value.color) {
      GameColorFilter.all => PrepSide.both,
      GameColorFilter.white => PrepSide.white,
      GameColorFilter.black => PrepSide.black,
    },
    speed: null,
    outcome: null,
    year: null,
    eco: null,
    opening: null,
    opponent: null,
    length: null,
  );

  PrepFilter withSpeed(PrepTimeControl? value) => copyWith(
    speed: value,
    base: base?.copyWith(timeControl: GameTimeControlFilter.all),
  );

  // What About offers to choose by. A tap takes a choice and a second tap
  // on it gives it up; every other narrowing stays as it was.

  PrepFilter toggleSpeed(PrepTimeControl value) =>
      withSpeed(speed == value ? null : value);

  PrepFilter toggleOutcome(PrepOutcome value) =>
      copyWith(outcome: outcome == value ? null : value);

  /// A colour taken drops the chosen opening, as on a player's profile: a
  /// line belongs to the colour it was chosen under, and the other colour
  /// may never have had it.
  PrepFilter toggleSide(PrepSide value) => side == value
      ? copyWith(side: PrepSide.both)
      : copyWith(side: value, eco: null, opening: null);

  /// Whether the [eco] line listed under [of] is the chosen one.
  bool holdsOpening(PrepSide of, String? eco) =>
      this.eco != null &&
      eco != null &&
      this.eco!.toUpperCase() == eco.toUpperCase() &&
      (side == PrepSide.both || side == of);

  /// A line is taken with its colour; giving it up leaves the colour.
  PrepFilter toggleOpening(PrepSide of, String eco) => holdsOpening(of, eco)
      ? copyWith(eco: null)
      : copyWith(side: of, eco: eco, opening: null);

  bool holdsOpponent(String name) =>
      opponent != null &&
      opponent!.trim().toLowerCase() == name.trim().toLowerCase();

  PrepFilter toggleOpponent(String name) =>
      copyWith(opponent: holdsOpponent(name) ? null : name);

  PrepFilter toggleYear(int value) =>
      copyWith(year: year == value ? null : value);

  PrepFilter toggleLength(int value) =>
      copyWith(length: length == value ? null : value);

  /// The About numbers for this filter's games among [facets]'. Each group
  /// of choices is counted without its own, so what is chosen keeps the
  /// rest of its group beside it. [ratingAccount] is [PrepStats.of]'s.
  PrepStats stats(PrepFacets facets, {String? ratingAccount}) => facets.stats(
    pick: PrepPick(
      white: switch (side) {
        PrepSide.both => null,
        PrepSide.white => true,
        PrepSide.black => false,
      },
      outcome: outcome,
      speed: speed,
      year: year,
      eco: eco,
      opponent: opponent,
      length: length,
    ),
    scope: _scope(facets),
    ratingAccount: ratingAccount,
  );

  /// The games the narrowings About cannot choose leave in: the source, the
  /// dates and the Games filters. Null where they leave every game.
  Uint8List? _scope(PrepFacets facets) {
    if (source == null &&
        accountFile == null &&
        window == PrepStatsWindow.all &&
        opening == null &&
        base == null) {
      return null;
    }
    final within = PrepFilter(
      source: source,
      accountFile: accountFile,
      window: window,
      opening: opening,
      base: base,
    );
    final since = within._since(facets.games);
    return facets.scoped((
      source,
      accountFile,
      window,
      opening,
      base,
    ), (game) => within.matches(game, since: since));
  }

  PrepFilter copyWith({
    Object? source = _keep,
    Object? speed = _keep,
    PrepSide? side,
    Object? accountKey = _keep,
    Object? accountFile = _keep,
    Object? outcome = _keep,
    Object? year = _keep,
    Object? eco = _keep,
    Object? opening = _keep,
    Object? opponent = _keep,
    Object? length = _keep,
    PrepStatsWindow? window,
    Object? base = _keep,
  }) => PrepFilter(
    source: identical(source, _keep) ? this.source : source as PrepSource?,
    speed: identical(speed, _keep) ? this.speed : speed as PrepTimeControl?,
    side: side ?? this.side,
    accountKey: identical(accountKey, _keep)
        ? this.accountKey
        : accountKey as String?,
    accountFile: identical(accountFile, _keep)
        ? this.accountFile
        : accountFile as String?,
    outcome: identical(outcome, _keep) ? this.outcome : outcome as PrepOutcome?,
    year: identical(year, _keep) ? this.year : year as int?,
    eco: identical(eco, _keep) ? this.eco : eco as String?,
    opening: identical(opening, _keep) ? this.opening : opening as String?,
    opponent: identical(opponent, _keep) ? this.opponent : opponent as String?,
    length: identical(length, _keep) ? this.length : length as int?,
    window: window ?? this.window,
    base: identical(base, _keep) ? this.base : base as GameFilter?,
  );

  bool matches(PrepGame g, {DateTime? since}) =>
      (source == null || g.source == source) &&
      (speed == null || g.speed == speed) &&
      (accountFile == null || g.sourcePath.endsWith(accountFile!)) &&
      (outcome == null || g.outcome == outcome) &&
      (year == null || g.date?.year == year) &&
      (eco == null || g.eco?.trim().toUpperCase() == eco!.toUpperCase()) &&
      (opening == null || g.openingFamily == opening) &&
      (length == null || PrepStats.lengthOf(g.plies) == length) &&
      _matchesBase(g) &&
      (since == null || (g.date != null && !g.date!.isBefore(since))) &&
      // Who the opponent was is only known once the player's side is.
      (opponent == null ||
          (g.playerIsWhite != null &&
              g.opponent.trim().toLowerCase() == opponent!.toLowerCase())) &&
      switch (side) {
        PrepSide.both => true,
        PrepSide.white => g.playerIsWhite == true,
        PrepSide.black => g.playerIsWhite == false,
      };

  bool _matchesBase(PrepGame game) {
    final f = base;
    if (f == null) return true;
    if (f.result.statusValue != null && game.result != f.result.statusValue) {
      return false;
    }
    if (f.color == GameColorFilter.white && game.playerIsWhite != true) {
      return false;
    }
    if (f.color == GameColorFilter.black && game.playerIsWhite != false) {
      return false;
    }
    final clockMatches = switch (f.timeControl) {
      GameTimeControlFilter.all => true,
      GameTimeControlFilter.blitz => const [
        PrepTimeControl.ultrabullet,
        PrepTimeControl.bullet,
        PrepTimeControl.blitz,
      ].contains(game.speed),
      GameTimeControlFilter.rapid => game.speed == PrepTimeControl.rapid,
      GameTimeControlFilter.classical =>
        game.speed == PrepTimeControl.classical,
    };
    if (!clockMatches || !f.eco.matches(game.eco)) return false;
    if (f.online == GameOnlineFilter.online && !game.isOnline) return false;
    if (f.online == GameOnlineFilter.otb && game.isOnline) return false;
    if (f.minYear != GameFilter.defaultMinYear ||
        f.maxYear != DateTime.now().year) {
      final year = game.date?.year;
      if (year == null || year < f.minYear || year > f.maxYear) return false;
    }
    if (f.minRating != GameFilter.defaultMinRating ||
        f.maxRating != GameFilter.absoluteMaxRating) {
      final rating = game.averageElo?.floor();
      if (rating == null || rating < f.minRating || rating > f.maxRating) {
        return false;
      }
    }
    final maxMoves = f.finish.maxMoveNumber;
    return maxMoves == null ||
        (game.plies > 0 && (game.plies + 1) ~/ 2 <= maxMoves);
  }

  List<PrepGame> apply(List<PrepGame> games) {
    if (source == null &&
        accountFile == null &&
        speed == null &&
        side == PrepSide.both &&
        !hasFacets &&
        window == PrepStatsWindow.all) {
      return games;
    }
    final since = _since(games);
    return [
      for (final game in games)
        if (matches(game, since: since)) game,
    ];
  }

  /// Where the date window opens: its length back from the latest game of
  /// the source read. Null without a window.
  DateTime? _since(List<PrepGame> games) {
    final days = window.days;
    if (days == null) return null;
    DateTime? latest;
    for (final game in games) {
      if (source != null && game.source != source) continue;
      if (accountFile != null && !game.sourcePath.endsWith(accountFile!)) {
        continue;
      }
      final date = game.date;
      if (date != null && (latest == null || date.isAfter(latest))) {
        latest = date;
      }
    }
    return latest?.subtract(Duration(days: days));
  }
}

const Object _keep = Object();

/// Sort only the Games presentation; statistics retain chronological input.
List<PrepGame> prepSortGames(
  List<PrepGame> games,
  List<GameSortCriterion> sorts,
) {
  if (sorts.isEmpty) return games;
  num? value(PrepGame game, GamebaseSortField field) => switch (field) {
    GamebaseSortField.date => game.date?.millisecondsSinceEpoch,
    GamebaseSortField.whiteElo => game.whiteElo,
    GamebaseSortField.blackElo => game.blackElo,
    GamebaseSortField.avgElo => game.averageElo,
  };
  return List<PrepGame>.of(games)..sort((a, b) {
    for (final sort in sorts) {
      final av = value(a, sort.field);
      final bv = value(b, sort.field);
      // Unknown dates/ratings remain at the end in either direction.
      if (av == null && bv != null) return 1;
      if (bv == null && av != null) return -1;
      if (av == null) continue;
      final comparison = av.compareTo(bv!);
      if (comparison != 0) {
        return sort.direction == GamebaseSortDirection.asc
            ? comparison
            : -comparison;
      }
    }
    return a.index.compareTo(b.index);
  });
}

/// A compact toggle chip; filled ink when on.
class PrepChip extends StatelessWidget {
  const PrepChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.leading,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? leading;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ink = selected ? colors.textInverse : colors.textPrimary;
    return Padding(
      padding: EdgeInsets.only(right: 6.w),
      child: Semantics(
        button: true,
        selected: selected,
        child: TappableScale(
          scaleDown: 0.97,
          onTap: () {
            HapticFeedbackService.selection();
            onTap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            constraints: const BoxConstraints(minHeight: 44),
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? colors.textPrimary : colors.surface,
              borderRadius: BorderRadius.circular(10.br),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leading != null) ...[leading!, SizedBox(width: 6.w)],
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: AppTypography.textXsMedium.copyWith(color: ink),
                  ),
                ),
                if (count != null) ...[
                  SizedBox(width: 5.w),
                  Text(
                    prepCount(count!),
                    style: AppTypography.textXsRegular.copyWith(
                      color: ink.withValues(alpha: 0.6),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// White / Black / Both, as one segmented row.
class PrepSidePicker extends StatelessWidget {
  const PrepSidePicker({
    super.key,
    required this.side,
    required this.onChanged,
    this.mine = false,
  });

  final PrepSide side;
  final ValueChanged<PrepSide> onChanged;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    String label(PrepSide s) => switch (s) {
      PrepSide.both => 'Both colours',
      PrepSide.white => mine ? 'As White' : 'Their White',
      PrepSide.black => mine ? 'As Black' : 'Their Black',
    };
    return Wrap(
      runSpacing: 6,
      children: [
        for (final s in [PrepSide.white, PrepSide.black, PrepSide.both])
          PrepChip(
            label: label(s),
            selected: side == s,
            onTap: () => onChanged(s),
          ),
      ],
    );
  }
}
