import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/providers/auth_state_provider.dart';

import 'package:chessever2/chat/botvinnik_provider.dart';
import 'package:chessever2/chat/chat_api.dart';
import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/screens/home/widget/home_nav_dock.dart';
import 'package:chessever2/screens/inbox/inbox_provider.dart';
import 'package:chessever2/screens/inbox/inbox_unread_dot.dart';
import 'package:chessever2/services/discovery_dots/discovery_dots_provider.dart';
import 'package:chessever2/services/analytics/analytics_service.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/phone_update_route_observer.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The five main sections: Home, Feed, Botvinnik, Collections, Profile.
///
/// Events lives on the Profile page with everything the sidebar used to
/// hold; the sidebar itself is gone. Search left the bar for Home's floating
/// button (Today), which opens it as a page of its own.
///
/// Tabs are only ever addressed by value or by [Enum.name] (analytics sends
/// the name, a launch reads it back), never by index, so reordering the bar
/// moves nothing else. A name no longer here (`search`, saved as the start
/// screen before Collections took its place) reads as Home
/// ([readDefaultBottomTab]).
enum BottomNavBarItem { forYou, feed, botvinnik, collections, profile }

/// Keep enum identities stable for callers; presentation has its own order.
const bottomNavBarOrder = [
  BottomNavBarItem.forYou,
  BottomNavBarItem.feed,
  BottomNavBarItem.botvinnik,
  BottomNavBarItem.collections,
  BottomNavBarItem.profile,
];

/// The Collections slot's mark: three stacked plates, drawn in the dock's
/// line weight (1.8 on 24, as Feed's and Botvinnik's).
const String collectionsNavIcon = 'assets/svgs/collections_nav.svg';

/// Whether Botvinnik has a tab: built in and not switched off in Settings.
final botvinnikTabAvailableProvider = Provider<bool>((ref) {
  if (!ChatApi.buildEnabled) return false;
  return ref.watch(botvinnikEnabledProvider).valueOrNull ?? true;
});

/// The sections the bar shows now, in order.
final visibleBottomNavItemsProvider = Provider<List<BottomNavBarItem>>((ref) {
  final botvinnik = ref.watch(botvinnikTabAvailableProvider);
  return [
    for (final item in bottomNavBarOrder)
      if (item != BottomNavBarItem.botvinnik || botvinnik) item,
  ];
});

/// Emitted whenever the user taps the already-selected bottom nav item.
/// Screens that own a scrollable surface for [item] should listen and
/// scroll their active list back to the top. [sequence] increments on
/// every fresh request so repeated re-taps re-fire the listener even
/// when [item] hasn't changed.
class BottomNavBarReTapRequest {
  const BottomNavBarReTapRequest({required this.item, required this.sequence});

  final BottomNavBarItem item;
  final int sequence;
}

class BottomNavBarReTapRequestNotifier
    extends StateNotifier<BottomNavBarReTapRequest> {
  BottomNavBarReTapRequestNotifier()
    : super(
        const BottomNavBarReTapRequest(
          item: BottomNavBarItem.forYou,
          sequence: 0,
        ),
      );

  void request(BottomNavBarItem item) {
    state = BottomNavBarReTapRequest(item: item, sequence: state.sequence + 1);
  }
}

final bottomNavBarReTapRequestProvider =
    StateNotifierProvider<
      BottomNavBarReTapRequestNotifier,
      BottomNavBarReTapRequest
    >((ref) => BottomNavBarReTapRequestNotifier());

/// Discovery-dot anchor ids of the root destinations, shared by the phone bar
/// and the tablet rail.
const bottomNavBarDotIds = {
  BottomNavBarItem.forYou: 'home.nav.home',
  BottomNavBarItem.feed: 'home.nav.feed',
  BottomNavBarItem.botvinnik: 'home.nav.botvinnik',
  // The id Collections wore when it last had a tab: dots published for it
  // light it again.
  BottomNavBarItem.collections: 'home.nav.collections',
  // Profile took over the side menu the avatar used to open, so it keeps the
  // avatar's id: published `drawer.*` dots trail through `home.menu`.
  BottomNavBarItem.profile: 'home.menu',
};

final namesBottomNavBarIcons = {
  BottomNavBarItem.forYou: 'Home',
  BottomNavBarItem.feed: 'Feed',
  BottomNavBarItem.botvinnik: 'Botvinnik',
  BottomNavBarItem.collections: 'Collections',
  BottomNavBarItem.profile: 'Profile',
};

/// The e2e key of each slot.
Key bottomNavBarItemKey(BottomNavBarItem item) => e2eKey(switch (item) {
  BottomNavBarItem.forYou => E2eIds.navForYou,
  BottomNavBarItem.feed => E2eIds.navFeed,
  BottomNavBarItem.botvinnik => E2eIds.navBotvinnik,
  BottomNavBarItem.collections => E2eIds.navCollections,
  BottomNavBarItem.profile => E2eIds.navProfile,
});

/// The mark a slot wears, at [side] in [ink]. Profile wears the reader's
/// own avatar, the circle that used to sit in every tab's top corner.
Widget bottomNavBarGlyph(
  BottomNavBarItem item, {
  required Color ink,
  required double side,
  required bool selected,
}) {
  Widget svg(String asset) => SvgWidget(
    asset,
    height: side,
    width: side,
    colorFilter: ColorFilter.mode(ink, BlendMode.srcIn),
  );
  return switch (item) {
    BottomNavBarItem.forYou => Icon(
      Icons.home_rounded,
      size: side + 4,
      color: ink,
    ),
    BottomNavBarItem.feed => svg(SvgAsset.feedNavIcon),
    BottomNavBarItem.botvinnik => svg(SvgAsset.botvinnikNavIcon),
    BottomNavBarItem.collections => svg(collectionsNavIcon),
    BottomNavBarItem.profile => _NavAvatar(
      side: side + 4,
      ink: ink,
      selected: selected,
    ),
  };
}

/// The reader's avatar as a nav mark: their photo, or their initial on a
/// disc tinted with the slot's own ink, so it reads with the marks beside
/// it (and clears AA in both themes, which the gradient initials of the old
/// top-bar avatar did not on paper). Selected, it wears a ring in the
/// selected ink with a gap of page between ring and photo. A guest has no
/// face to show (their name is the word "Guest"), so they get the bare person
/// mark like the glyphs beside it, never a mark on a disc. An unread Inbox
/// message puts the Inbox dot on its shoulder.
class _NavAvatar extends ConsumerWidget {
  const _NavAvatar({
    required this.side,
    required this.ink,
    required this.selected,
  });

  final double side;
  final Color ink;
  final bool selected;

  /// Inter's cap height as a share of the em (1490 of 2048 units).
  static const _interCapHeight = 1490 / 2048;

  static String _initial(String? name) {
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return '';
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(inboxHasUnreadProvider);
    final (:guest, :name) = ref.watch(
      currentUserProvider.select(
        (user) =>
            (guest: user == null || user.isAnonymous, name: user?.displayName),
      ),
    );
    // The photo is read even for a guest: [currentUserProvider] keeps quiet
    // when a guest links an account (same id), and this one does not.
    final url = ref.watch(profileAvatarUrlProvider)?.trim();
    final initial = guest ? '' : _initial(name);
    // The slot's discovery dot sits on the same shoulder; both say
    // "something new behind Profile", so one dot is drawn, never two side by
    // side.
    final discoveryLit = ref.watch(
      discoveryDotsProvider.select(
        (state) =>
            state.lit.contains(bottomNavBarDotIds[BottomNavBarItem.profile]),
      ),
    );
    // Centred on the slot's shoulder ([navMarkShoulder]) from this avatar's
    // centre: the 8pt dot's centre sits 2 right of the avatar's top-right
    // corner, level with it.
    final dot = unread && !discoveryLit
        ? const Positioned(
            top: -4,
            right: -6,
            child: InboxUnreadDot(key: ValueKey('nav-profile-inbox-dot')),
          )
        : null;

    if (initial.isEmpty && (url == null || url.isEmpty)) {
      // Home's size (glyph side + 4, this square is glyph side + 6), centred
      // in the avatar's square so the slot does not move when a guest signs in.
      return SizedBox.square(
        dimension: side,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(
              child: Icon(Icons.person_rounded, size: side - 2, color: ink),
            ),
            ?dot,
          ],
        ),
      );
    }

    const ring = 1.6;
    const gap = 1.6;
    final inner = side - 2 * (ring + gap);
    final fontSize = inner * 0.52;

    // A plain disc while a photo loads (or when it fails) for a reader with
    // no name to take an initial from.
    final disc = DecoratedBox(
      decoration: BoxDecoration(
        // 0.14 keeps the initial at AA on the disc in both themes,
        // selected or not (4.67:1 at worst, light unselected).
        color: ink.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: initial.isEmpty
          ? null
          : Align(
              alignment: Alignment.topCenter,
              // Centred on the capital's ink, not its line box (which put it
              // about 0.06em high): the baseline goes half a cap height
              // below the disc's centre, wherever the line box puts it.
              child: Baseline(
                baseline: inner / 2 + _interCapHeight * fontSize / 2,
                baselineType: TextBaseline.alphabetic,
                child: Text(
                  initial,
                  textScaler: TextScaler.noScaling,
                  style: AppTypography.textSmMedium.copyWith(
                    color: ink,
                    fontSize: fontSize,
                    height: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
    );
    final cacheWidth = (inner * MediaQuery.devicePixelRatioOf(context)).round();
    final photo = url == null || url.isEmpty
        ? disc
        : CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            width: inner,
            height: inner,
            memCacheWidth: cacheWidth,
            placeholder: (_, _) => disc,
            errorWidget: (_, _, _) => disc,
          );

    return SizedBox.square(
      dimension: side,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? ink : Colors.transparent,
                width: ring,
              ),
            ),
            child: Center(
              child: SizedBox.square(
                dimension: inner,
                child: ClipOval(child: photo),
              ),
            ),
          ),
          ?dot,
        ],
      ),
    );
  }
}

/// The section Home shows. The app opens on the stored default
/// ([readDefaultBottomTab], For You unless the viewer picked another); deep
/// links and notification taps push their screens over Home, so backing out
/// of them lands there too.
///
/// It also tells the store-update reminder whether the section is one it may
/// open over ([updatePromptSections]), from here because the bar, the tablet
/// rail, Home's fallbacks and deep links all write it.
final selectedBottomNavBarItemProvider =
    StateProvider.autoDispose<BottomNavBarItem>((ref) {
      void publish(BottomNavBarItem item) =>
          PhoneUpdateRouteObserver.homeSectionSafe.value = updatePromptSections
              .contains(item);
      // StateProvider has no Notifier to listen on; this is its only hook.
      // ignore: deprecated_member_use
      ref.listenSelf((_, item) => publish(item));
      ref.onDispose(
        () => PhoneUpdateRouteObserver.homeSectionSafe.value = true,
      );
      final initial = readDefaultBottomTab();
      publish(initial);
      return initial;
    });

/// The sections the store-update reminder may open over: pages to browse.
/// Botvinnik (a chat), Feed (a clip playing) and Collections (whose catalog
/// search may hold a query being typed, as Search's tab did in its slot)
/// keep it waiting until the reader is back on one of these.
const updatePromptSections = {
  BottomNavBarItem.forYou,
  BottomNavBarItem.profile,
};

/// Selects [item], announcing it to analytics. A section that is not on the
/// bar right now (Botvinnik switched off) is never selected.
void selectBottomNavBarItem(
  WidgetRef ref,
  BottomNavBarItem item, {
  String navigationType = 'bar',
}) => _selectSection(ref.read, item, navigationType: navigationType);

/// The route the home shell stands on while it is mounted, so a page over
/// it can take the reader back to one of its sections ([openHomeSection]).
ModalRoute<Object?>? _homeShellRoute;

/// The home shell standing on [route] (set as it mounts, and again if its
/// route changes).
void registerHomeShellRoute(ModalRoute<Object?>? route) {
  _homeShellRoute = route;
}

/// The home shell on [route] leaving: forgotten, unless a newer shell
/// already stands on another route.
void unregisterHomeShellRoute(ModalRoute<Object?>? route) {
  if (identical(_homeShellRoute, route)) _homeShellRoute = null;
}

/// Opens the dock's [item] as a tap on its slot would, from a page pushed
/// over the home shell (Search's Collections section) or from inside it
/// (Discovery's Collections tile), instead of pushing a second copy of a
/// section the dock already holds: the section is selected (so the page
/// closing over it reveals it) and every page over the shell closes.
///
/// Returns false, changing nothing, when no home shell stands under
/// [context]'s navigator (a page reached with no Home under it, a page
/// pumped alone in a test) or the section is not on the bar: the caller
/// then pushes a page of its own.
bool openHomeSection(
  BuildContext context,
  BottomNavBarItem item, {
  String navigationType = 'link',
}) {
  final shell = _homeShellRoute;
  if (shell == null || !shell.isActive) return false;
  final navigator = Navigator.maybeOf(context);
  if (navigator == null || !identical(shell.navigator, navigator)) {
    return false;
  }
  final container = ProviderScope.containerOf(context, listen: false);
  if (!container.read(visibleBottomNavItemsProvider).contains(item)) {
    return false;
  }
  _selectSection(container.read, item, navigationType: navigationType);
  if (!shell.isCurrent) navigator.popUntil((route) => route == shell);
  return true;
}

void _selectSection(
  T Function<T>(ProviderListenable<T> provider) read,
  BottomNavBarItem item, {
  required String navigationType,
}) {
  final previous = read(selectedBottomNavBarItemProvider);
  if (previous == item) {
    // Same tab re-tapped: signal screens to scroll their active list to top.
    // Selected subtab + data are preserved; no pull-to-refresh, no reload.
    read(bottomNavBarReTapRequestProvider.notifier).request(item);
    return;
  }
  if (!read(visibleBottomNavItemsProvider).contains(item)) return;
  read(selectedBottomNavBarItemProvider.notifier).state = item;
  unawaited(
    AnalyticsService.instance.trackEvent(
      'Bottom Nav Changed',
      properties: {
        'previous_tab': previous.name,
        'tab': item.name,
        'navigation_type': navigationType,
      },
    ),
  );
}

/// The launch section a Premium viewer picked (long-press a tab, or Settings
/// › Customization). Unset or unreadable means For You. Sections that are no
/// longer on the bar (Events, Search) fall back to For You: Search is a page
/// opened from Home now, so a reader who launched on it lands on Home, one
/// tap from it.
const String defaultBottomTabPrefsKey = 'default_bottom_tab_v1';

BottomNavBarItem readDefaultBottomTab() {
  final name = SharedPreferencesService.instance.prefsOrNull?.getString(
    defaultBottomTabPrefsKey,
  );
  if (name == null) return BottomNavBarItem.forYou;
  for (final item in BottomNavBarItem.values) {
    if (item.name == name) return item;
  }
  return BottomNavBarItem.forYou;
}

Future<void> writeDefaultBottomTab(BottomNavBarItem item) async {
  final prefs =
      SharedPreferencesService.instance.prefsOrNull ??
      await SharedPreferencesService.instance.ensureInitialized();
  await prefs?.setString(defaultBottomTabPrefsKey, item.name);
}

/// The phone's dock standing full: one large mark per section, no names
/// drawn (each slot announces its own). The home shell builds
/// [HomeNavDock] itself, on the section's chrome; this is the dock with
/// none, for a page or a test that only needs the marks.
class BottomNavBar extends StatelessWidget {
  const BottomNavBar({super.key});

  @override
  Widget build(BuildContext context) => const HomeNavDock();
}
