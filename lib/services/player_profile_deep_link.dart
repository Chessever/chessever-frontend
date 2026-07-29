class PlayerProfileDeepLink {
  const PlayerProfileDeepLink({
    required this.fideId,
    this.timeControl,
    this.result,
    this.color,
    this.eco,
  });

  final int fideId;
  final String? timeControl;
  final String? result;
  final String? color;
  final String? eco;

  bool get hasFilters =>
      timeControl != null || result != null || color != null || eco != null;
}

const _timeControls = {'classical', 'rapid', 'blitz'};
const _results = {'win', 'draw', 'loss'};
const _colors = {'white', 'black'};

PlayerProfileDeepLink? parsePlayerProfileDeepLink(Uri uri) {
  List<String> segments;
  if (uri.host == 'player') {
    segments = uri.pathSegments;
  } else if (uri.pathSegments.isNotEmpty &&
      uri.pathSegments.first == 'player') {
    segments = uri.pathSegments.skip(1).toList(growable: false);
  } else {
    return null;
  }

  final gamesIndex = segments.lastIndexOf('games');
  if (gamesIndex <= 0 || gamesIndex != segments.length - 1) return null;

  final fideId = int.tryParse(segments[gamesIndex - 1]);
  if (fideId == null || fideId <= 0) return null;

  String? supported(String key, Set<String> allowed) {
    final value = uri.queryParameters[key]?.trim().toLowerCase();
    return value != null && allowed.contains(value) ? value : null;
  }

  final rawEco = uri.queryParameters['eco']?.trim().toUpperCase();
  final eco =
      rawEco != null && RegExp(r'^[A-E]\d{2}$').hasMatch(rawEco)
          ? rawEco
          : null;

  return PlayerProfileDeepLink(
    fideId: fideId,
    timeControl: supported('time', _timeControls),
    result: supported('result', _results),
    color: supported('color', _colors),
    eco: eco,
  );
}
