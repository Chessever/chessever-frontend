import 'dart:io';
import 'dart:math' as math;

import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/widgets/standings_share_image_card.dart';
import 'package:chessever2/utils/share_card.dart';
import 'package:chessever2/widgets/event_card/event_context_menu.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Renders the active tournament's standings to a branded image and opens the
/// Share Image / Share Link preview. Shared by the tournament menu's "Share
/// standings" action and the screenshot nudge on the standings tab, so both
/// produce the same artifact. The link is the event page with the standings tab
/// marker (`?tab=standings`), which renders standings on the web.
Future<void> shareTournamentStandings(
  BuildContext context,
  WidgetRef ref,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final about =
        ref.read(tourDetailScreenProvider).valueOrNull?.aboutTourModel;
    if (about == null || about.name.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Open an event to share its standings.')),
      );
      return;
    }

    final fallbackId =
        about.groupBroadcastId?.isNotEmpty == true
            ? about.groupBroadcastId!
            : about.id;
    final shareUrl = buildEventShareUrl(
      id: fallbackId,
      title: about.name,
      tourId: about.id,
      tourSlug: about.slug,
      tab: kEventStandingsTab,
    );

    final standings = await ref.read(playerTourScreenProvider.future);
    if (!context.mounted) return;
    if (standings.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Standings are still loading. Try again in a moment.'),
        ),
      );
      return;
    }

    final width = math.min(MediaQuery.of(context).size.width, 430.0);
    final imageBytes = await captureCardPng(
      context,
      width: width,
      pixelRatio: 3.0,
      child: StandingsShareImageCard(
        width: width,
        eventName: about.name,
        standings: standings,
      ),
    );
    if (imageBytes == null) {
      throw StateError('Standings share render produced no image');
    }
    if (!context.mounted) return;

    final tempDir = await getTemporaryDirectory();
    final safeName =
        about.name
            .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
            .replaceAll(RegExp(r'^-+|-+$'), '')
            .toLowerCase();
    final file = File(
      '${tempDir.path}/${safeName.isEmpty ? 'chessever-event' : safeName}-standings.png',
    );
    await file.writeAsBytes(imageBytes);
    if (!context.mounted) return;

    final subject =
        about.name.trim().isNotEmpty
            ? '${about.name} standings'
            : 'ChessEver standings';
    await showShareImagePreview(
      context,
      imageBytes: imageBytes,
      onShareImage: () async {
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'image/png')],
          text: shareUrl,
          subject: subject,
          sharePositionOrigin: const Rect.fromLTWH(0, 0, 1, 1),
        );
      },
      onShareLink: () async {
        await Share.share(
          shareUrl,
          subject: subject,
          sharePositionOrigin: const Rect.fromLTWH(0, 0, 1, 1),
        );
      },
    );
  } catch (e) {
    debugPrint('Failed to share standings: $e');
    if (!context.mounted) return;
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Could not share standings. Please try again.'),
      ),
    );
  }
}
