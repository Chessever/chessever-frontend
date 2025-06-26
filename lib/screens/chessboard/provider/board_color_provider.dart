import 'package:chessever2/providers/board_settings_provider.dart';
import 'package:chessever2/repository/local_storage/board_settings_repository/board_settings_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final boardSettingsProvider = FutureProvider<BoardSettings?>((ref) async {
  final repo = ref.read(boardSettingsRepository);
  return await repo.loadBoardSettings();
});
