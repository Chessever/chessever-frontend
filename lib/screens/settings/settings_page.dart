import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/screens/settings/widgets/board_settings_body.dart';
import 'package:chessever2/screens/settings/widgets/engine_settings_body.dart';
import 'package:chessever2/screens/settings/widgets/notification_settings_body.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/hamburger_menu/hamburger_menu_dialogs.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum SettingsSection { board, engine, notification }

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

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
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
                _CollapsibleSection(
                  title: 'Board Settings',
                  subtitle: 'Board theme, pieces, auto-pin, sounds',
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
                  subtitle: 'Stockfish, depth, lines, arrows, eval bar',
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
                  subtitle: 'Push, alerts, library, updates',
                  leading: Icon(
                    Icons.notifications_active_outlined,
                    color: context.colors.iconPrimary,
                    size: 22.ic,
                  ),
                  expanded: _expanded == SettingsSection.notification,
                  onTap: () => _toggle(SettingsSection.notification),
                  child: NotificationSettingsBody(trackPersist: _trackPersist),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Delete Account',
                        style: AppTypography.textMdMedium.copyWith(
                          color: danger,
                          fontSize: 14.f,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        'Permanently remove your account and data',
                        style: AppTypography.textSmRegular.copyWith(
                          color: context.colors.textTertiary,
                          fontSize: 11.f,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8.w),
                Icon(
                  Icons.chevron_right_rounded,
                  color: danger,
                  size: 24.ic,
                ),
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
    required this.subtitle,
    required this.leading,
    required this.expanded,
    required this.onTap,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget leading;
  final bool expanded;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final accent = kPrimaryColor;
    final borderColor = expanded
        ? accent.withValues(alpha: 0.45)
        : context.colors.divider.withValues(alpha: 0.4);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(20.br),
        border: Border.all(color: borderColor),
        boxShadow: expanded
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.18),
                  blurRadius: 18,
                  spreadRadius: -4,
                  offset: const Offset(0, 6),
                ),
              ]
            : context.isLightTheme
                ? [
                    BoxShadow(
                      color: context.colors.shadow,
                      blurRadius: 8,
                      offset: const Offset(0, 1),
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
                        decoration: BoxDecoration(
                          color: expanded
                              ? accent.withValues(alpha: 0.16)
                              : context.colors.surfaceRecessed,
                          borderRadius: BorderRadius.circular(12.br),
                          border: Border.all(
                            color: expanded
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: AppTypography.textMdMedium.copyWith(
                                color: context.colors.textPrimary,
                                fontSize: 14.f,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: 2.h),
                            Text(
                              subtitle,
                              style: AppTypography.textSmRegular.copyWith(
                                color: context.colors.textTertiary,
                                fontSize: 11.f,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
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
