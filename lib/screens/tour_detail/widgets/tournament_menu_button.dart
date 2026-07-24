import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/event_mute_provider.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/group_event/widget/appbar_icons_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_pin_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
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
import 'package:flutter/rendering.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/share_card.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/utils/tablet_safe_menu.dart';
import 'package:chessever2/widgets/event_card/event_context_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
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

String gameDisplayModeMenuLabel({required bool isFocusingLiveGames}) {
  return isFocusingLiveGames ? 'Board order' : 'Live games first';
}

class TournamentMenuButton extends ConsumerWidget {
  const TournamentMenuButton({super.key, required this.tourData});

  final TourDetailViewModel tourData;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GlobalKey menuKey = GlobalKey();

    // Watch mute state here to keep the provider alive while on this screen
    // and ensure ref.read in the onTap gets a synchronous value.
    final groupBroadcastId = tourData.aboutTourModel.groupBroadcastId;
    final isMuted =
        (groupBroadcastId != null && groupBroadcastId.isNotEmpty)
            ? ref.watch(eventMuteProvider(groupBroadcastId)).valueOrNull ??
                false
            : false;
    final isGamesTab =
        ref.watch(selectedTourModeProvider) == TournamentDetailScreenMode.games;
    final noSpoilersEnabled =
        isGamesTab
            ? ref.watch(
              eventNoSpoilersProvider(
                tourData.aboutTourModel.id,
              ).select((state) => state.enabled),
            )
            : false;

    return AppBarIcons(
      key: menuKey,
      padding: EdgeInsets.symmetric(horizontal: 2.sp, vertical: 1.sp),
      image: SvgAsset.threeDots,
      onTap: () {
        final RenderBox? renderBox =
            menuKey.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox != null) {
          final visibleRoundIds =
              isGamesTab
                  ? ref.read(gamesAppBarProvider.notifier).getVisibleRoundIds()
                  : const <String>[];
          final allRoundIds =
              isGamesTab
                  ? ref
                      .read(gamesAppBarProvider.notifier)
                      .getAllRoundIdsWithGames()
                  : const <String>[];
          final visibleMatchKeys =
              isGamesTab
                  ? ref
                      .read(gamesAppBarProvider.notifier)
                      .getVisibleMatchKeys(visibleRoundIds)
                  : const <String>[];
          final allMatchKeys =
              isGamesTab
                  ? ref
                      .read(gamesAppBarProvider.notifier)
                      .getVisibleMatchKeys(allRoundIds)
                  : const <String>[];
          final Offset offset = renderBox.localToGlobal(Offset.zero);

          showTabletSafeMenu(
            context: context,
            position: RelativeRect.fromLTRB(
              offset.dx,
              offset.dy + renderBox.size.height,
              offset.dx + renderBox.size.width,
              offset.dy,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.br),
            ),
            color: context.colors.surface,
            constraints: BoxConstraints.tightFor(width: 208.w),
            items: _buildRedesignedMenuItems(
              ref,
              context,
              visibleRoundIds,
              visibleMatchKeys,
              allRoundIds,
              allMatchKeys,
              tourData,
              isMuted,
              isGamesTab,
              noSpoilersEnabled,
            ),
          );
        }
      },
    );
  }

  List<PopupMenuEntry<TournamentMenuAction>> _buildRedesignedMenuItems(
    WidgetRef ref,
    BuildContext context,
    List<String> visibleRoundIds,
    List<String> visibleMatchKeys,
    List<String> allRoundIds,
    List<String> allMatchKeys,
    TourDetailViewModel tourData,
    bool isMuted,
    bool isGamesTab,
    bool noSpoilersEnabled,
  ) {
    final List<PopupMenuEntry<TournamentMenuAction>> items = [];

    if (isGamesTab) {
      _addGamesTabItems(
        ref,
        context,
        items,
        visibleRoundIds,
        visibleMatchKeys,
        allRoundIds,
        allMatchKeys,
        tourData,
        noSpoilersEnabled,
      );
    }

    // Notifications + share are shared across tabs.
    _addSharedItems(ref, context, items, tourData, isMuted);

    return items;
  }

  void _addGamesTabItems(
    WidgetRef ref,
    BuildContext context,
    List<PopupMenuEntry<TournamentMenuAction>> items,
    List<String> visibleRoundIds,
    List<String> visibleMatchKeys,
    List<String> allRoundIds,
    List<String> allMatchKeys,
    TourDetailViewModel tourData,
    bool noSpoilersEnabled,
  ) {
    final gamesScreenState = ref.read(gamesTourScreenProvider).valueOrNull;
    final isFocusingLiveGames =
        gamesScreenState?.gameDisplayMode == GameDisplayMode.hideFinishedGames;

    // 1. Live games first / Board order
    items.add(
      PopupMenuItem<TournamentMenuAction>(
        value:
            isFocusingLiveGames
                ? TournamentMenuAction.showAllGames
                : TournamentMenuAction.focusLiveGames,
        padding: EdgeInsets.zero,
        height: 36.h,
        onTap: () {
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
        child: _MenuDropDownItem(
          text: gameDisplayModeMenuLabel(
            isFocusingLiveGames: isFocusingLiveGames,
          ),
          fontFamily: 'InterDisplay',
          icon: Icon(
            isFocusingLiveGames
                ? Icons.format_list_bulleted_outlined
                : Icons.center_focus_strong_outlined,
            color: context.colors.textPrimary,
            size: 16,
          ),
          hasBorder: false,
        ),
      ),
    );

    // 2. No spoilers
    items.add(
      PopupMenuItem<TournamentMenuAction>(
        value: TournamentMenuAction.noSpoilers,
        padding: EdgeInsets.zero,
        height: 36.h,
        onTap: () {
          unawaited(
            ref
                .read(
                  eventNoSpoilersProvider(tourData.aboutTourModel.id).notifier,
                )
                .toggle(),
          );
        },
        child: _MenuDropDownItem(
          text: noSpoilersEnabled ? "Disable No Spoilers" : "No Spoilers",
          icon: Icon(
            noSpoilersEnabled
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            color: context.colors.textPrimary,
            size: 16,
          ),
        ),
      ),
    );

    // 3. Pin/Unpin All
    final isAnyPinned =
        ref
            .read(gamesPinprovider(tourData.aboutTourModel.id))
            .allPins
            .isNotEmpty;

    items.add(
      PopupMenuItem<TournamentMenuAction>(
        value:
            isAnyPinned
                ? TournamentMenuAction.unpinAll
                : TournamentMenuAction.pinAll,
        padding: EdgeInsets.zero,
        height: 36.h,
        onTap: () {
          if (isAnyPinned) {
            ref.read(gamesTourScreenProvider.notifier).unpinAllGames();
          } else {
            ref.read(gamesTourScreenProvider.notifier).enableAutoPin();
          }
        },
        child: _MenuDropDownItem(
          text: isAnyPinned ? "Unpin all" : "Pin all",
          icon: SvgPicture.asset(
            isAnyPinned ? SvgAsset.unpine : SvgAsset.pin,
            height: 16,
            width: 16,
            colorFilter: ColorFilter.mode(
              context.colors.iconPrimary,
              BlendMode.srcIn,
            ),
          ),
        ),
      ),
    );

    // 4. Expand/Collapse All
    final roundExpansionState = ref.read(roundExpansionProvider);
    final matchExpansionState = ref.read(matchExpansionProvider);
    final isAllCollapsed = areAllVisibleSectionsCollapsed(
      visibleRoundIds: visibleRoundIds,
      visibleMatchKeys: visibleMatchKeys,
      roundExpansionState: roundExpansionState,
      matchExpansionState: matchExpansionState,
    );

    items.add(
      PopupMenuItem<TournamentMenuAction>(
        value:
            isAllCollapsed
                ? TournamentMenuAction.expandAllRounds
                : TournamentMenuAction.collapseAllRounds,
        padding: EdgeInsets.zero,
        height: 36.h,
        onTap: () {
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
        child: _MenuDropDownItem(
          text: isAllCollapsed ? "Expand all" : "Collapse all",
          icon: Icon(
            isAllCollapsed ? Icons.unfold_more : Icons.unfold_less,
            color: context.colors.textPrimary,
            size: 16,
          ),
        ),
      ),
    );
  }

  void _addSharedItems(
    WidgetRef ref,
    BuildContext context,
    List<PopupMenuEntry<TournamentMenuAction>> items,
    TourDetailViewModel tourData,
    bool isMuted,
  ) {
    // 4. Notifications
    final groupBroadcastId = tourData.aboutTourModel.groupBroadcastId;
    if (groupBroadcastId != null && groupBroadcastId.isNotEmpty) {
      items.add(
        PopupMenuItem<TournamentMenuAction>(
          value:
              isMuted
                  ? TournamentMenuAction.enableNotifications
                  : TournamentMenuAction.disableNotifications,
          padding: EdgeInsets.zero,
          height: 36.h,
          onTap: () {
            final isAuthenticated = ref.read(isAuthenticatedProvider);
            if (!isAuthenticated) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Please sign in to manage notifications'),
                ),
              );
              return;
            }
            ref.read(eventMuteProvider(groupBroadcastId).notifier).toggleMute();

            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  isMuted
                      ? 'Notifications enabled for this event'
                      : 'Notifications disabled for this event',
                ),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          child: _MenuDropDownItem(
            text: isMuted ? "Enable notifications" : "Disable notifications",
            icon: Icon(
              isMuted
                  ? Icons.notifications_none
                  : Icons.notifications_off_outlined,
              color: context.colors.textPrimary,
              size: 16,
            ),
          ),
        ),
      );
    }

    // 5. Share event
    // We have the active tour (id + slug) in hand here, so we can build the
    // Lichess-mirror URL `<tour.slug>/<tour.id>` directly without an extra
    // database round-trip. `groupBroadcastId` is passed only as the fallback
    // path id used when slug/tourId are missing (legacy events).
    final aboutModel = tourData.aboutTourModel;
    final fallbackId =
        aboutModel.groupBroadcastId?.isNotEmpty == true
            ? aboutModel.groupBroadcastId!
            : aboutModel.id;
    if (fallbackId.isNotEmpty && aboutModel.name.isNotEmpty) {
      items.add(
        PopupMenuItem<TournamentMenuAction>(
          value: TournamentMenuAction.shareEvent,
          padding: EdgeInsets.zero,
          height: 36.h,
          onTap: () {
            final url = buildEventShareUrl(
              id: fallbackId,
              title: aboutModel.name,
              tourId: aboutModel.id,
              tourSlug: aboutModel.slug,
            );
            final box = context.findRenderObject() as RenderBox?;
            final origin =
                box != null
                    ? box.localToGlobal(Offset.zero) & box.size
                    : const Rect.fromLTWH(0, 0, 1, 1);
            Share.share(url, sharePositionOrigin: origin);
          },
          child: _MenuDropDownItem(
            text: "Share event",
            icon: Icon(
              Icons.ios_share,
              color: context.colors.textPrimary,
              size: 16,
            ),
          ),
        ),
      );
      items.add(
        PopupMenuItem<TournamentMenuAction>(
          value: TournamentMenuAction.shareStandings,
          padding: EdgeInsets.zero,
          height: 36.h,
          onTap: () {
            // Standings share = the event link + the standings tab marker, so
            // the same URL renders standings on the web and opens the Standings
            // tab in-app.
            final url = buildEventShareUrl(
              id: fallbackId,
              title: aboutModel.name,
              tourId: aboutModel.id,
              tourSlug: aboutModel.slug,
              tab: kEventStandingsTab,
            );
            unawaited(_shareStandings(ref, context, aboutModel.name, url));
          },
          child: _MenuDropDownItem(
            text: "Share standings",
            icon: Icon(
              Icons.leaderboard_outlined,
              color: context.colors.textPrimary,
              size: 16,
            ),
          ),
        ),
      );

      // Team events: also offer the team standings leaderboard (teams, not
      // individuals). The same `?tab=standings` link opens the Standings tab
      // in-app, which for a team event shows the team table.
      final isTeamEvent = ref.read(isTeamEventProvider(aboutModel.id));
      if (isTeamEvent) {
        items.add(
          PopupMenuItem<TournamentMenuAction>(
            value: TournamentMenuAction.shareTeamStandings,
            padding: EdgeInsets.zero,
            height: 36.h,
            onTap: () {
              final url = buildEventShareUrl(
                id: fallbackId,
                title: aboutModel.name,
                tourId: aboutModel.id,
                tourSlug: aboutModel.slug,
                tab: kEventStandingsTab,
              );
              unawaited(
                _shareTeamStandings(ref, context, aboutModel.name, url),
              );
            },
            child: _MenuDropDownItem(
              text: "Share team standings",
              icon: Icon(
                Icons.groups_outlined,
                color: context.colors.textPrimary,
                size: 16,
              ),
            ),
          ),
        );
      }

      // Knockout events, only while the Bracket tab is on screen (so the live
      // canvas boundary exists to snapshot the framed area).
      final isKnockout =
          ref.read(knockoutTournamentStateProvider(aboutModel.id)).isKnockout;
      final onBracketTab =
          ref.read(selectedTourModeProvider) ==
          TournamentDetailScreenMode.bracket;
      if (isKnockout && onBracketTab) {
        items.add(
          PopupMenuItem<TournamentMenuAction>(
            value: TournamentMenuAction.shareBrackets,
            padding: EdgeInsets.zero,
            height: 36.h,
            onTap: () {
              final url = buildEventShareUrl(
                id: fallbackId,
                title: aboutModel.name,
                tourId: aboutModel.id,
                tourSlug: aboutModel.slug,
                tab: kEventBracketTab,
              );
              unawaited(_shareBrackets(ref, context, aboutModel.name, url));
            },
            child: _MenuDropDownItem(
              text: "Share brackets",
              icon: Icon(
                Icons.account_tree_outlined,
                color: context.colors.textPrimary,
                size: 16,
              ),
            ),
          ),
        );
      }
    }
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Standings are still loading. Try again in a moment.',
            ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not share standings. Please try again.'),
        ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Team standings are still loading. Try again in a moment.',
            ),
          ),
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
      debugPrint('Failed to share team standings: $e');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not share team standings. Please try again.'),
        ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Open the Bracket tab, then try sharing.'),
          ),
        );
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
      debugPrint('Failed to share bracket: $e');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not share the bracket. Please try again.'),
        ),
      );
    }
  }

  String _safeFileName(String name) => name
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '')
      .toLowerCase();
}

@visibleForTesting
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

class _MenuDropDownItem extends StatelessWidget {
  final String text;
  final Widget icon;
  final bool hasBorder;
  final String fontFamily;

  const _MenuDropDownItem({
    required this.text,
    required this.icon,
    this.hasBorder = true,
    this.fontFamily = 'SF Pro',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 40.h,
      padding: EdgeInsets.symmetric(horizontal: 14.w),
      decoration: BoxDecoration(
        color: context.colors.surface,
        border:
            hasBorder
                ? Border(
                  top: BorderSide(
                    color: const Color(0xFFE2E2E2).withValues(alpha: 0.04),
                    width: 1.w,
                  ),
                )
                : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 16.w, height: 16.h, child: icon),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: fontFamily,
                fontSize: 12.sp,
                fontWeight: FontWeight.w400,
                color: context.colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
