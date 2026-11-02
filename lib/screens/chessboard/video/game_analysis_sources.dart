import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../tour_detail/games_tour/models/games_tour_model.dart';
import 'video_stream.dart';

typedef GameVideoLookup = ({String gameId, String? pgn});

/// Remote authors remain distinct. A remote copy of an attached segment wins,
/// since discovery can carry richer author/avatar/follow metadata.
///
/// Discovery only adds videos, so a failed lookup is silent: the board keeps
/// the game's attached videos and says nothing, as round streams do.
List<EventVideoStream> gameAnalysisStreams(
  GamesTourModel game,
  AsyncValue<List<Map<String, dynamic>>> discovery,
) {
  final remote = EventVideoStream.readList(
    discovery.isLoading || discovery.hasError
        ? const []
        : discovery.valueOrNull ?? const [],
  );
  final urls = remote.map((stream) => stream.source.url).toSet();
  return [
    ...remote,
    for (final stream in game.collectionVideoStreams)
      if (urls.add(stream.source.url)) stream,
  ];
}
