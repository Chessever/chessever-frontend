import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum GamesTourScreenMode { normal, groupEvent }

final gamesTourScreenModeProvider = StateNotifierProvider((ref) {
  // Watch tour details first - this is the primary dependency
  final tourDetailAsync = ref.watch(tourDetailScreenProvider);

  if (tourDetailAsync.isLoading) {
    return _GamesTourScreenModeNotifier.loading(ref);
  }

  if (tourDetailAsync.hasError) {
    return _GamesTourScreenModeNotifier.error(ref);
  }

  final aboutTourModel = tourDetailAsync.valueOrNull?.aboutTourModel;

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
    final tourDetail = ref.read(tourDetailScreenProvider).value;
    if (tourDetail == null) return;

    // Listen to games changes and re-evaluate mode when games are loaded
    ref.listen(gamesTourProvider(tourDetail.aboutTourModel.id), (
      previous,
      next,
    ) {
      if (next.hasValue && next.value != null && next.value!.isNotEmpty) {
        _evaluateMode();
      }
    });

    ref.listen(
      knockoutTournamentStateProvider(tourDetail.aboutTourModel.id),
      (_, __) => _evaluateMode(),
    );
  }

  Future<void> _init() async {
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
    final hasAllTeams =
        tourDetail.aboutTourModel.players
            .where((e) => e.team != null)
            .toList()
            .length ==
        tourDetail.aboutTourModel.players.length;

    debugPrint('👥 All players have teams: $hasAllTeams');

    if (hasAllTeams) {
      debugPrint('📋 Setting mode to: groupEvent');
      state = AsyncValue.data(GamesTourScreenMode.groupEvent);
    } else {
      debugPrint('📋 Setting mode to: normal');
      state = AsyncValue.data(GamesTourScreenMode.normal);
    }
  }
}
