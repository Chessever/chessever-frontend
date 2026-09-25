
import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/streaks/widgets/wall_common.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/paywall/manage_subscription_sheet.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Who My Profile shows.
typedef MyProfileIdentity = ({
  String? displayName,
  String? email,
  bool isGuest,
});

/// The identity My Profile renders, selected field by field from
/// [authStateProvider]. [AppUser] equality is by id alone, so a guest who
/// signs in from this screen without changing id would leave
/// [currentUserProvider] quiet; a record notices.
final myProfileIdentityProvider = Provider.autoDispose<MyProfileIdentity>((
  ref,
) {
  return ref.watch(
    authStateProvider.select((auth) {
      final user = auth.valueOrNull?.user;
      final name = user?.displayName?.trim();
      return (
        displayName: (name?.isNotEmpty ?? false) ? name : null,
        email: user?.email,
        isGuest: user == null || user.isAnonymous,
      );
    }),
  );
});

/// Press feedback, gone when the system asks for less motion.
double? _pressScale(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context) ? null : 0.97;

/// The smallest hit box on this screen, in logical pixels. Fixed rather than
/// `.w`-scaled: `44.w` shrinks to about 40 on a 360-wide phone.
const double _minTarget = 44;

/// Header-scale text stops growing here, the way the Feed header does; the
/// rows under it still take the full system scale.
TextScaler _headerScaler(BuildContext context) =>
    MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.4);


/// The signed-in user's own page: who they are and their plan.
class MyProfileScreen extends ConsumerWidget {
  const MyProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final identity = ref.watch(myProfileIdentityProvider);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _ProfileHeader(),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  16.w,
                  12.w,
                  16.w,
                  40.w + bottomInset,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _IdentityBlock(identity: identity),
                        SizedBox(height: 20.w),
                        const _PlanRow(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader();

  @override
  Widget build(BuildContext context) {
    final ink = context.colors.textPrimary;
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 0, 16.w, 0),
      // A floor, not a fixed height: at large text sizes the bar grows
      // instead of slicing the title.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _minTarget),
        child: Row(
          children: [
            SizedBox.square(
              dimension: _minTarget,
              child: IconButton(
                tooltip: 'Back',
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: ink,
                  size: 20.w,
                ),
              ),
            ),
            SizedBox(width: 4.w),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  'Profile',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textScaler: _headerScaler(context),
                  style: wallText(22, 28, FontWeight.w700, ink),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IdentityBlock extends StatelessWidget {
  const _IdentityBlock({required this.identity});

  final MyProfileIdentity identity;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final name = identity.displayName ?? 'Guest';
    final detail = identity.isGuest ? 'Not signed in' : identity.email;

    return Row(
      children: [
        _ProfileAvatar(name: identity.displayName),
        SizedBox(width: 16.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: wallText(20, 26, FontWeight.w700, colors.textPrimary),
              ),
              if (detail != null) ...[
                SizedBox(height: 2.w),
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
            ],
          ),
        ),
      ],
    );
  }
}

/// The profile's picture: the sign-in photo when there is one, otherwise the
/// initials in body ink on a flat recessed disc (about 12:1 in either theme).
///
/// Deliberately not `UserAvatar`: its subscriber ring spins forever, ignores
/// reduced motion and shifts this row when the plan resolves, and its
/// initials sit on a fixed dark-theme gradient that fails AA on paper. The
/// Plan row already says which plan this is.
class _ProfileAvatar extends ConsumerWidget {
  const _ProfileAvatar({required this.name});

  final String? name;

  static const double _size = 64;

  /// First letters of the first and last words, or a knight with no name.
  static String _initials(String? name) {
    final words = (name ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '♞';
    String first(String word) =>
        String.fromCharCode(word.runes.first).toUpperCase();
    return words.length == 1
        ? first(words.first)
        : first(words.first) + first(words.last);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final url = ref.watch(
      currentUserProvider.select((user) => user?.avatarUrl?.trim()),
    );
    final diameter = _size.w;

    final disc = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceRecessed,
        shape: BoxShape.circle,
      ),
      child: Padding(
        // Keeps the letters inside the square the circle inscribes, so large
        // text shrinks to fit instead of being cut by the round edge.
        padding: EdgeInsets.all(diameter * 0.18),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _initials(name),
              maxLines: 1,
              style: wallText(22, 28, FontWeight.w700, colors.textPrimary),
            ),
          ),
        ),
      ),
    );

    Widget content = disc;
    if (url != null && url.isNotEmpty) {
      final cacheWidth = (diameter * MediaQuery.devicePixelRatioOf(context))
          .round();
      content = CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        width: diameter,
        height: diameter,
        memCacheWidth: cacheWidth,
        placeholder: (_, _) => disc,
        errorWidget: (_, _, _) => disc,
      );
    }

    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: diameter,
        child: ClipOval(child: content),
      ),
    );
  }
}

/// The plan, and the way into it: Manage for subscribers (the drawer header
/// used to open this sheet directly), the paywall for everyone else.
class _PlanRow extends ConsumerWidget {
  const _PlanRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPremium = ref.watch(
      subscriptionProvider.select((s) => s.isSubscribed),
    );
    return _ProfileRow(
      title: isPremium ? 'ChessEver Premium' : 'Free plan',
      subtitle: isPremium
          ? 'Manage your subscription'
          : 'See what Premium adds',
      onTap: () {
        if (isPremium) {
          showManageSubscriptionSheet(context);
        } else {
          showPremiumPaywallSheet(context: context, featureId: 'my_profile');
        }
      },
    );
  }
}

/// A full-width row that opens something: a title, an optional line under
/// it, a chevron.
class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final subtitle = this.subtitle;
    return WallPressable(
      pressScale: _pressScale(context),
      onTap: () {
        HapticFeedbackService.buttonPress();
        onTap();
      },
      child: Container(
        constraints: BoxConstraints(minHeight: subtitle == null ? 52.w : 60.w),
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.w),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(4.br),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: wallText(
                      15,
                      20,
                      FontWeight.w600,
                      colors.textPrimary,
                    ),
                  ),
                  if (subtitle != null) ...[
                    SizedBox(height: 2.w),
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
            SizedBox(width: 12.w),
            Icon(
              Icons.chevron_right_rounded,
              size: 20.w,
              color: colors.iconSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
