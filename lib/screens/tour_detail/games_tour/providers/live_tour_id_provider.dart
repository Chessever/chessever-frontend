import 'package:chessever2/repository/supabase/settings/settings_repository.dart';
import 'package:chessever2/utils/owned_stream.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final liveTourIdProvider = AutoDisposeStreamProvider<List<String>>(
  (ref) => ownedStream(
    ref,
    ref.read(settingsRepositoryProvider).subscribeToLiveTourIds(),
  ),
);
