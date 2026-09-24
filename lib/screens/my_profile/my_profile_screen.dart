import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/feed/race/race_flames.dart';
import 'package:chessever2/screens/feed/race/race_lobby_screen.dart';
import 'package:chessever2/screens/my_profile/chess_accounts.dart';
import 'package:chessever2/screens/my_profile/race_stats_provider.dart';
import 'package:chessever2/screens/my_space/widgets/pixel_flame.dart';
import 'package:chessever2/screens/streaks/widgets/wall_common.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/paywall/manage_subscription_sheet.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';
import 'package:url_launcher/url_launcher.dart';

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

/// Error ink. The theme's danger token already clears AA in both themes
/// (light deepens it to #C53128 on paper), so the profile shares it rather
/// than carrying its own red.
Color _dangerInk(BuildContext context) => context.colors.danger;

/// The signed-in user's own page: who they are, their plan, the chess-site
/// usernames they link, and their Puzzle Race bests.
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
                        SizedBox(height: 40.w),
                        const _SectionTitle('Chess accounts'),
                        SizedBox(height: 4.w),
                        if (identity.isGuest)
                          const _GuestAccountsPrompt()
                        else
                          const _ChessAccountsForm(),
                        SizedBox(height: 40.w),
                        const _SectionTitle('Puzzle Race'),
                        SizedBox(height: 12.w),
                        const _RaceStatsSection(),
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        text,
        style: wallText(18, 24, FontWeight.w700, context.colors.textPrimary),
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: wallText(14, 20, FontWeight.w400, context.colors.textSecondary),
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
    this.haptic = true,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  /// False when [onTap] already gives its own tap feedback.
  final bool haptic;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final subtitle = this.subtitle;
    return WallPressable(
      pressScale: _pressScale(context),
      onTap: () {
        if (haptic) HapticFeedbackService.buttonPress();
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

class _GuestAccountsPrompt extends StatelessWidget {
  const _GuestAccountsPrompt();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Caption('Sign in to link your accounts.'),
        SizedBox(height: 16.w),
        _ProfileButton(
          label: 'Sign in',
          onPressed: () {
            HapticFeedbackService.buttonPress();
            showAuthUpgradeSheet(
              context: context,
              title: 'Sign in to link your accounts',
              message:
                  'Your Lichess and Chess.com usernames are kept with your '
                  'ChessEver account.',
              completeSignInInSheet: true,
            );
          },
        ),
      ],
    );
  }
}

/// The two username fields and their Save. Existence is checked on Save only,
/// one request per changed name; a name the site does not know is flagged
/// once and can then be saved anyway.
class _ChessAccountsForm extends ConsumerStatefulWidget {
  const _ChessAccountsForm();

  @override
  ConsumerState<_ChessAccountsForm> createState() => _ChessAccountsFormState();
}

class _ChessAccountsFormState extends ConsumerState<_ChessAccountsForm> {
  final Map<ChessSite, TextEditingController> _controllers = {
    for (final site in ChessSite.values) site: TextEditingController(),
  };
  final Map<ChessSite, FocusNode> _focus = {
    for (final site in ChessSite.values) site: FocusNode(),
  };
  final Map<ChessSite, String> _errors = {};
  final Map<ChessSite, String> _warnings = {};

  /// What the server holds.
  late LinkedChessAccounts _committed;

  /// The typed names the last Save warned about. Saving these same names
  /// again goes straight through, without asking the sites a second time.
  LinkedChessAccounts? _warnedTyped;

  /// What that warned pass would store (the site's own casing folded in),
  /// and which sites it could not reach.
  LinkedChessAccounts? _warnedToSave;
  List<ChessSite> _warnedUnconfirmed = const [];

  bool _saving = false;

  /// Back was asked for while unsaved: leave as soon as the save lands
  /// clean. Cleared when the save stops short (a format error, a warning, a
  /// failure) so the user stays to see why.
  bool _leaveAfterSave = false;

  @override
  void initState() {
    super.initState();
    _committed = ref.read(linkedChessAccountsProvider);
    for (final site in ChessSite.values) {
      _controllers[site]!.text = _committed.of(site) ?? '';
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  String _typed(ChessSite site) =>
      normalizeChessUsername(_controllers[site]!.text);

  LinkedChessAccounts get _typedAccounts {
    String? orNull(String value) => value.isEmpty ? null : value;
    return (
      lichess: orNull(_typed(ChessSite.lichess)),
      chesscom: orNull(_typed(ChessSite.chesscom)),
    );
  }

  bool _isDirty(ChessSite site) => _typed(site) != (_committed.of(site) ?? '');

  bool get _dirty => ChessSite.values.any(_isDirty);

  /// A newer server value (a save landing, another device) replaces any field
  /// the user is not in the middle of editing.
  void _adopt(LinkedChessAccounts next) {
    setState(() {
      for (final site in ChessSite.values) {
        if (!_isDirty(site)) _controllers[site]!.text = next.of(site) ?? '';
      }
      _committed = next;
    });
  }

  void _edited(ChessSite site) {
    setState(() {
      _errors.remove(site);
      _warnings.remove(site);
      _warnedTyped = null;
      _warnedToSave = null;
      _warnedUnconfirmed = const [];
    });
  }

  /// Back (the button, a swipe, the system gesture) with unsaved names:
  /// save them or let them go, never drop them silently.
  Future<void> _onBlockedPop() async {
    if (_saving) {
      // Already on its way; the Save button shows it. Leave when it lands.
      _leaveAfterSave = true;
      return;
    }
    final choice = await _confirmLeave(context);
    if (!mounted || choice == null) return;
    switch (choice) {
      case _LeaveChoice.discard:
        _leave();
      case _LeaveChoice.save:
        _leaveAfterSave = true;
        await _save();
    }
  }

  /// Pops this screen, unless something has since been pushed over it.
  void _leave() {
    _leaveAfterSave = false;
    if (ModalRoute.of(context)?.isCurrent ?? false) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_dirty) {
      if (_leaveAfterSave) _leave();
      return;
    }
    FocusScope.of(context).unfocus();

    final typed = _typedAccounts;
    // Only these go to the server. The others show the cached session,
    // which may be older than a link made on another device since.
    final changed = [
      for (final site in ChessSite.values)
        if (_isDirty(site)) site,
    ];
    final errors = <ChessSite, String>{};
    for (final site in changed) {
      final error = validateChessUsername(site, typed.of(site) ?? '');
      if (error != null) errors[site] = error;
    }
    if (errors.isNotEmpty) {
      HapticFeedbackService.error();
      _leaveAfterSave = false;
      setState(() {
        _errors
          ..clear()
          ..addAll(errors);
      });
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(chessAccountsServiceProvider);
    setState(() {
      _saving = true;
      _errors.clear();
    });

    try {
      var toSave = typed;
      var unconfirmed = <ChessSite>[];

      if (_warnedTyped == typed && _warnedToSave != null) {
        // "Save anyway": the user has seen the warning for these names.
        toSave = _warnedToSave!;
        unconfirmed = [..._warnedUnconfirmed];
      } else {
        // One request per changed, non-empty name, both at once.
        final checks = <ChessSite, Future<UsernameLookup>>{
          for (final site in ChessSite.values)
            if (typed.of(site) != null && typed.of(site) != _committed.of(site))
              site: service.lookup(site, typed.of(site)!),
        };
        final warnings = <ChessSite, String>{};
        for (final entry in checks.entries) {
          final site = entry.key;
          final name = typed.of(site)!;
          final result = await entry.value;
          switch (result.status) {
            case UsernameLookupStatus.found:
              final canonical = result.canonicalUsername;
              if (canonical != null) toSave = toSave.withSite(site, canonical);
            case UsernameLookupStatus.notFound:
              warnings[site] =
                  '${site.label} has no player called $name. Check the '
                  'spelling, or save anyway.';
            case UsernameLookupStatus.closed:
              warnings[site] =
                  'This ${site.label} account is closed. Save anyway if it '
                  'is yours.';
            case UsernameLookupStatus.unreachable:
              unconfirmed.add(site);
          }
        }
        if (!mounted) return;
        if (warnings.isNotEmpty) {
          HapticFeedbackService.light();
          _leaveAfterSave = false;
          setState(() {
            _warnings
              ..clear()
              ..addAll(warnings);
            _warnedTyped = typed;
            _warnedToSave = toSave;
            _warnedUnconfirmed = unconfirmed;
          });
          return;
        }
      }

      final stored = await service.save(toSave, sites: changed);
      if (!mounted) return;
      setState(() {
        _committed = stored;
        for (final site in ChessSite.values) {
          // The fields are read-only while saving; this also guarantees a
          // name typed since the snapshot is never overwritten.
          if (_typed(site) == (typed.of(site) ?? '')) {
            _controllers[site]!.text = stored.of(site) ?? '';
          }
        }
        _warnings.clear();
        _warnedTyped = null;
        _warnedToSave = null;
        _warnedUnconfirmed = const [];
      });
      HapticFeedbackService.success();
      showAppSnackOn(
        messenger,
        unconfirmed.isEmpty
            ? 'Chess accounts saved'
            : 'Saved. ${unconfirmed.map((s) => s.label).join(' and ')} '
                  'could not be reached to check the name.',
        tone: unconfirmed.isEmpty ? AppSnackTone.success : AppSnackTone.neutral,
      );
      // The snack rides the app's messenger, so it outlives this screen.
      if (_leaveAfterSave) _leave();
    } catch (error) {
      debugPrint('My Profile: saving chess accounts failed: $error');
      HapticFeedbackService.error();
      _leaveAfterSave = false;
      showAppSnackOn(
        messenger,
        userFacingError(
          error,
          fallback: 'Could not save your chess accounts. Please try again.',
        ),
        tone: AppSnackTone.danger,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<LinkedChessAccounts>(linkedChessAccountsProvider, (_, next) {
      if (next != _committed) _adopt(next);
    });

    final dirty = _dirty;
    final enabled = dirty && !_saving;
    final saveAnyway = _warnedTyped != null && _warnedTyped == _typedAccounts;

    // Registers with the whole route, so the header's back button, the iOS
    // swipe and Android's back gesture all stop here while names are unsaved.
    return PopScope<Object?>(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_onBlockedPop());
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Caption('Just the username, no password.'),
          SizedBox(height: 16.w),
          for (final site in ChessSite.values) ...[
            _UsernameField(
              site: site,
              controller: _controllers[site]!,
              focusNode: _focus[site]!,
              error: _errors[site],
              warning: _warnings[site],
              linkedName: _isDirty(site) ? null : _committed.of(site),
              // Typing during a save would be overwritten when it lands.
              readOnly: _saving,
              textInputAction: site == ChessSite.values.last
                  ? TextInputAction.done
                  : TextInputAction.next,
              onChanged: () => _edited(site),
              onSubmitted: () {
                if (site == ChessSite.values.last) {
                  unawaited(_save());
                } else {
                  _focus[ChessSite.values[site.index + 1]]!.requestFocus();
                }
              },
            ),
            SizedBox(height: 12.w),
          ],
          SizedBox(height: 8.w),
          _ProfileButton(
            label: saveAnyway ? 'Save anyway' : 'Save',
            loading: _saving,
            onPressed: enabled ? () => unawaited(_save()) : null,
          ),
        ],
      ),
    );
  }
}

enum _LeaveChoice { discard, save }

/// Asks what to do with unsaved usernames. Null (a tap outside, back) means
/// stay on the page.
Future<_LeaveChoice?> _confirmLeave(BuildContext context) {
  HapticFeedbackService.light();
  return showDialog<_LeaveChoice>(
    context: context,
    barrierColor: context.colors.scrim,
    builder: (dialogContext) {
      final colors = dialogContext.colors;
      return Dialog(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4.br),
        ),
        // Scrolls rather than overflowing at the largest text sizes on a
        // short phone.
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20.w, 22.w, 20.w, 20.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Save your usernames?',
                style: wallText(20, 26, FontWeight.w700, colors.textPrimary),
              ),
              SizedBox(height: 8.w),
              Text(
                'Your chess account changes are not saved yet.',
                style: wallText(15, 21, FontWeight.w400, colors.textSecondary),
              ),
              SizedBox(height: 20.w),
              Row(
                children: [
                  Expanded(
                    child: _ProfileButton(
                      label: 'Discard',
                      tone: _ButtonTone.quiet,
                      onPressed: () =>
                          Navigator.of(dialogContext).pop(_LeaveChoice.discard),
                    ),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: _ProfileButton(
                      label: 'Save',
                      onPressed: () =>
                          Navigator.of(dialogContext).pop(_LeaveChoice.save),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

enum _ButtonTone { primary, quiet }

/// The screen's buttons: a 4px slab with the same press as its rows, 0.97 on
/// a spring, and a tonal step instead when the system asks for less motion.
/// Disabled reads as a recessed slab with quiet ink.
class _ProfileButton extends StatefulWidget {
  const _ProfileButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.tone = _ButtonTone.primary,
  });

  final String label;

  /// Null disables the button.
  final VoidCallback? onPressed;

  /// Shows a spinner on the primary fill and ignores taps.
  final bool loading;
  final _ButtonTone tone;

  @override
  State<_ProfileButton> createState() => _ProfileButtonState();
}

class _ProfileButtonState extends State<_ProfileButton> {
  bool _pressed = false;

  void _set(bool value) {
    if (_pressed != value && mounted) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final loading = widget.loading;
    final enabled = widget.onPressed != null && !loading;

    final Color fill;
    final Color ink;
    if (!enabled && !loading) {
      fill = colors.surfaceRecessed;
      ink = colors.textSecondary;
    } else if (widget.tone == _ButtonTone.primary) {
      fill = colors.textPrimary;
      ink = colors.textInverse;
    } else {
      fill = colors.surfaceRecessed;
      ink = colors.textPrimary;
    }
    final pressed = _pressed && enabled;

    return Semantics(
      button: true,
      enabled: enabled,
      label: loading ? 'Saving' : widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: enabled ? (_) => _set(false) : null,
        onTapCancel: enabled ? () => _set(false) : null,
        onTap: enabled ? widget.onPressed : null,
        child: SingleMotionBuilder(
          motion: reduceMotion
              ? const Motion.none()
              : const CupertinoMotion.snappy(),
          value: pressed && !reduceMotion ? 0.97 : 1.0,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: pressed && reduceMotion
                  ? Color.lerp(fill, ink, 0.14)
                  : fill,
              borderRadius: BorderRadius.circular(4.br),
            ),
            child: loading
                ? SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: ink,
                    ),
                  )
                : Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    style: wallText(16, 22, FontWeight.w600, ink),
                  ),
          ),
        ),
      ),
    );
  }
}

/// A username field drawn as the public address it becomes: the site's
/// profile prefix, then the name.
class _UsernameField extends StatelessWidget {
  const _UsernameField({
    required this.site,
    required this.controller,
    required this.focusNode,
    required this.error,
    required this.warning,
    required this.linkedName,
    required this.textInputAction,
    required this.onChanged,
    required this.onSubmitted,
    this.readOnly = false,
  });

  final ChessSite site;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String? error;
  final String? warning;

  /// The saved name, when the field still shows it: offers the profile link.
  final String? linkedName;

  /// Shown as usual but takes no typing (a save is in flight).
  final bool readOnly;
  final TextInputAction textInputAction;
  final VoidCallback onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final quiet = wallText(15, 20, FontWeight.w400, colors.textSecondary);
    final error = this.error;
    final warning = this.warning;
    final linkedName = this.linkedName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListenableBuilder(
          listenable: focusNode,
          builder: (context, child) {
            final border = error != null
                ? _dangerInk(context)
                : focusNode.hasFocus
                ? colors.textPrimary
                : colors.textTertiary;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: focusNode.requestFocus,
              child: Container(
                // A floor, not a fixed height: large text grows the field
                // instead of slicing the name.
                constraints: BoxConstraints(minHeight: 48.w),
                alignment: Alignment.centerLeft,
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.w),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(4.br),
                  border: Border.all(color: border),
                ),
                child: child,
              ),
            );
          },
          child: Row(
            children: [
              // The address prefix keeps its width at large text sizes (the
              // field label says the same to screen readers), so the name
              // always has room.
              ExcludeSemantics(
                child: Text(
                  site.profilePrefix,
                  maxLines: 1,
                  softWrap: false,
                  style: quiet,
                  textScaler: MediaQuery.textScalerOf(
                    context,
                  ).clamp(maxScaleFactor: 1.3),
                ),
              ),
              Expanded(
                child: Semantics(
                  label: '${site.label} username',
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    readOnly: readOnly,
                    style: wallText(
                      15,
                      20,
                      FontWeight.w500,
                      colors.textPrimary,
                    ),
                    cursorColor: colors.textPrimary,
                    autocorrect: false,
                    enableSuggestions: false,
                    smartDashesType: SmartDashesType.disabled,
                    smartQuotesType: SmartQuotesType.disabled,
                    textCapitalization: TextCapitalization.none,
                    textInputAction: textInputAction,
                    inputFormatters: [LengthLimitingTextInputFormatter(120)],
                    onChanged: (_) => onChanged(),
                    onSubmitted: (_) => onSubmitted(),
                    decoration: InputDecoration.collapsed(
                      hintText: 'username',
                      hintStyle: quiet,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (error != null)
          Padding(
            padding: EdgeInsets.only(top: 8.w),
            child: Text(
              error,
              style: wallText(13, 18, FontWeight.w500, _dangerInk(context)),
            ),
          )
        else if (warning != null)
          Padding(
            padding: EdgeInsets.only(top: 8.w),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: 1.w),
                  child: Icon(
                    Icons.info_outline_rounded,
                    size: 16.w,
                    color: colors.textSecondary,
                  ),
                ),
                SizedBox(width: 6.w),
                Expanded(
                  child: Text(
                    warning,
                    style: wallText(
                      13,
                      18,
                      FontWeight.w400,
                      colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          )
        else if (linkedName != null)
          Align(
            alignment: Alignment.centerLeft,
            child: _ViewProfileLink(site: site, username: linkedName),
          ),
      ],
    );
  }
}

class _ViewProfileLink extends StatelessWidget {
  const _ViewProfileLink({required this.site, required this.username});

  final ChessSite site;
  final String username;

  Future<void> _open(BuildContext context) async {
    HapticFeedbackService.buttonPress();
    final messenger = ScaffoldMessenger.maybeOf(context);
    var opened = false;
    try {
      opened = await launchUrl(
        site.profileUrl(username),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!opened && messenger != null) {
      showAppSnackOn(
        messenger,
        'Could not open ${site.label}',
        tone: AppSnackTone.danger,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = context.colors.textPrimary;
    return Semantics(
      link: true,
      label: 'View $username on ${site.label}',
      excludeSemantics: true,
      child: WallPressable(
        pressScale: _pressScale(context),
        onTap: () => _open(context),
        // A 44pt floor on every phone, and a little run past the arrow so
        // the target is wider than the words it carries.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _minTarget),
          child: Padding(
            padding: EdgeInsets.only(right: 12.w),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    'View on ${site.label}',
                    style: wallText(13, 18, FontWeight.w600, ink),
                  ),
                ),
                SizedBox(width: 4.w),
                Icon(Icons.north_east_rounded, size: 14.w, color: ink),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Flames and personal bests from Puzzle Race, or an honest empty state with
/// the way in. A signed-in player's figures are the race service's (every
/// device), never lower than this device's own; a guest's live only here.
class _RaceStatsSection extends ConsumerWidget {
  const _RaceStatsSection();

  /// Opens the race lobby over the profile, the same route the Feed's
  /// galloping knight opens. Back from the race lands here with any unsaved
  /// usernames intact, and what it wrote reads in fresh.
  Future<void> _startRace(BuildContext context, WidgetRef ref) async {
    await RaceLobbyScreen.open(context, from: 'Profile');
    if (!context.mounted) return;
    ref.invalidate(raceStatsProvider);
    ref.invalidate(raceServerStatsProvider);
  }

  void _keepFlames(BuildContext context) {
    HapticFeedbackService.buttonPress();
    showAuthUpgradeSheet(
      context: context,
      title: 'Keep your flames',
      message: 'Flames you earn signed in are saved to your account.',
      completeSignInInSheet: true,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A sign-in, or another account, reads its own kept flames.
    ref.listen<String?>(
      currentUserProvider.select((user) => user?.id),
      (_, _) => ref.invalidate(raceServerStatsProvider),
    );
    ref.listen<bool>(
      myProfileIdentityProvider.select((identity) => identity.isGuest),
      (_, _) => ref.invalidate(raceServerStatsProvider),
    );
    final guest = ref.watch(
      myProfileIdentityProvider.select((identity) => identity.isGuest),
    );
    final stats = ref.watch(raceStatsProvider);
    final server = guest
        ? null
        : ref.watch(raceServerStatsProvider).valueOrNull;
    final start = _ProfileRow(
      title: 'Start a Puzzle Race',
      // The lobby gives its own navigation tap.
      haptic: false,
      onTap: () => unawaited(_startRace(context, ref)),
    );

    return stats.when(
      // SharedPreferences answers within a frame; hold the space meanwhile.
      loading: () => SizedBox(height: 120.w),
      error: (_, _) => _RaceEmpty(start: start),
      data: (local) {
        if (local.isEmpty && (server == null || server.racesPlayed == 0)) {
          return _RaceEmpty(start: start);
        }
        int best(int mine, int? kept) => kept == null || mine > kept
            ? mine
            : kept;
        final flames = raceFlameTotal(server: server, local: local.flames);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (flames > 0) ...[
              Row(
                children: [
                  PixelFlame(streak: raceFlameHeat(flames), size: 30.w),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: _Stat(
                      key: const ValueKey('profile_race_flames'),
                      label: 'Flames',
                      value: flames,
                    ),
                  ),
                ],
              ),
              if (guest) _KeepFlamesLink(onTap: () => _keepFlames(context)),
              SizedBox(height: guest ? 8.w : 20.w),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _Stat(
                    label: 'Survival best',
                    value: best(local.survivalBest, server?.survivalBest),
                  ),
                ),
                SizedBox(width: 16.w),
                Expanded(
                  child: _Stat(
                    label: 'Infinite best',
                    value: best(local.infiniteBest, server?.infiniteBest),
                  ),
                ),
              ],
            ),
            SizedBox(height: 20.w),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _Stat(
                    label: 'Races played',
                    value: best(local.racesPlayed, server?.racesPlayed),
                  ),
                ),
                SizedBox(width: 16.w),
                Expanded(
                  child: _Stat(
                    label: 'Best streak',
                    value: best(local.bestStreak, server?.bestStreak),
                  ),
                ),
              ],
            ),
            SizedBox(height: 24.w),
            start,
          ],
        );
      },
    );
  }
}

/// A guest's quiet way to keep the flames they earn from now on.
class _KeepFlamesLink extends StatelessWidget {
  const _KeepFlamesLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = context.colors.textSecondary;
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        button: true,
        label: 'Sign in to keep your flames',
        excludeSemantics: true,
        child: WallPressable(
          key: const ValueKey('profile_keep_flames'),
          pressScale: _pressScale(context),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _minTarget),
            child: Padding(
              padding: EdgeInsets.only(right: 12.w),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      'Sign in to keep your flames',
                      style: wallText(14, 20, FontWeight.w600, ink),
                    ),
                  ),
                  SizedBox(width: 2.w),
                  Icon(Icons.chevron_right_rounded, size: 18.w, color: ink),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RaceEmpty extends StatelessWidget {
  const _RaceEmpty({required this.start});

  final Widget start;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'No races yet',
          style: wallText(16, 22, FontWeight.w600, context.colors.textPrimary),
        ),
        SizedBox(height: 4.w),
        const _Caption('Your flames and bests will show up here.'),
        SizedBox(height: 16.w),
        start,
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, super.key});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      label: '$label, $value',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            maxLines: 1,
            style: wallText(
              28,
              34,
              FontWeight.w700,
              colors.textPrimary,
              tabular: true,
            ),
          ),
          SizedBox(height: 2.w),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: wallText(13, 18, FontWeight.w500, colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
