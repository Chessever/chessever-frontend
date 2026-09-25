import 'dart:async';

import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_game_cards.dart';
import 'package:chessever2/screens/library/miniatures/miniature_game_launcher.dart';
import 'package:chessever2/screens/library/miniatures/miniatures_access.dart';
import 'package:chessever2/screens/library/miniatures_screen.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/time_control_glyph.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The Premium outcome the Miniatures boundary sells, from the spec: the
/// same line the Miniatures screen ends its free list on.
const String kMiniaturesUpgradeCta = kMiniaturesArchiveCta;

/// Miniatures: the day's decisive games that ended by move 25, free to
/// open, as a short preview laid out the way an event's Games tab lays out
/// its games (the viewer's own games view setting). Each grid or board card
/// carries one line over it, "19 moves · Ø 2751": the length is what makes a
/// miniature. Four cards (two boards in board view); "See all" opens the
/// Miniatures screen, where today is free and every earlier day is the
/// Premium archive, and opening any card walks the whole day.
class TodaysMiniaturesSection extends ConsumerWidget {
  const TodaysMiniaturesSection({super.key});

  /// The Miniatures screen. Today is free there and it locks its own
  /// archive, so reaching it needs no paywall.
  static Future<void> open(BuildContext context) {
    HapticFeedbackService.cardTap();
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const MiniaturesScreen()),
    );
  }

  Future<void> _openArchive(BuildContext context, WidgetRef ref) {
    return unlockThen(
      context,
      ref,
      () {
        if (context.mounted) unawaited(open(context));
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        DiscoverySectionHeader(
          title: 'Miniatures',
          trailing: DiscoveryAction(
            label: 'See all',
            arrow: true,
            semanticsLabel: 'See all Miniatures',
            onTap: () => open(context),
          ),
        ),
        SizedBox(height: 8.w),
        minis.when(
          data: (list) {
            if (list.isEmpty) {
              return const DiscoveryNotice(text: 'No miniatures yet today');
            }
            // A miniature needs its PGN fetched first, so the launcher opens
            // it, on the whole day.
            return DiscoveryGameList(
              games: [for (final m in list) m.game],
              limit: kDiscoveryPreviewCards,
              boardLimit: kDiscoveryPreviewBoards,
              streamEnabled: false,
              allowStockfishFallback: false,
              labelFor: (i) => miniatureMeta(list[i]),
              rowLabelFor: (i) => miniatureMeta(list[i]),
              onOpen: (games, index) => openMiniatureGame(
                context: context,
                ref: ref,
                games: games,
                index: index,
                returnTo: discoveryReturnTo('todays_miniatures'),
              ),
            );
          },
          loading: () => DiscoveryGameListSkeleton(
            count: kDiscoveryPreviewCards,
            boardCount: kDiscoveryPreviewBoards,
            labels: true,
            rowLabels: true,
          ),
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
            quiet: true,
            onTap: () => _openArchive(context, ref),
          ),
        ],
      ],
    );
  }

  /// "[owl] 19 moves · Ø 2751" over a grid or board card: the time-control
  /// glyph, then the length as the line's one bold figure, then the average
  /// rating. Ratings are never comma-grouped.
  static Widget miniatureMeta(DiscoveryMiniature mini) {
    final avg = discoveryAverageRating(mini.game);
    final unit = mini.moves == 1 ? ' move' : ' moves';
    final timeControl = mini.game.timeControl?.trim();
    return DiscoveryCardMeta(
      timeControlAsset: TimeControlGlyph.assetForLabel(mini.game.timeControl),
      parts: [
        DiscoveryMetaPart.figure('${mini.moves}', unit: unit),
        if (avg != null) DiscoveryMetaPart.figure('$avg', prefix: 'Ø '),
      ],
      semanticsLabel: [
        '${mini.moves}$unit',
        if (timeControl != null && timeControl.isNotEmpty) timeControl,
        if (avg != null) 'average rating $avg',
      ].join(', '),
    );
  }
}
