import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Tabs of the Miniatures screen, in display order. About leads because it
/// explains what a miniature is before the lists show any.
enum MiniaturesScreenMode { about, games, players }

const Map<MiniaturesScreenMode, String> miniaturesModeNames = {
  MiniaturesScreenMode.about: 'About',
  MiniaturesScreenMode.games: 'Games',
  MiniaturesScreenMode.players: 'Players',
};

/// Games is the landing tab even though About sits first in the strip — the
/// list is the point of the screen, About is there to be looked up. The
/// screen's PageController seeds its initial page from this, so changing it
/// changes where the screen opens.
final selectedMiniaturesModeProvider =
    StateProvider.autoDispose<MiniaturesScreenMode>(
      (ref) => MiniaturesScreenMode.games,
    );
