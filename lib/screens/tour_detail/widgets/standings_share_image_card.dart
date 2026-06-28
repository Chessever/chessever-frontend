import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/utils/location_service_provider.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/widgets/player_initials_avatar.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const Size standingsShareImageSize = Size(574, 1280);

int standingsShareRowLimit(int standingsCount) {
  if (standingsCount <= 10) return standingsCount;
  return standingsCount < 12 ? standingsCount : 12;
}

bool standingsShareShowsFooter(int standingsCount) => standingsCount <= 10;

class StandingsShareImageCard extends StatelessWidget {
  const StandingsShareImageCard({
    super.key,
    required this.eventName,
    required this.standings,
  });

  final String eventName;
  final List<PlayerStandingModel> standings;

  @override
  Widget build(BuildContext context) {
    final rows = standings.take(standingsShareRowLimit(standings.length));
    final showFooter = standingsShareShowsFooter(standings.length);

    return MediaQuery(
      data: const MediaQueryData(size: standingsShareImageSize),
      child: Material(
        color: const Color(0xFF070708),
        child: SizedBox.fromSize(
          size: standingsShareImageSize,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 44,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      eventName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                for (final player in rows)
                  _ShareStandingRow(
                    player: player,
                    rank: player.overallRank ?? standings.indexOf(player) + 1,
                  ),
                if (showFooter) const Spacer(),
                if (showFooter) const _ShareFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShareStandingRow extends ConsumerWidget {
  const _ShareStandingRow({required this.player, required this.rank});

  final PlayerStandingModel player;
  final int rank;

  String _initials(String name) {
    final parts = name.split(',');
    if (parts.length > 1) {
      final last = parts[0].trim();
      final first = parts[1].trim();
      return '${last.isNotEmpty ? last[0] : ''}${first.isNotEmpty ? first[0] : ''}'
          .toUpperCase();
    }
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.length >= 2) {
      return '${words[0].isNotEmpty ? words[0][0] : ''}${words[1].isNotEmpty ? words[1][0] : ''}'
          .toUpperCase();
    }
    return name.isEmpty
        ? ''
        : name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photoAsync = ref.watch(playerPhotoProvider(player.fideId));
    final validCountryCode = ref
        .read(locationServiceProvider)
        .getValidCountryCode(player.countryCode);

    return Container(
      height: 98,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF17171A), width: 1)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              rank.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF8A8A90),
                fontSize: 20,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 14),
          photoAsync.when(
            data:
                (photoUrl) => PlayerInitialsAvatar(
                  photoUrl: photoUrl,
                  initials: _initials(player.name),
                  size: 64,
                  borderRadius: 12,
                  title: player.title,
                ),
            loading:
                () => PlayerInitialsAvatar(
                  initials: _initials(player.name),
                  size: 64,
                  borderRadius: 12,
                  title: player.title,
                ),
            error:
                (_, __) => PlayerInitialsAvatar(
                  initials: _initials(player.name),
                  size: 64,
                  borderRadius: 12,
                  title: player.title,
                ),
          ),
          const SizedBox(width: 28),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.1,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    if (player.countryCode.isNotEmpty) ...[
                      SizedBox(
                        width: 22,
                        height: 15,
                        child:
                            player.countryCode.toUpperCase() == 'FID'
                                ? Image.asset(
                                  PngAsset.fideLogo,
                                  fit: BoxFit.contain,
                                )
                                : validCountryCode.isNotEmpty
                                ? CountryFlag.fromCountryCode(
                                  validCountryCode,
                                  theme: const ImageTheme(
                                    height: 15,
                                    width: 22,
                                  ),
                                )
                                : const SizedBox.shrink(),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      player.score.toString(),
                      style: const TextStyle(
                        color: Color(0xFFA0A0A8),
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (player.scoreChange != 0) ...[
                      const SizedBox(width: 6),
                      Text(
                        player.scoreChange > 0
                            ? '+${player.scoreChange}'
                            : '${player.scoreChange}',
                        style: TextStyle(
                          color:
                              player.scoreChange > 0
                                  ? const Color(0xFF22C55E)
                                  : const Color(0xFFEF4444),
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Text(
            player.matchScore ?? '',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareFooter extends StatelessWidget {
  const _ShareFooter();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: double.infinity,
      height: 72,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'ChessEver',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 7),
          Text(
            'Follow Chess Better',
            style: TextStyle(
              color: Color(0xFFA5A5AD),
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
