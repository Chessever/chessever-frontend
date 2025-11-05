import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
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

    print('🔍 Evaluating tournament mode for: ${tourDetail.aboutTourModel.id}');

    final tourId = tourDetail.aboutTourModel.id;
    final knockoutState = ref.read(knockoutTournamentStateProvider(tourId));
    print('🥊 Knockout state: isKnockout=${knockoutState.isKnockout}, games=${knockoutState.allGames.length}');

    if (knockoutState.isKnockout) {
      print('🥊 Knockout format active - Using normal mode for match-based display');
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

    print('👥 All players have teams: $hasAllTeams');

    if (hasAllTeams) {
      print('📋 Setting mode to: groupEvent');
      state = AsyncValue.data(GamesTourScreenMode.groupEvent);
    } else {
      print('📋 Setting mode to: normal');
      state = AsyncValue.data(GamesTourScreenMode.normal);
    }
  }
}
