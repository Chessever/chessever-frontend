import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/services/prep_watch.dart';
import 'package:chessever2/services/analytics/analytics_service.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/star_notifications.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The width a profile's top bar keeps for [PrepWatchStar], whether or not
/// the star is drawn, so the name never moves.
const double kPrepWatchStarSlot = 44;

/// Whether [profile]'s top bar has a star slot at all: the reader's own
/// games are never news to them.
bool prepHasWatchSlot(PrepProfile profile) => profile.kind != PrepKind.mine;

/// Stars or unstars [profile]. A starred player is checked every hour, and a
/// push says the same day, while the reader is awake, that they have new
/// online games (twice a day at most). Unstarring stops it.
/// Starring is asking for that push, so it also makes sure it can arrive.
Future<void> togglePrepWatch(BuildContext context, PrepProfile profile) async {
  final allowed = await requireFullAuthGuard(context);
  if (!allowed || !context.mounted) return;
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final watching = !profile.watching;

  HapticFeedbackService.pin();
  container
      .read(prepProfilesProvider.notifier)
      .setWatching(profile.id, watching);
  AnalyticsService.instance.trackEventDetached(
    'Prep Profile Star Toggled',
    properties: {'starred': watching, 'kind': profile.kind.name},
  );
  if (!watching) return;

  final reachable = await makePlayerStarReachable(
    container: container,
    messenger: messenger,
  );
  if (reachable && messenger != null && messenger.mounted) {
    showAppSnackOn(
      messenger,
      "We'll tell you when ${profile.name} plays new games.",
    );
  }
}

/// The star in a Prep profile's top bar. Empty, in the same slot, while the
/// profile has no online account to watch.
class PrepWatchStar extends ConsumerWidget {
  const PrepWatchStar({super.key, required this.profileId});

  final String profileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(prepProfileProvider(profileId));
    const slot = SizedBox.square(dimension: kPrepWatchStarSlot);
    if (profile == null || !prepCanWatch(profile)) return slot;
    final starred = profile.watching;
    return Semantics(
      button: true,
      label: starred ? 'Unstar ${profile.name}' : 'Star ${profile.name}',
      child: SizedBox.square(
        dimension: kPrepWatchStarSlot,
        child: InkResponse(
          radius: kPrepWatchStarSlot / 2,
          onTap: () => togglePrepWatch(context, profile),
          child: Center(
            child: ExcludeSemantics(
              child: SvgWidget(
                starred ? SvgAsset.starFilledIcon : SvgAsset.starIcon,
                semanticsLabel: 'Favorite Icon',
                height: 20.h,
                width: 20.w,
                preserveOriginalColors: starred,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
