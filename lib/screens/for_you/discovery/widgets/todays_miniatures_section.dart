import 'dart:async';

import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_game_cards.dart';
import 'package:chessever2/screens/library/miniatures/miniature_game_launcher.dart';
import 'package:chessever2/screens/library/miniatures/miniatures_access.dart';
import 'package:chessever2/screens/library/miniatures_screen.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The Premium outcome the Miniatures boundary sells, from the spec: the
/// same line the Miniatures screen ends its free list on.
const String kMiniaturesUpgradeCta = kMiniaturesArchiveCta;

/// Miniatures: the day's decisive games that ended by move 25, free to
/// open. The date stepper sits in the header: the next day does not exist
/// yet, and every earlier day is the Premium archive.
class TodaysMiniaturesSection extends ConsumerWidget {
  const TodaysMiniaturesSection({super.key, this.now});

  /// Pins "today" in tests.
  final DateTime? now;

  Future<void> _openArchive(BuildContext context, WidgetRef ref) {
    return unlockThen(
      context,
      ref,
      () {
        unawaited(
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const MiniaturesScreen()),
          ),
        );
      },
      featureId: kMiniaturesArchiveFeatureId,
      returnTo: discoveryReturnTo('todays_miniatures'),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscribed = ref.watch(
      subscriptionProvider.select((s) => s.isSubscribed),
    );
    final minis = ref.watch(discoveryTodayMiniaturesProvider);
    final today = now ?? DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        DiscoverySectionHeader(
          title: 'Miniatures',
          trailingReachesEdge: true,
          trailing: DiscoveryDateStepper(
            label: discoveryWeekday(today, now: today),
            previousSemantics: subscribed
                ? 'Earlier days, in the Miniatures archive'
                : 'Earlier days, in the Miniatures archive, Premium',
            nextSemantics: 'Next day',
            previousLocked: !subscribed,
            onPrevious: () => _openArchive(context, ref),
            onNext: null,
            edgeInset: discoveryGutter,
          ),
        ),
        SizedBox(height: 8.w),
        minis.when(
          data: (list) {
            if (list.isEmpty) {
              return const DiscoveryNotice(text: 'No miniatures yet today');
            }
            // Listed as the Miniatures screen lists them; a miniature needs
            // its PGN fetched first, so the launcher opens it.
            return DiscoveryGameList(
              games: [for (final m in list) m.game],
              streamEnabled: false,
              footerFor: (i) => _footer(list[i]),
              onOpen: (games, index) => openMiniatureGame(
                context: context,
                ref: ref,
                games: games,
                index: index,
                returnTo: discoveryReturnTo('todays_miniatures'),
              ),
            );
          },
          loading: () {
            final card = discoveryGridCardWidth(context);
            return DiscoverySkeletonRail(
              width: card,
              height: card + 48.w + 24.w,
            );
          },
          error: (_, __) => DiscoveryNotice(
            text: "Couldn't load today's miniatures",
            actionLabel: 'Retry',
            onAction: () => ref.invalidate(discoveryTodayMiniaturesProvider),
          ),
        ),
        if (!subscribed) ...[
          SizedBox(height: 4.w),
          DiscoveryUpgradeLine(
            label: kMiniaturesUpgradeCta,
            onTap: () => _openArchive(context, ref),
          ),
        ],
      ],
    );
  }

  /// "19 moves · Ø 2751" under a list row: the length is what makes a
  /// miniature. Ratings are never comma-grouped.
  static String _footer(DiscoveryMiniature mini) {
    final avg = discoveryAverageRating(mini.game);
    final unit = mini.moves == 1 ? 'move' : 'moves';
    return [
      '${mini.moves} $unit',
      if (avg != null) 'Ø $avg',
    ].join(' · ');
  }
}
