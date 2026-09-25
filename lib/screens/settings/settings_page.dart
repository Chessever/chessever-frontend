import 'package:chessever2/chat/botvinnik_icon.dart';
import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/screens/settings/widgets/board_settings_body.dart';
import 'package:chessever2/screens/settings/widgets/botvinnik_settings_body.dart';
import 'package:chessever2/screens/settings/widgets/engine_settings_body.dart';
import 'package:chessever2/screens/settings/widgets/notification_settings_body.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/theme/theme_provider.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/hamburger_menu/hamburger_menu_dialogs.dart';
import 'package:chessever2/widgets/notification_settings/beta_badge.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

enum SettingsSection { botvinnik, board, engine, notification }

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key, this.initiallyExpanded});

  final SettingsSection? initiallyExpanded;

  static Route<void> route({SettingsSection? initiallyExpanded}) {
    return MaterialPageRoute<void>(
      builder: (_) => SettingsPage(initiallyExpanded: initiallyExpanded),
    );
  }

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final Set<Future<void>> _pendingPersists = {};
  SettingsSection? _expanded;

  // Used to scroll the Picture-in-Picture card into view when the page is opened
  // straight to the notification section.
  final GlobalKey _liveWidgetsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    if (widget.initiallyExpanded == SettingsSection.notification) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToLiveWidgets();
      });
    }
  }

  Future<void> _scrollToLiveWidgets() async {
    // Let the page lay out, then centre the Picture-in-Picture card so it is
    // immediately in view (it sits below a tall push card).
    await Future<void>.delayed(const Duration(milliseconds: 280));
    final ctx = _liveWidgetsKey.currentContext;
    if (!mounted || ctx == null || !ctx.mounted) return;
    await Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  void _trackPersist(Future<void> future) {
    _pendingPersists.add(future);
    future.whenComplete(() => _pendingPersists.remove(future));
  }

  Future<bool> _onWillPop() async {
    if (_pendingPersists.isNotEmpty) {
      await Future.wait(_pendingPersists);
    }
    return true;
  }

  void _toggle(SettingsSection section) {
    HapticFeedbackService.selection();
    setState(() {
      _expanded = _expanded == section ? null : section;
    });
  }

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 20.sp,
      tablet: 32.sp,
    );
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final canPop = await _onWillPop();
        if (canPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        key: e2eKey(E2eIds.settingsRoot),
        backgroundColor: context.colors.background,
        appBar: AppBar(
          title: Text(
            'Settings',
            style: AppTypography.textLgMedium.copyWith(
              color: context.colors.textPrimary,
              fontSize: 16.f,
            ),
          ),
          backgroundColor: context.colors.background,
          foregroundColor: context.colors.textPrimary,
          centerTitle: false,
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: ResponsiveHelper.contentMaxWidth,
            ),
            child: ListView(
              padding: EdgeInsets.only(
                left: horizontalPadding,
                right: horizontalPadding,
                top: 16.sp,
                bottom: 16.sp + bottomPadding,
              ),
              children: [
                const SettingsAppearanceSection(),
                SizedBox(height: 14.h),
                _CollapsibleSection(
                  title: 'Botvinnik',
                  // BotvinnikIcon picks its own tint per theme (paperTint on
                  // light); an accent-text override drowns the face.
                  leading: BotvinnikIcon(size: 24.ic),
                  expanded: _expanded == SettingsSection.botvinnik,
                  onTap: () => _toggle(SettingsSection.botvinnik),
                  child: BotvinnikSettingsBody(trackPersist: _trackPersist),
                ),
                SizedBox(height: 14.h),
                _CollapsibleSection(
                  title: 'Board Settings',
                  leading: SvgWidget(
                    SvgAsset.boardSettings,
                    height: 22.h,
                    width: 22.w,
                    preserveOriginalColors: true,
                  ),
                  expanded: _expanded == SettingsSection.board,
                  onTap: () => _toggle(SettingsSection.board),
                  child: BoardSettingsBody(trackPersist: _trackPersist),
                ),
                SizedBox(height: 14.h),
                _CollapsibleSection(
                  title: 'Engine Experience',
                  leading: Icon(
                    Icons.memory_outlined,
                    color: context.colors.iconPrimary,
                    size: 22.ic,
                  ),
                  expanded: _expanded == SettingsSection.engine,
                  onTap: () => _toggle(SettingsSection.engine),
                  child: EngineSettingsBody(trackPersist: _trackPersist),
                ),
                SizedBox(height: 14.h),
                _CollapsibleSection(
                  title: 'Notification Settings',
                  leading: Icon(
                    Icons.notifications_active_outlined,
                    color: context.colors.iconPrimary,
                    size: 22.ic,
                  ),
                  expanded: _expanded == SettingsSection.notification,
                  onTap: () => _toggle(SettingsSection.notification),
                  child: NotificationSettingsBody(
                    trackPersist: _trackPersist,
                    liveWidgetsKey: _liveWidgetsKey,
                  ),
                ),
                SizedBox(height: 24.h),
                _DeleteAccountRow(
                  onTap: () {
                    HapticFeedbackService.navigation();
                    showDeleteAccountDialog(context);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What the Beta mark says: Light is usable but not finished.
const String kLightModeBetaNotice =
    "Light mode is in beta. Some screens aren't finished yet.";

/// Dark / Light picker. Plain text segments on an inset track with a sliding
/// thumb: no icon tile, no accent flood. Dark stays the default for anyone
/// who never opens this card. Light carries a Beta mark over its segment;
/// tapping the mark, or picking Light, says it is not finished yet.
class SettingsAppearanceSection extends ConsumerWidget {
  const SettingsAppearanceSection({super.key});

  static const _modes = <(ThemeMode, String)>[
    (ThemeMode.dark, 'Dark'),
    (ThemeMode.light, 'Light'),
  ];

  static void _explainBeta(BuildContext context) {
    showAppSnack(context, kLightModeBetaNotice);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(themeModeProvider);
    final selectedIndex = _modes.indexWhere((m) => m.$1 == selected);

    return Container(
      key: const ValueKey('settings_appearance_card'),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(20.br),
        border: Border.all(
          color: context.colors.divider.withValues(alpha: 0.4),
        ),
        boxShadow: context.isLightTheme
            ? [
                BoxShadow(
                  color: context.colors.shadow,
                  blurRadius: 8,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      ),
      padding: EdgeInsets.fromLTRB(16.sp, 14.sp, 16.sp, 16.sp),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Appearance',
                  style: AppTypography.textMdMedium.copyWith(
                    color: context.colors.textPrimary,
                    fontSize: 14.f,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Over the Light segment, which ends the track on the right.
              Semantics(
                button: true,
                label: 'Light mode is in beta',
                excludeSemantics: true,
                child: GestureDetector(
                  key: const ValueKey('settings_light_beta'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedbackService.selection();
                    _explainBeta(context);
                  },
                  // A bigger reach than the mark, without moving it: the
                  // padding spills into the card's own inset.
                  child: Transform.translate(
                    offset: Offset(8.sp, 0),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 8.sp,
                        vertical: 6.sp,
                      ),
                      child: const BetaBadge(),
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 6.h),
          _ThemeModeSegments(
            labels: [for (final m in _modes) m.$2],
            selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
            onSelected: (index) {
              final mode = _modes[index].$1;
              if (mode == selected) return;
              HapticFeedbackService.selection();
              ref.read(themeModeProvider.notifier).setTheme(mode);
              if (mode == ThemeMode.light) _explainBeta(context);
            },
          ),
        ],
      ),
    );
  }
}

/// Inset segmented track with one thumb that springs between options.
/// Selection reads from three cues at once: the raised thumb, the label
/// weight and the label ink, so it survives both themes and colour-blindness.
class _ThemeModeSegments extends StatelessWidget {
  const _ThemeModeSegments({
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final isLight = context.isLightTheme;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    // Track sits a step below the card; the thumb a step above the track.
    final trackColor = context.colors.background;
    final thumbColor = isLight ? kWhiteColor : context.colors.surfaceRecessed;
    final thumbEdge = isLight
        ? context.colors.divider.withValues(alpha: 0.8)
        : context.colors.dividerStrong.withValues(alpha: 0.6);
    final count = labels.length;
    final inset = 3.sp;

    return Container(
      // A floor, not a fixed height: at large text sizes (and on short
      // phones, where 40.h shrinks) the track grows to its labels instead of
      // slicing their descenders.
      constraints: BoxConstraints(minHeight: 40.h),
      padding: EdgeInsets.all(inset),
      decoration: BoxDecoration(
        color: trackColor,
        borderRadius: BorderRadius.circular(4.br),
      ),
      child: IntrinsicHeight(
        child: Stack(
          children: [
            Positioned.fill(
              child: SingleMotionBuilder(
                motion: reduceMotion
                    ? const Motion.none()
                    : const CupertinoMotion.snappy(),
                value: selectedIndex.toDouble(),
                builder: (context, value, child) {
                  final x = count <= 1 ? 0.0 : -1 + 2 * value / (count - 1);
                  return Align(
                    alignment: Alignment(x.clamp(-1.0, 1.0), 0),
                    child: child,
                  );
                },
                child: FractionallySizedBox(
                  widthFactor: 1 / count,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: thumbColor,
                      borderRadius: BorderRadius.circular(2.br),
                      border: Border.all(color: thumbEdge, width: 0.5),
                      boxShadow: isLight
                          ? [
                              BoxShadow(
                                color: context.colors.textPrimary.withValues(
                                  alpha: 0.08,
                                ),
                                blurRadius: 2,
                                offset: const Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                for (var i = 0; i < count; i++)
                  Expanded(
                    child: _ThemeModeSegment(
                      label: labels[i],
                      selected: i == selectedIndex,
                      reduceMotion: reduceMotion,
                      onTap: () => onSelected(i),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeModeSegment extends StatefulWidget {
  const _ThemeModeSegment({
    required this.label,
    required this.selected,
    required this.reduceMotion,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool reduceMotion;
  final VoidCallback onTap;

  @override
  State<_ThemeModeSegment> createState() => _ThemeModeSegmentState();
}

class _ThemeModeSegmentState extends State<_ThemeModeSegment> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: widget.selected,
      label: '${widget.label} appearance',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        onTap: widget.onTap,
        child: SingleMotionBuilder(
          motion: widget.reduceMotion
              ? const Motion.none()
              : const CupertinoMotion.snappy(),
          value: _pressed ? 0.97 : 1.0,
          builder: (context, scale, child) {
            return Transform.scale(scale: scale, child: child);
          },
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // Control-scale text stops at 1.4x, as the Feed header does, so
                // three labels still fit across the track.
                textScaler: MediaQuery.textScalerOf(
                  context,
                ).clamp(maxScaleFactor: 1.4),
                style: AppTypography.textSmMedium.copyWith(
                  color: widget.selected
                      ? context.colors.textPrimary
                      : context.colors.textSecondary,
                  fontWeight: widget.selected
                      ? FontWeight.w600
                      : FontWeight.w500,
                  fontSize: 13.f,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeleteAccountRow extends StatelessWidget {
  const _DeleteAccountRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final danger = context.colors.danger;
    return Material(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(20.br),
      child: InkWell(
        key: e2eKey(E2eIds.settingsDeleteAccount),
        onTap: onTap,
        borderRadius: BorderRadius.circular(20.br),
        splashColor: danger.withValues(alpha: 0.08),
        highlightColor: danger.withValues(alpha: 0.04),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20.br),
            border: Border.all(color: danger.withValues(alpha: 0.45)),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 14.sp),
            child: Row(
              children: [
                Container(
                  width: 40.w,
                  height: 40.h,
                  decoration: BoxDecoration(
                    color: danger.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12.br),
                    border: Border.all(color: danger.withValues(alpha: 0.35)),
                  ),
                  child: Icon(
                    Icons.delete_forever_outlined,
                    color: danger,
                    size: 22.ic,
                  ),
                ),
                SizedBox(width: 14.w),
                Expanded(
                  child: Text(
                    'Delete Account',
                    style: AppTypography.textMdMedium.copyWith(
                      color: danger,
                      fontSize: 14.f,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(width: 8.w),
                Icon(Icons.chevron_right_rounded, color: danger, size: 24.ic),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CollapsibleSection extends StatelessWidget {
  const _CollapsibleSection({
    required this.title,
    required this.leading,
    required this.expanded,
    required this.onTap,
    required this.child,
  });

  final String title;
  final Widget leading;
  final bool expanded;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isLight = context.isLightTheme;
    // Paper takes the deep accent-text teal: raw brand cyan reads ~2.3:1
    // on the mint surface, under the 3:1 floor for UI chrome. Dark keeps
    // the brand cyan and its expanded bloom unchanged.
    final accent = isLight ? context.colors.accentText : kPrimaryColor;
    final borderColor = expanded
        ? (isLight ? accent : accent.withValues(alpha: 0.45))
        : context.colors.divider.withValues(alpha: 0.4);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(20.br),
        border: Border.all(color: borderColor),
        // Light: one tight ink-tinted shadow in both states, so expanding
        // never blooms a coloured smudge onto the mint page.
        boxShadow: isLight
            ? [
                BoxShadow(
                  color: context.colors.shadow,
                  blurRadius: 8,
                  offset: const Offset(0, 1),
                ),
              ]
            : expanded
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.18),
                  blurRadius: 18,
                  spreadRadius: -4,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20.br),
        child: Column(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                splashColor: accent.withValues(alpha: 0.08),
                highlightColor: accent.withValues(alpha: 0.04),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16.sp,
                    vertical: 14.sp,
                  ),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutCubic,
                        width: 40.w,
                        height: 40.h,
                        // Light never tints the tile; the section border
                        // alone carries the expanded state there.
                        decoration: BoxDecoration(
                          color: expanded && !isLight
                              ? accent.withValues(alpha: 0.16)
                              : context.colors.surfaceRecessed,
                          borderRadius: BorderRadius.circular(12.br),
                          border: Border.all(
                            color: expanded && !isLight
                                ? accent.withValues(alpha: 0.35)
                                : Colors.transparent,
                          ),
                        ),
                        child: Center(
                          child: SizedBox.square(
                            dimension: 22.ic,
                            child: FittedBox(
                              fit: BoxFit.contain,
                              child: leading,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 14.w),
                      Expanded(
                        child: Text(
                          title,
                          style: AppTypography.textMdMedium.copyWith(
                            color: context.colors.textPrimary,
                            fontSize: 14.f,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      SizedBox(width: 8.w),
                      AnimatedRotation(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                        turns: expanded ? 0.25 : 0.0,
                        child: Icon(
                          Icons.chevron_right_rounded,
                          color: expanded
                              ? accent
                              : context.colors.textTertiary,
                          size: 24.ic,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ClipRect(
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                heightFactor: expanded ? 1.0 : 0.0,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  opacity: expanded ? 1.0 : 0.0,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16.sp, 4.sp, 16.sp, 18.sp),
                    child: child,
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
