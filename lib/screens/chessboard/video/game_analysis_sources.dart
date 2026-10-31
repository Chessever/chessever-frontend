import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../providers/game_video_sources_provider.dart';
import '../../../widgets/app_snack.dart';
import '../../tour_detail/games_tour/models/games_tour_model.dart';
import 'video_stream.dart';

typedef GameVideoLookup = ({String gameId, String? pgn});

/// Remote authors remain distinct. A remote copy of an attached segment wins,
/// since discovery can carry richer author/avatar/follow metadata.
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

/// Report once per failed lookup, including an error cached before mount and
/// each explicit retry. Rebuilds do not replay the notice or resize the board.
/// Never include provider error details or protected URLs in the message.
class GameVideoDiscoveryNotice extends ConsumerStatefulWidget {
  const GameVideoDiscoveryNotice({super.key, required this.lookup});

  final GameVideoLookup lookup;

  @override
  ConsumerState<GameVideoDiscoveryNotice> createState() =>
      _GameVideoDiscoveryNoticeState();
}

class _GameVideoDiscoveryNoticeState
    extends ConsumerState<GameVideoDiscoveryNotice> {
  ProviderSubscription<AsyncValue<List<Map<String, dynamic>>>>? _subscription;
  int _notificationGeneration = 0;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(GameVideoDiscoveryNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lookup != widget.lookup) {
      _subscription?.close();
      _listen();
    }
  }

  void _listen() {
    final provider = gameVideoSourcesProvider(widget.lookup);
    _subscription = ref.listenManual(provider, (previous, next) {
      final generation = ++_notificationGeneration;
      if (next.isLoading || !next.hasError) return;
      if (previous?.hasError == true && previous?.isLoading == false) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _notificationGeneration) return;
        showAppSnack(
          context,
          "Couldn't look up additional game videos. You can keep using the board.",
          tone: AppSnackTone.danger,
          actionLabel: 'Retry',
          onAction: () {
            if (mounted) ref.invalidate(provider);
          },
        );
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
