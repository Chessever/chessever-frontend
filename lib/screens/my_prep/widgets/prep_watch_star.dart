import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/services/prep_watch.dart';
import 'package:chessever2/screens/my_space/actions/space_shortcut_removal.dart';
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
      prepCanWatch(profile)
          ? "We'll tell you when ${profile.name} plays new games."
          : "Starred. Add ${profile.name}'s Lichess or Chess.com and we'll "
                'tell you when they play new games.',
    );
  }
}

/// A My Space card's star going dark: the profile's pushes stop and its
/// card leaves My Space. Nothing else changes: the profile stays in Prep,
/// and favorites (the heart) are never touched. One Undo restores both.
Future<void> unstarPrepFromSpace(
  BuildContext context,
  PrepProfile profile, {
  required SpaceShortcutRemoval Function() removeFromSpace,
}) async {
  final allowed = await requireFullAuthGuard(context);
  if (!allowed || !context.mounted) return;
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final notifier = container.read(prepProfilesProvider.notifier);

  HapticFeedbackService.light();
  notifier.setWatching(profile.id, false);
  final removal = removeFromSpace();
  AnalyticsService.instance.trackEventDetached(
    'Prep Profile Star Toggled',
    properties: {
      'starred': false,
      'kind': profile.kind.name,
      'via': 'my_space',
    },
  );
  if (messenger != null && messenger.mounted) {
    showAppSnackOn(
      messenger,
      'Unstarred and removed from My Space',
      actionLabel: 'Undo',
      onAction: () {
        notifier.setWatching(profile.id, true);
        removal.undo();
      },
    );
  }
  await removal.written;
}

/// A Prep profile's star, in its top bar and at the end of its rows. Empty,
/// in the same slot, while the profile has nothing to watch or follow.
class PrepWatchStar extends ConsumerWidget {
  const PrepWatchStar({super.key, required this.profileId, this.onUnstar});

  final String profileId;

  /// Replaces the plain unstar (a My Space card also leaves My Space, see
  /// [unstarPrepFromSpace]). Starring is the same everywhere.
  final void Function(PrepProfile profile)? onUnstar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(prepProfileProvider(profileId));
    const slot = SizedBox.square(dimension: kPrepWatchStarSlot);
    if (profile == null || !prepCanStar(profile)) return slot;
    final starred = profile.watching;
    final unstar = onUnstar;
    return Semantics(
      button: true,
      label: starred ? 'Unstar ${profile.name}' : 'Star ${profile.name}',
      child: SizedBox.square(
        dimension: kPrepWatchStarSlot,
        child: InkResponse(
          radius: kPrepWatchStarSlot / 2,
          onTap: () => starred && unstar != null
              ? unstar(profile)
              : togglePrepWatch(context, profile),
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
