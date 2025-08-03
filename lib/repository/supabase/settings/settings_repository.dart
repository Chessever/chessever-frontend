import 'dart:async';
import 'package:chessever2/repository/supabase/base_repository.dart';
import 'package:chessever2/repository/supabase/settings/settings.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// providers.dart
final settingsRepositoryProvider = AutoDisposeProvider<SettingsRepository>(
  (ref) => SettingsRepository(),
);

class SettingsRepository extends BaseRepository {
  Future<Settings?> getSettings() => handleApiCall(() async {
    final response = await supabase.from('settings').select().maybeSingle();
    return response != null ? Settings.fromJson(response) : null;
  });

  Stream<List<String>> subscribeToLiveRoundIds() => supabase
      .from('settings')
      .stream(primaryKey: ['id'])
      .map(
        (data) =>
            data.isEmpty
                ? <String>[]
                : List<String>.from(data.first['live_round_ids'] ?? []),
      );

  Stream<List<String>> subscribeToLiveTourIds() => supabase
      .from('settings')
      .stream(primaryKey: ['id'])
      .map(
        (data) =>
            data.isEmpty
                ? <String>[]
                : List<String>.from(data.first['live_tour_ids'] ?? []),
      );

  Stream<List<String>> subscribeToLiveGroupBroadcastIds() => supabase
      .from('settings')
      .stream(primaryKey: ['id'])
      .map(
        (data) =>
            data.isEmpty
                ? <String>[]
                : List<String>.from(
                  data.first['live_group_broadcast_ids'] ?? [],
                ),
      );
}
