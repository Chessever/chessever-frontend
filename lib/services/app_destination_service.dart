import 'dart:async';

import 'package:chessever2/config/feature_flags.dart';
import 'package:chessever2/screens/calendar/calendar_screen.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/collections/collections_screen.dart';
import 'package:chessever2/screens/favorites/favorites_tab_screen.dart';
import 'package:chessever2/screens/favorites/provider/favorites_mode_provider.dart';
import 'package:chessever2/screens/feed/feed_screen.dart';
import 'package:chessever2/screens/for_you/discovery/likes_screen.dart';
import 'package:chessever2/screens/for_you/discovery/reports_screen.dart';
import 'package:chessever2/screens/for_you/providers/for_you_tab_provider.dart';
import 'package:chessever2/screens/gamebase/gamebase_explorer_screen.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_explorer_state.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/inbox/inbox_screen.dart';
import 'package:chessever2/screens/library/library_screen.dart';
import 'package:chessever2/screens/library/miniatures_screen.dart';
import 'package:chessever2/screens/library/twic_contents_screen.dart';
import 'package:chessever2/screens/my_likes/my_likes_screen.dart';
import 'package:chessever2/screens/my_prep/my_prep_home_screen.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/prep_profile_screen.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/screens/player_profile/provider/player_profile_provider.dart';
import 'package:chessever2/screens/settings/settings_page.dart';
import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:chessever2/screens/streaks/streak_player_screen.dart';
import 'package:chessever2/screens/streaks/streaks_screen.dart';
import 'package:chessever2/services/app_destination.dart';
import 'package:chessever2/widgets/paywall/premium_game_access.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

export 'app_destination.dart';

typedef AppDestinationAccessRequest =
    Future<bool> Function(BuildContext context, String featureId);
typedef AppDestinationPageNavigation =
    void Function(BuildContext context, Widget page, String routeName);

final appDestinationAccessRequestProvider =
    Provider<AppDestinationAccessRequest>(
      (ref) =>
          (context, featureId) => ensurePremiumGameAccess(
            context,
            featureId: featureId,
            returnTo: 'notification_route',
          ),
    );

final appDestinationPageNavigationProvider =
    Provider<AppDestinationPageNavigation>(
      (ref) => (context, page, routeName) {
        unawaited(
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              settings: RouteSettings(name: routeName),
              builder: (_) => page,
            ),
          ),
        );
      },
    );

/// Opens a previously validated destination above the app's Home route.
///
/// The caller owns startup/auth readiness and establishes Home on a cold start.
/// Content resolution and exact inbox-message loading stay in the existing
/// deep-link router, injected here so the catalog has no router dependency.
/// A dismissed Premium sheet consumes the route; it never falls through to a
/// different destination or a browser. False means unavailable, not dismissed.
Future<bool> openAppDestination(
  BuildContext context,
  WidgetRef ref,
  AppDestination destination, {
  required Future<bool> Function(String link) openLegacyLink,
  Future<bool> Function(String messageId)? openInboxMessage,
  bool Function()? isCurrent,
}) async {
  if (!context.mounted) return false;
  bool canOpen() => context.mounted && (isCurrent?.call() ?? true);
  // A newer notification owns navigation. Consuming this older request avoids
  // its caller opening a fallback above the newer destination.
  if (!canOpen()) return true;
  try {
    void push(Widget page) {
      if (!canOpen()) return;
      ref.read(appDestinationPageNavigationProvider)(
        context,
        page,
        destination.uri.path,
      );
    }

    Future<bool> access(String feature) => canOpen()
        ? ref.read(appDestinationAccessRequestProvider)(context, feature)
        : Future.value(false);

    switch (destination.kind) {
      case AppDestinationKind.home:
      case AppDestinationKind.events:
        if (!canOpen()) return true;
        _openHome(context, ref, destination);
      case AppDestinationKind.collections:
        push(const CollectionsScreen());
      case AppDestinationKind.collection:
        final repo = ref.read(collectionsRepositoryProvider);
        final release = repo.holdFreshAccess(destination.id!);
        try {
          var collection = await repo.fetchCollection(destination.id!);
          if (!canOpen()) return true;
          if (collection.isPremium && collection.contentLocked != false) {
            if (!await access(collectionPaywallFeatureId(collection.kind))) {
              return true;
            }
            if (!canOpen()) return true;
            collection = await repo.fetchCollection(destination.id!);
            if (!canOpen()) return true;
            if (collection.contentLocked == true) return false;
          }
          push(CollectionScreen(collection: collection));
        } finally {
          release();
        }
      case AppDestinationKind.inbox:
        if (destination.id != null) {
          if (openInboxMessage == null) return false;
          final opened = await openInboxMessage(destination.id!);
          return !canOpen() || opened;
        }
        push(const InboxScreen());
      case AppDestinationKind.feed:
        push(const FeedScreen());
      case AppDestinationKind.likes:
        push(const LikesScreen());
      case AppDestinationKind.miniatures:
        push(const MiniaturesScreen());
      case AppDestinationKind.reports:
        if (!await access('game_reports')) return true;
        push(const ReportsScreen());
      case AppDestinationKind.myPrep:
        push(const MyPrepHomeScreen());
      case AppDestinationKind.prepProfile:
        final profile = await _prepProfile(context, destination.id!);
        if (!canOpen()) return true;
        if (profile == null) return false;
        final account = destination.query['account'];
        if (account != null && !profile.accounts.any((a) => a.key == account)) {
          return false;
        }
        push(PrepProfileScreen(profileId: profile.id, accountKey: account));
      case AppDestinationKind.library:
        push(const LibraryScreen());
      case AppDestinationKind.database:
        push(TwicContentsScreen(initialEvent: destination.query['event']));
      case AppDestinationKind.myLikes:
        push(const MyLikesScreen());
      case AppDestinationKind.calendar:
        final date = destination.query['date'];
        push(
          CalendarScreen(
            initialDate: date == null ? null : DateTime.parse(date),
          ),
        );
      case AppDestinationKind.favorites:
        push(
          FavoritesTabScreen(
            initialMode: switch (destination.section) {
              'events' || 'list' => FavoritesScreenMode.favorites,
              'players' => FavoritesScreenMode.players,
              _ => FavoritesScreenMode.games,
            },
          ),
        );
      case AppDestinationKind.settings:
        push(
          SettingsPage(
            initiallyExpanded: switch (destination.section) {
              'board' => SettingsSection.board,
              'engine' => SettingsSection.engine,
              'botvinnik' => SettingsSection.botvinnik,
              'notifications' => SettingsSection.notification,
              'customization' => SettingsSection.customization,
              _ => null,
            },
          ),
        );
      case AppDestinationKind.player:
        push(
          PlayerProfileScreen(
            fideId: int.parse(destination.id!),
            playerName: destination.query['name'] ?? '',
            initialTab: switch (destination.section) {
              'games' => PlayerProfileTab.games,
              'events' => PlayerProfileTab.events,
              _ => PlayerProfileTab.about,
            },
          ),
        );
      case AppDestinationKind.playerOpenings:
        if (!await access('opening_tree')) return true;
        if (!canOpen()) return true;
        final fideId = int.parse(destination.id!);
        final name = destination.query['name'] ?? '';
        final playerId = await ref
            .read(
              twicPlayerIdProvider(
                PlayerProfileKey(
                  fideId: fideId,
                  playerName: name,
                  source: PlayerProfileDataSource.twic,
                ),
              ).future,
            )
            .timeout(const Duration(seconds: 10));
        if (!canOpen()) return true;
        if (playerId == null || playerId.isEmpty) {
          return false;
        }
        final color = switch (destination.query['color']) {
          'white' => GamebasePlayerColor.white,
          'black' => GamebasePlayerColor.black,
          _ => null,
        };
        push(
          GamebaseExplorerScreen.scoped(
            initialPlayer: GamebasePlayer(
              id: playerId,
              fideId: destination.id!,
              name: name,
              gender: PlayerGender.male,
              fed: '',
            ),
            initialFilters: color == null
                ? null
                : GamebaseFilters(playerColor: color),
            initialFen: destination.line?.fen,
            initialMoves: destination.line?.moves,
          ),
        );
      case AppDestinationKind.streaks:
        if (!FeatureFlags.streaks) return false;
        final timeClass = StreakTimeClassX.tryParse(destination.query['tc']);
        push(
          destination.id == null
              ? StreaksScreen(initialClass: timeClass)
              : StreakPlayerScreen(
                  fideId: int.parse(destination.id!),
                  initialClass: timeClass,
                ),
        );
      case AppDestinationKind.explorer:
        push(
          GamebaseExplorerScreen.scoped(
            initialFen: destination.line?.fen,
            initialMoves: destination.line?.moves,
          ),
        );
      case AppDestinationKind.legacy:
        if (!canOpen()) return true;
        final opened = await openLegacyLink(destination.legacyLink!);
        return !canOpen() || opened;
    }
    return true;
  } catch (error) {
    if (!canOpen()) return true;
    debugPrint(
      '[AppDestination] Could not open ${destination.kind.name}: '
      '${error.runtimeType}',
    );
    return false;
  }
}

void _openHome(
  BuildContext context,
  WidgetRef ref,
  AppDestination destination,
) {
  // The main-tab provider auto-disposes. Hold it until Home has painted when
  // this notification creates Home for the first time.
  final container = ProviderScope.containerOf(context, listen: false);
  final hold = container.listen(selectedBottomNavBarItemProvider, (_, _) {});
  ref
      .read(selectedBottomNavBarItemProvider.notifier)
      .state = destination.kind == AppDestinationKind.events
      ? BottomNavBarItem.tournaments
      : BottomNavBarItem.forYou;
  if (destination.kind == AppDestinationKind.home) {
    ref.read(selectedForYouTabProvider.notifier).select(
      switch (destination.section) {
        'my-space' => ForYouTab.mySpace,
        'discovery' => ForYouTab.discovery,
        _ => ForYouTab.today,
      },
    );
    ref.read(forYouSearchQueryProvider.notifier).state = '';
  }
  final navigator = Navigator.of(context);
  var foundHome = false;
  navigator.popUntil((route) {
    foundHome = route.settings.name == '/home_screen';
    return foundHome || route.isFirst;
  });
  if (!foundHome) {
    unawaited(navigator.pushNamed('/home_screen'));
  }
  unawaited(WidgetsBinding.instance.endOfFrame.then((_) => hold.close()));
}

Future<PrepProfile?> _prepProfile(BuildContext context, String id) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final ready = Completer<AsyncValue<List<PrepProfile>>>();
  final subscription = container.listen(prepProfilesProvider, (_, value) {
    if (!value.isLoading && !ready.isCompleted) ready.complete(value);
  }, fireImmediately: true);
  try {
    final profiles = await ready.future.timeout(const Duration(seconds: 10));
    return profiles.valueOrNull
        ?.where((profile) => profile.id == id)
        .firstOrNull;
  } finally {
    subscription.close();
  }
}
