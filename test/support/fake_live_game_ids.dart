import 'package:chessever2/providers/live_game_ids_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A live-game-id poll ([LiveGameIdsNotifier]) with no server: it holds the
/// answer it is given (null: not answered yet) and records what the page
/// asks of it.
class FakeLiveGameIds extends StateNotifier<LiveGameIds>
    implements LiveGameIdsNotifier {
  FakeLiveGameIds([super.state]);

  /// How many times the page asked again ([refresh]).
  int refreshes = 0;

  /// Every [visible] the page set, in order.
  final List<bool> visibility = <bool>[];

  bool _visible = true;

  @override
  bool get visible => _visible;

  @override
  set visible(bool value) {
    visibility.add(value);
    _visible = value;
  }

  @override
  Duration get poll => const Duration(seconds: 30);

  @override
  Future<void> refresh() async => refreshes++;

  /// The server's next answer.
  void answer(Set<String>? ids) => state = ids;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
