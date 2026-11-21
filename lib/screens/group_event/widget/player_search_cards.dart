import 'package:chessever2/repository/supabase/game/games.dart'
    show SearchPlayer;
import 'package:chessever2/repository/gamebase/memorial_player.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/screens/player_profile/utils/player_menu_actions.dart';
import 'package:chessever2/services/fide_photo_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/country_utils.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/text_scale.dart';
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:chessever2/widgets/hub_tile.dart' show kHubTileInk;
import 'package:chessever2/widgets/media_card.dart';
import 'package:chessever2/widgets/search/enhanced_group_broadcast_local_storage.dart'
    show EnhancedSearchResult;
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Maximum number of player cards to display
const int _maxPlayerCards = 4;

/// Up to [limit] (by default [_maxPlayerCards]) distinct players from
/// [results], in the search's own order (relevance, then Elo).
///
/// Taken from the results the screen is already showing, never from a shared
/// query: Home and Events each search independently, so cards read off a
/// global query showed the other tab's players (or none at all on Home).
List<SearchPlayer> topSearchedPlayers(
  EnhancedSearchResult results, {
  int limit = _maxPlayerCards,
}) {
  // Different people with the same display name must remain distinct.
  final seen = <String>{};
  final uniquePlayers = <SearchPlayer>[];
  for (final result in results.playerResults) {
    final player = result.player;
    if (player == null) continue;
    final identity = player.fideId != null && player.fideId! > 0
        ? 'fide:${player.fideId}'
        : (player.memorialSourceIdentity?.trim().isNotEmpty ?? false)
        ? 'memorial:${player.memorialSourceIdentity!.trim().toLowerCase()}'
        : 'name:${player.name.toLowerCase().trim()}';
    if (seen.add(identity)) {
      uniquePlayers.add(player);
      if (uniquePlayers.length >= limit) break;
    }
  }
  return uniquePlayers;
}

/// Player search cards displayed at the top of search results.
/// Shows up to 4 player cards in a grid layout with profile photos and country flags.
class PlayerSearchCards extends StatelessWidget {
  const PlayerSearchCards({
    super.key,
    required this.players,
    this.onOpen,
    this.animateIn = true,
    this.bottomPadding,
  });

  /// From [topSearchedPlayers] on the results being shown.
  final List<SearchPlayer> players;

  /// Under the cards; 16 by default, the Events page's gap to its list. A
  /// page that spaces its own sections passes 0.
  final double? bottomPadding;

  /// Opens a card's player in place of the profile push here: the card
  /// still gives its own tap haptic, then hands the player over (the Search
  /// tab records the pick, then opens the same profile). Its long-press
  /// Open row runs the same path.
  final ValueChanged<SearchPlayer>? onOpen;

  /// The Events page's entrance: the cards settle the last few points into
  /// place on a spring ([MediaCardsEntrance]), visible from their first
  /// frame either way. Off, they simply stand where they are.
  final bool animateIn;

  @override
  Widget build(BuildContext context) {
    if (players.isEmpty) {
      return const SizedBox.shrink();
    }

    final grid = Padding(
      padding: EdgeInsets.only(bottom: bottomPadding ?? 16.sp),
      child: _buildPlayerGrid(players),
    );
    if (!animateIn) return grid;
    return MediaCardsEntrance(child: grid);
  }

  Widget _card(SearchPlayer player, {required bool isCompact}) =>
      _PlayerSearchCard(player: player, isCompact: isCompact, onOpen: onOpen);

  Widget _buildPlayerGrid(List<SearchPlayer> players) {
    if (players.length == 1) {
      // Single player: full-width card
      return _card(players.first, isCompact: false);
    }

    if (players.length == 2) {
      // Two players: single row
      return Row(
        children: [
          Expanded(child: _card(players[0], isCompact: true)),
          SizedBox(width: 12.sp),
          Expanded(child: _card(players[1], isCompact: true)),
        ],
      );
    }

    // 3-4 players: 2x2 grid
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _card(players[0], isCompact: true)),
            SizedBox(width: 12.sp),
            Expanded(child: _card(players[1], isCompact: true)),
          ],
        ),
        SizedBox(height: 12.sp),
        Row(
          children: [
            Expanded(child: _card(players[2], isCompact: true)),
            SizedBox(width: 12.sp),
            if (players.length > 3)
              Expanded(child: _card(players[3], isCompact: true))
            else
              const Expanded(child: SizedBox()), // Empty space for 3 players
          ],
        ),
      ],
    );
  }
}

class _PlayerSearchCard extends ConsumerWidget {
  const _PlayerSearchCard({
    required this.player,
    this.isCompact = false,
    this.onOpen,
  });

  final SearchPlayer player;
  final bool isCompact;
  final ValueChanged<SearchPlayer>? onOpen;

  void _navigateToProfile(BuildContext context) {
    // Navigate to player profile - works with or without fideId
    // Players without fideId will have games fetched by name instead
    HapticFeedbackService.buttonPress();
    final open = onOpen;
    if (open != null) {
      open(player);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerProfileScreen(
          fideId: player.fideId,
          playerName: player.name,
          title: player.title,
          federation: player.fed,
          rating: player.rating,
          gamebasePlayerId: player.gamebasePlayerId,
          memorialSourceIdentity: player.memorialSourceIdentity,
          memorialRouteId: player.memorialRouteId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Long-press lifts the card itself into the shared focus menu, half-width
    // cards included: the copy lays out at the card's own width (never the
    // menu's), so the pressed card stays legible above the blur.
    return CardContextMenu(
      onPreviewTap: () => _navigateToProfile(context),
      actions: (cardContext) => playerMenuActions(
        cardContext,
        ref,
        playerName: player.name,
        fideId: player.fideId,
        title: player.title,
        federation: player.fed,
        rating: player.rating,
        gamebasePlayerId: player.gamebasePlayerId,
        memorialSourceIdentity: player.memorialSourceIdentity,
        memorialRouteId: player.memorialRouteId,
        onOpen: () {
          if (context.mounted) _navigateToProfile(context);
        },
      ),
      child: _buildCard(context, ref),
    );
  }

  /// A media card, one design in both themes (the dark one, [MediaTheme]):
  /// the player's flag edge to edge in its own colours, their photo whole at
  /// the right edge with only its left side fading into the flag, and the
  /// words bottom-left, their full name free to run over the photo's faded
  /// edge, carried by one soft shade out of that corner ([MediaTextScrim]).
  Widget _buildCard(BuildContext context, WidgetRef ref) {
    // The vector flag, crisp at the card's size, however the federation is
    // written; one with no flag of its own (FIDE's neutral players) leaves
    // the card's plain ink.
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
    // Only a flag the package can draw; never its question-mark stand-in.
    final countryCode = MediaFlagBackdrop.flagCodeOf(player.fed);
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
            // Title badge (GM, IM, etc): on its own fill, with the label
            // ink that reads on it.
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
            // ("M. Carlsen") only when the full one cannot fit; a
            // full-width card's runs to two lines.
            if (isCompact)
              MediaCardName(
                name: _formatPlayerName(player.name),
                style: nameStyle,
              )
            else
              Text(
                _formatPlayerName(player.name),
                style: nameStyle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            SizedBox(height: 2.sp),
            // Subtitle: Rating + Country
            Row(
              children: [
                if (countryCode != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2.br),
                    child: CountryFlag.fromCountryCode(
                      countryCode,
                      theme: ImageTheme(
                        width: isCompact ? 14.sp : 16.sp,
                        height: isCompact ? 10.sp : 12.sp,
                      ),
                    ),
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

    if (player.rating != null && player.rating! > 0) {
      parts.add('${player.rating}');
    }

    if (player.fed != null && player.fed!.isNotEmpty) {
      final countryName = CountryUtils.getCountryName(player.fed!);
      if (countryName.isNotEmpty) {
        parts.add(countryName);
      }
    }

    return parts.join(' \u2022 ');
  }

  String _formatPlayerName(String name) {
    // Handle "Lastname, Firstname" format
    if (name.contains(',')) {
      final parts = name.split(',');
      if (parts.length >= 2) {
        return '${parts[1].trim()} ${parts[0].trim()}';
      }
    }
    return name;
  }
}

/// Provider to cache player photo URLs
final _searchPlayerPhotoUrlProvider = FutureProvider.family
    .autoDispose<
      String?,
      ({int? fideId, String playerName, String? memorialSourceIdentity})
    >((ref, request) async {
      final memorialUrl = memorialPlayerPhotoUrl(
        playerName: request.playerName,
        sourceIdentity: request.memorialSourceIdentity,
      );
      final fideId = request.fideId;
      if (fideId == null) return memorialUrl;
      return await FidePhotoService.getPhotoUrlOrNull(fideId.toString()) ??
          memorialUrl;
    });

/// [player]'s photo address, as [_searchPlayerPhotoUrlProvider] looks it up.
AutoDisposeFutureProvider<String?> _photoUrlOf(SearchPlayer player) =>
    _searchPlayerPhotoUrlProvider((
      fideId: player.fideId,
      playerName: player.name,
      memorialSourceIdentity: player.memorialSourceIdentity,
    ));

/// The player's photo ([MediaCardPortrait]), once its address is known.
class _PlayerPhotoOverlay extends ConsumerWidget {
  const _PlayerPhotoOverlay({required this.player, this.isCompact = false});

  final SearchPlayer player;
  final bool isCompact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photoUrl = ref.watch(_photoUrlOf(player)).valueOrNull;
    if (photoUrl == null) return const SizedBox.shrink();
    return MediaCardPortrait(url: photoUrl, compact: isCompact);
  }
}
