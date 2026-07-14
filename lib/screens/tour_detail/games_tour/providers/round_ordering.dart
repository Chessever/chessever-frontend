import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';

typedef RoundDateResolver = DateTime? Function(GamesAppBarModel model);
typedef RoundHasGames = bool Function(GamesAppBarModel model);
typedef RoundIsFullyPlayed = bool Function(GamesAppBarModel model);

const Duration upcomingRoundPromotionWindow = Duration(hours: 2);

List<GamesAppBarModel> sortRoundsForDisplay(
  List<GamesAppBarModel> models, {
  required RoundDateResolver resolveDate,
  RoundHasGames? hasGames,
  RoundIsFullyPlayed? isRoundFullyPlayed,
  DateTime? now,
}) {
  if (models.length <= 1) return List<GamesAppBarModel>.from(models);

  final effectiveNow = now ?? DateTime.now();
  final allHaveStartTimes = models.every((m) => resolveDate(m) != null);
  final useGenericRoundOrder = _shouldUseGenericRoundOrder(models);

  if (!allHaveStartTimes) {
    final started =
        models
            .where((model) => _isStartedRound(model, effectiveNow, resolveDate))
            .toList()
          ..sort((a, b) {
            if (useGenericRoundOrder) {
              final roundCompare = _compareByGenericRoundNumber(a, b);
              if (roundCompare != 0) return roundCompare;
            }
            return _compareByStart(a, b, false, resolveDate);
          });
    final future =
        models
            .where(
              (model) => !_isStartedRound(model, effectiveNow, resolveDate),
            )
            .toList()
          ..sort((a, b) => _compareByStart(a, b, true, resolveDate));
    final promoted = pickUpcomingRoundForPromotion(
      models,
      resolveDate: resolveDate,
      hasGames: hasGames,
      isRoundFullyPlayed: isRoundFullyPlayed,
      now: effectiveNow,
    );
    return <GamesAppBarModel>[
      if (promoted != null) promoted,
      ...started,
      ...future.where((round) => round.id != promoted?.id),
    ];
  }

  final started =
      models
          .where((m) => _isStartedRound(m, effectiveNow, resolveDate))
          .toList()
        ..sort((a, b) {
          if (useGenericRoundOrder) {
            final roundCompare = _compareByGenericRoundNumber(a, b);
            if (roundCompare != 0) return roundCompare;
          }
          return _compareByStart(a, b, false, resolveDate);
        });
  final future =
      models
          .where((m) => !_isStartedRound(m, effectiveNow, resolveDate))
          .toList()
        ..sort((a, b) => _compareByStart(a, b, true, resolveDate));
  final promoted = pickUpcomingRoundForPromotion(
    models,
    resolveDate: resolveDate,
    hasGames: hasGames,
    isRoundFullyPlayed: isRoundFullyPlayed,
    now: effectiveNow,
  );

  return <GamesAppBarModel>[
    if (promoted != null) promoted,
    ...started,
    ...future.where((round) => round.id != promoted?.id),
  ];
}

GamesAppBarModel? pickPreferredRoundForSelection(
  List<GamesAppBarModel> models, {
  required RoundDateResolver resolveDate,
  RoundHasGames? hasGames,
  RoundIsFullyPlayed? isRoundFullyPlayed,
  DateTime? now,
}) {
  if (models.isEmpty) return null;

  final effectiveNow = now ?? DateTime.now();
  final allHaveStartTimes = models.every((m) => resolveDate(m) != null);
  final useGenericRoundOrder = _shouldUseGenericRoundOrder(models);

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
    final startedRounds =
        models
            .where(
              (m) =>
                  _isStartedRound(m, effectiveNow, resolveDate) && include(m),
            )
            .toList()
          ..sort((a, b) {
            if (useGenericRoundOrder) {
              final roundCompare = _compareByGenericRoundNumber(a, b);
              if (roundCompare != 0) return roundCompare;
            }
            return _compareByStart(a, b, false, resolveDate);
          });
    if (startedRounds.isNotEmpty) {
      final latestStarted = startedRounds.first;
      final promoted = pickUpcomingRoundForPromotion(
        models,
        resolveDate: resolveDate,
        hasGames: hasGames,
        isRoundFullyPlayed: isRoundFullyPlayed,
        now: effectiveNow,
      );
      if (promoted != null) {
        return promoted;
      }
      return latestStarted;
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
    candidates.sort((a, b) {
      if (status == RoundStatus.upcoming) {
        return _compareByStart(a, b, true, resolveDate);
      }
      if (useGenericRoundOrder) {
        final roundCompare = _compareByGenericRoundNumber(a, b);
        if (roundCompare != 0) return roundCompare;
      }
      return _compareByStart(a, b, false, resolveDate);
    });
    return candidates.first;
  }

  final fallback = models.where(include);
  if (fallback.isEmpty) return null;
  return fallback.first;
}

GamesAppBarModel? pickUpcomingRoundForPromotion(
  List<GamesAppBarModel> models, {
  required RoundDateResolver resolveDate,
  RoundHasGames? hasGames,
  RoundIsFullyPlayed? isRoundFullyPlayed,
  DateTime? now,
}) {
  final effectiveNow = now ?? DateTime.now();
  bool include(GamesAppBarModel model) => hasGames?.call(model) ?? true;
  bool fullyPlayed(GamesAppBarModel model) =>
      isRoundFullyPlayed?.call(model) ??
      model.roundStatus == RoundStatus.completed;

  final startedRounds = models.where(
    (model) =>
        include(model) && _isStartedRound(model, effectiveNow, resolveDate),
  );
  if (startedRounds.isEmpty || !startedRounds.every(fullyPlayed)) {
    return null;
  }

  final soonUpcoming =
      models.where((model) {
          if (!include(model) || model.roundStatus != RoundStatus.upcoming) {
            return false;
          }
          final startsAt = resolveDate(model);
          if (startsAt == null) return false;
          final timeUntilStart = startsAt.difference(effectiveNow);
          return timeUntilStart >= Duration.zero &&
              timeUntilStart <= upcomingRoundPromotionWindow;
        }).toList()
        ..sort((a, b) => _compareByStart(a, b, true, resolveDate));

  return soonUpcoming.isEmpty ? null : soonUpcoming.first;
}

bool _isStartedRound(
  GamesAppBarModel model,
  DateTime now,
  RoundDateResolver resolveDate,
) {
  if (model.roundStatus == RoundStatus.live ||
      model.roundStatus == RoundStatus.ongoing ||
      model.roundStatus == RoundStatus.completed) {
    return true;
  }
  final startsAt = resolveDate(model);
  if (startsAt == null) return false;
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
    compare = _compareByGenericRoundNumber(a, b, ascending: true);
  } else if (aStart == null) {
    compare = 1;
  } else if (bStart == null) {
    compare = -1;
  } else {
    compare = aStart.compareTo(bStart);
    if (compare == 0) {
      compare = _compareByGenericRoundNumber(a, b, ascending: true);
    }
  }

  return ascending ? compare : -compare;
}

bool _shouldUseGenericRoundOrder(List<GamesAppBarModel> models) {
  if (models.every((model) => model.roundStatus == RoundStatus.upcoming)) {
    return false;
  }

  return models.every((model) => _genericRoundNumber(model.name) != null);
}

int _compareByGenericRoundNumber(
  GamesAppBarModel a,
  GamesAppBarModel b, {
  bool ascending = false,
}) {
  final aNumber = _genericRoundNumber(a.name);
  final bNumber = _genericRoundNumber(b.name);
  if (aNumber == null && bNumber == null) return a.name.compareTo(b.name);
  if (aNumber == null) return 1;
  if (bNumber == null) return -1;

  final numberCompare =
      ascending ? aNumber.compareTo(bNumber) : bNumber.compareTo(aNumber);
  if (numberCompare != 0) return numberCompare;
  return a.name.compareTo(b.name);
}

int? _genericRoundNumber(String name) {
  final match = RegExp(
    r'^round\s+(\d+)$',
    caseSensitive: false,
  ).firstMatch(name.trim());
  return match == null ? null : int.tryParse(match.group(1)!);
}
