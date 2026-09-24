import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/event_mute_provider.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/group_event/widget/appbar_icons_widget.dart';
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_pin_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/round_space_shortcut.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/match_expansion_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/round_expansion_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:chessever2/screens/tour_detail/team_tour/team_tour_screen_provider.dart'
    show teamStandingsProvider;
import 'package:chessever2/screens/tour_detail/bracket/providers/bracket_share_provider.dart';
import 'package:chessever2/screens/tour_detail/bracket/widgets/bracket_share_image_card.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart'
    show playerTourScreenProvider;
import 'package:chessever2/screens/tour_detail/widgets/standings_share_image_card.dart';
import 'package:chessever2/screens/tour_detail/widgets/team_standings_share_image_card.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:flutter/rendering.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/share_card.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:chessever2/widgets/event_card/event_context_menu.dart';
import 'package:chessever2/widgets/space_shortcut_drafts.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

enum TournamentMenuAction {
  focusLiveGames,
  showAllGames,
  noSpoilers,
  unpinAll,
  pinAll,
  collapseAllRounds,
  expandAllRounds,
  disableNotifications,
  enableNotifications,
  shareEvent,
  shareStandings,
  shareTeamStandings,
  shareBrackets,
}

class TournamentMenuButton extends ConsumerWidget {
  const TournamentMenuButton({super.key, required this.tourData});

  final TourDetailViewModel tourData;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch mute state here to keep the provider alive while on this screen
    // and ensure ref.read in the menu gets a synchronous value.
    final groupBroadcastId = tourData.aboutTourModel.groupBroadcastId;
    if (groupBroadcastId != null && groupBroadcastId.isNotEmpty) {
      ref.watch(eventMuteProvider(groupBroadcastId));
    }
    final isGamesTab =
        ref.watch(selectedTourModeProvider) == TournamentDetailScreenMode.games;
    if (isGamesTab) {
      ref.watch(
        eventNoSpoilersProvider(
          tourData.aboutTourModel.id,
        ).select((state) => state.enabled),
      );
    }

    // The shared focus menu, anchored to this button: the same menu, rows
    // and motion as every long-press in the app. Rows are built when it
    // opens, so every label reads live state.
    void open() => unawaited(
      CardContextMenu.open(
        context,
        actions: (menuContext) => _menuActions(menuContext, ref),
      ),
    );

    // The glyph is the shipped app-bar tile, laid out exactly as before: its
    // own 32x32 box is the whole footprint, so the dropdown and the sibling
    // grid toggle never move. Do not wrap it in a larger box to grow the tap
    // target; that widens the Row's trailing slot and shifts the header.
    // Semantics adds a name for screen readers without touching layout.
    return Semantics(
      button: true,
      label: 'Event actions',
      excludeSemantics: true,
      onTap: open,
      child: AppBarIcons(
        padding: EdgeInsets.symmetric(horizontal: 2.sp, vertical: 1.sp),
        image: SvgAsset.threeDots,
        onTap: open,
      ),
    );
  }

  List<LibraryMenuAction> _menuActions(BuildContext context, WidgetRef ref) {
    final isGamesTab =
        ref.read(selectedTourModeProvider) == TournamentDetailScreenMode.games;
    final groupBroadcastId = tourData.aboutTourModel.groupBroadcastId;
    final isMuted =
        (groupBroadcastId != null && groupBroadcastId.isNotEmpty)
            ? ref.read(eventMuteProvider(groupBroadcastId)).valueOrNull ?? false
            : false;

    return [
      if (isGamesTab) ..._gamesTabActions(ref),
      // Notifications + share are shared across tabs.
      ..._sharedActions(ref, context, isMuted),
      ..._spaceActions(ref, context, isGamesTab),
    ];
  }

  List<LibraryMenuAction> _gamesTabActions(WidgetRef ref) {
    final appBar = ref.read(gamesAppBarProvider.notifier);
    final visibleRoundIds = appBar.getVisibleRoundIds();
    final allRoundIds = appBar.getAllRoundIdsWithGames();
    final visibleMatchKeys = appBar.getVisibleMatchKeys(visibleRoundIds);
    final allMatchKeys = appBar.getVisibleMatchKeys(allRoundIds);
    final tourId = tourData.aboutTourModel.id;

    final gamesScreenState = ref.read(gamesTourScreenProvider).valueOrNull;
    final isFocusingLiveGames =
        gamesScreenState?.gameDisplayMode == GameDisplayMode.hideFinishedGames;
    final noSpoilersEnabled = ref.read(eventNoSpoilersProvider(tourId)).enabled;
    final isAnyPinned = ref.read(gamesPinprovider(tourId)).allPins.isNotEmpty;
    final isAllCollapsed = areAllVisibleSectionsCollapsed(
      visibleRoundIds: visibleRoundIds,
      visibleMatchKeys: visibleMatchKeys,
      roundExpansionState: ref.read(roundExpansionProvider),
      matchExpansionState: ref.read(matchExpansionProvider),
    );

    return [
      // 1. Live games first / Board order
      LibraryMenuAction(
        icon:
            isFocusingLiveGames
                ? Icons.format_list_bulleted_outlined
                : Icons.center_focus_strong_outlined,
        label: liveFocusOrderingMenuLabel(
          isFocusingLiveGames: isFocusingLiveGames,
        ),
        onSelected: () {
          if (isFocusingLiveGames) {
            unawaited(
              ref.read(gamesTourScreenProvider.notifier).showAllGames(),
            );
          } else {
            unawaited(
              ref.read(gamesTourScreenProvider.notifier).hideFinishedGames(),
            );
          }
        },
      ),
      // 2. No spoilers
      LibraryMenuAction(
        icon:
            noSpoilersEnabled
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
        label: noSpoilersEnabled ? "Disable No Spoilers" : "No Spoilers",
        onSelected: () {
          unawaited(
            ref.read(eventNoSpoilersProvider(tourId).notifier).toggle(),
          );
        },
      ),
      // 3. Pin/Unpin All
      LibraryMenuAction(
        icon: isAnyPinned ? Icons.push_pin : Icons.push_pin_outlined,
        label: isAnyPinned ? "Unpin all" : "Pin all",
        onSelected: () {
          if (isAnyPinned) {
            ref.read(gamesTourScreenProvider.notifier).unpinAllGames();
          } else {
            ref.read(gamesTourScreenProvider.notifier).enableAutoPin();
          }
        },
      ),
      // 4. Expand/Collapse All
      LibraryMenuAction(
        icon: isAllCollapsed ? Icons.unfold_more : Icons.unfold_less,
        label: isAllCollapsed ? "Expand all" : "Collapse all",
        onSelected: () {
          if (isAllCollapsed) {
            ref.read(roundExpansionProvider.notifier).expandAll(allRoundIds);
            if (allMatchKeys.isNotEmpty) {
              ref.read(matchExpansionProvider.notifier).expandAll();
            }
          } else {
            ref.read(roundExpansionProvider.notifier).collapseAll(allRoundIds);
            if (allMatchKeys.isNotEmpty) {
              ref
                  .read(matchExpansionProvider.notifier)
                  .collapseAll(allMatchKeys);
            }
          }
        },
      ),
    ];
  }

  List<LibraryMenuAction> _sharedActions(
    WidgetRef ref,
    BuildContext context,
    bool isMuted,
  ) {
    final actions = <LibraryMenuAction>[];

    // 5. Notifications
    final groupBroadcastId = tourData.aboutTourModel.groupBroadcastId;
    if (groupBroadcastId != null && groupBroadcastId.isNotEmpty) {
      actions.add(
        LibraryMenuAction(
          icon:
              isMuted
                  ? Icons.notifications_none
                  : Icons.notifications_off_outlined,
          label: isMuted ? "Enable notifications" : "Disable notifications",
          onSelected: () {
            if (!context.mounted) return;
            final isAuthenticated = ref.read(isAuthenticatedProvider);
            if (!isAuthenticated) {
              showAppSnack(context, 'Please sign in to manage notifications');
              return;
            }
            ref.read(eventMuteProvider(groupBroadcastId).notifier).toggleMute();

            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            showAppSnack(
              context,
              isMuted
                  ? 'Notifications enabled for this event'
                  : 'Notifications disabled for this event',
            );
          },
        ),
      );
    }

    // 6. Share event
    // We have the active tour (id + slug) in hand here, so we can build the
    // Lichess-mirror URL `<tour.slug>/<tour.id>` directly without an extra
    // database round-trip. `groupBroadcastId` is passed only as the fallback
    // path id used when slug/tourId are missing (legacy events).
    final aboutModel = tourData.aboutTourModel;
    final fallbackId =
        aboutModel.groupBroadcastId?.isNotEmpty == true
            ? aboutModel.groupBroadcastId!
            : aboutModel.id;
    if (fallbackId.isEmpty || aboutModel.name.isEmpty) return actions;

    actions.add(
      LibraryMenuAction(
        icon: Icons.ios_share_rounded,
        label: "Share event",
        onSelected: () {
          final url = buildEventShareUrl(
            id: fallbackId,
            title: aboutModel.name,
            tourId: aboutModel.id,
            tourSlug: aboutModel.slug,
          );
          final box =
              context.mounted ? context.findRenderObject() as RenderBox? : null;
          final origin =
              box != null && box.hasSize
                  ? box.localToGlobal(Offset.zero) & box.size
                  : const Rect.fromLTWH(0, 0, 1, 1);
          Share.share(url, sharePositionOrigin: origin);
        },
      ),
    );

    // Standings share actions are tab-scoped (same idea as Share brackets).
    // Individual table: Standings on non-team events, Players on team events.
    // Team table: Standings tab on team events only.
    final isTeamEvent = ref.read(isTeamEventProvider(aboutModel.id));
    final mode = ref.read(selectedTourModeProvider);
    final standingsShares = standingsShareActionsFor(
      mode: mode,
      isTeamEvent: isTeamEvent,
    );
    if (standingsShares.contains(TournamentMenuAction.shareStandings)) {
      actions.add(
        LibraryMenuAction(
          icon: Icons.leaderboard_outlined,
          label: "Share standings",
          onSelected: () {
            // Standings share = the event link + the standings tab marker, so
            // the same URL renders standings on the web and opens the
            // Standings tab in-app.
            final url = buildEventShareUrl(
              id: fallbackId,
              title: aboutModel.name,
              tourId: aboutModel.id,
              tourSlug: aboutModel.slug,
              tab: kEventStandingsTab,
            );
            unawaited(_shareStandings(ref, context, aboutModel.name, url));
          },
        ),
      );
    }
    if (standingsShares.contains(TournamentMenuAction.shareTeamStandings)) {
      actions.add(
        LibraryMenuAction(
          icon: Icons.groups_outlined,
          label: "Share team standings",
          onSelected: () {
            final url = buildEventShareUrl(
              id: fallbackId,
              title: aboutModel.name,
              tourId: aboutModel.id,
              tourSlug: aboutModel.slug,
              tab: kEventStandingsTab,
            );
            unawaited(_shareTeamStandings(ref, context, aboutModel.name, url));
          },
        ),
      );
    }

    // Knockout events, only while the Bracket tab is on screen (so the live
    // canvas boundary exists to snapshot the framed area).
    final isKnockout =
        ref.read(knockoutTournamentStateProvider(aboutModel.id)).isKnockout;
    final onBracketTab = mode == TournamentDetailScreenMode.bracket;
    if (isKnockout && onBracketTab) {
      actions.add(
        LibraryMenuAction(
          icon: Icons.account_tree_outlined,
          label: "Share brackets",
          onSelected: () {
            final url = buildEventShareUrl(
              id: fallbackId,
              title: aboutModel.name,
              tourId: aboutModel.id,
              tourSlug: aboutModel.slug,
              tab: kEventBracketTab,
            );
            unawaited(_shareBrackets(ref, context, aboutModel.name, url));
          },
        ),
      );
    }
    return actions;
  }

  /// The event itself, and on the Games tab the round on screen. A
  /// gamebase-only virtual event pins by its virtual id; its rounds are left
  /// out, since the round opener resolves real broadcasts only.
  List<LibraryMenuAction> _spaceActions(
    WidgetRef ref,
    BuildContext context,
    bool isGamesTab,
  ) {
    final eventDraft = tournamentEventSpaceDraft(
      broadcast: ref.read(selectedBroadcastModelProvider),
      about: tourData.aboutTourModel,
    );
    GamesAppBarModel? currentRound;
    if (isGamesTab) {
      final rounds = ref.read(gamesAppBarProvider).valueOrNull;
      if (rounds != null) {
        for (final round in rounds.gamesAppBarModels) {
          if (round.id == rounds.selectedId) currentRound = round;
        }
      }
    }
    final roundDraft =
        currentRound == null
            ? null
            : currentEventRoundSpaceDraft(ref, currentRound);
    final roundName =
        currentRound == null ? '' : spaceRoundLabelName(currentRound.name);

    return [
      if (eventDraft != null)
        labeledSpaceMenuAction(
          context: context,
          ref: ref,
          draft: eventDraft,
          addLabel: 'Add event to My Space',
          removeLabel: 'Remove event from My Space',
        ),
      if (roundDraft != null)
        labeledSpaceMenuAction(
          context: context,
          ref: ref,
          draft: roundDraft,
          addLabel: 'Add $roundName to My Space',
          removeLabel: 'Remove $roundName from My Space',
        ),
    ];
  }

  /// Renders the tournament standings to a branded share image and opens the
  /// preview sheet (Share Image / Share Link). Mirrors the player scorecard
  /// share: off-screen [captureCardPng] + [showShareImagePreview]. The link is
  /// the event page (`/broadcast/<slug>/<id>`), which carries its own OG tags.
  Future<void> _shareStandings(
    WidgetRef ref,
    BuildContext context,
    String eventName,
    String shareUrl,
  ) async {
    try {
      final standings = await ref.read(playerTourScreenProvider.future);
      if (!context.mounted) return;
      if (standings.isEmpty) {
        showAppSnack(
          context,
          'Standings are still loading. Try again in a moment.',
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
          eventName: eventName,
          standings: standings,
        ),
      );
      if (imageBytes == null) {
        throw StateError('Standings share render produced no image');
      }
      if (!context.mounted) return;

      final tempDir = await getTemporaryDirectory();
      final safeName =
          eventName
              .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
              .replaceAll(RegExp(r'^-+|-+$'), '')
              .toLowerCase();
      final file = File(
        '${tempDir.path}/${safeName.isEmpty ? 'chessever-event' : safeName}-standings.png',
      );
      await file.writeAsBytes(imageBytes);
      if (!context.mounted) return;

      final subject =
          eventName.trim().isNotEmpty
              ? '$eventName standings'
              : 'ChessEver standings';
      await showShareImagePreview(
        context,
        imageBytes: imageBytes,
        onShareImage: () async {
          await shareFilesWithText(
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
      showAppSnack(
        context,
        'Could not share standings. Please try again.',
        tone: AppSnackTone.danger,
      );
    }
  }

  /// Renders the team-event team standings (teams ranked by match points) to a
  /// branded share image. Mirrors [_shareStandings] but with the team table.
  Future<void> _shareTeamStandings(
    WidgetRef ref,
    BuildContext context,
    String eventName,
    String shareUrl,
  ) async {
    try {
      // The team standings derive from the individual standings; awaiting the
      // latter guarantees the team AsyncValue has resolved before we read it.
      await ref.read(playerTourScreenProvider.future);
      if (!context.mounted) return;
      final teams = ref.read(teamStandingsProvider).valueOrNull ?? const [];
      if (teams.isEmpty) {
        showAppSnack(
          context,
          'Team standings are still loading. Try again in a moment.',
        );
        return;
      }

      final width = math.min(MediaQuery.of(context).size.width, 430.0);
      final imageBytes = await captureCardPng(
        context,
        width: width,
        pixelRatio: 3.0,
        child: TeamStandingsShareImageCard(
          width: width,
          eventName: eventName,
          standings: teams,
        ),
      );
      if (imageBytes == null) {
        throw StateError('Team standings share render produced no image');
      }
      if (!context.mounted) return;

      final tempDir = await getTemporaryDirectory();
      final safeName = _safeFileName(eventName);
      final file = File(
        '${tempDir.path}/${safeName.isEmpty ? 'chessever-event' : safeName}-team-standings.png',
      );
      await file.writeAsBytes(imageBytes);
      if (!context.mounted) return;

      final subject =
          eventName.trim().isNotEmpty
              ? '$eventName team standings'
              : 'ChessEver team standings';
      await showShareImagePreview(
        context,
        imageBytes: imageBytes,
        onShareImage: () async {
          await shareFilesWithText(
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
      debugPrint('Failed to share team standings: $e');
      if (!context.mounted) return;
      showAppSnack(
        context,
        'Could not share team standings. Please try again.',
      );
    }
  }

  /// Snapshots the currently-framed bracket canvas (the live pan/zoom viewport)
  /// and wraps it in branded chrome for sharing. The snapshot target is the
  /// [RepaintBoundary] the bracket screen attaches via
  /// [bracketShareBoundaryKeyProvider].
  Future<void> _shareBrackets(
    WidgetRef ref,
    BuildContext context,
    String eventName,
    String shareUrl,
  ) async {
    try {
      final key = ref.read(bracketShareBoundaryKeyProvider);
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null || !boundary.hasSize) {
        showAppSnack(context, 'Open the Bracket tab, then try sharing.');
        return;
      }
      final size = boundary.size;
      final aspect = size.height > 0 ? size.width / size.height : 3 / 4;

      // The bracket is pannable/zoomable, so a zoomed-out frame packs tiny
      // text. Snapshot the live viewport at a high pixel ratio, and re-render
      // the branded card at the same ratio, so the double capture
      // (viewport -> embedded image -> card) keeps that text sharp when the
      // recipient zooms into the shared PNG. 4x keeps a phone viewport well
      // under any decode limit while roughly doubling legible detail vs 3x.
      const bracketPixelRatio = 4.0;
      final snapshot =
          await captureBoundaryPng(key, pixelRatio: bracketPixelRatio);
      if (snapshot == null) {
        throw StateError('Bracket snapshot produced no image');
      }
      if (!context.mounted) return;

      final width = math.min(MediaQuery.of(context).size.width, 430.0);
      final imageBytes = await captureCardPng(
        context,
        width: width,
        pixelRatio: bracketPixelRatio,
        child: BracketShareImageCard(
          width: width,
          eventName: eventName,
          snapshot: snapshot,
          snapshotAspectRatio: aspect,
        ),
      );
      if (imageBytes == null) {
        throw StateError('Bracket share render produced no image');
      }
      if (!context.mounted) return;

      final tempDir = await getTemporaryDirectory();
      final safeName = _safeFileName(eventName);
      final file = File(
        '${tempDir.path}/${safeName.isEmpty ? 'chessever-event' : safeName}-bracket.png',
      );
      await file.writeAsBytes(imageBytes);
      if (!context.mounted) return;

      final subject =
          eventName.trim().isNotEmpty
              ? '$eventName bracket'
              : 'ChessEver bracket';
      await showShareImagePreview(
        context,
        imageBytes: imageBytes,
        onShareImage: () async {
          await shareFilesWithText(
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
      debugPrint('Failed to share bracket: $e');
      if (!context.mounted) return;
      showAppSnack(
        context,
        'Could not share the bracket. Please try again.',
        tone: AppSnackTone.danger,
      );
    }
  }

  String _safeFileName(String name) => name
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '')
      .toLowerCase();
}

/// Off-state label for the games-tab live-focus toggle in the ⋮ menu.
const String kLiveGamesFirstMenuLabel = 'Live games first';

/// On-state label for the games-tab live-focus toggle in the ⋮ menu
/// (shown while live-focus mode is active; restores board order).
const String kBoardOrderMenuLabel = 'Board order';

/// Label for the games-tab ordering toggle. Behavior is unchanged: only
/// the wording differs between live-focus and board-order modes.
String liveFocusOrderingMenuLabel({required bool isFocusingLiveGames}) {
  return isFocusingLiveGames ? kBoardOrderMenuLabel : kLiveGamesFirstMenuLabel;
}

/// Which standings-related share actions belong on the tournament detail ⋮ menu
/// for the current tab and event type.
///
/// - Individual standings ("Share standings"): non-team [standings] tab, or
///   team-event [players] tab (individual table).
/// - Team standings ("Share team standings"): team-event [standings] tab only.
///
/// Games / About / Bracket never include either action.
List<TournamentMenuAction> standingsShareActionsFor({
  required TournamentDetailScreenMode mode,
  required bool isTeamEvent,
}) {
  final showIndividualStandingsShare =
      isTeamEvent
          ? mode == TournamentDetailScreenMode.players
          : mode == TournamentDetailScreenMode.standings;
  final showTeamStandingsShare =
      isTeamEvent && mode == TournamentDetailScreenMode.standings;

  return [
    if (showIndividualStandingsShare) TournamentMenuAction.shareStandings,
    if (showTeamStandingsShare) TournamentMenuAction.shareTeamStandings,
  ];
}

bool areAllVisibleSectionsCollapsed({
  required Iterable<String> visibleRoundIds,
  required Iterable<String> visibleMatchKeys,
  required Map<String, bool> roundExpansionState,
  required Map<String, bool> matchExpansionState,
}) {
  final rounds = visibleRoundIds.toList(growable: false);
  final matches = visibleMatchKeys.toList(growable: false);

  if (rounds.isEmpty && matches.isEmpty) {
    return false;
  }

  final areRoundsCollapsed = rounds.every(
    (id) => !(roundExpansionState[id] ?? true),
  );
  final areMatchesCollapsed = matches.every(
    (key) => !resolveMatchExpansionState(matchExpansionState, key),
  );

  return areRoundsCollapsed && areMatchesCollapsed;
}
