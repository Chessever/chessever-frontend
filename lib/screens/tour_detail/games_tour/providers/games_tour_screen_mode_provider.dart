import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/knockout_match_detector.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
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
    ref.listen(gamesTourProvider(tourDetail.aboutTourModel.id), (previous, next) {
      if (next.hasValue && next.value != null && next.value!.isNotEmpty) {
        _evaluateMode();
      }
    });
  }

  Future<void> _init() async {
    _evaluateMode();
  }

  void _evaluateMode() {
    final tourDetail = ref.read(tourDetailScreenProvider).value;
    if (tourDetail == null) return;

    print('🔍 Evaluating tournament mode for: ${tourDetail.aboutTourModel.id}');

    // PRIORITY 1: Check for knockout match format FIRST
    // This should override team-based group event detection
    // Knockout tournaments may have team metadata but should display as matches
    final gamesAsync = ref.read(gamesTourProvider(tourDetail.aboutTourModel.id));

    print('📊 Games loaded: ${gamesAsync.hasValue}, Count: ${gamesAsync.value?.length ?? 0}');

    if (gamesAsync.hasValue) {
      final allGames = gamesAsync.value ?? [];
      if (allGames.isNotEmpty) {
        // Convert to GamesTourModel for knockout detection
        final gameModels = <GamesTourModel>[];
        for (final game in allGames) {
          try {
            gameModels.add(GamesTourModel.fromGame(game));
          } catch (_) {}
        }

        print('🎮 Converted ${gameModels.length} games for knockout detection');

        // If knockout format detected, use normal mode (which handles knockout rendering)
        if (KnockoutMatchDetector.isKnockoutMatchFormat(gameModels)) {
          print('🥊 Knockout format detected - Using normal mode for match-based display');
          state = AsyncValue.data(GamesTourScreenMode.normal);
          return;
        } else {
          print('❌ Knockout format NOT detected');
        }
      }
    }

    // PRIORITY 2: Check for team-based group events
    final hasAllTeams = tourDetail.aboutTourModel.players
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
