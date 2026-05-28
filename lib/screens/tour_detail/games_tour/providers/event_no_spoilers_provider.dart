import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class EventNoSpoilersState {
  const EventNoSpoilersState({this.enabled = false, this.isLoading = true});

  final bool enabled;
  final bool isLoading;

  EventNoSpoilersState copyWith({bool? enabled, bool? isLoading}) {
    return EventNoSpoilersState(
      enabled: enabled ?? this.enabled,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

final eventNoSpoilersProvider = StateNotifierProvider.family<
  EventNoSpoilersController,
  EventNoSpoilersState,
  String
>((ref, tourId) => EventNoSpoilersController(ref: ref, tourId: tourId));

final eventNoSpoilersRevealedGamesProvider =
    StateNotifierProvider<EventNoSpoilersRevealedGamesController, Set<String>>(
      (ref) => EventNoSpoilersRevealedGamesController(),
    );

class EventNoSpoilersRevealedGamesController
    extends StateNotifier<Set<String>> {
  EventNoSpoilersRevealedGamesController() : super(<String>{});

  void reveal(String gameId) {
    if (gameId.isEmpty || state.contains(gameId)) return;
    state = {...state, gameId};
  }

  void hide(String gameId) {
    if (gameId.isEmpty || !state.contains(gameId)) return;
    state = state.where((id) => id != gameId).toSet();
  }
}

class EventNoSpoilersController extends StateNotifier<EventNoSpoilersState> {
  EventNoSpoilersController({required this.ref, required this.tourId})
    : super(const EventNoSpoilersState()) {
    load();
  }

  final Ref ref;
  final String tourId;
  bool _hasLocalOverride = false;

  String get _key => 'event_no_spoilers_$tourId';

  Future<void> load() async {
    if (tourId.isEmpty) {
      state = const EventNoSpoilersState(enabled: false, isLoading: false);
      return;
    }

    try {
      final db = ref.read(appDatabaseProvider);
      final enabled = await db.getBool(_key) ?? false;
      if (_hasLocalOverride) return;
      state = EventNoSpoilersState(enabled: enabled, isLoading: false);
    } catch (_) {
      if (_hasLocalOverride) return;
      state = const EventNoSpoilersState(enabled: false, isLoading: false);
    }
  }

  Future<void> setEnabled(bool enabled) async {
    _hasLocalOverride = true;
    state = state.copyWith(enabled: enabled, isLoading: false);
    if (tourId.isEmpty) return;

    try {
      final db = ref.read(appDatabaseProvider);
      await db.setBool(_key, enabled);
    } catch (_) {
      // Local preference persistence failure should not block the UI toggle.
    }
  }

  Future<void> toggle() => setEnabled(!state.enabled);
}
