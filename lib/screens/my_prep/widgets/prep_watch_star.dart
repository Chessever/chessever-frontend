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
  return _followed(ref, player.fideId, player.name);
}

bool _followed(WidgetRef ref, String? fideId, String name) {
  final favorites =
      ref.watch(favoritePlayersProviderNew).valueOrNull ?? const [];
  return favorites.any(
    (f) => favoritePlayerMatchesIdentity(f, fideId: fideId, playerName: name),
  );
}

/// Stars or unstars [profile] whichever way it is watched: online accounts
/// through [togglePrepWatch], anyone else by following them.
Future<void> togglePrepStar(
  BuildContext context,
  WidgetRef ref,
  PrepProfile profile,
) async {
  final player = prepStarPlayer(profile);
  if (player == null) return togglePrepWatch(context, profile);
  return _toggleFollow(
    context,
    ref,
    fideId: player.fideId,
    name: player.name,
    shownName: profile.name,
    kind: profile.kind.name,
    country: profile.country,
    title: profile.title,
    gamebasePlayerId: profile.databaseAccount?.externalId,
  );
}

/// A My Space card's star when its profile is not on this device (profiles
/// stay on the phone that made them): follows the player by the card's name.
bool prepNameStarred(WidgetRef ref, String name) =>
    _followed(ref, null, name.trim());

Future<void> togglePrepNameStar(
  BuildContext context,
  WidgetRef ref,
  String name,
) => _toggleFollow(
  context,
  ref,
  fideId: null,
  name: name.trim(),
  shownName: name.trim(),
  kind: 'unknown',
);

Future<void> _toggleFollow(
  BuildContext context,
  WidgetRef ref, {
  required String? fideId,
  required String name,
  required String shownName,
  required String kind,
  String? country,
  String? title,
  String? gamebasePlayerId,
}) async {
  final allowed = await requireFullAuthGuard(context);
  if (!allowed || !context.mounted) return;
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final notifier = ref.read(favoritePlayersProviderNew.notifier);
  final starring = !_followed(ref, fideId, name);
  if (starring && !await canAddMoreFavorites(context, ref)) return;
  if (!context.mounted) return;

  HapticFeedbackService.pin();
  try {
    if (starring) {
      await notifier.addFavorite(
        fideId: fideId,
        playerName: name,
        countryCode: country,
        title: title,
        gamebasePlayerId: gamebasePlayerId,
      );
    } else {
      await notifier.removeFavorite(name, fideId: fideId);
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
    properties: {'starred': starring, 'kind': kind, 'via': 'player'},
  );
  if (!starring) return;
  final reachable = await makePlayerStarReachable(
    container: container,
    messenger: messenger,
  );
  if (reachable && messenger != null && messenger.mounted) {
    showAppSnackOn(
      messenger,
      "We'll tell you the moment $shownName sits down at a live board.",
    );
  }
}

/// A Prep profile's star, in its top bar and at the end of its rows. Empty,
/// in the same slot, while the profile has nothing to watch or follow.
class PrepWatchStar extends ConsumerWidget {
  const PrepWatchStar({super.key, required this.profileId, this.fallbackName});

  final String profileId;

  /// The name a My Space card follows when the profile is not on this
  /// device. Without it, a missing profile keeps the slot empty.
  final String? fallbackName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(prepProfileProvider(profileId));
    const slot = SizedBox.square(dimension: kPrepWatchStarSlot);
    final fallback = fallbackName?.trim() ?? '';
    final bool starred;
    final String name;
    final VoidCallback onTap;
    if (profile != null && prepCanStar(profile)) {
      starred = prepStarred(ref, profile);
      name = profile.name;
      onTap = () => togglePrepStar(context, ref, profile);
    } else if (profile == null &&
        fallback.isNotEmpty &&
        // Not while the profiles are still read: it may yet be here.
        ref.watch(prepProfilesProvider).hasValue) {
      starred = prepNameStarred(ref, fallback);
      name = fallback;
      onTap = () => togglePrepNameStar(context, ref, fallback);
    } else {
      return slot;
    }
    return Semantics(
      button: true,
      label: starred ? 'Unstar $name' : 'Star $name',
      child: SizedBox.square(
        dimension: kPrepWatchStarSlot,
        child: InkResponse(
          radius: kPrepWatchStarSlot / 2,
          onTap: onTap,
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
