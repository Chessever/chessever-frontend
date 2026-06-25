import 'package:chessever2/screens/group_event/model/about_tour_model.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum GamesTourScreenMode { normal, groupEvent }

final gamesTourScreenModeProvider = StateNotifierProvider((ref) {
  // Only selected tournament data should recreate mode evaluation. Live-tour
  // status churn should not flip the Games tab through loading.
  final tourDetailAsync = ref.watch(
    tourDetailScreenProvider.select(_GamesTourModeDetailSlice.from),
  );

  if (tourDetailAsync.isLoading) {
    return _GamesTourScreenModeNotifier.loading(ref);
  }

  if (tourDetailAsync.hasError) {
    return _GamesTourScreenModeNotifier.error(ref);
  }

  final aboutTourModel = tourDetailAsync.aboutTourModel;

  if (aboutTourModel == null) {
    return _GamesTourScreenModeNotifier.loading(ref);
  }

  // The notifier will read games/pins itself and keep state in sync
  return _GamesTourScreenModeNotifier(ref);
});

class _GamesTourScreenModeNotifier
    extends StateNotifier<AsyncValue<GamesTourScreenMode>> {
  _GamesTourScreenModeNotifier(this.ref) : super(AsyncValue.loading()) {
    _setupListeners();
    _init();
  }

  _GamesTourScreenModeNotifier.loading(this.ref) : super(AsyncValue.loading());

  _GamesTourScreenModeNotifier.error(this.ref) : super(AsyncValue.loading());

  final Ref ref;

  void _setupListeners() {
    // No listeners needed - tournament mode is structural and never changes
    // Once a knockout tournament, always a knockout tournament
    // Once a team tournament, always a team tournament
  }

  Future<void> _init() async {
    // Evaluate mode ONLY ONCE - the tournament structure never changes
    _evaluateMode();
  }

  void _evaluateMode() {
    final tourDetail = ref.read(tourDetailScreenProvider).value;
    if (tourDetail == null) return;

    debugPrint(
      '🔍 Evaluating tournament mode for: ${tourDetail.aboutTourModel.id}',
    );

    final tourId = tourDetail.aboutTourModel.id;
    final knockoutState = ref.read(knockoutTournamentStateProvider(tourId));
    debugPrint(
      '🥊 Knockout state: isKnockout=${knockoutState.isKnockout}, games=${knockoutState.allGames.length}',
    );

    if (knockoutState.isKnockout) {
      debugPrint(
        '🥊 Knockout format active - Using normal mode for match-based display',
      );
      state = const AsyncValue.data(GamesTourScreenMode.normal);
      return;
    }

    // PRIORITY 2: Check for team-based group events
    // Prefer explicit backend/tour metadata when present; fall back to player
    // team metadata for older broadcast payloads.
    final players = tourDetail.aboutTourModel.players;
    final formatString =
        tourDetail.tours
            .where(
              (tourModel) => tourModel.tour.id == tourDetail.aboutTourModel.id,
            )
            .firstOrNull
            ?.tour
            .info
            .format;
    final formatSaysTeam = (formatString ?? '').toLowerCase().contains('team');
    final hasAllTeams =
        players.isNotEmpty &&
        players.where((e) => e.team != null).length == players.length;

    debugPrint(
      '👥 Players count: ${players.length}, All have teams: $hasAllTeams',
    );

    if (formatSaysTeam || hasAllTeams) {
      debugPrint('📋 Setting mode to: groupEvent');
      state = AsyncValue.data(GamesTourScreenMode.groupEvent);
    } else {
      debugPrint('📋 Setting mode to: normal');
      state = AsyncValue.data(GamesTourScreenMode.normal);
    }
  }
}

class _GamesTourModeDetailSlice {
  const _GamesTourModeDetailSlice({
    required this.isLoading,
    required this.error,
    required this.aboutTourModel,
  });

  factory _GamesTourModeDetailSlice.from(
    AsyncValue<TourDetailViewModel> value,
  ) {
    return _GamesTourModeDetailSlice(
      isLoading: value.isLoading,
      error: value.error,
      aboutTourModel: value.valueOrNull?.aboutTourModel,
    );
  }

  final bool isLoading;
  final Object? error;
  final AboutTourModel? aboutTourModel;

  bool get hasError => error != null;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _GamesTourModeDetailSlice &&
            other.isLoading == isLoading &&
            other.error == error &&
            other.aboutTourModel == aboutTourModel;
  }

  @override
  int get hashCode => Object.hash(isLoading, error, aboutTourModel);
}
