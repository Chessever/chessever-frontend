import 'package:chessever2/screens/standings/player_standing_sections_provider.dart';
import 'package:chessever2/screens/gamebase/event_view/gamebase_virtual_event_id.dart';
import 'dart:io';
import 'dart:math' as math;

import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/widgets/standings_share_image_card.dart';
import 'package:chessever2/screens/standings/team_standing_model.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_category.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_standings.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/team_tour/team_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/widgets/team_standings_share_image_card.dart';
import 'package:chessever2/utils/share_card.dart';
import 'package:chessever2/widgets/app_snack.dart';
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
  // Combined lists every category's table, so "the standings" is the table
  // the reader has in front of them, not the category selected underneath.
  final combined = combinedStandingsShareTarget(ref);
  if (combined != null) {
    return shareCombinedStandingsSection(
      context,
      ref,
      tourId: combined.tourId,
      teams: combined.teams,
    );
  }

  final messenger = ScaffoldMessenger.of(context);
  try {
    final about = ref
        .read(tourDetailScreenProvider)
        .valueOrNull
        ?.aboutTourModel;
    if (about == null || about.name.isEmpty) {
      showAppSnackOn(messenger, 'Open an event to share its standings.');
      return;
    }

    final detail = ref.read(tourDetailScreenProvider).valueOrNull;
    final tour = detail?.tours
        .where((item) => item.tour.id == about.id)
        .firstOrNull
        ?.tour;
    final section = selectedOfficialPlayerSection(
      tour?.info.playerStandingSections ?? const [],
      ref.read(selectedPlayerStandingSectionProvider(about.id)),
    );
    final standingsTitle = section == null
        ? about.name
        : '${about.name} | ${section.name}';

    final fallbackId = about.groupBroadcastId?.isNotEmpty == true
        ? about.groupBroadcastId!
        : about.id;
    // Gamebase-only virtual events have no page on chessever.com, so their
    // standings image goes out without a (dead) event link.
    final shareUrl = section?.sourceUrl ??
        (isVirtualGamebaseId(about.id)
            ? null
            : buildEventShareUrl(
                id: fallbackId,
                title: about.name,
                tourId: about.id,
                tourSlug: about.slug,
                tab: kEventStandingsTab,
              ));

    final standings = await ref.read(playerTourScreenProvider.future);
    if (!context.mounted) return;
    if (standings.isEmpty) {
      showAppSnackOn(
        messenger,
        'Standings are still loading. Try again in a moment.',
      );
      return;
    }

    await _presentStandingsShare(
      context,
      title: standingsTitle,
      fileStem: about.name,
      fileSuffix: 'standings',
      shareUrl: shareUrl,
      card:
          (width) => StandingsShareImageCard(
            width: width,
            eventName: standingsTitle,
            standings: standings,
          ),
    );
  } catch (e) {
    debugPrint('Failed to share standings: $e');
    if (!context.mounted) return;
    showAppSnackOn(
      messenger,
      'Could not share standings. Please try again.',
      tone: AppSnackTone.danger,
    );
  }
}

/// Renders [card] to an image and opens the Share Image / Share Link preview.
Future<void> _presentStandingsShare(
  BuildContext context, {
  required String title,
  required String fileStem,
  required String fileSuffix,
  required String? shareUrl,
  required Widget Function(double width) card,
}) async {
  final width = math.min(MediaQuery.of(context).size.width, 430.0);
  final imageBytes = await captureCardPng(
    context,
    width: width,
    pixelRatio: 3.0,
    child: card(width),
  );
  if (imageBytes == null) {
    throw StateError('Standings share render produced no image');
  }
  if (!context.mounted) return;

  final tempDir = await getTemporaryDirectory();
  final safeName = fileStem
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '')
      .toLowerCase();
  final file = File(
    '${tempDir.path}/${safeName.isEmpty ? 'chessever-event' : safeName}-$fileSuffix.png',
  );
  await file.writeAsBytes(imageBytes);
  if (!context.mounted) return;

  final subject =
      title.trim().isNotEmpty ? '$title standings' : 'ChessEver standings';
  await showShareImagePreview(
    context,
    imageBytes: imageBytes,
    onShareImage: () async {
      await shareFilesWithText(
        [XFile(file.path, mimeType: 'image/png')],
        text: shareUrl,
        subject: subject,
        sharePositionOrigin: sharePreviewOrigin(),
      );
    },
    onShareLink:
        shareUrl == null
            ? null
            : () async {
              await Share.share(
                shareUrl,
                subject: subject,
                sharePositionOrigin: sharePreviewOrigin(),
              );
            },
  );
}

/// The table a standings share captures while the Standings or Players tab is
/// shown in Combined: the first one the reader has left open, which is the
/// one at the top of their list. Null when the tab shows a single category.
({String tourId, String label, bool teams})? combinedStandingsShareTarget(
  WidgetRef ref,
) {
  if (!ref.read(combinedCategorySelectedProvider)) return null;
  final mode = ref.read(selectedTourModeProvider);
  final CombinedStandingsView view;
  switch (mode) {
    case TournamentDetailScreenMode.standings:
      view = CombinedStandingsView.standings;
    case TournamentDetailScreenMode.players:
      view = CombinedStandingsView.players;
    case TournamentDetailScreenMode.about:
    case TournamentDetailScreenMode.games:
    case TournamentDetailScreenMode.bracket:
      return null;
  }
  final sections = [
    for (final section in ref.read(combinedStandingsProvider(view)).sections)
      if (!section.hasError) section,
  ];
  if (sections.isEmpty) return null;
  final collapsed = ref.read(combinedStandingsCollapsedProvider);
  final target = sections.firstWhere(
    (section) => !collapsed.contains(section.group.id),
    orElse: () => sections.first,
  );
  return (
    tourId: target.tourId,
    label: target.group.label,
    teams: target.showsTeams,
  );
}

/// Shares one category's table from the Combined Standings tab: its players,
/// or its teams when [teams] is set. The image and the link name that
/// category, whichever one is selected underneath.
Future<void> shareCombinedStandingsSection(
  BuildContext context,
  WidgetRef ref, {
  required String tourId,
  required bool teams,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final tour = ref
        .read(tourDetailScreenProvider)
        .valueOrNull
        ?.tours
        .where((item) => item.tour.id == tourId)
        .firstOrNull
        ?.tour;
    if (tour == null) {
      showAppSnackOn(messenger, 'Open an event to share its standings.');
      return;
    }

    final section = selectedOfficialPlayerSection(
      tour.info.playerStandingSections,
      ref.read(selectedPlayerStandingSectionProvider(tourId)),
    );
    // A table that spans the pages of a board-paginated tournament is that
    // tournament's, not "Boards 1-100"'s.
    final tours =
        ref.read(tourDetailScreenProvider).valueOrNull?.tours ?? const [];
    final spansPages =
        standingsToursFor(tours, tourId: tourId, tourName: tour.name).length >
        1;
    final pagedName = boardPaginationBaseName(
      tour.name,
    ).replaceFirst(RegExp(r'[\s|:\-–—]+$'), '');
    final tableName =
        spansPages && pagedName.isNotEmpty ? pagedName : tour.name;
    final title =
        section == null ? tableName : '$tableName | ${section.name}';
    final groupId = tour.groupBroadcastId;
    final shareUrl =
        section?.sourceUrl ??
        (isVirtualGamebaseId(tour.id)
            ? null
            : buildEventShareUrl(
              id: groupId != null && groupId.isNotEmpty ? groupId : tour.id,
              title: tour.name,
              tourId: tour.id,
              tourSlug: tour.slug,
              tab: kEventStandingsTab,
            ));

    // The team table is built from the players', so awaiting these settles
    // both.
    final players = await ref.read(categoryStandingsProvider(tourId).future);
    if (!context.mounted) return;
    final teamTable =
        teams
            ? ref.read(categoryTeamStandingsProvider(tourId)).valueOrNull ??
                const <TeamStandingModel>[]
            : const <TeamStandingModel>[];
    if (teams ? teamTable.isEmpty : players.isEmpty) {
      showAppSnackOn(
        messenger,
        'Standings are still loading. Try again in a moment.',
      );
      return;
    }

    await _presentStandingsShare(
      context,
      title: title,
      fileStem: tableName,
      fileSuffix: teams ? 'team-standings' : 'standings',
      shareUrl: shareUrl,
      card:
          (width) =>
              teams
                  ? TeamStandingsShareImageCard(
                    width: width,
                    eventName: title,
                    standings: teamTable,
                  )
                  : StandingsShareImageCard(
                    width: width,
                    eventName: title,
                    standings: players,
                  ),
    );
  } catch (e) {
    debugPrint('Failed to share standings: $e');
    if (!context.mounted) return;
    showAppSnackOn(
      messenger,
      'Could not share standings. Please try again.',
      tone: AppSnackTone.danger,
    );
  }
}
