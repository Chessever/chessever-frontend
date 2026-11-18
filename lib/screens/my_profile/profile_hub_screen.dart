import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/main.dart';
import 'package:chessever2/providers/app_version_provider.dart';
import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/authentication/auth_screen_provider.dart';
import 'package:chessever2/screens/calendar/calendar_screen.dart';
import 'package:chessever2/screens/collections/collections_screen.dart';
import 'package:chessever2/screens/favorites/favorites_tab_screen.dart';
import 'package:chessever2/screens/favorites/provider/favorites_mode_provider.dart';
import 'package:chessever2/screens/gamebase/gamebase_explorer_screen.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/inbox/inbox_provider.dart';
import 'package:chessever2/screens/inbox/inbox_screen.dart';
import 'package:chessever2/screens/inbox/inbox_unread_dot.dart';
import 'package:chessever2/screens/my_profile/my_profile_screen.dart';
import 'package:chessever2/screens/streaks/widgets/wall_common.dart';
import 'package:chessever2/services/review_prompt_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/board_navigation_icon.dart';
import 'package:chessever2/widgets/discovery_dot.dart';
import 'package:chessever2/services/discovery_dots/discovery_dot.dart';
import 'package:chessever2/widgets/hamburger_menu/hamburger_menu.dart';
import 'package:chessever2/widgets/hamburger_menu/hamburger_menu_dialogs.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:chessever2/widgets/profile_avatar_editor.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:chessever2/widgets/user_avatar.dart';
import 'package:chessever2/widgets/press_spring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Pushes the Events lists (Current, Upcoming, Past and search), which left
/// the bottom bar for Profile.
Future<void> openEventsScreen(BuildContext context) {
  HapticFeedbackService.navigation();
  return Navigator.of(context).push(eventsScreenRoute());
}

/// The Events page's route, for callers holding a navigator (a deep link).
Route<void> eventsScreenRoute() => MaterialPageRoute<void>(
  builder: (_) =>
      const Scaffold(resizeToAvoidBottomInset: false, body: GroupEventScreen()),
);

/// The Profile tab: the reader, then everything the sidebar used to hold
/// and the two sections that left the bottom bar (Events, Collections).
///
/// One quiet page in My Profile's language: the reader at the top, then
/// rows of stacked surface slabs in three runs (places to go, the app, the
/// account), each with a bare mark. The bottom bar steps away as it scrolls.
class ProfileHubScreen extends HookConsumerWidget {
  const ProfileHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final side = ResponsiveHelper.adaptive(phone: 16.w, tablet: 32.0);
    final inbox = ref.watch(inboxAvailableProvider);
    final botvinnik = ref.watch(botvinnikTabAvailableProvider);
    final unread = ref.watch(inboxHasUnreadProvider);
    final scroll = useScrollController();

    ref.listen<BottomNavBarReTapRequest>(bottomNavBarReTapRequestProvider, (
      previous,
      next,
    ) {
      if (next.item != BottomNavBarItem.profile) return;
      if (previous != null && previous.sequence == next.sequence) return;
      if (scroll.hasClients) {
        scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      }
    });

    void push(Widget page) {
      HapticFeedbackService.navigation();
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    }

    final places = <Widget>[
      _HubRow(
        key: e2eKey(E2eIds.profileEvents),
        title: 'Events',
        dotId: 'home.nav.events',
        mark: _svgMark(context, SvgAsset.tournamentIcon),
        onTap: () => openEventsScreen(context),
      ),
      _HubRow(
        key: e2eKey(E2eIds.profileCollections),
        title: 'Collections',
        dotId: 'home.nav.collections',
        mark: _svgMark(context, 'assets/svgs/collections_nav.svg'),
        onTap: () => CollectionsScreen.open(context),
      ),
      if (botvinnik)
        _HubRow(
          key: const ValueKey('profile-botvinnik'),
          title: 'Botvinnik',
          mark: _svgMark(context, SvgAsset.botvinnikNavIcon),
          onTap: () => selectBottomNavBarItem(
            ref,
            BottomNavBarItem.botvinnik,
            navigationType: 'profile',
          ),
        ),
      if (inbox)
        _HubRow(
          key: const ValueKey('profile-inbox'),
          title: 'Inbox',
          dotId: 'drawer.inbox',
          mark: _iconMark(context, Icons.inbox_outlined),
          trailing: unread
              ? const InboxUnreadDot(key: ValueKey('profile-inbox-dot'))
              : null,
          onTap: () => push(const InboxScreen()),
        ),
      _HubRow(
        key: e2eKey(E2eIds.drawerBoard),
        title: 'Board',
        dotId: 'drawer.board',
        mark: BoardNavigationIcon(size: 22, semanticsLabel: 'Board'),
        onTap: () async {
          final allowed = await requireFullAuthGuard(context);
          if (!allowed || !context.mounted) return;
          push(GamebaseExplorerScreen.scoped());
        },
      ),
      _HubRow(
        key: e2eKey(E2eIds.drawerFullCalendar),
        title: 'Calendar',
        dotId: 'drawer.calendar',
        mark: _svgMark(context, SvgAsset.calendarNavIcon),
        onTap: () => openCalendarScreen(context, source: 'profile'),
      ),
      _HubRow(
        key: const ValueKey('profile-rankings'),
        title: 'Rankings',
        dotId: 'drawer.rankings',
        mark: _iconMark(context, Icons.leaderboard_outlined),
        onTap: () => push(
          const FavoritesTabScreen(initialMode: FavoritesScreenMode.players),
        ),
      ),
    ];

    final app = <Widget>[
      _HubRow(
        key: e2eKey(E2eIds.drawerSettings),
        title: 'Settings',
        dotId: 'drawer.settings',
        mark: _svgMark(context, SvgAsset.settings),
        onTap: () => showSettingsDialog(context),
      ),
      _HubRow(
        key: const ValueKey('profile-feedback'),
        title: 'Feedback',
        dotId: 'drawer.feedback',
        mark: _svgMark(context, SvgAsset.leaveFeedback),
        onTap: () =>
            ReviewPromptService.instance.openSidebarDirectFeedback(context),
      ),
      _HubRow(
        key: const ValueKey('profile-rate'),
        title: 'Rate ChessEver',
        dotId: 'drawer.rate',
        mark: _iconMark(context, Icons.star_outline_rounded),
        onTap: openChessEverStoreListing,
      ),
      _HubRow(
        key: const ValueKey('profile-about'),
        title: 'About',
        dotId: 'drawer.about',
        mark: _svgMark(context, SvgAsset.versionIcon),
        onTap: () => showChessEverAbout(
          context,
          ref.read(appVersionProvider).valueOrNull ?? '',
        ),
      ),
    ];

    return Material(
      key: e2eKey(E2eIds.profileRoot),
      color: colors.background,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          // The status bar's inset stays page, as on Home and Search: rows
          // scroll away below it, never under the clock.
          child: Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.viewPaddingOf(context).top,
            ),
            child: ListView(
              controller: scroll,
              padding: EdgeInsets.fromLTRB(side, 20.h, side, 32.h),
              children: [
                const _ReaderHeader(),
                SizedBox(height: 20.h),
                const _PlanSlab(),
                SizedBox(height: 28.h),
                _Run(children: places),
                SizedBox(height: 28.h),
                _Run(children: app),
                SizedBox(height: 28.h),
                const _Run(children: [_RestoreRow(), _SignOutRow()]),
                SizedBox(height: 28.h),
                const _VersionLine(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A row's mark from an SVG, in the row's ink. The sidebar's assets carry
/// white baked in; the filter makes them read in both themes.
Widget _svgMark(BuildContext context, String asset) => SvgWidget(
  asset,
  height: 22,
  width: 22,
  colorFilter: ColorFilter.mode(
    context.colors.textPrimary.withValues(alpha: 0.86),
    BlendMode.srcIn,
  ),
);

Widget _iconMark(BuildContext context, IconData icon) => Icon(
  icon,
  size: 22,
  color: context.colors.textPrimary.withValues(alpha: 0.86),
);

/// The reader: their avatar (a tap changes it), their name and how they are
/// signed in. The rest of the row opens My Profile.
class _ReaderHeader extends ConsumerWidget {
  const _ReaderHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final identity = ref.watch(myProfileIdentityProvider);
    final unread = ref.watch(inboxHasUnreadProvider);
    final name = identity.displayName ?? 'Guest';
    final detail = identity.isGuest
        ? 'Not signed in'
        : (identity.email ?? 'Your account');

    return Row(
      children: [
        Semantics(
          button: true,
          label: 'Change your photo',
          onTap: () => showProfileAvatarEditor(context),
          excludeSemantics: true,
          child: InboxAvatarBadge(
            unread: unread,
            child: UserAvatar(
              size: 64,
              onTap: () => showProfileAvatarEditor(context),
            ),
          ),
        ),
        SizedBox(width: 16.w),
        Expanded(
          child: WallPressable(
            semanticLabel: '$name, $detail, open your profile',
            onTap: () {
              HapticFeedbackService.navigation();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const MyProfileScreen(),
                ),
              );
            },
            // The label says the name and the line under it once.
            child: ExcludeSemantics(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 64),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: wallText(
                              22,
                              28,
                              FontWeight.w700,
                              colors.textPrimary,
                            ),
                          ),
                          SizedBox(height: 2.h),
                          Text(
                            detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: wallText(
                              14,
                              20,
                              FontWeight.w400,
                              colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 22,
                      color: colors.iconSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The plan, right under the reader: Premium for subscribers (opens My
/// Profile, where they manage it), the way to Premium for everyone else.
/// Upgrade wears the brand blue, as on the rewarded popup (Trello #1416),
/// through [AppColors.accentText]: raw brand cyan reads 2.3:1 on paper.
class _PlanSlab extends ConsumerWidget {
  const _PlanSlab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final premium = ref.watch(
      subscriptionProvider.select((state) => state.isSubscribed),
    );
    return _HubRow(
      key: e2eKey(E2eIds.drawerPremium),
      title: premium ? 'ChessEver Premium' : 'Free plan',
      subtitle: premium ? 'Manage your subscription' : 'See what Premium adds',
      mark: Icon(
        premium ? Icons.workspace_premium_rounded : Icons.bolt_rounded,
        size: 22,
        color: premium
            ? colors.accentText
            : colors.textPrimary.withValues(alpha: 0.86),
      ),
      trailing: premium
          ? null
          : Text(
              'Upgrade',
              style: wallText(15, 20, FontWeight.w600, colors.accentText),
            ),
      onTap: () async {
        if (premium) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const MyProfileScreen()),
          );
          return;
        }
        final authOk = await requireFullAuthGuard(context);
        if (!authOk || !context.mounted) return;
        await showPremiumPaywallSheet(
          context: context,
          allowRewarded: false,
          featureId: 'profile',
        );
      },
    );
  }
}

/// Rows in one run: slabs stacked with a hairline of page between them, so
/// the run reads as one object without a line drawn through it.
class _Run extends StatelessWidget {
  const _Run({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 2),
          children[i],
        ],
      ],
    );
  }
}

/// One slab: a bare mark, the title (and a line under it), a chevron or the
/// row's own trailing piece. At least 52 tall; grows with the text.
class _HubRow extends StatelessWidget {
  const _HubRow({
    super.key,
    required this.title,
    required this.mark,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.danger = false,
    this.showChevron = true,
    this.dotId,
  });

  final String title;
  final String? subtitle;
  final Widget mark;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool danger;
  final bool showChevron;

  /// The discovery-dot anchor, for a row that took over a surface the admin
  /// console's catalog (chessever-admin-portal `shared/nudges.ts`) already
  /// names, a sidebar row or a bottom-bar tab: dots published at it, and
  /// trails through it, still land here. Others are `profile.<title>`.
  final String? dotId;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final subtitle = this.subtitle;
    final ink = danger ? colors.danger : colors.textPrimary;
    return DiscoveryDotAnchor(
      id: dotId ?? discoveryDotId('profile', title),
      alignment: Alignment.centerLeft,
      offset: const Offset(16 + 22, -12),
      // Rows open a page, a dialog or the store over this one, where a
      // bubble would point at nothing; the snack outlives the tap.
      message: DiscoveryDotMessage.snack,
      child: WallPressable(
        semanticLabel: subtitle == null ? title : '$title, $subtitle',
        onTap: () {
          HapticFeedbackService.navigation();
          onTap();
        },
        // The app's press; a beat late, so a scroll that starts on a row
        // does not dip it first.
        child: PressSpring(
          pressedScale: 0.97,
          delay: const Duration(milliseconds: 70),
          child: Container(
            constraints: BoxConstraints(minHeight: subtitle == null ? 52 : 64),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(4.br),
            ),
            child: Row(
              children: [
                // The label above already says the title and its line; read
                // again here (and Board's mark names itself) they would repeat.
                // The trailing piece, Inbox's unread dot or Upgrade, still
                // speaks for itself.
                ExcludeSemantics(
                  child: SizedBox.square(
                    dimension: 24,
                    child: Center(child: mark),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: wallText(15, 20, FontWeight.w600, ink),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: wallText(
                              13,
                              18,
                              FontWeight.w400,
                              colors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 12), trailing!],
                if (showChevron && trailing == null) ...[
                  const SizedBox(width: 12),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: colors.iconSecondary,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Restore Purchases, kept for App Store compliance.
class _RestoreRow extends ConsumerWidget {
  const _RestoreRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _HubRow(
      key: const ValueKey('profile-restore'),
      title: 'Restore purchases',
      showChevron: false,
      mark: _iconMark(context, Icons.restore_rounded),
      onTap: () async {
        final success = await ref
            .read(subscriptionProvider.notifier)
            .restorePurchases();
        if (!context.mounted) return;
        showAppSnack(
          context,
          success ? 'Purchases restored' : 'No purchases found to restore',
          tone: success ? AppSnackTone.success : AppSnackTone.neutral,
        );
      },
    );
  }
}

/// Log out for a signed-in reader (confirmed first); Sign up for a guest,
/// which keeps the guest's session until the new account replaces it.
class _SignOutRow extends ConsumerWidget {
  const _SignOutRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guest =
        ref.watch(myProfileIdentityProvider).isGuest &&
        Supabase.instance.client.auth.currentUser?.isAnonymous == true;
    return _HubRow(
      key: e2eKey(E2eIds.drawerLogout),
      title: guest ? 'Sign up' : 'Log out',
      danger: !guest,
      showChevron: guest,
      mark: Icon(
        guest ? Icons.person_add_outlined : Icons.logout_rounded,
        size: 22,
        color: guest
            ? context.colors.textPrimary.withValues(alpha: 0.86)
            : context.colors.danger,
      ),
      onTap: () async {
        if (guest) {
          ref.read(authScreenProvider.notifier).reset();
          await Navigator.of(context).pushNamed('/auth_screen');
          return;
        }
        final confirmed = await showSmoothConfirmDialog(
          context: context,
          title: 'Log out',
          message: 'Are you sure you want to log out?',
          confirmText: 'Log out',
        );
        if (confirmed == true) {
          await ref.read(authStateProvider.notifier).signOut();
        }
      },
    );
  }
}

/// The build, in small print at the foot of the page. Seven taps open the
/// debug console (the sidebar's old trick, kept for support sessions).
class _VersionLine extends HookConsumerWidget {
  const _VersionLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taps = useRef(0);
    final version = ref.watch(appVersionProvider).valueOrNull ?? '';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        taps.value++;
        if (taps.value < 7) return;
        taps.value = 0;
        if (logarte.isOverlayAttached) {
          logarte.detachOverlay();
          showAppSnack(context, 'Logarte Debug Console Disabled');
        } else {
          logarte.attach(context: context, visible: true);
          showAppSnack(context, 'Logarte Debug Console Enabled');
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          version.isEmpty ? 'ChessEver' : 'ChessEver $version',
          textAlign: TextAlign.center,
          style: wallText(
            12,
            16,
            FontWeight.w400,
            context.colors.textSecondary,
          ),
        ),
      ),
    );
  }
}
