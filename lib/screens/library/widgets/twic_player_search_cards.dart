import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/library/providers/library_combined_search_provider.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/services/fide_photo_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/country_utils.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/text_scale.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:chessever2/widgets/hub_tile.dart' show kHubTileInk;
import 'package:chessever2/widgets/media_card.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Maximum number of player cards to display
const int _maxTwicPlayerCards = 4;

/// Provider that extracts top players from the TWIC/library combined search.
/// Mirrors `topSearchedPlayers` from the home page but for `GamebasePlayer`.
final topTwicSearchedPlayersProvider = Provider.autoDispose
    .family<List<GamebasePlayer>, String>((ref, query) {
      final trimmed = query.trim();
      if (trimmed.isEmpty) return const [];

      final searchAsync = ref.watch(libraryCombinedSearchProvider(trimmed));
      return searchAsync.maybeWhen(
        data: (result) {
          if (result.players.isEmpty) return const [];
          final seen = <String>{};
          final unique = <GamebasePlayer>[];
          for (final p in result.players) {
            final key = p.name.toLowerCase().trim();
            if (seen.add(key)) {
              unique.add(p);
              if (unique.length >= _maxTwicPlayerCards) break;
            }
          }
          return unique;
        },
        orElse: () => const [],
      );
    });

/// Player search cards displayed above the TWIC games list.
/// Mirrors the home-page `PlayerSearchCards` aesthetic but consumes
/// `GamebasePlayer` from the gamebase combined search.
class TwicPlayerSearchCards extends ConsumerWidget {
  const TwicPlayerSearchCards({super.key, required this.searchQuery});

  final String searchQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final players = ref.watch(topTwicSearchedPlayersProvider(searchQuery));

    if (players.isEmpty) {
      return const SizedBox.shrink();
    }

    // A short settle into place on a spring; the cards are fully visible
    // from their first frame, never faded in from nothing.
    return MediaCardsEntrance(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 12.h),
        child: _buildPlayerGrid(players),
      ),
    );
  }

  Widget _buildPlayerGrid(List<GamebasePlayer> players) {
    if (players.length == 1) {
      return _TwicPlayerCard(player: players.first, isCompact: false);
    }

    if (players.length == 2) {
      return Row(
        children: [
          Expanded(child: _TwicPlayerCard(player: players[0], isCompact: true)),
          SizedBox(width: 12.sp),
          Expanded(child: _TwicPlayerCard(player: players[1], isCompact: true)),
        ],
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _TwicPlayerCard(player: players[0], isCompact: true),
            ),
            SizedBox(width: 12.sp),
            Expanded(
              child: _TwicPlayerCard(player: players[1], isCompact: true),
            ),
          ],
        ),
        SizedBox(height: 12.sp),
        Row(
          children: [
            Expanded(
              child: _TwicPlayerCard(player: players[2], isCompact: true),
            ),
            SizedBox(width: 12.sp),
            if (players.length > 3)
              Expanded(
                child: _TwicPlayerCard(player: players[3], isCompact: true),
              )
            else
              const Expanded(child: SizedBox()),
          ],
        ),
      ],
    );
  }
}

class _TwicPlayerCard extends ConsumerWidget {
  const _TwicPlayerCard({required this.player, this.isCompact = false});

  final GamebasePlayer player;
  final bool isCompact;

  void _navigateToProfile(BuildContext context) {
    HapticFeedbackService.buttonPress();
    final fideIdInt = int.tryParse(player.fideId.trim());
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerProfileScreen(
          fideId: fideIdInt,
          playerName: player.name,
          title: player.title,
          federation: player.fed,
          rating: player.highestRating,
          gamebasePlayerId: player.id,
        ),
      ),
    );
  }

  /// A media card, one design in both themes (the dark one, [MediaTheme]),
  /// as the home search cards draw it: the player's flag edge to edge in its
  /// own colours, their photo whole at the right edge with its left side
  /// fading into the flag, and the words bottom-left, their full name free
  /// to run over the photo's faded edge, carried by one soft shade out of
  /// that corner ([MediaTextScrim]).
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The vector flag, crisp at the card's size (the small raster flags
    // blur and step when stretched across it), however TWIC writes the
    // federation (a FIDE code, England, a country name); one with no flag
    // of its own (FIDE's neutral players, "Unknown") leaves the card's
    // plain ink.
    final backdrop = MediaFlagBackdrop.ofFederation(player.fed);
    final height = (isCompact ? 108.sp : 120.sp) * context.textGrowth;
    final inset = isCompact ? 12.sp : 14.sp;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _navigateToProfile(context),
      child: MediaTheme(
        child: Builder(
          // The card fills the width it is given: its stack holds only
          // positioned layers (and an empty slot while the photo loads), so
          // nothing inside it sets a width of its own.
          builder: (context) => Container(
            width: double.infinity,
            height: height,
            decoration: BoxDecoration(
              color: kHubTileInk,
              borderRadius: BorderRadius.circular(12.br),
              border: Border.all(color: context.colors.divider, width: 1),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12.br),
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  if (backdrop != null) Positioned.fill(child: backdrop),
                  _PlayerPhotoOverlay(player: player, isCompact: isCompact),
                  Positioned.fill(
                    child: _words(context, padding: EdgeInsets.all(inset)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The card's words, bottom-left: the title badge, the name, the rating
  /// and federation, over the card's whole face and its one shade.
  Widget _words(BuildContext context, {required EdgeInsets padding}) {
    final hasTitle = player.title != null && player.title!.isNotEmpty;
    final nameStyle =
        (isCompact ? AppTypography.textMdBold : AppTypography.textLgBold)
            .copyWith(
              color: kMediaOnInk,
              letterSpacing: 0.3,
              shadows: kMediaTitleShadows,
            );
    return MediaTextScrim(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // The title badge, on its own fill with the label ink that reads
            // on it.
            if (hasTitle)
              Padding(
                padding: EdgeInsets.only(bottom: 4.sp),
                child: MediaTitleBadge(
                  title: player.title!,
                  compact: isCompact,
                ),
              ),
            // A half-width card's name runs the card's full width, over the
            // photo's faded edge, stepping down to a shorter form
            // ("M. Carlsen") only when the full one cannot fit.
            if (isCompact)
              MediaCardName(name: player.displayName, style: nameStyle)
            else
              Text(
                player.displayName,
                style: nameStyle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            SizedBox(height: 2.sp),
            Row(
              children: [
                if (FederationFlag.hasVisibleFlag(player.fed)) ...[
                  FederationFlag(
                    federation: player.fed,
                    width: isCompact ? 14.sp : 16.sp,
                    height: isCompact ? 10.sp : 12.sp,
                    borderRadius: BorderRadius.circular(2.br),
                  ),
                  SizedBox(width: 5.sp),
                ],
                Flexible(
                  child: Text(
                    _buildSubtitle(),
                    style: AppTypography.textXsRegular.copyWith(
                      color: kMediaOnInkQuiet,
                      fontSize: isCompact ? 10.sp : 11.sp,
                      shadows: kMediaCaptionShadows,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _buildSubtitle() {
    final parts = <String>[];

    final rating = player.highestRating;
    if (rating != null && rating > 0) {
      parts.add('$rating');
    }

    final fed = player.fed.trim();
    if (fed.isNotEmpty) {
      final countryName = CountryUtils.getCountryName(fed);
      parts.add(countryName.isNotEmpty ? countryName : fed);
    }

    return parts.join(' • ');
  }
}

/// FIDE photo cache provider — keyed by raw fideId string so empty/non-numeric
/// fall through cleanly to placeholder.
final _twicPlayerPhotoUrlProvider = FutureProvider.family
    .autoDispose<String?, String>((ref, fideId) async {
      if (fideId.isEmpty) return null;
      return FidePhotoService.getPhotoUrlOrNull(fideId);
    });

/// The player's photo ([MediaCardPortrait]), once its address is known.
class _PlayerPhotoOverlay extends ConsumerWidget {
  const _PlayerPhotoOverlay({required this.player, this.isCompact = false});

  final GamebasePlayer player;
  final bool isCompact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photoUrl = ref
        .watch(_twicPlayerPhotoUrlProvider(player.fideId.trim()))
        .valueOrNull;
    if (photoUrl == null) return const SizedBox.shrink();
    return MediaCardPortrait(url: photoUrl, compact: isCompact);
  }
}
