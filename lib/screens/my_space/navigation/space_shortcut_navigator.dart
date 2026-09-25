import 'dart:async';

import 'package:chessever2/config/feature_flags.dart';
import 'package:chessever2/repository/gamebase/memorial_tree_scope.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/supabase/calendar_event/calendar_event.dart';
import 'package:chessever2/repository/supabase/calendar_event/calendar_event_repository.dart';
import 'package:chessever2/screens/calendar/calendar_event_detail_screen.dart';
import 'package:chessever2/screens/chessboard/utils/game_share_utils.dart'
    show kGamebaseShareSourceParam, kGamebaseShareSourceValue;
import 'package:chessever2/screens/countrymen/countrymen_tab_screen.dart';
import 'package:chessever2/screens/gamebase/event_view/gamebase_virtual_event.dart';
import 'package:chessever2/screens/gamebase/gamebase_explorer_screen.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_explorer_state.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_screen.dart';
import 'package:chessever2/screens/library/folder_contents_screen.dart';
import 'package:chessever2/screens/library/miniatures_screen.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart'
    show kMiniaturesBookId, kTwicBookId;
import 'package:chessever2/screens/library/twic_contents_screen.dart';
import 'package:chessever2/screens/library/utils/load_saved_analysis.dart';
import 'package:chessever2/screens/my_likes/my_likes_screen.dart';
import 'package:chessever2/screens/my_likes/provider/my_likes_provider.dart'
    show isArchivedLike;
import 'package:chessever2/screens/my_likes/widgets/my_likes_archive_boundary.dart'
    show kMyLikesHistoryFeatureId;
import 'package:chessever2/screens/my_space/actions/space_share.dart'
    show isSpaceCalendarEvent;
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/screens/player_profile/provider/player_profile_provider.dart';
import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:chessever2/screens/streaks/streak_player_screen.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/services/deep_link_service.dart';
import 'package:chessever2/utils/eco_openings.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/event_card/event_context_menu.dart'
    show kEventTabQueryParam;
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _deadShortcutMessage = 'This shortcut can no longer open';

/// Where a Premium gate opened from My Space resumes once entitled.
const _kMySpaceReturnTo = 'for_you/my_space';

/// Opens [s] in the exact state it was saved in: the profile on the
/// saved tab, the explorer on the saved line, the event on the saved round.
///
/// Every kind fails soft. A target that is gone, or params too thin to
/// rebuild the destination, raise one danger snack instead of a dead tap or a
/// half-built screen. A user who backs out of a paywall is not a failure.
Future<void> openSpaceShortcut(
  BuildContext context,
  WidgetRef ref,
  SpaceShortcut s,
) async {
  // Captured up front: most branches await the network before pushing.
  final messenger = ScaffoldMessenger.maybeOf(context);
  final shortcuts = ref.read(spaceShortcutsProvider.notifier);

  var opened = false;
  try {
    opened = await _open(context, ref, s);
  } catch (e) {
    debugPrint('[MySpace] open ${s.kind.name}:${s.targetId} failed: $e');
  }
  if (!opened && messenger != null && messenger.mounted) {
    showAppSnackOn(messenger, _deadShortcutMessage, tone: AppSnackTone.danger);
  }
  // Every tap still counts, but the write rebuilds every My Space tile, so it
  // waits until the page the open pushed has finished sliding in.
  unawaited(_afterTransition().then((_) => shortcuts.markOpened(s.id)));
}

/// Longest wait for the frames to go quiet: a destination that animates for
/// good (a live clock, a spinner) never idles.
const _kTransitionWait = Duration(milliseconds: 900);

/// Resolves once no frame is pending (the push transition is over), or after
/// [_kTransitionWait]. Waits on frames, not a timer.
Future<void> _afterTransition() async {
  final binding = WidgetsBinding.instance;
  final watch = Stopwatch()..start();
  do {
    await binding.endOfFrame;
  } while (binding.hasScheduledFrame && watch.elapsed < _kTransitionWait);
}

/// Returns false only when the destination cannot be reached.
Future<bool> _open(BuildContext context, WidgetRef ref, SpaceShortcut s) {
  final p = s.params;
  return switch (s.kind) {
    SpaceShortcutKind.player => _openProfile(
      context,
      s,
      PlayerProfileTab.about,
    ),
    SpaceShortcutKind.streak => _openStreak(context, s),
    SpaceShortcutKind.playerGames => _openProfile(
      context,
      s,
      PlayerProfileTab.games,
    ),
    SpaceShortcutKind.playerOpenings => _openPlayerOpenings(context, ref, s),
    SpaceShortcutKind.event => _openEvent(context, ref, s),
    SpaceShortcutKind.round => DeepLinkService.instance.openEventForShortcut(
      eventId: _str(p['groupBroadcastId']) ?? _str(p['eventId']),
      tourId: _str(p['tourId']),
      roundId: s.targetId,
    ),
    SpaceShortcutKind.game => _openGame(context, ref, s),
    SpaceShortcutKind.position => _openPosition(context, s),
    SpaceShortcutKind.opening => _openOpening(context, s),
    SpaceShortcutKind.folder => _openFolder(context, ref, s),
    SpaceShortcutKind.smartEvent => _openSmartEvent(context, s),
    SpaceShortcutKind.countrymen => _openCountrymen(context, ref, s),
    SpaceShortcutKind.miniatures => _push(context, const MiniaturesScreen()),
    SpaceShortcutKind.likes => _push(context, const MyLikesScreen()),
    SpaceShortcutKind.link => _openLink(context, s.targetId),
  };
}

// ------------------------------------------------------------------- events

/// targetId is a tour or a group broadcast id; the resolver probes both.
/// Calendar (community / FIDE major) events and database-only events are not
/// broadcasts and open on their own screens.
Future<bool> _openEvent(BuildContext context, WidgetRef ref, SpaceShortcut s) {
  final p = s.params;
  if (isSpaceCalendarEvent(s)) return _openCalendarEvent(context, s);
  final eventId =
      _str(p['groupBroadcastId']) ?? _str(p['eventId']) ?? s.targetId;
  final virtualId = isVirtualGamebaseId(eventId)
      ? eventId
      : isVirtualGamebaseId(s.targetId)
      ? s.targetId
      : null;
  if (virtualId != null) return _openVirtualEvent(context, ref, virtualId);
  return DeepLinkService.instance.openEventForShortcut(
    eventId: eventId,
    tourId: _str(p['tourId']),
  );
}

/// A gamebase-only event, through the same tournament screen a database
/// event tapped on a player profile opens in.
Future<bool> _openVirtualEvent(
  BuildContext context,
  WidgetRef ref,
  String virtualId,
) {
  final key = virtualEventKeyFromId(virtualId);
  if (key == null) return Future.value(false);
  if (!context.mounted) return Future.value(true);
  ref
      .read(selectedBroadcastModelProvider.notifier)
      .state = virtualGroupBroadcastForEvent(
    key.eventName,
    site: key.site,
    slug: key.slug,
  );
  ref.read(selectedTourModeProvider.notifier).state =
      TournamentDetailScreenMode.games;
  unawaited(Navigator.of(context).pushNamed('/tournament_detail_screen'));
  return Future.value(true);
}

Future<bool> _openCalendarEvent(BuildContext context, SpaceShortcut s) async {
  final event = await _findCalendarEvent(s);
  if (event == null) return false;
  if (!context.mounted) return true;
  return _push(
    context,
    CalendarEventDetailScreen(events: [event], initialIndex: 0),
  );
}

/// Calendar events are keyed by name. A pin names it in its params, or at
/// least carries it as its title; the oldest pins only have the card's
/// `cal_event_` id, matched against a search for the title.
Future<CalendarEvent?> _findCalendarEvent(SpaceShortcut s) async {
  final client = Supabase.instance.client;
  for (final name in spaceCalendarEventNames(s)) {
    try {
      final rows = await client
          .from('calendar_events')
          .select()
          .eq('name', name)
          .limit(1);
      if (rows.isNotEmpty) return CalendarEvent.fromJson(rows.first);
    } catch (e) {
      debugPrint('[MySpace] calendar event "$name" unavailable: $e');
    }
  }
  final cardId = [
    _str(s.params['calendarEventId']),
    s.targetId,
  ].whereType<String>().where((id) => id.startsWith('cal_event_')).firstOrNull;
  if (cardId == null) return null;
  try {
    final hits = await CalendarEventRepository().searchCalendarEvents(s.title);
    return hits
        .where((e) => GroupEventCardModel.fromCalendarEvent(e).id == cardId)
        .firstOrNull;
  } catch (e) {
    debugPrint('[MySpace] calendar search for ${s.title} failed: $e');
    return null;
  }
}

/// Names a calendar pin may be stored under, most specific first.
@visibleForTesting
List<String> spaceCalendarEventNames(SpaceShortcut s) {
  final p = s.params;
  final id = _str(p['calendarEventId']);
  return {
    ?_str(p['calendarEventName']),
    ?_str(p['eventName']),
    if (id != null && !id.startsWith('cal_event_')) id,
    ?_str(s.title),
  }.toList(growable: false);
}

// -------------------------------------------------------------- countrymen

/// Countrymen for the pinned federation. The country is chosen before the
/// push so the screen's first fetch is already for it; a code the picker
/// does not know opens on the user's own country, as older pins always did.
Future<bool> _openCountrymen(
  BuildContext context,
  WidgetRef ref,
  SpaceShortcut s,
) {
  final code = _str(s.targetId);
  final known = CountrymenTabScreen.preselect(ref, code);
  return _push(
    context,
    CountrymenTabScreen(initialCountryCode: known ? code : null),
  );
}

// ------------------------------------------------------------------ players

Future<bool> _openProfile(
  BuildContext context,
  SpaceShortcut s,
  PlayerProfileTab tab,
) {
  final screen = _profileFor(s, tab);
  if (screen == null) return Future.value(false);
  return _push(context, screen);
}

PlayerProfileScreen? _profileFor(SpaceShortcut s, PlayerProfileTab tab) {
  final p = s.params;
  final fideId = _int(p['fideId']) ?? _int(s.targetId);
  final name = _str(p['playerName']) ?? _str(s.title);
  if (name == null && fideId == null) return null;
  return PlayerProfileScreen(
    fideId: fideId,
    playerName: name ?? '',
    title: _str(p['title']),
    federation: _str(p['federation']),
    rating: _int(p['rating']),
    gamebasePlayerId: _str(p['gamebasePlayerId']),
    memorialSourceIdentity: _str(p['memorialSourceIdentity']),
    memorialRouteId: _str(p['memorialRouteId']),
    initialTab: tab,
  );
}

/// A streak card opens on the class it was pinned in. A shortcut whose FIDE
/// id no longer parses still reaches the player's profile by name.
Future<bool> _openStreak(BuildContext context, SpaceShortcut s) {
  final p = s.params;
  final fideId = _int(p['fideId']) ?? _int(s.targetId);
  if (fideId == null) return _openProfile(context, s, PlayerProfileTab.about);
  final name = _str(p['playerName']) ?? _str(s.title);
  return _push(
    context,
    StreakPlayerScreen(
      fideId: fideId,
      initialClass: StreakTimeClassX.tryParse(_str(p['timeClass'])),
      fallbackName: name == null ? null : streakDisplayName(name),
    ),
  );
}

Future<bool> _openPlayerOpenings(
  BuildContext context,
  WidgetRef ref,
  SpaceShortcut s,
) async {
  // Same gate the profile's "Study openings" row applies. A confirmed
  // purchase resumes straight into the saved tree; backing out is not a dead
  // shortcut.
  var opened = true;
  await requirePremiumGuard(
    context,
    ref,
    featureId: 'opening_tree',
    returnTo: _kMySpaceReturnTo,
    onEntitled: () async {
      opened = await _pushPlayerOpenings(context, ref, s);
    },
  );
  return opened;
}

Future<bool> _pushPlayerOpenings(
  BuildContext context,
  WidgetRef ref,
  SpaceShortcut s,
) async {
  final p = s.params;
  final fideId = _int(p['fideId']) ?? _int(s.targetId);
  final name = _str(p['playerName']) ?? s.title;

  final memorialIdentity = _str(p['memorialSourceIdentity']);
  var playerId =
      _str(p['gamebasePlayerId']) ??
      (memorialIdentity == null
          ? null
          : memorialTreeScopeKey(memorialIdentity));
  playerId ??= await ref.read(
    twicPlayerIdProvider(
      PlayerProfileKey(
        fideId: fideId,
        playerName: name,
        source: PlayerProfileDataSource.twic,
      ),
    ).future,
  );
  if (playerId == null || playerId.isEmpty) return false;
  if (!context.mounted) return true;

  final line = resolveSpaceLine(fen: _str(p['fen']), moves: p['moves']);
  // `white` / `black` pin one side of the tree; `all` (or none) keeps both.
  final color = GamebasePlayerColor.values
      .where((c) => c.name == _str(p['color']))
      .firstOrNull;
  return _push(
    context,
    GamebaseExplorerScreen.scoped(
      initialPlayer: GamebasePlayer(
        id: playerId,
        fideId: fideId?.toString() ?? '',
        name: name,
        gender: PlayerGender.male,
        fed: _str(p['federation']) ?? '',
        title: _str(p['title']),
        ratingClassical: _int(p['rating']),
      ),
      initialFilters: color == null
          ? null
          : GamebaseFilters(playerColor: color),
      initialFen: line?.fen,
      initialMoves: line?.ucis,
    ),
  );
}

// -------------------------------------------------------------------- games

Future<bool> _openGame(
  BuildContext context,
  WidgetRef ref,
  SpaceShortcut s,
) async {
  final p = s.params;
  Future<bool> openSource() => DeepLinkService.instance.openGameForShortcut(
    s.targetId,
    initialFen: _str(p['fen']),
    preferGamebase: _str(p['source']) == 'gamebase',
  );

  // A liked or saved game reopens the user's own analysis copy, with their
  // variations and comments, before falling back to the source game.
  final analysisId = _str(p['analysisId']);
  if (analysisId != null) {
    try {
      final analysis = await ref
          .read(libraryRepositoryProvider)
          .getSavedAnalysis(analysisId);
      if (analysis != null) {
        // A like a free user no longer sees in My Likes (past their latest
        // 20) is Premium history. The pin is keyed on the public source game,
        // so that still opens; the copy waits behind the paywall only when
        // the source game is gone.
        if (await isArchivedLike(ref.read, analysis)) {
          if (await openSource()) return true;
          if (!context.mounted) return true;
          // A confirmed purchase or restore resumes into the saved copy.
          await requirePremiumGuard(
            context,
            ref,
            featureId: kMyLikesHistoryFeatureId,
            returnTo: _kMySpaceReturnTo,
            onEntitled: () => unawaited(loadSavedAnalysis(context, analysis)),
          );
          return true;
        }
        if (!context.mounted) return true;
        unawaited(loadSavedAnalysis(context, analysis));
        return true;
      }
    } catch (e) {
      debugPrint('[MySpace] saved analysis $analysisId unavailable: $e');
    }
  }

  return openSource();
}

// ---------------------------------------------------------------- explorer

Future<bool> _openPosition(BuildContext context, SpaceShortcut s) {
  final p = s.params;
  final line = resolveSpaceLine(
    fen: s.targetId,
    moves: p['moves'] ?? p['sans'],
  );
  if (line == null) return Future.value(false);
  return _push(
    context,
    GamebaseExplorerScreen.scoped(
      initialPlayer: _filterPlayer(p),
      initialFen: line.fen,
      initialMoves: line.ucis,
    ),
  );
}

Future<bool> _openOpening(BuildContext context, SpaceShortcut s) {
  final p = s.params;
  final code = s.targetId.trim().toUpperCase();
  final line =
      resolveSpaceLine(fen: _str(p['fen']), moves: p['moves']) ??
      resolveSpaceLine(
        moves: EcoOpenings.canonicalRecordForCode(code)?.moves,
      ) ??
      resolveSpaceLine(moves: EcoOpenings.getFamily(code)?.moves);
  if (line == null) return Future.value(false);
  return _push(
    context,
    GamebaseExplorerScreen.scoped(
      initialFen: line.fen,
      initialMoves: line.ucis,
    ),
  );
}

/// The board a board-carrying shortcut (a position, an opening, a player's
/// opening tree) shows, resolved exactly as opening it would resolve it, so
/// "Open in board editor" sets up the position the tile draws. Null for
/// every other kind, or a line that no longer replays.
String? spaceShortcutFen(SpaceShortcut s) {
  final p = s.params;
  final SpaceLine? line;
  switch (s.kind) {
    case SpaceShortcutKind.position:
      line = resolveSpaceLine(fen: s.targetId, moves: p['moves'] ?? p['sans']);
    case SpaceShortcutKind.opening:
      final code = s.targetId.trim().toUpperCase();
      line =
          resolveSpaceLine(fen: _str(p['fen']), moves: p['moves']) ??
          resolveSpaceLine(
            moves: EcoOpenings.canonicalRecordForCode(code)?.moves,
          ) ??
          resolveSpaceLine(moves: EcoOpenings.getFamily(code)?.moves);
    case SpaceShortcutKind.playerOpenings:
      line = resolveSpaceLine(fen: _str(p['fen']), moves: p['moves']);
    default:
      line = null;
  }
  return line?.fen;
}

/// The optional player filter a position was saved under.
GamebasePlayer? _filterPlayer(Map<String, dynamic> p) {
  final id = _str(p['playerId']);
  if (id == null) return null;
  return GamebasePlayer(
    id: id,
    fideId: _str(p['playerFideId']) ?? '',
    name: _str(p['playerName']) ?? '',
    gender: PlayerGender.male,
    fed: '',
  );
}

// ------------------------------------------------------------------ library

Future<bool> _openFolder(
  BuildContext context,
  WidgetRef ref,
  SpaceShortcut s,
) async {
  final id = s.targetId.trim();
  if (id == kTwicBookId) return _push(context, const TwicContentsScreen());
  // One event of the ChessEver Database: the database, filtered to it.
  final twicEvent = spaceTwicEventName(s);
  if (twicEvent != null) {
    return _push(context, TwicContentsScreen(initialEvent: twicEvent));
  }
  if (id == kMiniaturesBookId) return _push(context, const MiniaturesScreen());

  final repo = ref.read(libraryRepositoryProvider);
  LibraryFolder? folder;
  try {
    folder = await repo.getFolder(id);
  } catch (_) {
    // Not the owner: a subscribed database is looked up below.
  }
  if (folder == null) {
    try {
      final subscribed = await repo.getSubscribedBooks();
      folder = subscribed.where((f) => f.id == id).firstOrNull;
    } catch (_) {}
  }
  if (folder == null) return false;
  if (!context.mounted) return true;
  if (folder.isLikedGames) return _push(context, const MyLikesScreen());
  return _push(context, FolderContentsScreen(folder: folder));
}

/// The ChessEver Database event a folder pin is filtered to: targetId
/// `<kTwicBookId>:<event>` with the event also in `params.event`. Null for
/// every other folder.
@visibleForTesting
String? spaceTwicEventName(SpaceShortcut s) {
  if (s.kind != SpaceShortcutKind.folder) return null;
  const prefix = '$kTwicBookId:';
  final id = s.targetId.trim();
  if (!id.startsWith(prefix)) return null;
  return _str(s.params['event']) ?? _str(id.substring(prefix.length));
}

// -------------------------------------------------------------- smart event

Future<bool> _openSmartEvent(BuildContext context, SpaceShortcut s) {
  final request = _smartEventRequest(s);
  if (request == null) return Future.value(false);
  return _push(context, SmartEventScreen(request: request));
}

/// The saved request, rebuilt through the same path saved smart favorites
/// use. An opening smart event whose metadata did not survive still reopens
/// from its ECO.
SmartEventRequest? _smartEventRequest(SpaceShortcut s) {
  try {
    final request = smartEventRequestFromSpaceShortcut(s);
    if (request != null) return request;
  } catch (e) {
    debugPrint('[MySpace] smart event request unreadable: $e');
  }
  final raw = s.params['request'];
  final eco =
      _str(s.params['eco']) ??
      _str(s.params['ecoCode']) ??
      (raw is Map ? _str(raw['ecoCode']) ?? _str(raw['eco']) : null);
  if (eco == null) return null;
  return SmartEventRequest.forOpening(GameEcoFilter.forCode(eco));
}

// -------------------------------------------------------------------- links

Future<bool> _openLink(BuildContext context, String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || (uri.pathSegments.isEmpty && uri.host.isEmpty)) {
    return Future.value(false);
  }
  // streaks.chessever.com: `/` is the wall, `/p/<fideId>?tc=` a player card.
  final streak = FeatureFlags.streaks ? streakLinkTarget(uri) : null;
  if (streak != null) return _push(context, streakLinkScreen(streak));
  // handleDeepLink silently ignores links it does not know; only hand over
  // the shapes it routes, so a dead shortcut says so instead of doing nothing.
  if (!isRoutableSpaceLink(uri)) return Future.value(false);

  // Shapes with an in-app opener open above My Space and report a dead
  // target. The shared-link router below resets the stack to Home and
  // returns before it knows whether the target exists.
  final links = DeepLinkService.instance;
  switch (_spaceLinkRoot(uri)) {
    case 'broadcast':
      final target = spaceBroadcastLinkTarget(uri);
      if (target == null) return Future.value(false);
      final fideId = target.playerFideId;
      final team = target.teamName;
      if (fideId != null) {
        return links.openPlayerScorecardForShortcut(
          eventId: target.eventId,
          fideId: fideId,
        );
      }
      if (team != null) {
        return links.openTeamScorecardForShortcut(
          eventId: target.eventId,
          teamName: team,
        );
      }
      return links.openEventForShortcut(
        eventId: target.eventId,
        tab: target.tab,
      );
    case 'games':
      final game = spaceGameLinkTarget(uri);
      if (game == null) return Future.value(false);
      return links.openGameForShortcut(
        game.gameId,
        initialFen: game.fen,
        preferGamebase: game.preferGamebase,
      );
  }
  // Books, databases, folders and player profiles have no in-app opener yet.
  return Future.value(links.openLinkFromApp(uri));
}

const _routableLinkRoots = {
  'games',
  'books',
  'databases',
  'folders',
  'broadcast',
  'player',
};

/// Whether the app's deep-link router opens [uri]: chessever.com (or the
/// app scheme) under one of [_routableLinkRoots]. Team and player scorecards
/// (`/broadcast/<slug>/<id>/team/<name>`, `.../player/<fideId>`) and a tab of
/// an event (`?tab=standings`) all ride the `broadcast` root.
@visibleForTesting
bool isRoutableSpaceLink(Uri uri) {
  final root = _spaceLinkRoot(uri);
  return root != null && _routableLinkRoots.contains(root);
}

bool _isAppSchemeLink(Uri uri) => uri.scheme == 'com.chessever.app';

/// The first routing segment of a chessever.com or app-scheme link, or null
/// for any other link. Custom-scheme links carry it in the host
/// (com.chessever.app://games/..).
String? _spaceLinkRoot(Uri uri) {
  final isApp = _isAppSchemeLink(uri);
  final isWeb =
      (uri.scheme == 'https' || uri.scheme == 'http') &&
      (uri.host == 'chessever.com' || uri.host.endsWith('.chessever.com'));
  if (!isApp && !isWeb) return null;
  return isApp ? uri.host : uri.pathSegments.firstOrNull;
}

/// What a `broadcast` link opens: the event, a player's or a team's
/// scorecard in it, or one of its tabs. Player wins over team, team over
/// tab, exactly as the shared-link router reads it.
typedef SpaceBroadcastLinkTarget = ({
  String eventId,
  int? playerFideId,
  String? teamName,
  String? tab,
});

/// Reads a `broadcast` link the way `DeepLinkService.handleDeepLink` does:
/// `/broadcast/<slug>/<id>` (or `/broadcast/<id>`), then `/player/<fideId>`
/// or `/team/<name>` after the id, and `?tab=`. The app scheme finds the id
/// just before `player` / `team`, else takes the last segment. Null when the
/// link names no event.
@visibleForTesting
SpaceBroadcastLinkTarget? spaceBroadcastLinkTarget(Uri uri) {
  if (_spaceLinkRoot(uri) != 'broadcast') return null;
  String? eventId;
  int? fideId;
  String? team;
  if (_isAppSchemeLink(uri)) {
    final segs = uri.pathSegments;
    if (segs.isEmpty) return null;
    final playerIdx = segs.indexOf('player');
    final teamIdx = segs.indexOf('team');
    if (playerIdx > 0) {
      eventId = segs[playerIdx - 1];
      if (playerIdx + 1 < segs.length) fideId = _int(segs[playerIdx + 1]);
    } else if (teamIdx > 0) {
      eventId = segs[teamIdx - 1];
      if (teamIdx + 1 < segs.length) team = _str(segs[teamIdx + 1]);
    } else {
      eventId = segs.last;
    }
  } else {
    final segs = uri.pathSegments;
    if (segs.length >= 3) {
      eventId = segs[2];
    } else if (segs.length == 2) {
      eventId = segs[1];
    }
    if (segs.length >= 5 && segs[3] == 'player') {
      fideId = _int(segs[4]);
    } else if (segs.length >= 5 && segs[3] == 'team') {
      // pathSegments are already percent-decoded.
      team = _str(segs[4]);
    }
  }
  final id = _str(eventId);
  if (id == null) return null;
  return (
    eventId: id,
    playerFideId: fideId,
    teamName: fideId == null ? team : null,
    tab: _str(uri.queryParameters[kEventTabQueryParam]),
  );
}

/// What a `games` link opens: the game, on the move its `fen` names, from
/// the gamebase when `src=gamebase`.
typedef SpaceGameLinkTarget = ({
  String gameId,
  String? fen,
  bool preferGamebase,
});

/// Reads a `games` link (`/games/<id>` or `com.chessever.app://games/<id>`)
/// the way the shared-link router does. Null when it names no game.
@visibleForTesting
SpaceGameLinkTarget? spaceGameLinkTarget(Uri uri) {
  if (_spaceLinkRoot(uri) != 'games') return null;
  final segs = uri.pathSegments;
  final id = _str(
    _isAppSchemeLink(uri) ? segs.firstOrNull : segs.elementAtOrNull(1),
  );
  if (id == null) return null;
  return (
    gameId: id,
    fen: _str(uri.queryParameters['fen']),
    preferGamebase:
        uri.queryParameters[kGamebaseShareSourceParam] ==
        kGamebaseShareSourceValue,
  );
}

// ------------------------------------------------------------------ helpers

Future<bool> _push(BuildContext context, Widget screen) {
  if (!context.mounted) return Future.value(true);
  unawaited(
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen)),
  );
  return Future.value(true);
}

String? _str(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int? _int(Object? value) {
  if (value is int) return value > 0 ? value : null;
  if (value is num) return value > 0 ? value.toInt() : null;
  final parsed = int.tryParse(value?.toString().trim() ?? '');
  return parsed != null && parsed > 0 ? parsed : null;
}

// --------------------------------------------------------- explorer lines

/// An explorer line the explorer can open: the FEN on the board and the UCI
/// moves that reach it from the standard start. [ucis] is empty for a bare
/// position (board-editor setups, or a saved line that no longer replays),
/// which the explorer queries by FEN alone.
typedef SpaceLine = ({String fen, List<String> ucis});

final _uciPattern = RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$');

/// Normalises a saved line. [moves] may be a UCI list, a SAN list, or one SAN
/// string with move numbers ("1. e4 c5 2. Nf3"). When [fen] is given it wins:
/// moves that do not reach it are dropped rather than trusted. Returns null
/// when neither a valid FEN nor a replayable move is left.
SpaceLine? resolveSpaceLine({String? fen, Object? moves}) {
  final target = _validFen(fen);
  final tokens = _moveTokens(moves);
  if (tokens.isEmpty) {
    return target == null ? null : (fen: target, ucis: const <String>[]);
  }

  final replay = _replay(tokens);
  if (target != null) {
    final reaches =
        replay.complete && _positionKey(replay.fen) == _positionKey(target);
    return (fen: target, ucis: reaches ? replay.ucis : const <String>[]);
  }
  if (replay.ucis.isEmpty) return null;
  return (fen: replay.fen, ucis: replay.ucis);
}

/// SAN for each UCI move from the standard start, stopping at the first move
/// that does not replay.
List<String> spaceSansForUcis(List<String> ucis) => _replay(ucis).sans;

/// The deepest named catalog opening along [sans] (from the standard start).
EcoOpeningRecord? spaceOpeningForSans(List<String> sans) {
  final path = sans.map(_bareSan).toList(growable: false);
  for (var depth = path.length; depth > 0; depth--) {
    final hit = _catalogByPath[EcoOpenings.movePathKey(path.take(depth))];
    if (hit != null) return hit;
  }
  return null;
}

final Map<String, EcoOpeningRecord> _catalogByPath = () {
  final out = <String, EcoOpeningRecord>{};
  for (final record in EcoOpenings.exactCatalog) {
    final key = EcoOpenings.movePathKey(
      EcoOpenings.moveTokens(record.moves).map(_bareSan),
    );
    out.putIfAbsent(key, () => record);
  }
  return out;
}();

String _bareSan(String san) => san.replaceAll(RegExp(r'[+#!?]'), '');

List<String> _moveTokens(Object? moves) {
  if (moves is String) return EcoOpenings.moveTokens(moves);
  if (moves is List) {
    return [
      for (final m in moves)
        if (m != null && m.toString().trim().isNotEmpty) m.toString().trim(),
    ];
  }
  return const [];
}

({String fen, List<String> ucis, List<String> sans, bool complete}) _replay(
  List<String> tokens,
) {
  Position position = Chess.initial;
  final ucis = <String>[];
  final sans = <String>[];
  for (final token in tokens) {
    final move = _parseMove(position, token);
    if (move == null) {
      return (fen: position.fen, ucis: ucis, sans: sans, complete: false);
    }
    final (next, san) = position.makeSan(move);
    ucis.add(_standardCastlingUci(position, move));
    sans.add(san);
    position = next;
  }
  return (fen: position.fen, ucis: ucis, sans: sans, complete: true);
}

Move? _parseMove(Position position, String token) {
  final lower = token.toLowerCase();
  if (_uciPattern.hasMatch(lower)) {
    final move = NormalMove.fromUci(lower);
    if (position.isLegal(move)) return move;
    // e1g1 and e1h1 both mean castling depending on who wrote the line.
    final alt = _castlingAlternates['${move.from.name}${move.to.name}'];
    if (alt != null) {
      final altMove = NormalMove.fromUci(alt);
      if (position.isLegal(altMove)) return altMove;
    }
    return null;
  }
  return position.parseSan(_bareSan(token));
}

const _castlingAlternates = <String, String>{
  'e1g1': 'e1h1',
  'e1h1': 'e1g1',
  'e1c1': 'e1a1',
  'e1a1': 'e1c1',
  'e8g8': 'e8h8',
  'e8h8': 'e8g8',
  'e8c8': 'e8a8',
  'e8a8': 'e8c8',
};

/// dartchess spells castling king-takes-rook (e1h1); the explorer's own tree
/// and the board speak standard UCI (e1g1).
String _standardCastlingUci(Position position, Move move) {
  final uci = move.uci;
  if (move is! NormalMove) return uci;
  final piece = position.board.pieceAt(move.from);
  final target = position.board.pieceAt(move.to);
  final isCastle =
      piece?.role == Role.king &&
      target?.role == Role.rook &&
      target?.color == piece?.color;
  if (!isCastle) return uci;
  return _castlingAlternates[uci] ?? uci;
}

String? _validFen(String? fen) {
  final trimmed = fen?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  try {
    Setup.parseFen(trimmed);
    return trimmed;
  } catch (_) {
    return null;
  }
}

String _positionKey(String fen) =>
    fen.trim().split(RegExp(r'\s+')).take(4).join(' ');
