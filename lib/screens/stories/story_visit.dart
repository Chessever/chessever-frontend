import 'package:chessever2/providers/for_you_games_provider.dart'
    show forYouSurfaceVisibleProvider;
import 'package:chessever2/screens/stories/story_row_prefs.dart'
    show storyClockProvider, storyDayKey;
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A visit keeps its picks together, even if a circle is opened twice or
/// Today rebuilds. The next visit can choose from what the reader watched.
class StoryVisit {
  StoryVisit(this.startedAt, {int? rotation})
    : rotation =
          rotation ??
          DateTime.utc(
            startedAt.year,
            startedAt.month,
            startedAt.day,
          ).difference(DateTime.utc(1970)).inDays;

  final DateTime startedAt;
  final int rotation;
  String get day => storyDayKey(startedAt);

  final _games = <(String, String), String>{};

  String? pickFor(String slug, String signature) => _games[(slug, signature)];

  void remember(String slug, String signature, String gameId) {
    _games[(slug, signature)] = gameId;
  }
}

/// A brief switch or the viewer closing should leave the reader's picks in
/// place. A return after a minute away, or on another day, makes new picks.
const storyReturnPause = Duration(minutes: 1);

class StoryVisitController extends StateNotifier<StoryVisit> {
  StoryVisitController(this._clock, {required bool visible})
    : _awaySince = visible ? null : _clock(),
      super(StoryVisit(_clock()));

  final DateTime Function() _clock;
  DateTime? _awaySince;

  void visibilityChanged(bool visible) {
    final now = _clock();
    if (!visible) {
      _awaySince ??= now;
      return;
    }
    final away = _awaySince;
    _awaySince = null;
    if (storyDayKey(now) != state.day ||
        (away != null && now.difference(away) >= storyReturnPause)) {
      state = StoryVisit(now, rotation: state.rotation + 1);
    }
  }
}

final storyVisitProvider =
    StateNotifierProvider<StoryVisitController, StoryVisit>((ref) {
      final controller = StoryVisitController(
        ref.watch(storyClockProvider),
        visible: ref.read(forYouSurfaceVisibleProvider),
      );
      ref.listen(forYouSurfaceVisibleProvider, (_, visible) {
        controller.visibilityChanged(visible);
      });
      return controller;
    });
