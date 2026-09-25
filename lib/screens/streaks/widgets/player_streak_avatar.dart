import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart'
    show playerPhotoProvider;
import 'package:chessever2/screens/streaks/widgets/player_streak_format.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:chessever2/widgets/player_initials_avatar.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The app's player avatar (photo or initials, title strip) with the
/// federation flag cut into its top-right corner, as the Avatar design draws
/// it: the flag's ring is the page colour, so it reads as notched out of the
/// circle rather than stuck on top.
class PlayerStreakAvatar extends ConsumerWidget {
  const PlayerStreakAvatar({
    super.key,
    required this.fideId,
    required this.name,
    required this.size,
    this.title,
    this.fed,
  });

  final int fideId;
  final String name;
  final double size;
  final String? title;
  final String? fed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photo = ref.watch(playerPhotoProvider(fideId)).valueOrNull;
    final showFlag = FederationFlag.hasVisibleFlag(fed);
    final ring = size * 0.028;
    final flagW = size * 0.25;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          PlayerInitialsAvatar(
            photoUrl: photo,
            initials: streakInitials(name),
            size: size,
            title: title,
            isCircular: true,
          ),
          if (showFlag)
            Positioned(
              right: size * 0.02 - ring,
              top: size * 0.02 - ring,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.colors.background,
                  borderRadius: BorderRadius.circular(ring + 2),
                ),
                child: Padding(
                  padding: EdgeInsets.all(ring),
                  child: FederationFlag(
                    federation: fed,
                    width: flagW,
                    height: flagW * 0.75,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
