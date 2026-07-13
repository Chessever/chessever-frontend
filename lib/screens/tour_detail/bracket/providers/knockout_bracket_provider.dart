import 'dart:async';

import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/repository/supabase/round/round_repository.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/tour_detail/bracket/models/knockout_bracket.dart';
import 'package:chessever2/screens/tour_detail/bracket/utils/knockout_bracket_builder.dart';
import 'package:chessever2/screens/tour_detail/bracket/utils/knockout_stage_parser.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_rounds_id_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_tour_id_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

typedef KnockoutBracketRoundsLoader =
    Future<Map<String, List<Round>>> Function(List<String> tourIds);

/// Test seam around the repository batch query.
final knockoutBracketRoundsLoaderProvider =
    Provider<KnockoutBracketRoundsLoader>((ref) {
      final repository = ref.watch(roundRepositoryProvider);
      return (tourIds) => repository.getRoundsByTourIds(tourIds);
    });

class _KnockoutBracketSource {
  const _KnockoutBracketSource({
    required this.selectedTour,
    required this.relevantTours,
    required this.fallbackLiveTourIds,
  });

  final Tour selectedTour;
  final List<Tour> relevantTours;
  final Set<String> fallbackLiveTourIds;
}

/// Selected category lane and its stage tours.
///
/// This is synchronous and auto-disposed with tournament detail. Round I/O is
/// owned by [_knockoutBracketRoundsProvider], which can refresh independently
/// when the existing games safety net discovers a newly published round.
final _knockoutBracketSourceProvider =
    Provider.autoDispose<_KnockoutBracketSource?>((ref) {
      final detail = ref.watch(tourDetailScreenProvider).valueOrNull;
      if (detail == null) return null;
      final selectedTourId = detail.aboutTourModel.id;
      if (selectedTourId.isEmpty) return null;

      Tour? selectedTour;
      final siblingTours = <Tour>[];
      for (final model in detail.tours) {
        final tour = model.tour;
        siblingTours.add(tour);
        if (tour.id == selectedTourId) selectedTour = tour;
      }
      if (selectedTour == null) return null;

      // Category separation happens before any repository work. A combined
      // Men/Women broadcast therefore never downloads or models the other
      // lane's rounds/games for this bracket.
      final relevantTours = filterKnockoutSiblingTours(
        selectedTour: selectedTour,
        siblingTours: siblingTours,
      );
      return _KnockoutBracketSource(
        selectedTour: selectedTour,
        relevantTours: List.unmodifiable(relevantTours),
        fallbackLiveTourIds: Set.unmodifiable(detail.liveTourIds),
      );
    });

@immutable
class _KnockoutBracketRoundsRequest {
  _KnockoutBracketRoundsRequest(Iterable<String> tourIds)
    : tourIds = List.unmodifiable(tourIds);

  final List<String> tourIds;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _KnockoutBracketRoundsRequest &&
          listEquals(other.tourIds, tourIds);

  @override
  int get hashCode => Object.hashAll(tourIds);
}

final _knockoutBracketRoundsProvider = StateNotifierProvider.autoDispose.family<
  _KnockoutBracketRoundsNotifier,
  AsyncValue<Map<String, List<Round>>>,
  _KnockoutBracketRoundsRequest
>((ref, request) => _KnockoutBracketRoundsNotifier(ref, request));

/// Owns round metadata for one filtered lane.
///
/// It has no standing poller. It listens to the already-required complete game
/// snapshots and re-runs the one batched rounds query only when a game
/// references a round not present in the current metadata. If games beat their
/// round row into the database, three bounded one-shot retries bridge that
/// publication race. A change to the backend's existing live-round ID list
/// also refreshes once, covering a just-published live round before its first
/// game row arrives. Auto-disposal cancels retries and listeners with the route.
class _KnockoutBracketRoundsNotifier extends KnockoutRoundMetadataCoordinator {
  _KnockoutBracketRoundsNotifier(Ref ref, _KnockoutBracketRoundsRequest request)
    : super(
        tourIds: request.tourIds,
        loadRounds:
            (tourIds) => ref.read(knockoutBracketRoundsLoaderProvider)(tourIds),
        readGames: () {
          final gamesByTourId = <String, List<Games>>{};
          for (final tourId in request.tourIds) {
            final games = ref.read(gamesTourProvider(tourId)).valueOrNull;
            if (games != null) gamesByTourId[tourId] = games;
          }
          return gamesByTourId;
        },
      ) {
    for (final tourId in request.tourIds) {
      ref.listen<AsyncValue<List<Games>>>(gamesTourProvider(tourId), (
        previous,
        next,
      ) {
        if (previous?.valueOrNull == next.valueOrNull) return;
        gamesChanged();
      });
    }

    var lastLiveRoundSignature = _idSignature(
      ref.read(liveRoundsIdProvider).valueOrNull ?? const <String>[],
    );
    ref.listen<AsyncValue<List<String>>>(liveRoundsIdProvider, (
      previous,
      next,
    ) {
      final liveIds = next.valueOrNull;
      if (liveIds == null) return;
      final signature = _idSignature(liveIds);
      if (signature == lastLiveRoundSignature) return;
      lastLiveRoundSignature = signature;
      liveRoundSetChanged();
    });

    start();
  }
}

/// Small async state machine shared by production and the provider race tests.
///
/// Its dependencies are callbacks so tests can deterministically model the
/// database sequence "game row first, round row later" without exposing the
/// private Riverpod family or waiting on real timers.
@visibleForTesting
class KnockoutRoundMetadataCoordinator
    extends StateNotifier<AsyncValue<Map<String, List<Round>>>> {
  KnockoutRoundMetadataCoordinator({
    required Iterable<String> tourIds,
    required Future<Map<String, List<Round>>> Function(List<String> tourIds)
    loadRounds,
    required Map<String, List<Games>> Function() readGames,
    Duration? Function(int scheduledRetryCount)? retryDelay,
    Timer Function(Duration delay, void Function() callback)? createTimer,
  }) : tourIds = List.unmodifiable(tourIds),
       _loadRoundsCallback = loadRounds,
       _readGames = readGames,
       _retryDelay = retryDelay ?? knockoutBracketRoundRetryDelay,
       _createTimer =
           createTimer ?? ((delay, callback) => Timer(delay, callback)),
       super(const AsyncValue.loading());

  final List<String> tourIds;
  final Future<Map<String, List<Round>>> Function(List<String> tourIds)
  _loadRoundsCallback;
  final Map<String, List<Games>> Function() _readGames;
  final Duration? Function(int scheduledRetryCount) _retryDelay;
  final Timer Function(Duration delay, void Function() callback) _createTimer;
  bool _loadInFlight = false;
  bool _reloadAfterLoad = false;
  bool _checkAfterLoad = false;
  String _activeUnknownSignature = '';
  int _scheduledUnknownRetryCount = 0;
  Timer? _unknownRoundRetryTimer;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    _loadRounds(showLoading: true);
  }

  void gamesChanged() => _refreshIfGamesReferenceUnknownRounds();

  void liveRoundSetChanged() {
    _resetUnknownRetryBudget();
    _loadRounds(showLoading: false);
  }

  Future<void> _loadRounds({required bool showLoading}) async {
    if (_loadInFlight) {
      _reloadAfterLoad = true;
      return;
    }

    final previous = state.valueOrNull;
    _unknownRoundRetryTimer?.cancel();
    _unknownRoundRetryTimer = null;
    _loadInFlight = true;
    var loadedSuccessfully = false;
    if (showLoading && previous == null) {
      state = const AsyncValue.loading();
    }

    try {
      final loaded = await _loadRoundsCallback(tourIds);
      if (!mounted) return;
      state = AsyncValue.data(
        Map.unmodifiable({
          for (final tourId in tourIds)
            tourId: List<Round>.unmodifiable(loaded[tourId] ?? const <Round>[]),
        }),
      );
      loadedSuccessfully = true;
    } catch (error, stackTrace) {
      if (!mounted) return;
      // A background refresh must not replace a useful bracket with an error.
      // Initial failures still surface the normal retry state.
      if (previous == null) {
        state = AsyncValue.error(error, stackTrace);
      }
    } finally {
      _loadInFlight = false;
      if (mounted && _reloadAfterLoad) {
        _reloadAfterLoad = false;
        _loadRounds(showLoading: false);
      } else if (mounted && _checkAfterLoad) {
        _checkAfterLoad = false;
        _refreshIfGamesReferenceUnknownRounds();
        if (!_loadInFlight && loadedSuccessfully) {
          _scheduleRetryIfUnknownRoundsRemain();
        }
      } else if (mounted && (loadedSuccessfully || previous != null)) {
        _scheduleRetryIfUnknownRoundsRemain();
      }
    }
  }

  void _refreshIfGamesReferenceUnknownRounds() {
    final roundsByTourId = state.valueOrNull;
    if (roundsByTourId == null) {
      _checkAfterLoad = true;
      return;
    }

    final unknown = knockoutBracketUnknownRoundIds(
      roundsByTourId: roundsByTourId,
      gamesByTourId: _readGames(),
    );
    if (unknown.isEmpty) {
      _clearUnknownRetryState();
      return;
    }

    final signature = _idSignature(unknown);
    if (signature == _activeUnknownSignature) return;
    _unknownRoundRetryTimer?.cancel();
    _unknownRoundRetryTimer = null;
    _activeUnknownSignature = signature;
    _scheduledUnknownRetryCount = 0;
    _loadRounds(showLoading: false);
  }

  void _scheduleRetryIfUnknownRoundsRemain() {
    if (_loadInFlight || _unknownRoundRetryTimer != null) return;
    final roundsByTourId = state.valueOrNull;
    if (roundsByTourId == null) return;

    final unknown = knockoutBracketUnknownRoundIds(
      roundsByTourId: roundsByTourId,
      gamesByTourId: _readGames(),
    );
    if (unknown.isEmpty) {
      _clearUnknownRetryState();
      return;
    }

    final signature = _idSignature(unknown);
    if (signature != _activeUnknownSignature) {
      _activeUnknownSignature = signature;
      _scheduledUnknownRetryCount = 0;
      _loadRounds(showLoading: false);
      return;
    }

    final delay = _retryDelay(_scheduledUnknownRetryCount);
    if (delay == null) return;
    _scheduledUnknownRetryCount += 1;
    _unknownRoundRetryTimer = _createTimer(delay, () {
      _unknownRoundRetryTimer = null;
      if (mounted) _loadRounds(showLoading: false);
    });
  }

  void _resetUnknownRetryBudget() {
    _unknownRoundRetryTimer?.cancel();
    _unknownRoundRetryTimer = null;
    _activeUnknownSignature = '';
    _scheduledUnknownRetryCount = 0;
  }

  void _clearUnknownRetryState() => _resetUnknownRetryBudget();

  @override
  void dispose() {
    _unknownRoundRetryTimer?.cancel();
    _unknownRoundRetryTimer = null;
    super.dispose();
  }
}

const _knockoutBracketRoundRetryBackoff = <Duration>[
  Duration(seconds: 2),
  Duration(seconds: 5),
  Duration(seconds: 12),
];

@visibleForTesting
Duration? knockoutBracketRoundRetryDelay(int scheduledRetryCount) {
  if (scheduledRetryCount < 0 ||
      scheduledRetryCount >= _knockoutBracketRoundRetryBackoff.length) {
    return null;
  }
  return _knockoutBracketRoundRetryBackoff[scheduledRetryCount];
}

@visibleForTesting
Set<String> knockoutBracketUnknownRoundIds({
  required Map<String, List<Round>> roundsByTourId,
  required Map<String, List<Games>> gamesByTourId,
}) {
  final known = <String>{
    for (final rounds in roundsByTourId.values)
      for (final round in rounds) round.id,
  };
  return {
    for (final games in gamesByTourId.values)
      for (final game in games)
        if (game.roundId.isNotEmpty && !known.contains(game.roundId))
          game.roundId,
  };
}

String _idSignature(Iterable<String> ids) {
  final sorted = ids.toSet().toList()..sort();
  return sorted.join('\u0000');
}

/// Complete normalized bracket for the currently selected individual lane.
///
/// Games come from [gamesTourProvider], whose initial repository path pages
/// through the complete tour and whose safety net publishes membership/status
/// changes. Watching every *filtered* stage tour here therefore keeps live
/// scores current without opening board streams or starting a second poller.
final knockoutBracketProvider =
    Provider.autoDispose<AsyncValue<KnockoutBracket>>((ref) {
      final detailState = ref.watch(tourDetailScreenProvider);
      final selectedTourId = detailState.valueOrNull?.aboutTourModel.id;
      final source = ref.watch(_knockoutBracketSourceProvider);

      if (source == null || source.selectedTour.id != selectedTourId) {
        if (detailState.hasError) {
          return AsyncValue.error(
            detailState.error!,
            detailState.stackTrace ?? StackTrace.current,
          );
        }
        return const AsyncValue.loading();
      }

      final request = _KnockoutBracketRoundsRequest(
        source.relevantTours.map((tour) => tour.id),
      );
      final roundsState = ref.watch(_knockoutBracketRoundsProvider(request));
      final roundsByTourId = roundsState.valueOrNull;
      if (roundsByTourId == null && roundsState.hasError) {
        return AsyncValue.error(
          roundsState.error!,
          roundsState.stackTrace ?? StackTrace.current,
        );
      }

      final gamesByTourId = <String, List<Games>>{};
      for (final tour in source.relevantTours) {
        final gamesState = ref.watch(gamesTourProvider(tour.id));
        final games = gamesState.valueOrNull;
        if (games == null) {
          if (gamesState.hasError) {
            return AsyncValue.error(
              gamesState.error!,
              gamesState.stackTrace ?? StackTrace.current,
            );
          }
          return const AsyncValue.loading();
        }
        gamesByTourId[tour.id] = games;
      }
      if (roundsByTourId == null) return const AsyncValue.loading();

      try {
        final liveTourIds =
            ref.watch(liveTourIdProvider).valueOrNull?.toSet() ??
            source.fallbackLiveTourIds;
        final liveRoundIds =
            ref.watch(liveRoundsIdProvider).valueOrNull?.toSet() ??
            const <String>{};
        return AsyncValue.data(
          buildKnockoutBracket(
            selectedTour: source.selectedTour,
            siblingTours: source.relevantTours,
            roundsByTourId: roundsByTourId,
            gamesByTourId: gamesByTourId,
            liveTourIds: liveTourIds,
            liveRoundIds: liveRoundIds,
          ),
        );
      } catch (error, stackTrace) {
        return AsyncValue.error(error, stackTrace);
      }
    });

/// Retry only bracket dependencies. Shared tournament-detail state is intact.
void retryKnockoutBracket(WidgetRef ref) {
  final source = ref.read(_knockoutBracketSourceProvider);
  if (source != null) {
    final request = _KnockoutBracketRoundsRequest(
      source.relevantTours.map((tour) => tour.id),
    );
    ref.invalidate(_knockoutBracketRoundsProvider(request));
    for (final tour in source.relevantTours) {
      ref.invalidate(gamesTourProvider(tour.id));
    }
  }
  ref.invalidate(_knockoutBracketSourceProvider);
}
