import 'package:chessever2/repository/supabase/settings/settings_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final liveTourIdProvider = AutoDisposeStreamProvider<List<String>>((ref) {
  final settings = ref.watch(liveSettingsProvider).valueOrNull;
  return Stream<List<String>>.value(settings?.liveTourIds ?? const <String>[]);
});
