import 'package:chessever2/config/puzzle_service_config.dart';
import 'package:chessever2/screens/feed/race/race_client.dart';
import 'package:chessever2/screens/feed/race/race_controller.dart';
import 'package:chessever2/screens/my_space/widgets/pixel_flame.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Flames: Puzzle Race's lasting score.
///
/// Every solved puzzle earns flames by its rating (a miss earns none):
///
/// | Rating      | Flames |
/// | ----------- | ------ |
/// | under 1000  | 1      |
/// | 1000-1499   | 2      |
/// | 1500-1999   | 3      |
/// | 2000-2499   | 4      |
/// | 2500 and up | 5      |
///
/// The room counts them as it judges (`apps/race/src/flames.ts`) and keeps
/// them for signed-in accounts; this mirror only fills in where the room's
/// own count is missing (a run the room never confirmed, an older room). Both
/// sides pin the same table in their tests.
int raceFlamesForRating(int rating) {
  if (rating < 1000) return 1;
  if (rating < 1500) return 2;
  if (rating < 2000) return 3;
  if (rating < 2500) return 4;
  return 5;
}

/// The flames [records] earned, counted on this device.
int raceLocalFlames(Iterable<RacePuzzleRecord> records) {
  var total = 0;
  for (final record in records) {
    if (record.solved) total += raceFlamesForRating(record.puzzle.rating);
  }
  return total;
}

/// How hot a flame count burns, as the streak [PixelFlame] reads it: any
/// flames at all burn at its first heat, and it climbs at 100 and 500. The
/// first heat is also the one whose outer tone clears 3:1 on paper.
int raceFlameHeat(int flames) {
  if (flames <= 0) return 0;
  if (flames >= 500) return 20;
  if (flames >= 100) return 10;
  return 5;
}

/// Where a signed-in player's kept flames come from. Overridden in tests.
abstract interface class RaceServerStatsSource {
  /// The kept record; null when there is none to show (a guest, no
  /// service, an older service, or no answer).
  Future<RaceServerStats?> read();
}

/// [RaceServerStatsSource] over the race service. Its own light client, so
/// My Profile can read flames without starting the race's sound engine.
class RaceHttpServerStatsSource implements RaceServerStatsSource {
  const RaceHttpServerStatsSource({required this.api, required this.auth});

  final RaceApi api;
  final RaceAuth auth;

  @override
  Future<RaceServerStats?> read() async {
    if (!api.isConfigured || !auth.signedIn) return null;
    try {
      final auth = this.auth;
      final token = auth is RaceRefreshingAuth
          ? await auth.freshAccessToken()
          : auth.accessToken;
      if (token == null) return null;
      return await api.myStats(token);
    } catch (error) {
      debugPrint('[Race] could not read flames: ${error.runtimeType}');
      return null;
    }
  }
}

final raceServerStatsSourceProvider =
    Provider.autoDispose<RaceServerStatsSource>((ref) {
      final api = RaceHttpApi(baseUrl: kRaceApiUrl);
      ref.onDispose(api.close);
      return RaceHttpServerStatsSource(
        api: api,
        auth: const SupabaseRaceAuth(),
      );
    });

/// The signed-in player's kept flames and bests. Read on every visit; the
/// lobby and My Profile invalidate it when the account or a race changes it.
final raceServerStatsProvider = FutureProvider.autoDispose<RaceServerStats?>(
  (ref) => ref.watch(raceServerStatsSourceProvider).read(),
);

/// The flame total to show: the kept one when the service answered, this
/// device's own count otherwise.
int raceFlameTotal({required RaceServerStats? server, required int local}) =>
    server?.flames ?? local;

/// A flame count with the streak flame beside it: the same pixel flame the
/// Streaks wall burns, hotter as the count grows.
class RaceFlameMark extends StatelessWidget {
  const RaceFlameMark({
    required this.flames,
    this.size = 22,
    this.style,
    this.earned = false,
    super.key,
  });

  final int flames;

  /// The flame's height.
  final double size;
  final TextStyle? style;

  /// Reads as what one run just earned ("+12 flames").
  final bool earned;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final count = flames == 1 ? '1 flame' : '$flames flames';
    final text = earned ? '+$count' : count;
    return Semantics(
      label: earned ? '$count earned' : count,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          PixelFlame(streak: raceFlameHeat(flames), size: size),
          SizedBox(width: size * 0.36),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  style ??
                  AppTypography.textLgBold.copyWith(
                    fontSize: 17,
                    height: 22 / 17,
                    color: colors.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
