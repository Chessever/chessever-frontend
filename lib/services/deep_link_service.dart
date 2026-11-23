import 'dart:async';
import 'package:chessever2/screens/webview/app_webview_screen.dart';
import 'package:chessever2/services/webview_link.dart';
import 'package:chessever2/screens/feed/news/news_links.dart';
import 'favorite_player_news_destination.dart';
import 'onesignal_push_payload.dart';
import 'package:chessever2/providers/event_video_provider.dart';
import 'dart:io' show Platform;

import 'package:app_links/app_links.dart';
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/repository/authentication/model/auth_state.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/supabase/chess_player/chess_player_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/repository/supabase/round/round_repository.dart';
import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/memorial_player_local_search.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/collections/collections_data.dart'
    show Collection, collectionsRepositoryProvider;
import 'package:chessever2/screens/collections/collections_screen.dart'
    show CollectionScreen;
import 'package:chessever2/screens/collections/collection_share.dart'
    show collectionSlugFromUri;
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart'
    show smartEventRequestFromPushData;
import 'package:chessever2/screens/group_event/smart_event/smart_event_screen.dart'
    show SmartEventScreen, smartEventGamesTab;
import 'package:chessever2/screens/my_prep/models/prep_models.dart'
    show PrepProfile;
import 'package:chessever2/screens/my_prep/my_prep_home_screen.dart'
    show MyPrepHomeScreen;
import 'package:chessever2/screens/my_prep/prep_profile_screen.dart'
    show PrepProfileScreen, prepProfileGamesTab;
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart'
    show prepProfilesProvider;
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/utils/game_share_utils.dart'
    show kGamebaseShareSourceParam, kGamebaseShareSourceValue;
import 'package:chessever2/screens/inbox/inbox_provider.dart';
import 'package:chessever2/screens/inbox/inbox_screen.dart';
import 'package:chessever2/screens/library/book_preview_screen.dart';
import 'package:chessever2/screens/library/folder_contents_screen.dart';
import 'package:chessever2/screens/library/utils/gamebase_game_to_games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_repo_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_tabs.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart'
    show playerTourScreenProvider;
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/team_standing_model.dart';
import 'package:chessever2/screens/standings/score_card_screen.dart'
    show
        selectedPlayerProvider,
        scoreCardGamesContextProvider,
        scoreCardHasEventContextProvider,
        scoreCardPlayerProfileDataSourceProvider;
import 'package:chessever2/screens/tour_detail/team_tour/team_tour_screen_provider.dart'
    show selectedTeamProvider, teamStandingsProvider;
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart'
    show PlayerProfileDataSource;
import 'package:chessever2/screens/player_profile/player_profile_screen.dart'
    show PlayerProfileScreen, PlayerProfileTab;
import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:chessever2/screens/streaks/streak_player_screen.dart';
import 'package:chessever2/screens/streaks/streaks_screen.dart';
import 'package:chessever2/services/app_destination_service.dart';
import 'package:chessever2/services/pgn_file_intake_service.dart';
import 'package:chessever2/widgets/event_card/event_context_menu.dart'
    show kEventTabQueryParam;
import 'package:chessever2/widgets/paywall/premium_game_access.dart';
import 'package:chessever2/widgets/paywall/past_event_access.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/guest_session_gate_listener.dart'
    show GuestGateRouteObserver;
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart'
    show homeChromeRevealRequestProvider, popToHomeShell, hasHomeShellOn;
import 'package:chessever2/utils/own_web_page.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Where a streaks link points: the wall ([fideId] null) or one player's
/// card, optionally on a time class (`?tc=standard|rapid|blitz`).
typedef StreakLinkTarget = ({int? fideId, StreakTimeClass? timeClass});

// Streak links are WEB-ONLY from outside the app, so [handleDeepLink] has no
// streaks branch. The OS never hands a streaks.chessever.com link to the app:
// no Runner*.entitlements lists `applinks:streaks.chessever.com`, the Android
// manifest has no intent filter for that host, and the streaks-site worker
// serves no apple-app-site-association / assetlinks.json. Shared card links
// (`https://streaks.chessever.com/p/<fideId>?tc=`) therefore always open the
// site. To make them open the app, land all three platform pieces first, then
// route [streakLinkTarget] from [handleDeepLink] to [streakLinkScreen].
// Until then the parser below serves in-app links only (My Space shortcuts).

const _streakLinkHosts = {
  'streaks.chessever.com',
  'www.streaks.chessever.com',
  'streak.chessever.com',
  'www.streak.chessever.com',
};

final _streakFideIdPattern = RegExp(r'^\d{1,12}$');

/// Reads a streaks.chessever.com link the way the site's router does:
/// `/p/<fideId>` is a player, every other path is the wall, and `?tc=` picks
/// the time class. Null for any other link. In-app only; see the note above.
StreakLinkTarget? streakLinkTarget(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  final host = uri.host.toLowerCase();
  final isWeb =
      (scheme == 'https' || scheme == 'http') &&
      _streakLinkHosts.contains(host);
  if (!isWeb) return null;

  final segments = [
    for (final s in uri.pathSegments)
      if (s.trim().isNotEmpty) s.trim(),
  ];
  int? fideId;
  if (segments.length == 2 &&
      segments[0] == 'p' &&
      _streakFideIdPattern.hasMatch(segments[1])) {
    final parsed = int.tryParse(segments[1]);
    if (parsed != null && parsed > 0) fideId = parsed;
  }
  return (
    fideId: fideId,
    timeClass: StreakTimeClassX.tryParse(uri.queryParameters['tc']),
  );
}

/// The in-app screen for a streaks link.
Widget streakLinkScreen(StreakLinkTarget target) {
  final fideId = target.fideId;
  if (fideId == null) return StreaksScreen(initialClass: target.timeClass);
  return StreakPlayerScreen(fideId: fideId, initialClass: target.timeClass);
}

/// Gamebase archive ids are uuids; Supabase-native share links use uuids too,
/// but Lichess short ids are 8 alphanumerics — this only gates the gamebase
/// fallback lookup after a failed Supabase resolution.
final _sharedGameUuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

List<GamesTourModel> _buildSortedRoundGameModels(List<Games> roundGames) {
  final gameList = roundGames
      .map(GamesTourModel.fromGame)
      .toList(growable: false);
  gameList.sort((a, b) {
    final aBoard = a.boardNr ?? 1 << 30;
    final bBoard = b.boardNr ?? 1 << 30;
    if (aBoard != bBoard) return aBoard.compareTo(bBoard);
    return a.gameId.compareTo(b.gameId);
  });
  return gameList;
}

/// Service to handle deep links and notification tap routing.
/// Handles URLs like: `https://chessever.com/games/{id}`
/// Handles URLs like: `https://chessever.com/databases/{id}`
/// Handles notification data routing for games, events, rounds, and databases.
/// Where a Prep "new games" push lands: the player's profile on its Games
/// tab, or My Prep when this device does not hold the profile.
@visibleForTesting
Widget prepPushDestination(PrepProfile? profile, {int? newGames}) =>
    profile == null
    ? const MyPrepHomeScreen()
    : PrepProfileScreen(
        profileId: profile.id,
        newGames: newGames,
        initialTab: prepProfileGamesTab,
      );

/// What a Prep push says when this device does not hold the profile: it is
/// starred on another of the reader's devices (profiles live on the device).
@visibleForTesting
String prepPushElsewhereMessage(String? profileName) {
  final name = profileName?.trim();
  final who = name == null || name.isEmpty ? 'This player' : name;
  return '$who is starred on another of your devices.';
}

/// 1240 → "1,240".
String _thousands(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

/// What a collection push says once the collection is open: the count it
/// announced. Null when the push carried none.
@visibleForTesting
String? collectionPushArrivalMessage({int? added, String? title}) {
  if (added == null || added < 1) return null;
  final games = added == 1 ? '1 new game' : '${_thousands(added)} new games';
  final name = title?.trim();
  return name == null || name.isEmpty
      ? '$games just landed.'
      : '$games just landed in $name.';
}

/// What a link or push that could not open says, over the page the reader
/// stays on.
const String kLinkFailedMessage = "Couldn't open that link.";

/// What a link or push held during a sign-in says when the sign-in ended
/// with no session to open it for (O20): quietly, over the page in view.
const String kHeldLinkNeedsSignInMessage = 'Sign in to open that link.';

/// What a collection push says when the collection cannot be opened.
@visibleForTesting
String collectionPushFailedMessage(String? title) {
  final name = title?.trim();
  return name == null || name.isEmpty
      ? 'That collection could not be opened right now.'
      : '$name could not be opened right now.';
}

/// Where a player profile link points: the profile identity and the view
/// named after it, if any.
typedef PlayerProfileLinkTarget = ({String routeId, PlayerProfileTab? tab});

/// The web's `parsePlayerProfileRoute` identity: a FIDE id (with an old
/// accidental `-NN` suffix, or `-reused` for a recycled historical id) or a
/// Memorial route id.
final _playerIdentitySegment = RegExp(
  r'^(?:\d+(?:(?:-\d+)|-reused)?|memorial-[0-9a-f]{16})$',
);

/// Reads a player profile path as the web does (src/lib/player-profile-view.ts):
/// the identity is the FIRST segment that looks like one, the segment after
/// it is the view. `[1503014, games]`, `[magnus-carlsen, 1503014, events]`
/// and `[x, memorial-<16 hex>, news]` all resolve; `games` alone does not.
/// A `-NN` suffix is dropped (`5000017-63` is 5000017). Views the app has no
/// tab for (overview, news, streaming) open About. Null without an identity.
@visibleForTesting
PlayerProfileLinkTarget? playerProfileLinkTarget(Iterable<String> segments) {
  final parts = [for (final s in segments) s.trim()];
  final index = parts.indexWhere(_playerIdentitySegment.hasMatch);
  if (index < 0) return null;
  final segment = parts[index];
  final routeId = segment.startsWith('memorial-') || segment.endsWith('-reused')
      ? segment
      : RegExp(r'^(\d+)').firstMatch(segment)!.group(1)!;
  final view = index + 1 < parts.length ? parts[index + 1] : null;
  final tab = switch (view) {
    null => null,
    'games' => PlayerProfileTab.games,
    'events' => PlayerProfileTab.events,
    _ => PlayerProfileTab.about,
  };
  return (routeId: routeId, tab: tab);
}

final _shortIdSegment = RegExp(r'^[A-Za-z0-9]{8}$');

/// The game or round a Lichess-shaped broadcast path on chessever.com names,
/// as the web's `legacyShareRedirectPath` reads it: five segments with two
/// short ids at the end are a game, four segments ending in a short id
/// after a round-like (or non-id) slug are a round. Null for every
/// ChessEver shape (player, team, round pages).
@visibleForTesting
({String? gameId, String? roundId})? lichessShapedBroadcastTarget(Uri uri) {
  if (!isOwnWebHost(uri)) return null;
  final parts = [
    for (final s in uri.pathSegments)
      if (s.isNotEmpty) s,
  ];
  if (parts.isEmpty || parts.first != 'broadcast') return null;
  if (parts.length == 5 &&
      _shortIdSegment.hasMatch(parts[3]) &&
      _shortIdSegment.hasMatch(parts[4])) {
    return (gameId: parts[4], roundId: parts[3]);
  }
  if (parts.length == 4 &&
      _shortIdSegment.hasMatch(parts[3]) &&
      parts[2] != 'player' &&
      parts[2] != 'team' &&
      (RegExp('round', caseSensitive: false).hasMatch(parts[2]) ||
          !_shortIdSegment.hasMatch(parts[2]))) {
    return (gameId: null, roundId: parts[3]);
  }
  return null;
}

/// chessever.com pages under the app's claimed prefixes (`/broadcast/*`,
/// `/games/*`) that are no event, game or profile: the broadcast sign-in,
/// editor, settings and hubs index, a hub page (`/broadcast/<hub-slug>`,
/// kebab-case where event ids are short ids or snake_case), an event's team
/// list and game search. The app opens them on the web.
@visibleForTesting
bool isWebOnlyChesseverPage(Uri uri) {
  if (!isOwnWebHost(uri)) return false;
  final parts = [
    for (final s in uri.pathSegments)
      if (s.isNotEmpty) s,
  ];
  if (parts.length < 2) return false;
  if (parts.first == 'games') return parts[1] == 'search';
  if (parts.first != 'broadcast') return false;
  if (const {'editor', 'hubs', 'settings', 'signin'}.contains(parts[1])) {
    return true;
  }
  if (parts.length == 2) return parts[1].contains('-');
  return parts.length == 3 && parts[2] == 'teams';
}

class DeepLinkService {
  static final DeepLinkService instance = DeepLinkService._();
  DeepLinkService._();

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;
  bool _isInitialized = false;

  // Guards against duplicate and stale navigation. Every inbound link, push
  // and in-app reference takes the next generation; one that is no longer
  // the newest when its awaits return opens nothing (the newest tap wins,
  // never the first). The same game twice within [_debounceDuration] is one
  // tap.
  String? _lastHandledGameId;
  DateTime? _lastHandledTime;
  int _destinationGeneration = 0;

  /// The link or push being routed now. Kept as [_pending] when it cannot
  /// open yet (no session, or onboarding or sign-in on screen) and routed
  /// again once Home is up ([drainPendingDestination]).
  _InboundDestination? _inbound;
  _InboundDestination? _pending;

  /// How long a held destination waits for sign-in or onboarding to finish.
  static const _pendingLifetime = Duration(minutes: 30);

  /// Routes on which a link must wait instead of opening: the reader is
  /// signing in or onboarding, and Home is where it lands next.
  static const _signInRoutes = {
    '/auth_screen',
    '/onboarding',
    '/player_selection_screen',
  };

  /// Test seam: what the board route of a resolved game shows. Null in the
  /// app (the real board).
  @visibleForTesting
  Widget Function(GamesTourModel game)? debugBoardPageBuilder;

  /// Test seam: every other page this service pushes (profile, collection,
  /// smart event, prep, book, folder) passes through it. Null in the app.
  @visibleForTesting
  Widget Function(Widget page)? debugPageOverride;

  Widget _page(Widget page) => debugPageOverride?.call(page) ?? page;

  // Debounce duration to prevent duplicate link events
  static const _debounceDuration = Duration(milliseconds: 500);

  /// Timeout for individual network fetches (game, event).
  static const _fetchTimeout = Duration(seconds: 10);

  /// Where a notification tap is routed once the widget tree that owns a
  /// [WidgetRef] exists. Null until [attachNotificationRouter] runs.
  GlobalKey<NavigatorState>? _routerNavigatorKey;
  WidgetRef? _routerRef;

  /// Taps that arrived before the router was attached.
  ///
  /// The direct-push click listener is registered from `main()`, which is minutes
  /// of engine work earlier than the first frame of `MyApp` — on a cold start
  /// the OS replays the tapped notification while `StartupGate` is still
  /// opening the database, so the payload has nowhere to go yet. Holding it
  /// here is what makes a terminated-app tap behave like a backgrounded one;
  /// dropping it is what left the user on Home.
  final List<Map<String, dynamic>> _pendingNotificationData =
      <Map<String, dynamic>>[];

  /// Bound so a stuck payload can never pin the app to a stale destination.
  static const _maxPendingNotificationData = 8;

  /// Feed a notification tap in. Routes immediately when the app can navigate,
  /// buffers otherwise. Safe to call from anywhere, including before `runApp`.
  ///
  /// A push in OneSignal's envelope (a phone that updated from an SDK build
  /// and has not registered directly yet, O6) is unwrapped first, so it
  /// routes exactly like the same push sent directly.
  void ingestNotificationData(Map<String, dynamic> raw) {
    final data = unwrapOneSignalPush(raw);
    final navigatorKey = _routerNavigatorKey;
    final ref = _routerRef;
    if (navigatorKey != null && ref != null) {
      handleNotificationData(data, navigatorKey, ref);
      return;
    }

    _addBreadcrumb(
      'notification tap buffered before router attached',
      data: {'type': _asNonEmptyString(data['type'])},
    );
    if (_pendingNotificationData.length >= _maxPendingNotificationData) {
      _pendingNotificationData.removeAt(0);
    }
    _pendingNotificationData.add(data);
  }

  /// Called once the app has a navigator and a [WidgetRef]. Drains anything
  /// that arrived while the tree was still being built.
  void attachNotificationRouter(
    GlobalKey<NavigatorState> navigatorKey,
    WidgetRef ref,
  ) {
    _routerNavigatorKey = navigatorKey;
    _routerRef = ref;

    if (_pendingNotificationData.isEmpty) return;
    // Only the most recent tap can win — the user tapped one notification, and
    // routing several in a row would fight over the navigator.
    final data = _pendingNotificationData.removeLast();
    _pendingNotificationData.clear();
    _addBreadcrumb(
      'draining buffered notification tap',
      data: {'type': _asNonEmptyString(data['type'])},
    );
    handleNotificationData(data, navigatorKey, ref);
  }

  void detachNotificationRouter() {
    _destinationGeneration++;
    _stopWatchingSignInAttempt();
    _routerNavigatorKey = null;
    _routerRef = null;
  }

  /// Opens an in-app game reference through the same resolver used by shared
  /// game links, preserving round/tournament swipe context where available.
  bool openGameFromApp(String gameId) {
    final navigatorKey = _routerNavigatorKey;
    final ref = _routerRef;
    final normalizedId = gameId.trim();
    if (navigatorKey == null || ref == null || normalizedId.isEmpty) {
      return false;
    }
    // An in-app reference is no inbound link to hold for sign-in.
    _inbound = null;
    unawaited(
      _navigateToGame(
        normalizedId,
        navigatorKey,
        ref,
        preserveCurrentRoute: true,
      ),
    );
    return true;
  }

  /// Opens an event reference above the current route so Back returns to the
  /// chat that initiated the navigation.
  bool openEventFromApp({String? eventId, String? tourId, String? roundId}) {
    final navigatorKey = _routerNavigatorKey;
    final ref = _routerRef;
    final normalizedEventId = eventId?.trim();
    final normalizedTourId = tourId?.trim();
    final normalizedRoundId = roundId?.trim();
    final hasIdentifier =
        (normalizedEventId?.isNotEmpty ?? false) ||
        (normalizedTourId?.isNotEmpty ?? false) ||
        (normalizedRoundId?.isNotEmpty ?? false);
    if (navigatorKey == null || ref == null || !hasIdentifier) return false;
    // An in-app reference is no inbound link to hold for sign-in.
    _inbound = null;
    unawaited(
      _navigateToEvent(
        normalizedEventId,
        navigatorKey,
        ref,
        tourId: normalizedTourId,
        roundId: normalizedRoundId,
        preserveCurrentRoute: true,
      ),
    );
    return true;
  }

  /// Awaitable twin of [openGameFromApp] for My Space shortcuts. Resolves the
  /// game exactly like a shared link and pushes the board above the current
  /// route. Returns false only when the game could not be resolved or opened;
  /// a tap swallowed by the in-flight/debounce guard counts as handled.
  Future<bool> openGameForShortcut(
    String gameId, {
    String? initialFen,
    bool preferGamebase = false,
  }) async {
    final navigatorKey = _routerNavigatorKey;
    final ref = _routerRef;
    final normalizedId = gameId.trim();
    if (navigatorKey == null || ref == null || normalizedId.isEmpty) {
      return false;
    }
    _inbound = null;
    return _navigateToGame(
      normalizedId,
      navigatorKey,
      ref,
      initialFen: initialFen,
      preferGamebase: preferGamebase,
      preserveCurrentRoute: true,
    );
  }

  /// Awaitable twin of [openEventFromApp] for My Space shortcuts: same event
  /// and round resolution as a shared link (tour ids, group broadcast ids and
  /// bare round ids all work), with the round preselected. [tab] is a link's
  /// `?tab=` value (standings, bracket); absent opens Games. Returns false
  /// when the event could not be resolved.
  Future<bool> openEventForShortcut({
    String? eventId,
    String? tourId,
    String? roundId,
    String? tab,
  }) async {
    final navigatorKey = _routerNavigatorKey;
    final ref = _routerRef;
    final normalizedEventId = _asNonEmptyString(eventId);
    final normalizedTourId = _asNonEmptyString(tourId);
    final normalizedRoundId = _asNonEmptyString(roundId);
    if (navigatorKey == null ||
        ref == null ||
        (normalizedEventId == null &&
            normalizedTourId == null &&
            normalizedRoundId == null)) {
      return false;
    }
    _inbound = null;
    return _navigateToEvent(
      normalizedEventId,
      navigatorKey,
      ref,
      tourId: normalizedTourId,
      roundId: normalizedRoundId,
      tab: _asNonEmptyString(tab),
      preserveCurrentRoute: true,
    );
  }

  /// Awaitable, in-app twin of a shared player-scorecard link
  /// (`/broadcast/<slug>/<id>/player/<fideId>`) for My Space shortcuts. Opens
  /// the event on Standings above the current route, then the player's
  /// scorecard. Returns false only when the event could not be opened; a
  /// player missing from the standings leaves the event open and counts.
  Future<bool> openPlayerScorecardForShortcut({
    required String eventId,
    required int fideId,
  }) async {
    final navigatorKey = _routerNavigatorKey;
    final ref = _routerRef;
    final normalizedEventId = _asNonEmptyString(eventId);
    if (navigatorKey == null ||
        ref == null ||
        normalizedEventId == null ||
        fideId <= 0) {
      return false;
    }
    _inbound = null;
    return _navigateToPlayerScorecard(
      normalizedEventId,
      fideId,
      navigatorKey,
      ref,
      preserveCurrentRoute: true,
    );
  }

  /// Awaitable, in-app twin of a shared team-page link
  /// (`/broadcast/<slug>/<id>/team/<name>`) for My Space shortcuts. Opens the
  /// event on Standings above the current route, then the team's scorecard.
  /// Returns false only when the event could not be opened.
  Future<bool> openTeamScorecardForShortcut({
    required String eventId,
    required String teamName,
  }) async {
    final navigatorKey = _routerNavigatorKey;
    final ref = _routerRef;
    final normalizedEventId = _asNonEmptyString(eventId);
    final normalizedTeam = _asNonEmptyString(teamName);
    if (navigatorKey == null ||
        ref == null ||
        normalizedEventId == null ||
        normalizedTeam == null) {
      return false;
    }
    _inbound = null;
    return _navigateToTeamScorecard(
      normalizedEventId,
      normalizedTeam,
      navigatorKey,
      ref,
      preserveCurrentRoute: true,
    );
  }

  /// Opens a link tapped on a page in the app (an Inbox message, a nudge, a
  /// Botvinnik Inbox card) above that page, so Back returns to it: every
  /// `/app/...` route (My Space's pages, Likes, Reports, a player's games,
  /// settings) and every content path (a game, an event, a scorecard, a
  /// collection, a profile, a book) alike. Dock sections still open on the
  /// dock, and an article still opens in Discovery's reader. A link that
  /// cannot open leaves the reader on the page, with a snack. False while
  /// the router is not attached.
  bool openLinkInPlace(Uri uri) {
    final navigatorKey = _routerNavigatorKey;
    final ref = _routerRef;
    if (navigatorKey == null || ref == null) return false;
    _handleDeepLink(uri, navigatorKey, ref, trusted: true, inPlace: true);
    return true;
  }

  /// Routes a chessever.com (or app-scheme) link from inside the app exactly
  /// like one tapped outside it. Returns false while the router is not yet
  /// attached.
  bool openLinkFromApp(Uri uri) {
    final navigatorKey = _routerNavigatorKey;
    final ref = _routerRef;
    if (navigatorKey == null || ref == null) return false;
    _handleDeepLink(uri, navigatorKey, ref, trusted: true);
    return true;
  }

  /// Completer that resolves when the app navigates past the splash screen.
  /// Prevents deep link navigation from racing with splash screen navigation.
  static Completer<void> _appReadyCompleter = Completer<void>();

  /// Call after the splash screen has completed navigation.
  static void notifyAppReady() {
    if (!_appReadyCompleter.isCompleted) {
      _appReadyCompleter.complete();
    }
  }

  /// Public access to the splash-complete gate so other services that need to
  /// push routes from a cold-start intent (e.g. PGN file-open handler) can
  /// wait instead of racing the navigator.
  static Future<void> awaitAppReady() => _appReadyCompleter.future;

  /// Initialize the deep link service
  /// Should be called once after app startup when auth state is ready
  Future<void> initialize(
    GlobalKey<NavigatorState> navigatorKey,
    WidgetRef ref,
  ) async {
    if (_isInitialized) return;
    _isInitialized = true;

    // Handle initial link (app opened from link when cold started)
    try {
      final initialLink = await _appLinks.getInitialLink();
      if (initialLink != null) {
        _addBreadcrumb(
          'cold-start link received',
          data: _sanitizedUriData(initialLink),
        );
        handleDeepLink(initialLink, navigatorKey, ref);
      }
    } catch (e, stackTrace) {
      debugPrint('DeepLinkService: Error getting initial link: $e');
      _captureDeepLinkException(e, stackTrace, stage: 'get_initial_link');
    }

    // Listen for links while app is running (warm start / already open)
    _subscription = _appLinks.uriLinkStream.listen(
      (uri) {
        _addBreadcrumb(
          'warm-start link received',
          data: _sanitizedUriData(uri),
        );
        handleDeepLink(uri, navigatorKey, ref);
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('DeepLinkService: Error listening to links: $error');
        _captureDeepLinkException(error, stackTrace, stage: 'uri_link_stream');
      },
    );
  }

  /// Parse and handle an incoming deep link: a universal link, an App Link
  /// or a custom-scheme link from outside the app.
  void handleDeepLink(
    Uri uri,
    GlobalKey<NavigatorState> navigatorKey,
    WidgetRef ref,
  ) => _handleDeepLink(uri, navigatorKey, ref, trusted: false);

  /// [trusted] is false for links from outside the app, which anyone can
  /// write: their `/webview?url=` opens only ChessEver's own pages in the
  /// app's WebView (any other page goes to the system browser, never inside
  /// the ChessEver chrome). Links the app itself routes (Inbox, articles,
  /// configured push routes) are trusted.
  ///
  /// [inPlace] marks a link tapped on a page in the app ([openLinkInPlace]):
  /// it opens over that page instead of replacing the pages over Home, a
  /// failure leaves the reader there with a snack, and it is never held for
  /// sign-in (the reader is in the app).
  void _handleDeepLink(
    Uri uri,
    GlobalKey<NavigatorState> navigatorKey,
    WidgetRef ref, {
    required bool trusted,
    bool inPlace = false,
  }) {
    debugPrint('DeepLinkService: Received link: $uri');
    _inbound = inPlace ? null : _InboundDestination.link(uri, trusted: trusted);

    if (isWebViewLink(uri)) {
      final target = webViewLinkTarget(uri);
      if (target != null) {
        if (trusted || isExternalWebViewTarget(target)) {
          unawaited(
            _navigateToWebView(
              target,
              navigatorKey,
              ref,
              generation: ++_destinationGeneration,
              inPlace: inPlace,
            ),
          );
        } else {
          _addBreadcrumb(
            'outside webview link opened in the browser',
            data: {'host': target.host},
          );
          unawaited(openExternalWebPage(target));
        }
      }
      return;
    }

    final newsLink = NewsLink.parse(uri);
    final appDestination =
        parseAppDestination(uri.toString()) ??
        (newsLink == null ? null : parseAppDestination('/app${newsLink.path}'));
    if (appDestination != null) {
      unawaited(
        _navigateToAppDestination(
          appDestination,
          navigatorKey,
          ref,
          generation: ++_destinationGeneration,
          preserveCurrentRoute:
              inPlace || (newsLink != null && _appReadyCompleter.isCompleted),
        ),
      );
      return;
    }

    // iOS "Open in ChessEver" delivers `.pgn` as a file:// URI through
    // app_links (SceneDelegate forwards the URL). With
    // LSSupportsOpeningDocumentsInPlace disabled in Info.plist, iOS copies
    // the file into Documents/Inbox/ first, so the path is freely readable.
    // On Android, ACTION_VIEW for .pgn is handled by receive_sharing_intent
    // (which also resolves content:// URIs to real file paths), so we skip
    // this branch on Android to avoid double-handling the same file.
    if (Platform.isIOS && uri.scheme == 'file') {
      _addBreadcrumb(
        'file uri received',
        data: {'scheme': uri.scheme, 'path': _maskedValue(uri.path)},
      );
      try {
        final path = uri.toFilePath();
        unawaited(
          PgnFileIntakeService.instance.handlePgnFilePath(
            path,
            navigatorKey,
            waitAppReady: true,
          ),
        );
      } catch (e, stackTrace) {
        debugPrint('DeepLinkService: Failed routing file uri: $e');
        _captureDeepLinkException(
          e,
          stackTrace,
          stage: 'route_file_uri',
          extras: {'path': _maskedValue(uri.path)},
        );
      }
      return;
    }

    try {
      String? gameId;
      String? bookShareToken;
      String? folderId;
      String? broadcastId;
      int? playerFideId;
      String? teamName;
      String? profileRouteId;

      String? roundId;
      PlayerProfileTab? profileTab;

      // chessever.com pages under the claimed prefixes that the app has no
      // screen for (hubs, sign-in, editor, team lists, game search) open on
      // the web instead of resolving a bogus id and failing.
      if (isWebOnlyChesseverPage(uri)) {
        _openUnroutedWebPage(uri, reason: 'web-only page');
        return;
      }

      // Lichess-shaped paths a host-only rebrand put on chessever.com:
      // /broadcast/<tour>/<roundSlug>/<roundId>/<gameId> is a game,
      // /broadcast/<tour>/<roundSlug>/<roundId> a round (as the web's
      // legacyShareRedirectPath reads them).
      final lichess = lichessShapedBroadcastTarget(uri);
      if (lichess != null) {
        gameId = lichess.gameId;
        roundId = lichess.roundId;
      }

      // Universal link: https://chessever.com/games/<id>
      if (gameId == null &&
          uri.pathSegments.length >= 2 &&
          uri.pathSegments[0] == 'games') {
        gameId = uri.pathSegments[1];
      }

      // Universal link: https://chessever.com/books/<shareToken>
      if (uri.pathSegments.length >= 2 && uri.pathSegments[0] == 'books') {
        bookShareToken = uri.pathSegments[1];
      }

      // Universal link: https://chessever.com/collections/<slug>, and the web
      // page's hand-off com.chessever.app://collections/<slug>.
      final collectionSlug = collectionSlugFromUri(uri);

      // Universal link: https://chessever.com/databases/<folderId>
      if (uri.pathSegments.length >= 2 &&
          (uri.pathSegments[0] == 'databases' ||
              uri.pathSegments[0] == 'folders')) {
        folderId = uri.pathSegments[1];
      }

      // Universal link: https://chessever.com/broadcast/<slug>/<id>
      // Also accept /broadcast/<id> for links without a slug.
      // Player scorecard: https://chessever.com/broadcast/<slug>/<id>/player/<fideId>
      // Team scorecard:   https://chessever.com/broadcast/<slug>/<id>/team/<teamName>
      // Round page:      https://chessever.com/broadcast/<slug>/<id>/round/<roundId>
      if (lichess == null &&
          uri.pathSegments.isNotEmpty &&
          uri.pathSegments[0] == 'broadcast') {
        if (uri.pathSegments.length >= 3) {
          broadcastId = uri.pathSegments[2];
        } else if (uri.pathSegments.length == 2) {
          broadcastId = uri.pathSegments[1];
        }
        if (uri.pathSegments.length >= 5 && uri.pathSegments[3] == 'round') {
          final round = uri.pathSegments[4].trim();
          if (round.isNotEmpty) roundId = round;
        } else if (uri.pathSegments.length >= 5 &&
            uri.pathSegments[3] == 'player') {
          playerFideId = int.tryParse(uri.pathSegments[4]);
        } else if (uri.pathSegments.length >= 5 &&
            uri.pathSegments[3] == 'team') {
          // pathSegments are already percent-decoded by Uri.
          teamName = uri.pathSegments[4].trim();
          if (teamName.isEmpty) teamName = null;
        }
      }

      // Player profile: https://chessever.com/player/<fideId>, the canonical
      // SEO form /player/<name-slug>/<fideId>, and either with a view
      // (/games, /events, /about, /news). The identity is the first segment
      // the web's route parser accepts: a FIDE id or a reviewed Memorial
      // route id; the segment after it is the view.
      if (uri.pathSegments.length >= 2 && uri.pathSegments[0] == 'player') {
        final target = playerProfileLinkTarget(uri.pathSegments.skip(1));
        profileRouteId = target?.routeId;
        profileTab = target?.tab;
      }

      // Custom scheme: com.chessever.app://games/<id>
      if (gameId == null &&
          uri.host == 'games' &&
          uri.pathSegments.isNotEmpty) {
        gameId = uri.pathSegments[0];
      }

      // Custom scheme: com.chessever.app://player/<fideId>[/<view>]
      if (profileRouteId == null &&
          uri.host == 'player' &&
          uri.pathSegments.isNotEmpty) {
        final target = playerProfileLinkTarget(uri.pathSegments);
        profileRouteId = target?.routeId;
        profileTab = target?.tab;
      }

      // Custom scheme: com.chessever.app://books/<shareToken>
      if (bookShareToken == null &&
          uri.host == 'books' &&
          uri.pathSegments.isNotEmpty) {
        bookShareToken = uri.pathSegments[0];
      }

      // Custom scheme: com.chessever.app://databases/<folderId>
      if (folderId == null &&
          (uri.host == 'databases' || uri.host == 'folders') &&
          uri.pathSegments.isNotEmpty) {
        folderId = uri.pathSegments[0];
      }

      // Custom scheme: com.chessever.app://broadcast/<slug>/<id>
      // Also accept com.chessever.app://broadcast/<id>,
      // .../player/<fideId>, and .../team/<teamName>.
      if (broadcastId == null &&
          uri.host == 'broadcast' &&
          uri.pathSegments.isNotEmpty) {
        final segs = uri.pathSegments;
        final playerIdx = segs.indexOf('player');
        final teamIdx = segs.indexOf('team');
        if (playerIdx > 0) {
          broadcastId = segs[playerIdx - 1];
          if (playerIdx + 1 < segs.length) {
            playerFideId = int.tryParse(segs[playerIdx + 1]);
          }
        } else if (teamIdx > 0) {
          broadcastId = segs[teamIdx - 1];
          if (teamIdx + 1 < segs.length) {
            final t = segs[teamIdx + 1].trim();
            teamName = t.isEmpty ? null : t;
          }
        } else {
          broadcastId = segs.last;
        }
      }

      _addBreadcrumb(
        'deep link parsed',
        data: {
          ..._sanitizedUriData(uri),
          'gameId': _maskedValue(gameId),
          'bookShareToken': _maskedValue(bookShareToken),
          'folderId': _maskedValue(folderId),
          'collectionSlug': collectionSlug,
          'broadcastId': _maskedValue(broadcastId),
          'teamName': teamName,
        },
      );

      if (gameId != null && gameId.isNotEmpty) {
        // Pinned-game taps carry the focused move's FEN so the board opens on
        // that exact move (not the live tail).
        final initialFen = uri.queryParameters['fen'];
        // `src=gamebase` marks a TWIC/gamebase archive game whose uuid lives
        // in the gamebase, not the app's games table.
        final preferGamebase =
            uri.queryParameters[kGamebaseShareSourceParam] ==
            kGamebaseShareSourceValue;
        _addBreadcrumb(
          'routing to game',
          data: {'gameId': gameId, 'preferGamebase': preferGamebase},
        );
        unawaited(
          _captureDeepLinkMessage(
            'deep link routing to game',
            stage: 'route_to_game',
            extras: {'gameId': gameId, 'preferGamebase': preferGamebase},
          ),
        );
        final opening = _navigateToGame(
          gameId,
          navigatorKey,
          ref,
          initialFen: initialFen,
          preferGamebase: preferGamebase,
          preserveCurrentRoute: inPlace,
        );
        if (inPlace) _snackUnlessOpened(opening, navigatorKey);
      } else if (bookShareToken != null && bookShareToken.isNotEmpty) {
        _addBreadcrumb(
          'routing to shared book',
          data: {'shareToken': _maskedValue(bookShareToken)},
        );
        _navigateToBookPreview(bookShareToken, navigatorKey, ref);
      } else if (folderId != null && folderId.isNotEmpty) {
        _addBreadcrumb(
          'routing to database folder',
          data: {'folderId': _maskedValue(folderId)},
        );
        _navigateToFolder(folderId, navigatorKey, ref);
      } else if (collectionSlug != null) {
        _addBreadcrumb(
          'routing to collection',
          data: {'collectionSlug': collectionSlug},
        );
        _navigateToCollection(
          collectionSlug,
          navigatorKey,
          ref,
          preserveCurrentRoute: inPlace,
        );
      } else if (broadcastId != null &&
          broadcastId.isNotEmpty &&
          playerFideId != null) {
        _addBreadcrumb(
          'routing to player scorecard',
          data: {
            'broadcastId': _maskedValue(broadcastId),
            'fideId': playerFideId.toString(),
          },
        );
        final opening = _navigateToPlayerScorecard(
          broadcastId,
          playerFideId,
          navigatorKey,
          ref,
          preserveCurrentRoute: inPlace,
        );
        if (inPlace) _snackUnlessOpened(opening, navigatorKey);
      } else if (broadcastId != null &&
          broadcastId.isNotEmpty &&
          teamName != null &&
          teamName.isNotEmpty) {
        _addBreadcrumb(
          'routing to team scorecard',
          data: {
            'broadcastId': _maskedValue(broadcastId),
            'teamName': teamName,
          },
        );
        final opening = _navigateToTeamScorecard(
          broadcastId,
          teamName,
          navigatorKey,
          ref,
          preserveCurrentRoute: inPlace,
        );
        if (inPlace) _snackUnlessOpened(opening, navigatorKey);
      } else if (broadcastId != null && broadcastId.isNotEmpty) {
        // `?tab=standings` opens the event on its Standings tab (the same link
        // that renders standings on the web). Absent/other values open Games.
        final eventTab = uri.queryParameters[kEventTabQueryParam];
        _addBreadcrumb(
          'routing to broadcast event',
          data: {
            'broadcastId': _maskedValue(broadcastId),
            'tab': eventTab,
            'hasRoundId': roundId != null,
          },
        );
        // A link is a free entry to an event, in place or not: the
        // past-event gate stays with My Space shortcuts and in-app
        // references (open item O8).
        final opening = _navigateToEvent(
          broadcastId,
          navigatorKey,
          ref,
          roundId: roundId,
          tab: eventTab,
          preserveCurrentRoute: inPlace,
          gatePastEvent: false,
        );
        if (inPlace) _snackUnlessOpened(opening, navigatorKey);
      } else if (roundId != null) {
        _addBreadcrumb('routing to broadcast round');
        final opening = _navigateToEvent(
          null,
          navigatorKey,
          ref,
          roundId: roundId,
          preserveCurrentRoute: inPlace,
          gatePastEvent: false,
        );
        if (inPlace) _snackUnlessOpened(opening, navigatorKey);
      } else if (profileRouteId != null) {
        _addBreadcrumb(
          'routing to player profile',
          data: {'routeId': profileRouteId, 'tab': profileTab?.name},
        );
        _navigateToPlayerProfile(
          profileRouteId,
          navigatorKey,
          ref,
          tab: profileTab,
        );
      } else if (isOwnWebHost(uri)) {
        // A chessever.com page the app has no screen for: open it on the
        // web, over the app, rather than ignore the tap.
        _openUnroutedWebPage(uri, reason: 'unsupported path');
      } else {
        _addBreadcrumb(
          'deep link ignored',
          data: {'reason': 'unsupported path', ..._sanitizedUriData(uri)},
        );
      }
    } catch (e, stackTrace) {
      debugPrint('DeepLinkService: Failed parsing deep link: $e');
      _captureDeepLinkException(
        e,
        stackTrace,
        stage: 'parse_handle_deep_link',
        extras: _sanitizedUriData(uri),
      );
    }
  }

  /// Opens a chessever.com page the app has no route for in a browser over
  /// the app. In-app (Custom Tabs, SFSafariViewController), never the system
  /// browser: the OS would hand the page straight back to the app.
  void _openUnroutedWebPage(Uri uri, {required String reason}) {
    _addBreadcrumb(
      'deep link opened on the web',
      data: {'reason': reason, ..._sanitizedUriData(uri)},
    );
    unawaited(() async {
      await _appReadyCompleter.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {},
      );
      await openOwnWebPage(uri, mode: LaunchMode.inAppBrowserView);
    }());
  }

  /// An in-place link ([openLinkInPlace]) whose destination could not open:
  /// the reader stays on the page that asked and is told. A tap a newer one
  /// took over counts as opened (the router returns true for it).
  void _snackUnlessOpened(
    Future<bool> opening,
    GlobalKey<NavigatorState> navigatorKey,
  ) {
    unawaited(
      opening.then((opened) {
        if (!opened) _snackLinkFailed(navigatorKey);
      }),
    );
  }

  /// The one message a link or push that could not open leaves.
  void _snackLinkFailed(
    GlobalKey<NavigatorState> navigatorKey, {
    String message = kLinkFailedMessage,
  }) {
    _snackAfterNavigation(navigatorKey, message, tone: AppSnackTone.danger);
  }

  /// Navigate to the book preview screen for a shared book deep link.
  Future<void> _navigateToBookPreview(
    String shareToken,
    GlobalKey<NavigatorState> navigatorKey,
    WidgetRef ref,
  ) async {
    final generation = ++_destinationGeneration;
    bool superseded() => generation != _destinationGeneration;

    try {
      try {
        await _appReadyCompleter.future.timeout(const Duration(seconds: 30));
      } catch (_) {
        debugPrint(
          'DeepLinkService: Timed out waiting for app ready, proceeding',
        );
      }
      if (superseded()) return;

      final ready = await _readyToOpen(
        ref,
        navigatorKey,
        stage: 'book_preview_requires_auth',
      );
      if (superseded() || !ready) return;

      debugPrint('DeepLinkService: Opening book preview: $shareToken');

      final navigator = navigatorKey.currentState;
      if (navigator != null) {
        navigator.push(
          MaterialPageRoute(
            builder: (_) => _page(BookPreviewScreen(shareToken: shareToken)),
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('DeepLinkService: Failed to open book preview: $e');
      _captureDeepLinkException(
        e,
        stackTrace,
        stage: 'navigate_to_book_preview',
        extras: {'shareToken': _maskedValue(shareToken)},
      );
      if (!superseded()) {
        _linkFailed(navigatorKey, reason: 'book_preview_failed', report: false);
      }
    }
  }

  /// Opens the collection a "new games" push was sent for, or a shared
  /// `chessever.com/collections/<slug>` link points at, over Home (over the
  /// current page with [preserveCurrentRoute]). A push names its count again
  /// once the collection is open ([added], [title]). A collection that is no
  /// longer published (or cannot be read right now): a push lands on Home
  /// and says so with a way to try again; a link leaves the reader where
  /// they are and says why ([_linkFailed]), Home only on a cold start.
  Future<void> _navigateToCollection(
    String slug,
    GlobalKey<NavigatorState> navigatorKey,
    WidgetRef ref, {
    int? added,
    String? title,
    bool fromPush = false,
    bool preserveCurrentRoute = false,
  }) async {
    final generation = ++_destinationGeneration;
    bool superseded() => generation != _destinationGeneration;

    try {
      await _appReadyCompleter.future.timeout(const Duration(seconds: 30));
    } catch (_) {
      debugPrint(
        'DeepLinkService: Timed out waiting for app ready, proceeding',
      );
    }
    if (superseded()) return;
    // A collection opens for any session, a guest's too. With none (a
    // cold start signed out, onboarding on screen) it waits for Home
    // instead of putting a session-less Home over sign-in.
    if (!await _readyToOpen(
          ref,
          navigatorKey,
          stage: 'collection_requires_auth',
        ) ||
        superseded()) {
      return;
    }

    Collection? collection;
    Object? failure;
    try {
      collection = await ref
          .read(collectionsRepositoryProvider)
          .fetchCollection(slug);
    } catch (e, stackTrace) {
      failure = e;
      _captureDeepLinkException(
        e,
        stackTrace,
        stage: 'navigate_to_collection',
        extras: {'slug': slug},
      );
    }

    final navigator = navigatorKey.currentState;
    if (navigator == null || superseded()) return;
    final opened = collection;
    if (opened == null && !fromPush) {
      // A link closes nothing it could not replace: the reader stays on the
      // page they were reading and hears why (offline, gone, unreadable).
      _linkFailed(
        navigatorKey,
        reason: 'collection_unavailable',
        extras: {'slug': slug},
        report: false, // captured above
        message: userFacingError(
          failure,
          fallback: "Couldn't open that collection.",
        ),
      );
      return;
    }
    // Over Home, so Back lands on the app rather than leaving it.
    if (!preserveCurrentRoute) _ensureHomeRoot(navigator);
    if (opened == null) {
      // A push: Home, saying so, with a way to try again.
      _snackAfterNavigation(
        navigatorKey,
        collectionPushFailedMessage(title),
        tone: AppSnackTone.danger,
        actionLabel: 'Try again',
        onAction: () => _navigateToCollection(
          slug,
          navigatorKey,
          ref,
          added: added,
          title: title,
          fromPush: true,
        ),
      );
      return;
    }
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => _page(CollectionScreen(collection: opened)),
      ),
    );
    final arrived = collectionPushArrivalMessage(
      added: added,
      title: title ?? opened.title,
    );
    if (fromPush && arrived != null) {
      _snackAfterNavigation(navigatorKey, arrived);
    }
  }

  /// Shows a snack over whatever the navigator lands on, once it has drawn.
  void _snackAfterNavigation(
    GlobalKey<NavigatorState> navigatorKey,
    String message, {
    AppSnackTone tone = AppSnackTone.neutral,
    String? actionLabel,
    FutureOr<void> Function()? onAction,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = navigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      showAppSnack(
        context,
        message,
        tone: tone,
        actionLabel: actionLabel,
        onAction: onAction,
      );
    });
    // Nothing else may be drawing (a page standing still): the snack must
    // not wait for the next unrelated frame.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// Opens the smart event an evening "new games" push was sent for, on its
  /// Games tab: the reader's own starred row once favorites have loaded, else
  /// one rebuilt from the criteria the push carries.
  Future<void> _navigateToSmartEvent(
    Map<String, dynamic> data,
    GlobalKey<NavigatorState> navigatorKey,
    WidgetRef ref,
  ) async {
    final generation = ++_destinationGeneration;
    bool superseded() => generation != _destinationGeneration;

    try {
      await _appReadyCompleter.future.timeout(const Duration(seconds: 30));
    } catch (_) {
      debugPrint(
        'DeepLinkService: Timed out waiting for app ready, proceeding',
      );
    }
    if (superseded()) return;
    if (!await _readyToOpen(
          ref,
          navigatorKey,
          stage: 'smart_event_requires_auth',
        ) ||
        superseded()) {
      return;
    }

    final loaded = Completer<List<FavoriteEvent>?>();
    final subscription = ref.listenManual(favoriteEventsProvider, (_, value) {
      if (!value.isLoading && !loaded.isCompleted) {
        loaded.complete(value.valueOrNull);
      }
    }, fireImmediately: true);
    List<FavoriteEvent>? favorites;
    try {
      favorites = await loaded.future.timeout(const Duration(seconds: 10));
    } catch (_) {
      favorites = null;
    } finally {
      subscription.close();
    }
    final request = smartEventRequestFromPushData(
      data,
      favorites: favorites ?? const [],
    );

    final navigator = navigatorKey.currentState;
    if (navigator == null || superseded()) return;
    // Over Home, so Back lands on the app rather than leaving it.
    _ensureHomeRoot(navigator);
    if (request == null) return;
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => _page(
          SmartEventScreen(request: request, initialTab: smartEventGamesTab),
        ),
      ),
    );
  }

  /// Opens the My Prep profile a "new games" push was sent for, on its Games
  /// tab. One this device holds but no longer stars is unstarred on the
  /// server again, so the pushes stop. Profiles live on the device, so one
  /// this device does not hold is starred on another of the reader's
  /// devices: My Prep opens and says so, and the star is left alone unless
  /// the reader stops its alerts from there.
  Future<void> _navigateToPrepProfile(
    String profileId,
    GlobalKey<NavigatorState> navigatorKey,
    WidgetRef ref, {
    int? newGames,
    String? profileName,
  }) async {
    final generation = ++_destinationGeneration;
    bool superseded() => generation != _destinationGeneration;

    try {
      await _appReadyCompleter.future.timeout(const Duration(seconds: 30));
    } catch (_) {
      debugPrint(
        'DeepLinkService: Timed out waiting for app ready, proceeding',
      );
    }
    if (superseded()) return;
    if (!await _readyToOpen(
          ref,
          navigatorKey,
          stage: 'prep_profile_requires_auth',
        ) ||
        superseded()) {
      return;
    }

    final loaded = Completer<List<PrepProfile>?>();
    final subscription = ref.listenManual(prepProfilesProvider, (_, value) {
      if (!value.isLoading && !loaded.isCompleted) {
        loaded.complete(value.valueOrNull);
      }
    }, fireImmediately: true);
    List<PrepProfile>? profiles;
    try {
      profiles = await loaded.future.timeout(const Duration(seconds: 10));
    } catch (_) {
      profiles = null;
    } finally {
      subscription.close();
    }
    final profile = profiles?.where((p) => p.id == profileId).firstOrNull;
    if (profiles != null) {
      ref.read(prepProfilesProvider.notifier).settleWatch(profileId);
    }

    final navigator = navigatorKey.currentState;
    if (navigator == null || superseded()) return;
    // Over Home, so Back lands on the app rather than leaving it.
    _ensureHomeRoot(navigator);
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => _page(prepPushDestination(profile, newGames: newGames)),
      ),
    );
    if (profiles != null && profile == null) {
      final notifier = ref.read(prepProfilesProvider.notifier);
      _snackAfterNavigation(
        navigatorKey,
        prepPushElsewhereMessage(profileName),
        actionLabel: 'Stop alerts',
        onAction: () => notifier.stopWatch(profileId),
      );
    }
  }

  /// Navigate to a specific library folder for push notifications (e.g. game added/updated in a database).
  Future<void> _navigateToFolder(
    String folderId,
    GlobalKey<NavigatorState> navigatorKey,
    WidgetRef ref,
  ) async {
    final generation = ++_destinationGeneration;
    bool superseded() => generation != _destinationGeneration;

    try {
      try {
        await _appReadyCompleter.future.timeout(const Duration(seconds: 30));
      } catch (_) {
        debugPrint(
          'DeepLinkService: Timed out waiting for app ready, proceeding',
        );
      }
      if (superseded()) return;

      final ready = await _readyToOpen(
        ref,
        navigatorKey,
        stage: 'folder_requires_auth',
      );
      if (superseded() || !ready) return;

      debugPrint('DeepLinkService: Opening library folder: $folderId');

      final repo = ref.read(libraryRepositoryProvider);

      LibraryFolder? targetFolder;
      try {
        targetFolder = await repo.getFolder(folderId);
      } catch (_) {
        // Might fail if not owner, ignore
      }

      // Fallback: Check subscriptions
      if (targetFolder == null) {
        try {
          final subscribedBooks = await repo.getSubscribedBooks();
          targetFolder = subscribedBooks
              .where((f) => f.id == folderId)
              .firstOrNull;
        } catch (_) {
          // Ignore
        }
      }

      if (superseded()) return;
      final navigator = navigatorKey.currentState;
      if (navigator != null) {
        if (targetFolder != null) {
          navigator.push(
            MaterialPageRoute(
              builder: (_) =>
                  _page(FolderContentsScreen(folder: targetFolder!)),
            ),
          );
        } else {
          debugPrint(
            'DeepLinkService: Folder not found or access denied: $folderId',
          );
          _linkFailed(navigatorKey, reason: 'folder_not_found', report: false);
        }
      }
    } catch (e, stackTrace) {
      debugPrint('DeepLinkService: Failed to open folder: $e');
      _captureDeepLinkException(
        e,
        stackTrace,
        stage: 'navigate_to_folder',
        extras: {'folderId': _maskedValue(folderId)},
      );
      if (!superseded()) {
        _linkFailed(navigatorKey, reason: 'folder_failed', report: false);
      }
    }
  }

  /// Fetch game by ID, load full tournament context for swiping,
  /// and navigate to chess board screen.
  ///
  /// [preferGamebase] marks `src=gamebase` links: the id is a gamebase
  /// (TWIC archive) uuid, so skip the Supabase lookup and resolve through
  /// the gamebase API instead.
  ///
  /// Returns false when the game could not be opened. A call swallowed by the
  /// debounce guard, or superseded by a newer tap, returns true: the other
  /// call owns it.
  Future<bool> _navigateToGame(
    String gameId,
    GlobalKey<NavigatorState> navigatorKey,
    WidgetRef ref, {
    String? initialFen,
    bool preferGamebase = false,
    bool preserveCurrentRoute = false,
  }) async {
    // Guard: Debounce duplicate links (same game within short time). Before
    // taking a generation: the duplicate must not supersede the original.
    final now = DateTime.now();
    if (_lastHandledGameId == gameId && _lastHandledTime != null) {
      final timeSinceLastHandle = now.difference(_lastHandledTime!);
      if (timeSinceLastHandle < _debounceDuration) {
        debugPrint('DeepLinkService: Duplicate link ignored (debounce)');
        return true;
      }
    }

    // Update tracking
    _lastHandledGameId = gameId;
    _lastHandledTime = now;
    final generation = ++_destinationGeneration;
    bool superseded() => generation != _destinationGeneration;

    try {
      // Keep only auth restore and splash completion on the critical path.
      // Round-game context is useful for swiping, but it should never delay
      // opening the tapped game from a shared link.
      debugPrint('DeepLinkService: Fetching game: $gameId');
      _addBreadcrumb('fetching game', data: {'gameId': gameId});

      final authFuture = _waitForAuthenticatedSession(ref);
      final appReadyFuture = _appReadyCompleter.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          debugPrint(
            'DeepLinkService: Timed out waiting for app ready, proceeding',
          );
        },
      );

      // Auth is required before we can proceed.
      final isAuthenticated = await authFuture;
      if (superseded()) return true;
      // A guest's session outlives the Google or Apple sign-in it starts:
      // a board opened now would close the Sign up page mid sign-in.
      final underWay = _authUnderWay(ref);
      if (!isAuthenticated || _signInOnScreen || underWay) {
        debugPrint(
          'DeepLinkService: No session or sign-in on screen; holding the link',
        );
        await appReadyFuture;
        if (superseded()) return true;
        // Held for Home: the board opens once the reader is signed in.
        final ready = await _readyToOpen(
          ref,
          navigatorKey,
          stage: 'game_link_requires_auth',
          signedIn: underWay ? null : isAuthenticated,
        );
        if (superseded()) return true;
        // Onboarding or sign-in left the screen while the splash finished:
        // nothing was held, so the board opens now.
        if (!ready) return false;
      }

      if (preferGamebase) {
        await _openGamebaseGame(
          gameId,
          navigatorKey,
          ref,
          initialFen: initialFen,
          appReadyFuture: appReadyFuture,
          preserveCurrentRoute: preserveCurrentRoute,
          superseded: superseded,
        );
        return true;
      }

      final gameRepo = ref.read(gameRepositoryProvider);
      Games game;
      try {
        game = await gameRepo.getGameByAnyId(gameId).timeout(_fetchTimeout);
      } catch (e) {
        // Older gamebase share links (or ones with a stripped `src` param)
        // carry a gamebase uuid that isn't in the app's games table — fall
        // back to the gamebase API before giving up.
        if (!_sharedGameUuidPattern.hasMatch(gameId.trim())) rethrow;
        await _openGamebaseGame(
          gameId,
          navigatorKey,
          ref,
          initialFen: initialFen,
          appReadyFuture: appReadyFuture,
          preserveCurrentRoute: preserveCurrentRoute,
          superseded: superseded,
        );
        return true;
      }
      if (superseded()) return true;
      final resolvedGameId = game.id;
      final gameTourModel = GamesTourModel.fromGame(game);
      // Warm video alongside the remaining route/context hydration, including
      // cold links that never visited a tournament list or game card.
      ref.read(eventVideoMetadataProvider.notifier).prefetch([
        EventVideoKey(
          tourId: gameTourModel.tourId,
          roundId: gameTourModel.roundId,
        ),
      ], priority: true);

      await appReadyFuture;
      if (superseded()) return true;

      // Resolve tournament context so swiping and tournament button works.
      final roundRepo = ref.read(roundRepositoryProvider);
      final tourRepo = ref.read(tourRepositoryProvider);
      final broadcastRepo = ref.read(groupBroadcastRepositoryProvider);

      try {
        final round = await roundRepo
            .getRoundById(game.roundId)
            .timeout(_fetchTimeout);
        final tour = await tourRepo
            .getToursByIds([round.tourId])
            .timeout(_fetchTimeout);

        if (tour.isNotEmpty) {
          final broadcastId = tour.first.groupBroadcastId;
          if (broadcastId != null) {
            final broadcast = await broadcastRepo
                .getGroupBroadcastById(broadcastId)
                .timeout(_fetchTimeout);

            // Pre-select tour and round so the tournament button in board screen works
            await _preselectTourAndRound(
              ref,
              groupBroadcastId: broadcast.id,
              tourId: tour.first.id,
              roundId: round.id,
            );

            ref.read(selectedBroadcastModelProvider.notifier).state = broadcast;
            ref.read(chessboardViewFromProviderNew.notifier).state =
                ChessboardView.tour;
          } else {
            ref.read(chessboardViewFromProviderNew.notifier).state =
                ChessboardView.forYou;
          }
        } else {
          ref.read(chessboardViewFromProviderNew.notifier).state =
              ChessboardView.forYou;
        }
      } catch (e) {
        debugPrint('DeepLinkService: Failed to resolve full context: $e');
        ref.read(chessboardViewFromProviderNew.notifier).state =
            ChessboardView.forYou;
      }

      final roundGamesFuture = gameRepo
          .getGamesByRoundId(game.roundId)
          .timeout(_fetchTimeout);

      debugPrint('DeepLinkService: Game loaded, navigating to chess board');
      _addBreadcrumb(
        'navigating to chess board',
        data: {
          'gameId': gameId,
          'resolvedGameId': resolvedGameId,
          'roundId': game.roundId,
          'openIndex': 0,
          'gameListLength': 1,
        },
      );
      unawaited(
        _captureDeepLinkMessage(
          'deep link game loaded',
          stage: 'navigate_to_game_success',
          extras: {
            'gameId': gameId,
            'resolvedGameId': resolvedGameId,
            'roundId': game.roundId,
            'openIndex': 0,
            'gameListLength': 1,
          },
        ),
      );
      if (superseded()) return true;
      ref.read(shouldStreamProvider.notifier).state = false;

      final navigator = navigatorKey.currentState;
      final boardPage = debugBoardPageBuilder;
      if (navigator != null) {
        final route = MaterialPageRoute(
          builder: (_) =>
              boardPage?.call(gameTourModel) ??
              _DeepLinkedChessBoardRoute(
                initialGame: gameTourModel,
                initialGameId: resolvedGameId,
                viewSource: ref.read(chessboardViewFromProviderNew),
                initialFen: initialFen,
                roundGamesFuture: roundGamesFuture,
                onRoundGamesError: (error, stackTrace) {
                  debugPrint(
                    'DeepLinkService: Failed to load round games for swipe context: $error',
                  );
                  _captureDeepLinkException(
                    error,
                    stackTrace,
                    stage: 'load_round_games_for_swipe_context',
                    extras: {'gameId': gameId, 'roundId': game.roundId},
                    captureAsException: false,
                  );
                },
              ),
        );
        if (preserveCurrentRoute) {
          navigator.push(route);
        } else {
          navigator.pushAndRemoveUntil(route, (route) => route.isFirst);
        }
      }
      return navigator != null;
    } catch (e, stackTrace) {
      debugPrint('DeepLinkService: Failed to load game: $e');
      // Slow network (10s timeout, CHESSEVER-15M) or a stale/deleted game link
      // ("No rows found", CHESSEVER-162) are expected and recovered by routing
      // home — record a breadcrumb instead of alarming as a Sentry error.
      final msg = e.toString().toLowerCase();
      final expected =
          _isTransientNetworkError(e) ||
          msg.contains('no rows found') ||
          msg.contains('notfoundexception') ||
          msg.contains('gamebase game not found');
      _captureDeepLinkException(
        e,
        stackTrace,
        stage: 'navigate_to_game',
        extras: {'gameId': gameId},
        captureAsException: !expected,
      );
      if (superseded()) return true;
      _addBreadcrumb(
        preserveCurrentRoute
            ? 'in-app game reference failed'
            : 'game deep link failed',
        data: {'gameId': gameId},
      );
      if (!preserveCurrentRoute) {
        _linkFailed(
          navigatorKey,
          reason: 'game_link_failed',
          extras: {'gameId': gameId},
          report: false,
        );
      }
      return false;
    }
  }

  /// Resolve a TWIC/gamebase archive game by its gamebase uuid and open it
  /// on the board. Archive games have no round/tournament context in the
  /// app database, so the board opens as a single game without swipe context.
  Future<void> _openGamebaseGame(
    String gameId,
    GlobalKey<NavigatorState> navigatorKey,
    WidgetRef ref, {
    String? initialFen,
    required Future<void> appReadyFuture,
    bool preserveCurrentRoute = false,
    bool Function()? superseded,
  }) async {
    bool stale() => superseded?.call() ?? false;
    await appReadyFuture;
    if (stale()) return;
    final context = navigatorKey.currentState?.overlay?.context;
    if (context == null || !context.mounted) return;
    if (!await ensurePremiumGameAccess(
      context,
      featureId: 'archive_games',
      returnTo: 'shared_game',
    )) {
      return;
    }
    if (!context.mounted) return;
    final gamebaseGame = await ref
        .read(gamebaseRepositoryProvider)
        .getGameById(gameId)
        .timeout(_fetchTimeout);
    if (gamebaseGame == null) {
      // Message intentionally contains "not found" so the outer handler
      // treats a stale/deleted link as expected instead of a Sentry error.
      throw Exception('Gamebase game not found: $gameId');
    }

    final gameTourModel = mapGamebaseGameToGamesTourModel(gamebaseGame);

    if (!context.mounted || stale()) return;

    ref.read(chessboardViewFromProviderNew.notifier).state =
        ChessboardView.forYou;
    ref.read(shouldStreamProvider.notifier).state = false;

    _addBreadcrumb('navigating to gamebase game', data: {'gameId': gameId});
    unawaited(
      _captureDeepLinkMessage(
        'deep link gamebase game loaded',
        stage: 'navigate_to_gamebase_game_success',
        extras: {'gameId': gameId},
      ),
    );

    final route = MaterialPageRoute<void>(
      builder: (_) => ChessBoardScreenNew(
        key: ValueKey('deep-link-gamebase-$gameId'),
        games: [gameTourModel],
        currentIndex: 0,
        viewSource: ChessboardView.forYou,
        playerProfileDataSource: PlayerProfileDataSource.twic,
        initialFen: initialFen,
        showGamebaseButton: false,
        showClock: false,
      ),
    );
    // In-app references open above the screen that asked, like the
    // Supabase-game path does; shared links still reset to the root.
    if (preserveCurrentRoute) {
      navigatorKey.currentState?.push(route);
    } else {
      navigatorKey.currentState?.pushAndRemoveUntil(
        route,
        (route) => route.isFirst,
      );
    }
  }

  Future<bool> _waitForAuthenticatedSession(WidgetRef ref) async {
    final deadline = DateTime.now().add(kAuthRestoreTimeout);

    while (DateTime.now().isBefore(deadline)) {
      if (_isFullyAuthenticated(ref.read(authStateProvider).valueOrNull)) {
        return true;
      }

      final session = Supabase.instance.client.auth.currentSession;
      final user = Supabase.instance.client.auth.currentUser;
      if (session != null && user != null && !session.isExpired) {
        return true;
      }

      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    if (_isFullyAuthenticated(ref.read(authStateProvider).valueOrNull)) {
      return true;
    }

    final session = Supabase.instance.client.auth.currentSession;
    final user = Supabase.instance.client.auth.currentUser;
    return session != null && user != null && !session.isExpired;
  }

  /// Any session — including a guest (anonymous) one — can open shared links.
  /// A guest is a normal free account, and shared links are how most of them
  /// arrive, so gating deep links on a provider login would drop exactly the
  /// users this flow exists to keep.
  bool _isFullyAuthenticated(AppAuthState? state) {
    return state?.status == AppAuthStatus.authenticated;
  }

  /// Route based on notification data payload.
  /// Called from the direct-push click listener.
  void handleNotificationData(
    Map<String, dynamic> raw,
    GlobalKey<NavigatorState> navigatorKey,
    WidgetRef ref,
  ) {
    final data = unwrapOneSignalPush(raw);
    final generation = ++_destinationGeneration;
    _inbound = _InboundDestination.push(Map<String, dynamic>.of(data));
    if (data['type'] == 'favorite_player_news') {
      final article = favoritePlayerNewsDestination(data);
      if (article == null) return;
      unawaited(
        _navigateToAppDestination(
          article,
          navigatorKey,
          ref,
          generation: generation,
        ),
      );
      return;
    }
    final configuredRoute = _asNonEmptyString(data['route']);
    final inboxMessageId = _asNonEmptyString(data['inbox_message_id']);
    final destination = configuredRoute == null
        ? null
        : parseAppDestination(configuredRoute);
    final routeUri = configuredRoute == null
        ? null
        : Uri.tryParse(configuredRoute);
    final webTarget = routeUri == null
        ? null
        : (webViewLinkTarget(routeUri) ??
              (destination == null &&
                      !isWebViewLink(routeUri) &&
                      !isNativeAppLink(routeUri)
                  ? webViewUrl(configuredRoute)
                  : null));
    if (webTarget != null) {
      unawaited(
        _navigateToWebView(
          webTarget,
          navigatorKey,
          ref,
          generation: generation,
        ),
      );
      return;
    }
    if (destination != null) {
      unawaited(
        _navigateToAppDestination(
          destination,
          navigatorKey,
          ref,
          generation: generation,
          fallbackInboxMessageId: inboxMessageId,
        ),
      );
      return;
    }
    if (configuredRoute != null) {
      _addBreadcrumb('unsupported notification destination');
    }
    // An Inbox publication owns its tap unless an explicit destination is set.
    // Its article action URL is deliberately unrelated to the push destination.
    if (inboxMessageId != null) {
      unawaited(
        _navigateToInbox(
          navigatorKey,
          ref,
          messageId: inboxMessageId,
          generation: generation,
        ),
      );
      return;
    }
    final portalUrl = Uri.tryParse(
      data['url'] is String ? data['url'] as String : '',
    );
    if (portalUrl != null) {
      final explicitWebTarget = webViewLinkTarget(portalUrl);
      if (explicitWebTarget != null) {
        unawaited(
          _navigateToWebView(
            explicitWebTarget,
            navigatorKey,
            ref,
            generation: generation,
          ),
        );
        return;
      }
      final webUrl =
          isWebViewLink(portalUrl) ||
              (isNativeAppLink(portalUrl) &&
                  parseAppDestination(portalUrl.toString()) == null)
          ? null
          : webViewUrl(portalUrl.toString());
      if (webUrl != null) {
        // Preserve existing native URL notifications. Use the explicit
        // WebView wrapper (or data.route URL) to force those into the browser.
        final nativeHost =
            portalUrl.scheme == 'https' &&
            portalUrl.port == 443 &&
            const {
              'chessever.com',
              'www.chessever.com',
            }.contains(portalUrl.host);
        final legacyPath = portalUrl.pathSegments;
        final nativePath =
            parseAppDestination(portalUrl.toString()) != null ||
            NewsLink.parse(portalUrl) != null ||
            (legacyPath.length >= 2 &&
                const {
                  'games',
                  'broadcast',
                  'player',
                  'books',
                  'databases',
                  'folders',
                  'collections',
                }.contains(legacyPath.first));
        if (nativeHost && nativePath) {
          handleDeepLink(portalUrl, navigatorKey, ref);
        } else {
          unawaited(
            _navigateToWebView(
              webUrl,
              navigatorKey,
              ref,
              generation: generation,
            ),
          );
        }
        return;
      }
    }

    final type = _asNonEmptyString(data['type'])?.toLowerCase();

    debugPrint('DeepLinkService: Handling notification data: type=$type');

    final gameId = _firstNonEmptyString([data['game_id'], data['gameId']]);
    final broadcastId = _firstNonEmptyString([
      data['group_broadcast_id'],
      data['groupBroadcastId'],
      data['group_id'],
      data['event_id'],
    ]);
    final roundId = _firstNonEmptyString([data['round_id'], data['roundId']]);
    final tourId = _firstNonEmptyString([
      data['tour_id'],
      data['tourId'],
      data['category_id'],
    ]);
    final folderId = _firstNonEmptyString([
      data['folder_id'],
      data['folderId'],
    ]);
    final collectionSlug = _firstNonEmptyString([
      data['collection_slug'],
      data['collectionSlug'],
    ]);
    final prepProfileId = _firstNonEmptyString([data['prep_profile_id']]);

    // The notification path used to be completely untelemetered, so a tap that
    // ended on Home was indistinguishable from a tap that never reached Dart at
    // all. Record what arrived and whether the app was already past splash
    // (backgrounded) or still cold-starting — that split is the whole bug.
    final wasAppReady = _appReadyCompleter.isCompleted;
    _addBreadcrumb(
      'notification tap received',
      data: {
        'type': type,
        'appReady': wasAppReady,
        'hasGameId': gameId != null,
        'hasBroadcastId': broadcastId != null,
        'hasRoundId': roundId != null,
        'hasTourId': tourId != null,
        'hasFolderId': folderId != null,
        'hasCollectionSlug': collectionSlug != null,
        'hasPrepProfileId': prepProfileId != null,
        'keys': data.keys.toList()..sort(),
      },
    );

    switch (type) {
      case 'game_started':
      case 'game_finished':
        if (gameId != null && gameId.isNotEmpty) {
          _navigateToGame(gameId, navigatorKey, ref);
        } else {
          _navigateToHome(
            navigatorKey,
            reason: 'notification_missing_game_id',
            extras: {'type': type, 'appReady': wasAppReady},
          );
        }
        return;
      case 'round_started':
      case 'round_heads_up':
      case 'round_finished':
        if (broadcastId != null || roundId != null || tourId != null) {
          _navigateToEvent(
            broadcastId,
            navigatorKey,
            ref,
            roundId: roundId,
            tourId: tourId,
          );
        } else {
          _navigateToHome(
            navigatorKey,
            reason: 'notification_missing_event_ids',
            extras: {'type': type, 'appReady': wasAppReady},
          );
        }
        return;
      case 'collection_games_added':
        if (collectionSlug != null) {
          final added = data['added'];
          _navigateToCollection(
            collectionSlug,
            navigatorKey,
            ref,
            added: added is num
                ? added.toInt()
                : int.tryParse('${added ?? ''}'),
            title: _firstNonEmptyString([data['collection_title']]),
            fromPush: true,
          );
        } else {
          _navigateToHome(
            navigatorKey,
            reason: 'notification_missing_collection_slug',
            extras: {'type': type, 'appReady': wasAppReady},
          );
        }
        return;
      case 'smart_event_games':
        if (smartEventRequestFromPushData(data) != null) {
          _navigateToSmartEvent(data, navigatorKey, ref);
        } else if (gameId != null && gameId.isNotEmpty) {
          _navigateToGame(gameId, navigatorKey, ref);
        } else {
          _navigateToHome(
            navigatorKey,
            reason: 'notification_missing_smart_event',
            extras: {'type': type, 'appReady': wasAppReady},
          );
        }
        return;
      case 'prep_games_added':
        if (prepProfileId != null) {
          final added = data['added'];
          _navigateToPrepProfile(
            prepProfileId,
            navigatorKey,
            ref,
            newGames: added is num
                ? added.toInt()
                : int.tryParse('${added ?? ''}'),
            profileName: _firstNonEmptyString([data['profile_name']]),
          );
        } else {
          _navigateToHome(
            navigatorKey,
            reason: 'notification_missing_prep_profile_id',
            extras: {'type': type, 'appReady': wasAppReady},
          );
        }
        return;
      case 'book_game_added':
      case 'book_game_updated':
      case 'book_game_removed':
        if (folderId != null && folderId.isNotEmpty) {
          _navigateToFolder(folderId, navigatorKey, ref);
        } else {
          _navigateToHome(
            navigatorKey,
            reason: 'notification_missing_folder_id',
            extras: {'type': type, 'appReady': wasAppReady},
          );
        }
        return;
      default:
        // Best-effort fallback for payloads with routing hints.
        if (gameId != null) {
          _navigateToGame(gameId, navigatorKey, ref);
          return;
        }

        if (broadcastId != null || roundId != null || tourId != null) {
          _navigateToEvent(
            broadcastId,
            navigatorKey,
            ref,
            roundId: roundId,
            tourId: tourId,
          );
          return;
        }

        if (folderId != null) {
          _navigateToFolder(folderId, navigatorKey, ref);
          return;
        }

        // call_to_action and any unknown types — open the app to home.
        // Home IS the destination of a push that names nothing to open
        // (dashboard sends arrive as `default`), so this is not a failed
        // route: breadcrumb only (CHESSEVER-15Z was all this case).
        _navigateToHome(
          navigatorKey,
          reason: 'notification_no_routing_hints',
          extras: {'type': type, 'appReady': wasAppReady},
          report: false,
        );
        return;
    }
  }

  /// Opens [url] in the app's WebView over the app. A link or push waits,
  /// like every other destination, while a sign-in, sign-out or deletion is
  /// under way and while sign-in or onboarding is alone on screen (O22): the
  /// Home the reader lands on routes it ([drainPendingDestination]), or, for
  /// a sign-in that ends without one, [_resumeAfterAbandonedSignIn]. Opened
  /// then, the page sat over the Sign up page and the Home the finished
  /// sign-in builds removed it. A web page needs no account, so a reader
  /// with no session and no sign-in page in front still gets it at once.
  /// [inPlace] links (tapped on a page in the app) are never held.
  Future<void> _navigateToWebView(
    Uri url,
    GlobalKey<NavigatorState> navigatorKey,
    WidgetRef ref, {
    required int generation,
    bool inPlace = false,
  }) async {
    await _appReadyCompleter.future;
    final navigator = navigatorKey.currentState;
    bool isCurrent() =>
        navigator != null &&
        navigator.mounted &&
        generation == _destinationGeneration;
    if (!isCurrent()) return;
    if (!inPlace) {
      // A session still being restored decides whether sign-in comes up.
      if (ref.read(authStateProvider).isLoading) {
        try {
          await ref.read(authStateProvider.future).timeout(kAuthRestoreTimeout);
        } catch (_) {
          // Restore failed or timed out: the screen in front decides.
        }
        if (!isCurrent()) return;
      }
      if (_authUnderWay(ref) || _signInOnScreen) {
        _holdInbound('webview_waits_for_sign_in');
        return;
      }
    }
    if (!navigator!.mounted) return;
    ref.read(appDestinationPageNavigationProvider)(
      navigator.context,
      AppWebViewScreen(url: url),
      '/app/webview',
    );
  }

  Future<void> _navigateToAppDestination(
    AppDestination destination,
    GlobalKey<NavigatorState> navigatorKey,
    WidgetRef ref, {
    required int generation,
    String? fallbackInboxMessageId,
    bool preserveCurrentRoute = false,
  }) async {
    await _appReadyCompleter.future;
    final navigator = navigatorKey.currentState;
    bool isCurrent() =>
        generation == _destinationGeneration &&
        navigator != null &&
        navigator.mounted;
    if (!isCurrent()) return;
    try {
      if (!await _awaitDestinationSession(ref, isCurrent: isCurrent)) {
        // No session (sign-in or onboarding on screen): Home routes it once
        // the reader is signed in, instead of the tap being lost.
        if (isCurrent()) _holdInbound('app_destination_requires_auth');
        return;
      }
      if (!navigator!.mounted) return;
      if (destination.kind == AppDestinationKind.inbox) {
        await _navigateToInbox(
          navigatorKey,
          ref,
          messageId: destination.id,
          generation: generation,
        );
        return;
      }
      // Every configured destination starts above a usable app root on a cold
      // launch too. Existing content resolvers keep their auth/access guards.
      if (!preserveCurrentRoute) _ensureHomeRoot(navigator);
      final opened = await openAppDestination(
        navigator.context,
        ref,
        destination,
        isCurrent: isCurrent,
        openLegacyLink: (link) async {
          if (!isCurrent()) return true;
          // `/app/games/<id>` and its kin from a page in the app open over
          // that page too, never by replacing the pages over Home.
          _handleDeepLink(
            Uri.parse(link),
            navigatorKey,
            ref,
            trusted: true,
            inPlace: preserveCurrentRoute,
          );
          return true;
        },
        openInboxMessage: (messageId) => _navigateToInbox(
          navigatorKey,
          ref,
          messageId: messageId,
          generation: generation,
        ),
      );
      if (opened) return;
    } catch (error, stackTrace) {
      _captureDeepLinkException(
        error,
        stackTrace,
        stage: 'notification_app_destination',
      );
    }
    if (!isCurrent()) return;
    if (fallbackInboxMessageId != null) {
      await _navigateToInbox(
        navigatorKey,
        ref,
        messageId: fallbackInboxMessageId,
        generation: generation,
      );
    } else if (preserveCurrentRoute) {
      // Opened from a page in the app: the reader stays on it.
      _snackLinkFailed(navigatorKey);
    } else {
      _linkFailed(navigatorKey, reason: 'app_destination_unavailable');
    }
  }

  /// Startup may finish while the restored guest/account is still loading.
  /// If restoration fails, retain the existing auth screen rather than replacing
  /// it with Home. No notification destination grants a session of its own.
  Future<bool> _awaitDestinationSession(
    WidgetRef ref, {
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return false;
    if (ref.read(currentUserProvider) != null) return true;
    if (ref.read(authStateProvider).isLoading) {
      try {
        await ref.read(authStateProvider.future).timeout(kAuthRestoreTimeout);
      } catch (_) {
        return false;
      }
    }
    return isCurrent() &&
        (ref.read(currentUserProvider) != null ||
            _guestSessionOutlivesAuthState(
              ref.read(authStateProvider).valueOrNull,
            ));
  }

  /// Restores the Inbox stack after startup, then opens this exact publication.
  /// The detail observes the account-scoped controller while it refreshes, so
  /// a cold cache or an offline failure never marks a different message read.
  Future<bool> _navigateToInbox(
    GlobalKey<NavigatorState> navigatorKey,
    WidgetRef ref, {
    String? messageId,
    required int generation,
  }) async {
    await _appReadyCompleter.future;
    final navigator = navigatorKey.currentState;
    if (navigator == null ||
        !navigator.mounted ||
        generation != _destinationGeneration) {
      return false;
    }
    if (!await _awaitDestinationSession(
      ref,
      isCurrent: () =>
          navigator.mounted && generation == _destinationGeneration,
    )) {
      if (navigator.mounted && generation == _destinationGeneration) {
        _holdInbound('inbox_requires_auth');
      }
      return false;
    }
    final messageOwner = ref.read(inboxProvider).ownerId;
    _ensureHomeRoot(navigator);
    navigator.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/app/inbox'),
        builder: (_) => const InboxScreen(),
      ),
    );
    if (messageId != null && messageOwner != null) {
      navigator.push(
        MaterialPageRoute<void>(
          settings: RouteSettings(name: '/app/inbox/$messageId'),
          builder: (_) =>
              InboxMessageScreen(ownerId: messageOwner, messageId: messageId),
        ),
      );
    }
    return true;
  }

  /// Navigate to home screen — the fallback when a tap can't be resolved to a
  /// real destination.
  ///
  /// Every fallback is recorded. Landing on Home is precisely the reported
  /// failure, and until now it left no trace, so a device report ("I ended up
  /// on Home") could not be told apart from the tap never reaching Dart.
  /// [report] is false where the caller already captured the underlying error.
  void _navigateToHome(
    GlobalKey<NavigatorState> navigatorKey, {
    required String reason,
    Map<String, dynamic>? extras,
    bool report = true,
  }) {
    _addBreadcrumb(
      'falling back to home',
      data: {'reason': reason, ...?extras},
    );
    if (report) {
      unawaited(
        _captureDeepLinkMessage(
          'deep link fell back to home',
          stage: 'fallback_to_home',
          extras: {'reason': reason, ...?extras},
          level: SentryLevel.warning,
        ),
      );
    }
    final navigator = navigatorKey.currentState;
    if (navigator != null) _ensureHomeRoot(navigator);
  }

  /// Lands on Home. A home shell already standing on [navigator] is kept
  /// (pages over it close; its section, tabs and scroll stay) instead of
  /// being built anew, which re-ran its session count, ATT, Shorebird and
  /// review prompt on every tap. Only with no shell is Home made the one
  /// route. Home shows its dock either way.
  void _ensureHomeRoot(NavigatorState navigator) {
    if (!popToHomeShell(navigator)) {
      navigator.pushNamedAndRemoveUntil('/home_screen', (route) => false);
    }
    final ref = _routerRef;
    if (ref != null) {
      try {
        ref.read(homeChromeRevealRequestProvider.notifier).state++;
      } catch (_) {
        // A ref whose scope is gone: nothing to reveal.
      }
    }
  }

  /// A link or push that could not be opened. With the app already up on
  /// Home (a warm start, a board being read), the reader stays where they
  /// are and is told ([message], a [userFacingError] where there is an
  /// error to explain); only a cold start falls back to Home.
  void _linkFailed(
    GlobalKey<NavigatorState> navigatorKey, {
    required String reason,
    Map<String, dynamic>? extras,
    bool report = true,
    String message = kLinkFailedMessage,
  }) {
    final navigator = navigatorKey.currentState;
    if (navigator != null && hasHomeShellOn(navigator)) {
      _addBreadcrumb(
        'link failed; staying in place',
        data: {'reason': reason, ...?extras},
      );
      _snackLinkFailed(navigatorKey, message: message);
      return;
    }
    _navigateToHome(
      navigatorKey,
      reason: reason,
      extras: extras,
      report: report,
    );
  }

  /// Onboarding or sign-in owns the screen with no Home under it (a cold
  /// start signed out, a new reader onboarding). A guest's Sign up opened
  /// over the app has Home under it: links open there as before, since Home
  /// will not mount again to route a held one.
  bool get _signInOnScreen {
    if (!_signInRoutes.contains(
      GuestGateRouteObserver.instance.topRouteName.value,
    )) {
      return false;
    }
    final navigator = _routerNavigatorKey?.currentState;
    return navigator == null || !hasHomeShellOn(navigator);
  }

  /// Whether a sign-in (Google or Apple being asked), a sign-out or an
  /// account deletion is under way. The auth controller says so as data
  /// ([AppAuthStatus.loading]) until it lands, so the reader is neither
  /// signed in nor signed out yet.
  bool _authUnderWay(WidgetRef ref) {
    try {
      return ref.read(authStateProvider).valueOrNull?.status ==
          AppAuthStatus.loading;
    } catch (_) {
      return false;
    }
  }

  /// A Google or Apple sign-in that was cancelled or failed leaves the auth
  /// state at `error` (a guest's upgrade) or `unauthenticated` while the
  /// guest's anonymous session lives on, until a token refresh reports it
  /// again (O20). That reader is still the guest, and a guest is a session:
  /// links open for them as for any session, never with sign-in pushed over
  /// their Home.
  bool _guestSessionOutlivesAuthState(AppAuthState? state) {
    final status = state?.status;
    if (status != AppAuthStatus.error &&
        status != AppAuthStatus.unauthenticated) {
      return false;
    }
    try {
      final auth = Supabase.instance.client.auth;
      final session = auth.currentSession;
      return session != null && auth.currentUser != null && !session.isExpired;
    } catch (_) {
      return false;
    }
  }

  /// Watches the sign-in a held link waits on ([_holdInbound] while
  /// [_authUnderWay]). Null when nothing waits on one.
  ProviderSubscription<AsyncValue<AppAuthState>>? _signInAttempt;

  void _watchSignInAttempt() {
    final ref = _routerRef;
    if (ref == null || _signInAttempt != null) return;
    try {
      _signInAttempt = ref.listenManual<AsyncValue<AppAuthState>>(
        authStateProvider,
        (_, next) {
          if (next.isLoading ||
              next.valueOrNull?.status == AppAuthStatus.loading) {
            return;
          }
          final attempt = _signInAttempt;
          _signInAttempt = null;
          // Closed outside the notification that is delivering this call.
          scheduleMicrotask(() => attempt?.close());
          // Signed in: the Home the finished sign-in builds anew routes it
          // (AuthScreen, AuthStateListener), as before.
          if (next.valueOrNull?.status == AppAuthStatus.authenticated) return;
          // Cancelled or failed: let the sign-in page settle first.
          WidgetsBinding.instance
            ..addPostFrameCallback((_) => _resumeAfterAbandonedSignIn())
            ..ensureVisualUpdate();
        },
      );
    } catch (_) {
      // A ref whose scope is gone: the next Home routes the held link.
      _signInAttempt = null;
    }
  }

  void _stopWatchingSignInAttempt() {
    final attempt = _signInAttempt;
    _signInAttempt = null;
    attempt?.close();
    _abandonedSignInCheck?.cancel();
    _abandonedSignInCheck = null;
  }

  /// How long a held link waits, after an attempt ends with no session, for
  /// the sign-in page the app puts up then (a sign-out lands there after
  /// clearing the reader's caches) before it is let go.
  static const _abandonedSignInGrace = Duration(seconds: 3);
  Timer? _abandonedSignInCheck;

  /// The sign-in, sign-out or deletion a held link or push waited on ended
  /// without signing in (Google's or Apple's sheet dismissed, a failure), so
  /// no new Home will mount to route it (O20). With the guest's session
  /// still alive it opens now, as the guest
  /// ([_guestSessionOutlivesAuthState]). With sign-in or onboarding alone on
  /// screen it keeps waiting for the Home that sign-in builds; that screen
  /// may take a moment to come up (a sign-out), so with neither it is
  /// looked at again after [_abandonedSignInGrace]. Still neither: nothing
  /// can open it, and it is let go with a quiet word instead of waiting
  /// unseen or putting sign-in over Home.
  void _resumeAfterAbandonedSignIn({bool afterGrace = false}) {
    if (!afterGrace) _abandonedSignInCheck?.cancel();
    final pending = _pending;
    final navigatorKey = _routerNavigatorKey;
    final ref = _routerRef;
    if (pending == null || navigatorKey == null || ref == null) return;
    final AppAuthState? state;
    try {
      state = ref.read(authStateProvider).valueOrNull;
    } catch (_) {
      return;
    }
    switch (state?.status) {
      case AppAuthStatus.loading:
        // Tried again straight away: wait for that attempt.
        _watchSignInAttempt();
        return;
      case AppAuthStatus.authenticated:
        return;
      default:
        break;
    }
    if (_guestSessionOutlivesAuthState(state)) {
      _addBreadcrumb('sign-in abandoned; routing held link as the guest');
      drainPendingDestination();
      return;
    }
    if (_signInOnScreen) return;
    if (!afterGrace) {
      _abandonedSignInCheck = Timer(_abandonedSignInGrace, () {
        _abandonedSignInCheck = null;
        if (identical(_pending, pending)) {
          _resumeAfterAbandonedSignIn(afterGrace: true);
        }
      });
      return;
    }
    _pending = null;
    _addBreadcrumb('sign-in abandoned with no session; held link dropped');
    _snackAfterNavigation(navigatorKey, kHeldLinkNeedsSignInMessage);
  }

  /// Whether a link may open now: a session exists and the reader is not
  /// signing in or onboarding. Otherwise the link is held for Home
  /// ([drainPendingDestination]) and, with no session and no sign-in page
  /// on screen, sign-in opens.
  ///
  /// A sign-in, sign-out or deletion under way holds the link without
  /// opening anything: sign-in over a guest's Sign up would remove the Home
  /// under it, and a page opened now would be removed by the Home that a
  /// finished sign-in builds anew (AuthScreen, AuthStateListener). That
  /// Home routes it. [signedIn] is a caller's own finished check.
  Future<bool> _readyToOpen(
    WidgetRef ref,
    GlobalKey<NavigatorState> navigatorKey, {
    required String stage,
    bool? signedIn,
  }) async {
    var isSignedIn = signedIn;
    if (isSignedIn == null) {
      // A state still loading (a restore, a sign-in just made) is not read
      // from its previous value: that is the signed-out state it replaces.
      final auth = ref.read(authStateProvider);
      AppAuthState? resolvedState = auth.isLoading ? null : auth.value;
      if (resolvedState == null) {
        try {
          resolvedState = await ref
              .read(authStateProvider.future)
              .timeout(kAuthRestoreTimeout);
        } catch (_) {
          resolvedState = null;
        }
      }
      if (resolvedState?.status == AppAuthStatus.loading) {
        _holdInbound(stage, authUnderWay: true);
        return false;
      }
      isSignedIn =
          _isFullyAuthenticated(resolvedState) ||
          _guestSessionOutlivesAuthState(resolvedState);
    }
    if (isSignedIn && !_signInOnScreen) return true;
    _holdInbound(stage, signedIn: isSignedIn);
    if (!isSignedIn && !_signInOnScreen) {
      navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/auth_screen',
        (route) => false,
      );
    }
    return false;
  }

  /// Keeps the link or push being routed for Home ([drainPendingDestination]).
  void _holdInbound(
    String stage, {
    bool signedIn = false,
    bool authUnderWay = false,
  }) {
    final inbound = _inbound;
    if (inbound != null) _pending = inbound;
    final ref = _routerRef;
    final underWay = authUnderWay || (ref != null && _authUnderWay(ref));
    // A sign-in that ends without signing in builds no new Home to route
    // it: watch it, so the link opens or is let go then (O20).
    if (inbound != null && underWay) _watchSignInAttempt();
    _addBreadcrumb(
      'deep link held until Home',
      data: {
        'stage': stage,
        'signedIn': signedIn,
        if (underWay) 'authUnderWay': true,
      },
    );
  }

  /// Routes the link or push held while the reader signed in or onboarded.
  /// Home calls this once it is up; a no-op when nothing is held.
  void drainPendingDestination() {
    final pending = _pending;
    final navigatorKey = _routerNavigatorKey;
    final ref = _routerRef;
    if (pending == null || navigatorKey == null || ref == null) return;
    _pending = null;
    _stopWatchingSignInAttempt();
    if (DateTime.now().difference(pending.at) > _pendingLifetime) return;
    _addBreadcrumb('routing held deep link');
    // A deliberate second routing of the same link, never a duplicate
    // delivery: the same-game debounce must not swallow it.
    _lastHandledGameId = null;
    final link = pending.link;
    final push = pending.push;
    if (link != null) {
      // As trusted as it arrived: an outside link's WebView stays limited.
      _handleDeepLink(link, navigatorKey, ref, trusted: pending.trusted);
    } else if (push != null) {
      handleNotificationData(push, navigatorKey, ref);
    }
  }

  @visibleForTesting
  bool get hasPendingDestination => _pending != null;

  /// Fetch event by group_broadcast_id and navigate to tournament detail screen
  /// Returns false when the event could not be opened (or was held for
  /// sign-in). A call a newer tap superseded returns true: that tap owns the
  /// screen. [gatePastEvent] defaults to [preserveCurrentRoute].
  Future<bool> _navigateToEvent(
    String? groupBroadcastId,
    GlobalKey<NavigatorState> navigatorKey,
    WidgetRef ref, {
    String? roundId,
    String? tourId,
    String? tab,
    bool preserveCurrentRoute = false,
    bool? gatePastEvent,
  }) async {
    final generation = ++_destinationGeneration;
    bool superseded() => generation != _destinationGeneration;
    // In-app entries (My Space shortcuts, Botvinnik references) ask the
    // past-event gate; links do not, in place or not.
    final askPastEventAccess = gatePastEvent ?? preserveCurrentRoute;

    try {
      try {
        await _appReadyCompleter.future.timeout(const Duration(seconds: 30));
      } catch (_) {
        debugPrint(
          'DeepLinkService: Timed out waiting for app ready, proceeding',
        );
      }
      if (superseded()) return true;

      final ready = await _readyToOpen(
        ref,
        navigatorKey,
        stage: 'event_link_requires_auth',
      );
      if (superseded()) return true;
      if (!ready) return false;

      final routeContext = await _resolveEventRouteContext(
        ref,
        groupBroadcastId: groupBroadcastId,
        roundId: roundId,
        tourId: tourId,
      );
      if (superseded()) return true;
      if (routeContext == null) {
        debugPrint(
          'DeepLinkService: Could not resolve event route context from '
          'group_broadcast_id=$groupBroadcastId, round_id=$roundId, tour_id=$tourId',
        );
        _captureDeepLinkException(
          Exception('Failed to resolve event route context for deep link'),
          StackTrace.current,
          stage: 'resolve_event_route_context',
          extras: {
            'groupBroadcastId': groupBroadcastId,
            'roundId': roundId,
            'tourId': tourId,
          },
        );
        if (!preserveCurrentRoute) {
          _linkFailed(
            navigatorKey,
            reason: 'event_route_context_unresolved',
            extras: {
              'groupBroadcastId': groupBroadcastId,
              'roundId': roundId,
              'tourId': tourId,
            },
            report: false, // captured above as an exception
          );
        }
        return false;
      }

      debugPrint(
        'DeepLinkService: Fetching event: ${routeContext.groupBroadcastId}',
      );

      final broadcastRepo = ref.read(groupBroadcastRepositoryProvider);
      final broadcast = await broadcastRepo
          .getGroupBroadcastById(routeContext.groupBroadcastId)
          .timeout(_fetchTimeout);
      if (superseded()) return true;

      if (askPastEventAccess) {
        final context = navigatorKey.currentState?.context;
        if (context == null ||
            !context.mounted ||
            !await ensurePastEventAccess(context, broadcast: broadcast) ||
            !context.mounted) {
          // Dismissing access handles a valid shortcut without opening it.
          return true;
        }
      }

      await _preselectTourAndRound(
        ref,
        groupBroadcastId: broadcast.id,
        tourId: routeContext.tourId,
        roundId: routeContext.roundId,
      );
      if (superseded()) return true;

      ref.read(selectedBroadcastModelProvider.notifier).state = broadcast;
      ref.read(selectedTourModeProvider.notifier).state =
          tournamentDetailModeFromTabQuery(tab) ??
          TournamentDetailScreenMode.games;

      debugPrint(
        'DeepLinkService: Event loaded, navigating to tournament detail',
      );

      if (preserveCurrentRoute) {
        navigatorKey.currentState?.pushNamed('/tournament_detail_screen');
      } else {
        navigatorKey.currentState?.pushNamedAndRemoveUntil(
          '/tournament_detail_screen',
          (route) => route.isFirst,
        );
      }
      return navigatorKey.currentState != null;
    } catch (e, stackTrace) {
      debugPrint('DeepLinkService: Failed to load event: $e');
      // A slow/offline network makes the 10s fetch timeout (or socket failure)
      // throw here (CHESSEVER-169), and a stale/deleted event link yields
      // "No rows found" (CHESSEVER-1MF). Both are expected and recovered by
      // routing home, so record a breadcrumb rather than a Sentry error.
      final msg = e.toString().toLowerCase();
      final expected =
          _isTransientNetworkError(e) ||
          msg.contains('no rows found') ||
          msg.contains('notfoundexception');
      _captureDeepLinkException(
        e,
        stackTrace,
        stage: 'navigate_to_event',
        extras: {
          'groupBroadcastId': groupBroadcastId,
          'roundId': roundId,
          'tourId': tourId,
        },
        captureAsException: !expected,
      );
      if (superseded()) return true;
      if (!preserveCurrentRoute) {
        _linkFailed(navigatorKey, reason: 'event_link_failed', report: false);
      }
      return false;
    }
  }

  /// Transient, user-environment errors (slow/offline network) that are
  /// expected and recovered from — not actionable crashes.
  bool _isTransientNetworkError(Object error) {
    if (error is TimeoutException) return true;
    final text = error.toString().toLowerCase();
    return text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('connection closed') ||
        text.contains('connection reset') ||
        text.contains('network is unreachable') ||
        text.contains('no internet') ||
        text.contains('authretryablefetchexception');
  }

  /// The FCM transport turns a payload's JSON null into the string "null"
  /// (every data value is a string there), so "null" and "undefined" are
  /// absent ids, never a tour or group id to look up.
  String? _asNonEmptyString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    final lower = text.toLowerCase();
    if (lower == 'null' || lower == 'undefined') return null;
    return text;
  }

  String? _firstNonEmptyString(List<dynamic> values) {
    for (final value in values) {
      final text = _asNonEmptyString(value);
      if (text != null) return text;
    }
    return null;
  }

  /// Opens a specific player's scorecard from a shared link
  /// `chessever.com/broadcast/<slug>/<id>/player/<fideId>`. Resolves the event
  /// exactly like [_navigateToEvent], lands on the tournament detail (standings)
  /// so the scorecard has a back-stack, then matches the player by FIDE id in
  /// the standings and pushes the scorecard. If the player can't be resolved
  /// (standings still loading, no FIDE id) it degrades gracefully to the event.
  ///
  /// [preserveCurrentRoute] (in-app shortcuts) opens the event above the
  /// current route and never falls back to Home. Returns false when the event
  /// could not be opened. A call swallowed by the in-flight guard returns
  /// true: the earlier call owns it.
  Future<bool> _navigateToPlayerScorecard(
    String groupBroadcastId,
    int fideId,
    GlobalKey<NavigatorState> navigatorKey,
    WidgetRef ref, {
    bool preserveCurrentRoute = false,
  }) async {
    final generation = ++_destinationGeneration;
    bool superseded() => generation != _destinationGeneration;
    var landedOnEvent = false;

    try {
      try {
        await _appReadyCompleter.future.timeout(const Duration(seconds: 30));
      } catch (_) {
        debugPrint(
          'DeepLinkService: Timed out waiting for app ready, proceeding',
        );
      }
      if (superseded()) return true;

      final ready = await _readyToOpen(
        ref,
        navigatorKey,
        stage: 'player_scorecard_requires_auth',
      );
      if (superseded()) return true;
      if (!ready) return false;

      final routeContext = await _resolveEventRouteContext(
        ref,
        groupBroadcastId: groupBroadcastId,
      );
      if (superseded()) return true;
      if (routeContext == null) {
        debugPrint(
          'DeepLinkService: Could not resolve event for player scorecard '
          '(group_broadcast_id=$groupBroadcastId)',
        );
        if (preserveCurrentRoute) {
          _addBreadcrumb(
            'in-app player scorecard reference failed',
            data: {'groupBroadcastId': _maskedValue(groupBroadcastId)},
          );
        } else {
          _linkFailed(
            navigatorKey,
            reason: 'player_scorecard_event_unresolved',
            extras: {'groupBroadcastId': groupBroadcastId, 'fideId': fideId},
          );
        }
        return false;
      }

      final broadcastRepo = ref.read(groupBroadcastRepositoryProvider);
      final broadcast = await broadcastRepo
          .getGroupBroadcastById(routeContext.groupBroadcastId)
          .timeout(_fetchTimeout);
      if (superseded()) return true;

      await _preselectTourAndRound(
        ref,
        groupBroadcastId: broadcast.id,
        tourId: routeContext.tourId,
        roundId: routeContext.roundId,
      );
      if (superseded()) return true;

      ref.read(selectedBroadcastModelProvider.notifier).state = broadcast;
      ref.read(selectedTourModeProvider.notifier).state =
          TournamentDetailScreenMode.standings;

      // Land on the event first so the scorecard has a back-stack and the
      // standings providers are scoped to this broadcast.
      final eventRoute = _pushEventRoute(navigatorKey, preserveCurrentRoute);
      if (eventRoute == null) return false;
      landedOnEvent = true;
      var eventClosed = false;
      unawaited(eventRoute.whenComplete(() => eventClosed = true));

      // Resolve the player from the tournament standings, then open the
      // scorecard. `playerTourScreenProvider` returns synchronously with `[]`
      // until `tourDetailScreenProvider` resolves, so a one-shot `.future`
      // await sees an empty list on cold-start and bails out. Listen for the
      // first non-empty emission instead so we wait for real data.
      final matched = await _awaitPlayerInStandings(
        ref,
        fideId,
        timeout: const Duration(seconds: 20),
      );

      if (matched == null) {
        debugPrint(
          'DeepLinkService: Player $fideId not found in standings; '
          'staying on event',
        );
        return true;
      }
      // Backed out of the event while standings loaded, or a newer tap took
      // over: the scorecard would land on whatever screen is left.
      if (eventClosed || superseded()) return true;

      ref.read(selectedPlayerProvider.notifier).state = matched;
      ref.read(scoreCardGamesContextProvider.notifier).state = null;
      ref.read(scoreCardHasEventContextProvider.notifier).state = true;
      ref.read(scoreCardPlayerProfileDataSourceProvider.notifier).state =
          PlayerProfileDataSource.supabase;
      ref.read(chessboardViewFromProviderNew.notifier).state =
          ChessboardView.tour;

      navigatorKey.currentState?.pushNamed('/scorecard_screen');
      return true;
    } catch (e, stackTrace) {
      debugPrint('DeepLinkService: Failed to open player scorecard: $e');
      _captureDeepLinkException(
        e,
        stackTrace,
        stage: 'navigate_to_player_scorecard',
        extras: {
          'groupBroadcastId': groupBroadcastId,
          'fideId': fideId.toString(),
        },
      );
      if (superseded()) return true;
      if (!preserveCurrentRoute && !landedOnEvent) {
        _linkFailed(
          navigatorKey,
          reason: 'player_scorecard_failed',
          report: false,
        );
      }
      // In-app: an event that already opened is not a dead shortcut.
      return preserveCurrentRoute && landedOnEvent;
    }
  }

  /// Opens a team scorecard from
  /// `chessever.com/broadcast/<slug>/<id>/team/<teamName>`. Lands on the event
  /// first (standings tab for team events), resolves the team from standings,
  /// then pushes `/team_scorecard_screen`.
  ///
  /// [preserveCurrentRoute] and the result behave as in
  /// [_navigateToPlayerScorecard].
  Future<bool> _navigateToTeamScorecard(
    String groupBroadcastId,
    String teamName,
    GlobalKey<NavigatorState> navigatorKey,
    WidgetRef ref, {
    bool preserveCurrentRoute = false,
  }) async {
    final generation = ++_destinationGeneration;
    bool superseded() => generation != _destinationGeneration;
    var landedOnEvent = false;

    try {
      try {
        await _appReadyCompleter.future.timeout(const Duration(seconds: 30));
      } catch (_) {
        debugPrint(
          'DeepLinkService: Timed out waiting for app ready, proceeding',
        );
      }
      if (superseded()) return true;

      final ready = await _readyToOpen(
        ref,
        navigatorKey,
        stage: 'team_scorecard_requires_auth',
      );
      if (superseded()) return true;
      if (!ready) return false;

      final routeContext = await _resolveEventRouteContext(
        ref,
        groupBroadcastId: groupBroadcastId,
      );
      if (superseded()) return true;
      if (routeContext == null) {
        debugPrint(
          'DeepLinkService: Could not resolve event for team scorecard '
          '(group_broadcast_id=$groupBroadcastId)',
        );
        if (preserveCurrentRoute) {
          _addBreadcrumb(
            'in-app team scorecard reference failed',
            data: {'groupBroadcastId': _maskedValue(groupBroadcastId)},
          );
        } else {
          _linkFailed(
            navigatorKey,
            reason: 'team_scorecard_event_unresolved',
            extras: {
              'groupBroadcastId': groupBroadcastId,
              'teamName': teamName,
            },
          );
        }
        return false;
      }

      final broadcastRepo = ref.read(groupBroadcastRepositoryProvider);
      final broadcast = await broadcastRepo
          .getGroupBroadcastById(routeContext.groupBroadcastId)
          .timeout(_fetchTimeout);
      if (superseded()) return true;

      await _preselectTourAndRound(
        ref,
        groupBroadcastId: broadcast.id,
        tourId: routeContext.tourId,
        roundId: routeContext.roundId,
      );
      if (superseded()) return true;

      ref.read(selectedBroadcastModelProvider.notifier).state = broadcast;
      ref.read(selectedTourModeProvider.notifier).state =
          TournamentDetailScreenMode.standings;

      final eventRoute = _pushEventRoute(navigatorKey, preserveCurrentRoute);
      if (eventRoute == null) return false;
      landedOnEvent = true;
      var eventClosed = false;
      unawaited(eventRoute.whenComplete(() => eventClosed = true));

      final matched = await _awaitTeamInStandings(
        ref,
        teamName,
        timeout: const Duration(seconds: 20),
      );

      final team =
          matched ??
          TeamStandingModel(
            teamName: teamName,
            rank: 0,
            matchPoints: 0,
            gamePoints: 0,
            matchesWon: 0,
            matchesDrawn: 0,
            matchesLost: 0,
            boardsPlayed: 0,
            players: const [],
          );
      if (matched == null) {
        debugPrint(
          'DeepLinkService: Team "$teamName" not found in standings; '
          'opening stub scorecard',
        );
      }

      // Backed out of the event while standings loaded, or a newer tap took
      // over: the scorecard would land on whatever screen is left.
      if (eventClosed || superseded()) return true;

      ref.read(selectedTeamProvider.notifier).state = team;
      navigatorKey.currentState?.pushNamed('/team_scorecard_screen');
      return true;
    } catch (e, stackTrace) {
      debugPrint('DeepLinkService: Failed to open team scorecard: $e');
      _captureDeepLinkException(
        e,
        stackTrace,
        stage: 'navigate_to_team_scorecard',
        extras: {'groupBroadcastId': groupBroadcastId, 'teamName': teamName},
      );
      if (superseded()) return true;
      if (!preserveCurrentRoute && !landedOnEvent) {
        _linkFailed(
          navigatorKey,
          reason: 'team_scorecard_failed',
          report: false,
        );
      }
      // In-app: an event that already opened is not a dead shortcut.
      return preserveCurrentRoute && landedOnEvent;
    }
  }

  /// Pushes the tournament detail screen for a scorecard link: above the
  /// current route for in-app references, over the root for shared links.
  /// Returns the route's pop future, or null when there is no navigator.
  Future<Object?>? _pushEventRoute(
    GlobalKey<NavigatorState> navigatorKey,
    bool preserveCurrentRoute,
  ) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return null;
    if (preserveCurrentRoute) {
      return navigator.pushNamed<Object?>('/tournament_detail_screen');
    }
    return navigator.pushNamedAndRemoveUntil<Object?>(
      '/tournament_detail_screen',
      (route) => route.isFirst,
    );
  }

  /// Opens a player's overall profile from a shared link
  /// `chessever.com/player/<identity>` (or the canonical
  /// `/player/<name-slug>/<identity>` SEO form), on [tab] when the link names
  /// a view (`/games`, `/events`; none keeps the reader's last tab). Numeric identities resolve a current FIDE
  /// player. Reviewed Memorial route ids resolve locally so a share link
  /// cannot drift to a namesake or a recycled identity.
  Future<void> _navigateToPlayerProfile(
    String routeId,
    GlobalKey<NavigatorState> navigatorKey,
    WidgetRef ref, {
    PlayerProfileTab? tab,
  }) async {
    final generation = ++_destinationGeneration;
    bool superseded() => generation != _destinationGeneration;

    try {
      try {
        await _appReadyCompleter.future.timeout(const Duration(seconds: 30));
      } catch (_) {
        debugPrint(
          'DeepLinkService: Timed out waiting for app ready, proceeding',
        );
      }
      if (superseded()) return;

      final ready = await _readyToOpen(
        ref,
        navigatorKey,
        stage: 'player_profile_requires_auth',
      );
      if (superseded() || !ready) return;

      final memorial = await findBundledMemorialPlayerByRouteId(routeId);
      if (superseded()) return;
      if (memorial != null) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => _page(
              PlayerProfileScreen(
                fideId: int.tryParse(memorial.fideId ?? ''),
                playerName: memorial.name,
                title: memorial.title,
                federation: memorial.fed,
                rating: memorial.ratingClassical > 0
                    ? memorial.ratingClassical
                    : null,
                gamebasePlayerId: memorial.gamebasePlayerId,
                memorialSourceIdentity: memorial.sourceIdentity,
                memorialRouteId: memorial.routeId,
                initialTab: tab,
              ),
            ),
          ),
        );
        return;
      }

      final fideId = int.tryParse(routeId);
      if (fideId == null || fideId <= 0) {
        _linkFailed(
          navigatorKey,
          reason: 'player_profile_not_found',
          extras: {'routeId': routeId},
        );
        return;
      }

      final player = await ref
          .read(chessPlayerRepositoryProvider)
          .getPlayerByFideId(fideId)
          .timeout(_fetchTimeout);
      if (superseded()) return;
      if (player == null || player.name.trim().isEmpty) {
        debugPrint('DeepLinkService: Player $fideId not found');
        _linkFailed(
          navigatorKey,
          reason: 'player_profile_not_found',
          extras: {'fideId': fideId},
        );
        return;
      }

      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => _page(
            PlayerProfileScreen(
              fideId: player.fideid,
              playerName: player.name,
              title: player.title,
              federation: player.country,
              rating: player.rating,
              initialTab: tab,
            ),
          ),
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('DeepLinkService: Failed to open player profile: $e');
      _captureDeepLinkException(
        e,
        stackTrace,
        stage: 'navigate_to_player_profile',
        extras: {'routeId': routeId},
      );
      if (!superseded()) {
        _linkFailed(
          navigatorKey,
          reason: 'player_profile_failed',
          report: false,
        );
      }
    }
  }

  /// Waits for `playerTourScreenProvider` to emit a non-empty standings list
  /// and returns the player matching [fideId], or null on timeout / no match.
  ///
  /// One-shot `.future` is unsafe here: on cold-start the provider's `build`
  /// short-circuits to `[]` while `tourDetailScreenProvider` is still loading,
  /// so a single await resolves immediately with an empty list and the caller
  /// silently bails out. Subscribing instead waits until standings actually
  /// populate (or the player is confirmed absent).
  Future<PlayerStandingModel?> _awaitPlayerInStandings(
    WidgetRef ref,
    int fideId, {
    required Duration timeout,
  }) async {
    final completer = Completer<PlayerStandingModel?>();
    Timer? timer;
    ProviderSubscription<AsyncValue<List<PlayerStandingModel>>>? sub;

    void finish(PlayerStandingModel? value) {
      if (completer.isCompleted) return;
      completer.complete(value);
    }

    void inspect(AsyncValue<List<PlayerStandingModel>> async) {
      if (completer.isCompleted) return;
      async.when(
        data: (standings) {
          if (standings.isEmpty) return; // still warming up; keep listening
          for (final s in standings) {
            if (s.fideId == fideId) {
              finish(s);
              return;
            }
          }
          finish(null); // loaded but absent → degrade to event
        },
        loading: () {},
        error: (error, _) {
          debugPrint(
            'DeepLinkService: standings error while awaiting player: $error',
          );
          // Keep listening: provider can recover with cached data.
        },
      );
    }

    try {
      sub = ref.listenManual<AsyncValue<List<PlayerStandingModel>>>(
        playerTourScreenProvider,
        (_, next) => inspect(next),
        fireImmediately: true,
      );
      timer = Timer(timeout, () => finish(null));
      return await completer.future;
    } finally {
      timer?.cancel();
      sub?.close();
    }
  }

  Future<TeamStandingModel?> _awaitTeamInStandings(
    WidgetRef ref,
    String teamName, {
    required Duration timeout,
  }) async {
    final target = teamName.trim();
    final completer = Completer<TeamStandingModel?>();
    Timer? timer;
    ProviderSubscription<AsyncValue<List<TeamStandingModel>>>? sub;

    void finish(TeamStandingModel? value) {
      if (completer.isCompleted) return;
      completer.complete(value);
    }

    void inspect(AsyncValue<List<TeamStandingModel>> async) {
      if (completer.isCompleted) return;
      async.when(
        data: (standings) {
          if (standings.isEmpty) return;
          for (final t in standings) {
            if (t.teamName == target) {
              finish(t);
              return;
            }
          }
          finish(null);
        },
        loading: () {},
        error: (error, _) {
          debugPrint(
            'DeepLinkService: team standings error while awaiting team: $error',
          );
        },
      );
    }

    try {
      sub = ref.listenManual<AsyncValue<List<TeamStandingModel>>>(
        teamStandingsProvider,
        (_, next) => inspect(next),
        fireImmediately: true,
      );
      timer = Timer(timeout, () => finish(null));
      return await completer.future;
    } finally {
      timer?.cancel();
      sub?.close();
    }
  }

  Future<void> _preselectTourAndRound(
    WidgetRef ref, {
    required String groupBroadcastId,
    String? tourId,
    String? roundId,
  }) async {
    final cleanTourId = _asNonEmptyString(tourId);
    final cleanRoundId = _asNonEmptyString(roundId);

    if (cleanTourId != null) {
      try {
        await ref
            .read(tourDetailRepoProvider)
            .saveSelectedTourId(
              groupEventId: groupBroadcastId,
              tourId: cleanTourId,
            );
      } catch (e) {
        debugPrint('DeepLinkService: Failed to persist selected tour: $e');
      }
    }

    if (cleanRoundId != null) {
      ref.read(userSelectedRoundProvider.notifier).state = (
        id: cleanRoundId,
        userSelected: true,
      );
      ref.read(pendingRoundNavigationProvider.notifier).state = cleanRoundId;
    }
  }

  Future<_EventRouteContext?> _resolveEventRouteContext(
    WidgetRef ref, {
    String? groupBroadcastId,
    String? roundId,
    String? tourId,
  }) async {
    var resolvedGroupBroadcastId = _asNonEmptyString(groupBroadcastId);
    var resolvedRoundId = _asNonEmptyString(roundId);
    var resolvedTourId = _asNonEmptyString(tourId);

    // If only round_id is available, resolve its tour first.
    if (resolvedTourId == null && resolvedRoundId != null) {
      try {
        final round = await ref
            .read(roundRepositoryProvider)
            .getRoundById(resolvedRoundId)
            .timeout(_fetchTimeout);
        resolvedTourId = round.tourId;
      } catch (e) {
        debugPrint('DeepLinkService: Failed to resolve tour from round: $e');
      }
    }

    // Shared event URLs `chessever.com/broadcast/<slug>/<id>` mirror Lichess,
    // where `<id>` is a tour's short id (e.g. `QXavbhIZ`). When that's the
    // case, treat the path-tail value as the shared tour so the destination
    // category is preselected — matching Lichess's behavior for the same URL
    // shape. If `<id>` is actually a group_broadcasts.id (legacy shares) the
    // lookup misses and we fall through with the original value.
    final probeId = resolvedTourId == null && resolvedGroupBroadcastId != null
        ? resolvedGroupBroadcastId
        : null;

    // Resolve/validate group_broadcast_id from tour. Combines the tour-by-id
    // lookup for both an explicit `tourId` and the Lichess-style probe above
    // into a single Supabase round-trip.
    final lookupId = resolvedTourId ?? probeId;
    if (lookupId != null) {
      try {
        final tours = await ref
            .read(tourRepositoryProvider)
            .getToursByIds([lookupId])
            .timeout(_fetchTimeout);
        if (tours.isNotEmpty) {
          resolvedTourId ??= tours.first.id;
          final tourGroupId = _asNonEmptyString(tours.first.groupBroadcastId);
          if (tourGroupId != null) {
            resolvedGroupBroadcastId = tourGroupId;
          }
        }
      } catch (e) {
        debugPrint(
          'DeepLinkService: Failed to resolve tour/group broadcast: $e',
        );
      }
    }

    // `/broadcast/<slug>/<id>` from a PGN's BroadcastURL (rebranded from
    // lichess.org/broadcast/<tour>/<round>/<roundId>) carries a ROUND id, so
    // a probe that is no tour is tried as a round: the event then opens on
    // that round instead of failing as an unknown group broadcast.
    if (probeId != null && resolvedTourId == null && resolvedRoundId == null) {
      try {
        final round = await ref
            .read(roundRepositoryProvider)
            .getRoundById(probeId)
            .timeout(_fetchTimeout);
        final tours = await ref
            .read(tourRepositoryProvider)
            .getToursByIds([round.tourId])
            .timeout(_fetchTimeout);
        final tourGroupId = tours.isEmpty
            ? null
            : _asNonEmptyString(tours.first.groupBroadcastId);
        if (tourGroupId != null) {
          resolvedRoundId = round.id;
          resolvedTourId = round.tourId;
          resolvedGroupBroadcastId = tourGroupId;
        }
      } catch (e) {
        debugPrint('DeepLinkService: Probe id is not a round either: $e');
      }
    }

    if (resolvedGroupBroadcastId == null) {
      return null;
    }

    return _EventRouteContext(
      groupBroadcastId: resolvedGroupBroadcastId,
      tourId: resolvedTourId,
      roundId: resolvedRoundId,
    );
  }

  /// Dispose of resources
  void dispose() {
    _destinationGeneration++;
    _subscription?.cancel();
    _subscription = null;
    _isInitialized = false;
    _inbound = null;
    _pending = null;
    _stopWatchingSignInAttempt();
    debugBoardPageBuilder = null;
    debugPageOverride = null;
    _lastHandledGameId = null;
    _lastHandledTime = null;
    _appReadyCompleter = Completer<void>();
  }

  void _addBreadcrumb(String message, {Map<String, dynamic>? data}) {
    Sentry.addBreadcrumb(
      Breadcrumb(
        category: 'deep_link',
        message: message,
        type: 'navigation',
        data: data,
        level: SentryLevel.info,
      ),
    );
  }

  Map<String, dynamic> _sanitizedUriData(Uri uri) {
    return {
      'scheme': uri.scheme,
      'host': uri.host,
      'path': uri.path,
      'routeKind': _routeKindFromUri(uri),
      if (uri.queryParameters.isNotEmpty)
        'queryParameters': _whitelistedQueryParameters(uri),
    };
  }

  String _routeKindFromUri(Uri uri) {
    if (uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.first;
    }
    return uri.host;
  }

  Map<String, String> _whitelistedQueryParameters(Uri uri) {
    final allowed = <String>{'stop_live', kEventTabQueryParam, 'tc'};
    final safe = <String, String>{};
    for (final entry in uri.queryParameters.entries) {
      if (allowed.contains(entry.key)) {
        safe[entry.key] = entry.value;
      }
    }
    return safe;
  }

  String? _maskedValue(String? value) {
    if (value == null || value.isEmpty) return null;
    if (value.length <= 6) return '***';
    return '${value.substring(0, 3)}***${value.substring(value.length - 2)}';
  }

  Future<void> _captureDeepLinkException(
    dynamic error,
    StackTrace stackTrace, {
    required String stage,
    Map<String, dynamic>? extras,
    bool captureAsException = true,
  }) async {
    try {
      final mergedExtras = <String, dynamic>{'stage': stage, ...?extras};
      final sentryExtras = mergedExtras.map(
        (key, value) => MapEntry(key, value?.toString()),
      );
      if (!captureAsException) {
        _addBreadcrumb(
          'deep link warning',
          data: {'stage': stage, ...?extras, 'error': error.toString()},
        );
        return;
      }

      await Sentry.captureException(
        error,
        stackTrace: stackTrace,
        withScope: (scope) {
          scope.setTag('area', 'deep_link');
          scope.setTag('stage', stage);
          scope.setContexts('deep_link', sentryExtras);
        },
      ).timeout(const Duration(seconds: 2));
    } catch (telemetryError, telemetryStackTrace) {
      debugPrint(
        'DeepLinkService: Sentry logging failed at $stage: $telemetryError',
      );
      debugPrint('$telemetryStackTrace');
    }
  }

  Future<void> _captureDeepLinkMessage(
    String message, {
    required String stage,
    Map<String, dynamic>? extras,
    SentryLevel level = SentryLevel.info,
  }) async {
    // Info-level deep-link telemetry belongs in breadcrumbs, not as standalone
    // Sentry issues. captureMessage made "deep link game loaded" the #1 noisy
    // "issue" by user count (CHESSEVER-15Z). Only warning+ is worth a message.
    if (level == SentryLevel.info) {
      _addBreadcrumb(message, data: {'stage': stage, ...?extras});
      return;
    }
    try {
      final mergedExtras = <String, dynamic>{'stage': stage, ...?extras};
      final sentryExtras = mergedExtras.map(
        (key, value) => MapEntry(key, value?.toString()),
      );
      await Sentry.captureMessage(
        message,
        level: level,
        withScope: (scope) {
          scope.setTag('area', 'deep_link');
          scope.setTag('stage', stage);
          scope.setContexts('deep_link', sentryExtras);
        },
      ).timeout(const Duration(seconds: 2));
    } catch (telemetryError, telemetryStackTrace) {
      debugPrint(
        'DeepLinkService: Sentry message logging failed at $stage: $telemetryError',
      );
      debugPrint('$telemetryStackTrace');
    }
  }
}

class _DeepLinkedChessBoardRoute extends StatefulWidget {
  const _DeepLinkedChessBoardRoute({
    required this.initialGame,
    required this.initialGameId,
    required this.viewSource,
    required this.roundGamesFuture,
    required this.onRoundGamesError,
    this.initialFen,
  });

  final GamesTourModel initialGame;
  final String initialGameId;
  final ChessboardView viewSource;
  final String? initialFen;
  final Future<List<Games>> roundGamesFuture;
  final void Function(Object error, StackTrace stackTrace) onRoundGamesError;

  @override
  State<_DeepLinkedChessBoardRoute> createState() =>
      _DeepLinkedChessBoardRouteState();
}

class _DeepLinkedChessBoardRouteState
    extends State<_DeepLinkedChessBoardRoute> {
  late List<GamesTourModel> _games;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _games = <GamesTourModel>[widget.initialGame];
    _currentIndex = 0;
    _hydrateRoundGames();
  }

  Future<void> _hydrateRoundGames() async {
    try {
      final roundGames = await widget.roundGamesFuture;
      if (!mounted || roundGames.isEmpty) return;

      final gameList = _buildSortedRoundGameModels(roundGames);
      final index = gameList.indexWhere(
        (g) => g.gameId == widget.initialGameId,
      );
      if (index < 0) return;

      setState(() {
        _games = gameList;
        _currentIndex = index;
      });
    } catch (error, stackTrace) {
      widget.onRoundGamesError(error, stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Key MUST stay stable across the round-games hydrate above. It used to
    // carry `_games.length`, which changed 1 -> N when the round list landed
    // and remounted ChessBoardScreenNew wholesale. That skipped its
    // didUpdateWidget, and with it `syncPageIndex` — so the surviving
    // gameId-keyed notifier kept its stale index 0 while
    // currentlyVisiblePageIndexProvider moved to the game's real round index.
    // Every eval then failed the `index == currentVisiblePage` gate and the
    // engine looked dead on notification/deep-link opens while a normal open
    // (in-place update via _ExpandingChessBoardScreen) worked fine.
    return ChessBoardScreenNew(
      key: ValueKey('deep-link-${widget.initialGameId}'),
      games: _games,
      currentIndex: _currentIndex,
      viewSource: widget.viewSource,
      initialFen: widget.initialFen,
    );
  }
}

class _InboundDestination {
  _InboundDestination.link(Uri this.link, {required this.trusted})
    : push = null,
      at = DateTime.now();
  _InboundDestination.push(Map<String, dynamic> this.push)
    : link = null,
      trusted = true,
      at = DateTime.now();

  final Uri? link;
  final Map<String, dynamic>? push;

  /// Whether the link was ChessEver's own (a push route, an in-app link):
  /// replayed with the same trust ([DeepLinkService._handleDeepLink]).
  final bool trusted;
  final DateTime at;
}

class _EventRouteContext {
  const _EventRouteContext({
    required this.groupBroadcastId,
    this.tourId,
    this.roundId,
  });

  final String groupBroadcastId;
  final String? tourId;
  final String? roundId;
}
