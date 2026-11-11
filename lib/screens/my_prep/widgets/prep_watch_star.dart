import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/services/prep_watch.dart';
import 'package:chessever2/services/analytics/analytics_service.dart';
import 'package:chessever2/utils/favorite_constants.dart';
import 'package:chessever2/utils/favorite_limit_guard.dart';
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
      "We'll tell you when ${profile.name} plays new games.",
    );
  }
}

/// Whether [profile]'s star is lit: its online accounts are watched, or,
/// for a database player, the player is followed (see [prepStarPlayer]).
bool prepStarred(WidgetRef ref, PrepProfile profile) {
  final player = prepStarPlayer(profile);
  if (player == null) return profile.watching;
  final favorites =
      ref.watch(favoritePlayersProviderNew).valueOrNull ?? const [];
  return favorites.any(
    (f) => favoritePlayerMatchesIdentity(
      f,
      fideId: player.fideId,
      playerName: player.name,
    ),
  );
}

/// Stars or unstars [profile] whichever way it is watched: online accounts
/// through [togglePrepWatch], a database player by following them.
Future<void> togglePrepStar(
  BuildContext context,
  WidgetRef ref,
  PrepProfile profile,
) async {
  final player = prepStarPlayer(profile);
  if (player == null) return togglePrepWatch(context, profile);

  final allowed = await requireFullAuthGuard(context);
  if (!allowed || !context.mounted) return;
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final notifier = ref.read(favoritePlayersProviderNew.notifier);
  final starring = !prepStarred(ref, profile);
  if (starring && !await canAddMoreFavorites(context, ref)) return;
  if (!context.mounted) return;

  HapticFeedbackService.pin();
  try {
    if (starring) {
      await notifier.addFavorite(
        fideId: player.fideId,
        playerName: player.name,
        countryCode: profile.country,
        title: profile.title,
        gamebasePlayerId: profile.databaseAccount?.externalId,
      );
    } else {
      await notifier.removeFavorite(player.name, fideId: player.fideId);
    }
  } on FavoriteLimitExceededException {
    // The guard above shows the paywall; a race past it ends here quietly.
    return;
  } catch (error) {
    debugPrint('[MyPrep] player star not saved: $error');
    if (messenger != null && messenger.mounted) {
      showAppSnackOn(
        messenger,
        "Couldn't update the star. Try again.",
        tone: AppSnackTone.danger,
      );
    }
    return;
  }
  AnalyticsService.instance.trackEventDetached(
    'Prep Profile Star Toggled',
    properties: {
      'starred': starring,
      'kind': profile.kind.name,
      'via': 'player',
    },
  );
  if (!starring) return;
  final reachable = await makePlayerStarReachable(
    container: container,
    messenger: messenger,
  );
  if (reachable && messenger != null && messenger.mounted) {
    showAppSnackOn(
      messenger,
      "We'll tell you the moment ${profile.name} sits down at a live board.",
    );
  }
}

/// A Prep profile's star, in its top bar and at the end of its rows. Empty,
/// in the same slot, while the profile has nothing to watch or follow.
class PrepWatchStar extends ConsumerWidget {
  const PrepWatchStar({super.key, required this.profileId});

  final String profileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(prepProfileProvider(profileId));
    const slot = SizedBox.square(dimension: kPrepWatchStarSlot);
    if (profile == null || !prepCanStar(profile)) return slot;
    final starred = prepStarred(ref, profile);
    return Semantics(
      button: true,
      label: starred ? 'Unstar ${profile.name}' : 'Star ${profile.name}',
      child: SizedBox.square(
        dimension: kPrepWatchStarSlot,
        child: InkResponse(
          radius: kPrepWatchStarSlot / 2,
          onTap: () => togglePrepStar(context, ref, profile),
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
