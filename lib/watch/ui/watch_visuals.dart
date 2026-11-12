import 'package:flutter/cupertino.dart';
import 'package:flutter_watchos/flutter_watchos.dart';
import 'package:intl/intl.dart';
import '../../widgets/federation_flag.dart';
import '../core/watch_models.dart';
import '../core/watch_repository.dart';
import 'watch_widgets.dart';

/// "Next round 14:00", "Next round Fri 16:15", or null once the closest
/// round has started; the card then falls back to the time control.
String? watchNextRound(DateTime? start, DateTime now, {bool use24h = true}) {
  if (start == null || !start.isAfter(now)) return null;
  final time = (use24h ? DateFormat.Hm() : DateFormat.jm()).format(start);
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(start.year, start.month, start.day);
  final days = day.difference(today).inDays;
  final when = switch (days) {
    0 => time,
    1 => 'Tomorrow $time',
    < 7 => '${DateFormat.E().format(start)} $time',
    _ => '${DateFormat.MMMd().format(start)} $time',
  };
  return 'Next round $when';
}

/// An event as a picture: the tournament's own photograph fills the card and
/// the name and next round sit on it. A scrim darkens only the text band at
/// the bottom, so any photo stays readable. Without a photo the card is the
/// house green-black surface, so nothing waits on the network to be legible.
class WatchEventCard extends StatelessWidget {
  const WatchEventCard({
    super.key,
    required this.repository,
    required this.event,
    required this.followed,
    required this.onTap,
  });
  final WatchRepository repository;
  final WatchEvent event;
  final bool followed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final next = watchNextRound(
      event.closestRound,
      DateTime.now(),
      use24h: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final detail = next ?? watchTimeControl(event.timeControl);
    final scale = MediaQuery.textScalerOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Semantics(
        label: [
          event.name,
          if (detail != null && detail.isNotEmpty) detail,
          if (followed) 'Followed on iPhone',
        ].join('. '),
        excludeSemantics: true,
        onTap: () {
          WatchHaptics.click();
          onTap();
        },
        child: WatchPressable(
          onPressed: () {
            WatchHaptics.click();
            onTap();
          },
          builder: (context, pressed) => ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: scale.scale(92)),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ColoredBox(
                      color: pressed
                          ? WatchStyle.surfacePressed
                          : WatchStyle.surface,
                      child: _EventPhoto(
                        repository: repository,
                        eventId: event.id,
                      ),
                    ),
                  ),
                  // Scrim strongest behind the text band, easing to a faint veil
                  // at the top so light badges never wash out the name.
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Color(0xF0000000),
                            Color(0xC7000000),
                            Color(0x8C000000),
                            Color(0x14000000),
                          ],
                          stops: [0, 0.4, 0.68, 1],
                        ),
                      ),
                    ),
                  ),
                  if (pressed)
                    const Positioned.fill(
                      child: ColoredBox(color: Color(0x1FFFFFFF)),
                    ),
                  if (followed)
                    const Positioned(
                      top: 8,
                      right: 9,
                      child: Icon(
                        CupertinoIcons.star_fill,
                        size: 13,
                        color: WatchStyle.ink,
                        shadows: [
                          Shadow(color: Color(0x99000000), blurRadius: 3),
                        ],
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      WatchStyle.contentInset,
                      scale.scale(30),
                      WatchStyle.contentInset,
                      9,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: WatchStyle.body.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            height: 1.18,
                            shadows: const [
                              Shadow(color: Color(0xB3000000), blurRadius: 4),
                            ],
                          ),
                        ),
                        if (detail != null && detail.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: WatchStyle.figures.copyWith(
                              color: const Color(0xFFDCE3D7),
                              shadows: const [
                                Shadow(color: Color(0xB3000000), blurRadius: 3),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EventPhoto extends StatelessWidget {
  const _EventPhoto({required this.repository, required this.eventId});
  final WatchRepository repository;
  final String eventId;

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: repository.eventArtwork(eventId),
    builder: (context, snapshot) {
      final image = snapshot.data;
      if (image == null) return const SizedBox.expand();
      return LayoutBuilder(
        builder: (context, constraints) => Image.network(
          image,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          gaplessPlayback: true,
          excludeFromSemantics: true,
          cacheWidth:
              (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context))
                  .ceil(),
          errorBuilder: (_, _, _) => const SizedBox.expand(),
        ),
      );
    },
  );
}

Widget? watchFederation(String? federation) =>
    FederationFlag.hasVisibleFlag(federation)
    ? FederationFlag(federation: federation, width: 21, height: 14)
    : null;
