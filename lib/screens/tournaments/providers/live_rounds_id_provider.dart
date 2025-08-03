
import 'package:chessever2/repository/supabase/settings/settings_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final liveRoundsIdProvider = AutoDisposeStreamProvider<List<String>>(
      (ref) => ref.read(settingsRepositoryProvider).subscribeToLiveRoundIds(),
);