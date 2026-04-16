import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';

typedef RoundDateResolver = DateTime? Function(GamesAppBarModel model);
typedef RoundHasGames = bool Function(GamesAppBarModel model);

List<GamesAppBarModel> sortRoundsForDisplay(
  List<GamesAppBarModel> models, {
  required RoundDateResolver resolveDate,
  DateTime? now,
}) {
  if (models.length <= 1) return List<GamesAppBarModel>.from(models);

  final effectiveNow = now ?? DateTime.now();
  final allHaveStartTimes = models.every((m) => resolveDate(m) != null);

  if (!allHaveStartTimes) {
    final fallback = List<GamesAppBarModel>.from(models);
    fallback.sort((a, b) {
      final aStarts = resolveDate(a);
      final bStarts = resolveDate(b);
      if (aStarts != null && bStarts != null) {
        final startCompare = bStarts.compareTo(aStarts);
        if (startCompare != 0) return startCompare;
      } else if (aStarts != null) {
        return -1;
      } else if (bStarts != null) {
        return 1;
      }
      return a.name.compareTo(b.name);
    });
    return fallback;
  }

  final focusRound = pickPreferredRoundForSelection(
    models,
    resolveDate: resolveDate,
    now: effectiveNow,
  );

  if (focusRound == null) {
    final fallback = List<GamesAppBarModel>.from(models)
      ..sort((a, b) => _compareByStart(a, b, true, resolveDate));
    return fallback;
  }

  final others = models.where((m) => m.id != focusRound.id).toList();

  final startedOthers =
      others
          .where((m) => _isStartedRound(m, effectiveNow, resolveDate))
          .toList()
        ..sort((a, b) => _compareByStart(a, b, false, resolveDate));

  final futureOthers =
      others
          .where((m) => !_isStartedRound(m, effectiveNow, resolveDate))
          .toList()
        ..sort((a, b) => _compareByStart(a, b, true, resolveDate));

  return [focusRound, ...startedOthers, ...futureOthers];
}

GamesAppBarModel? pickPreferredRoundForSelection(
  List<GamesAppBarModel> models, {
  required RoundDateResolver resolveDate,
  RoundHasGames? hasGames,
  DateTime? now,
}) {
  if (models.isEmpty) return null;

  final effectiveNow = now ?? DateTime.now();
  final allHaveStartTimes = models.every((m) => resolveDate(m) != null);

  bool include(GamesAppBarModel model) => hasGames?.call(model) ?? true;

  final liveRounds =
      models
          .where((m) => m.roundStatus == RoundStatus.live && include(m))
          .toList()
        ..sort((a, b) => _compareByStart(a, b, false, resolveDate));
  if (liveRounds.isNotEmpty) {
    return liveRounds.first;
  }

  if (allHaveStartTimes) {
    final soonUpcoming =
        models.where((m) {
            if (m.roundStatus != RoundStatus.upcoming || !include(m)) {
              return false;
            }
            final starts = resolveDate(m);
            if (starts == null) return false;
            final delta = starts.difference(effectiveNow);
            return delta >= Duration.zero && delta <= const Duration(hours: 2);
          }).toList()
          ..sort((a, b) => _compareByStart(a, b, true, resolveDate));
    if (soonUpcoming.isNotEmpty) {
      return soonUpcoming.first;
    }

    final startedRounds =
        models
            .where(
              (m) =>
                  _isStartedRound(m, effectiveNow, resolveDate) && include(m),
            )
            .toList()
          ..sort((a, b) => _compareByStart(a, b, false, resolveDate));
    if (startedRounds.isNotEmpty) {
      return startedRounds.first;
    }

    final upcomingRounds =
        models
            .where((m) => m.roundStatus == RoundStatus.upcoming && include(m))
            .toList()
          ..sort((a, b) => _compareByStart(a, b, true, resolveDate));
    if (upcomingRounds.isNotEmpty) {
      return upcomingRounds.first;
    }
  }

  for (final status in const [
    RoundStatus.live,
    RoundStatus.ongoing,
    RoundStatus.completed,
    RoundStatus.upcoming,
  ]) {
    final candidates =
        models.where((m) => m.roundStatus == status && include(m)).toList();
    if (candidates.isEmpty) continue;
    final ascending = status == RoundStatus.upcoming;
    candidates.sort((a, b) => _compareByStart(a, b, ascending, resolveDate));
    return candidates.first;
  }

  final fallback = models.where(include);
  if (fallback.isEmpty) return null;
  return fallback.first;
}

bool _isStartedRound(
  GamesAppBarModel model,
  DateTime now,
  RoundDateResolver resolveDate,
) {
  final startsAt = resolveDate(model);
  if (startsAt == null) return false;
  if (model.roundStatus == RoundStatus.live ||
      model.roundStatus == RoundStatus.ongoing ||
      model.roundStatus == RoundStatus.completed) {
    return true;
  }
  return !startsAt.isAfter(now);
}

int _compareByStart(
  GamesAppBarModel a,
  GamesAppBarModel b,
  bool ascending,
  RoundDateResolver resolveDate,
) {
  final aStart = resolveDate(a);
  final bStart = resolveDate(b);

  int compare;
  if (aStart == null && bStart == null) {
    compare = a.name.compareTo(b.name);
  } else if (aStart == null) {
    compare = 1;
  } else if (bStart == null) {
    compare = -1;
  } else {
    compare = aStart.compareTo(bStart);
    if (compare == 0) {
      compare = a.name.compareTo(b.name);
    }
  }

  return ascending ? compare : -compare;
}
