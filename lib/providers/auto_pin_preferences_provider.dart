import 'dart:async';

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/local_storage/auto_pin_preferences/auto_pin_preferences_repository.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final autoPinPreferencesProvider =
    AsyncNotifierProvider<AutoPinPreferencesNotifier, AutoPinPreferences>(
      AutoPinPreferencesNotifier.new,
    );

class AutoPinPreferencesNotifier extends AsyncNotifier<AutoPinPreferences> {
  bool _listening = false;

  AutoPinPreferencesRepository get _repo =>
      AutoPinPreferencesRepository(AppDatabase.instance);

  String? get _userId => ref.read(currentUserProvider)?.id;

  @override
  Future<AutoPinPreferences> build() async {
    if (!_listening) {
      _listening = true;
      ref.listen(currentUserProvider, (prev, next) {
        if (prev?.id != next?.id) {
          unawaited(_reloadForUser());
        }
      });
    }

    return _repo.loadPreferences(_userId);
  }

  Future<void> _reloadForUser() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.loadPreferences(_userId));
  }

  Future<void> setFavoritePlayersAutoPin(bool enabled) async {
    final current = state.valueOrNull ?? AutoPinPreferences.defaults;
    final updated = current.copyWith(favoritePlayersAutoPinEnabled: enabled);
    state = AsyncValue.data(updated);
    await _repo.setFavoritePlayersAutoPin(enabled, _userId);
  }

  Future<void> setCountrymenAutoPin(bool enabled) async {
    final current = state.valueOrNull ?? AutoPinPreferences.defaults;
    final updated = current.copyWith(countrymenAutoPinEnabled: enabled);
    state = AsyncValue.data(updated);
    await _repo.setCountrymenAutoPin(enabled, _userId);
  }
}
