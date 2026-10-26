import 'package:flutter/cupertino.dart';
import '../../widgets/federation_flag.dart';
import '../core/watch_repository.dart';
import 'watch_widgets.dart';

/// Real event photography, kept small and decoded at watch resolution.
class WatchEventArtwork extends StatelessWidget {
  const WatchEventArtwork({
    super.key,
    required this.repository,
    required this.eventId,
  });
  final WatchRepository repository;
  final String eventId;

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: repository.eventArtwork(eventId),
    builder: (context, snapshot) {
      final image = snapshot.data;
      Widget fallback() => const Icon(
        CupertinoIcons.flag,
        size: 22,
        color: WatchStyle.secondary,
      );
      return SizedBox(
        width: 24,
        height: 24,
        child: image == null
            ? fallback()
            : ClipOval(
                child: Image.network(
                  image,
                  width: 24,
                  height: 24,
                  fit: BoxFit.cover,
                  cacheWidth: (24 * MediaQuery.devicePixelRatioOf(context))
                      .ceil(),
                  excludeFromSemantics: true,
                  errorBuilder: (_, _, _) => fallback(),
                ),
              ),
      );
    },
  );
}

Widget? watchFederation(String? federation) =>
    FederationFlag.hasVisibleFlag(federation)
    ? FederationFlag(federation: federation, width: 21, height: 14)
    : null;
