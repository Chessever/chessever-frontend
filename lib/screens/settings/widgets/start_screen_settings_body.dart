import 'package:chessever2/screens/for_you/providers/for_you_tab_provider.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/settings/widgets/settings_primitives.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Settings › Customization: which section and which Home page the app opens
/// on. Premium, like holding a bottom tab (see [makeBottomTabDefault]).
class StartScreenSettingsBody extends ConsumerStatefulWidget {
  const StartScreenSettingsBody({super.key});

  @override
  ConsumerState<StartScreenSettingsBody> createState() =>
      _StartScreenSettingsBodyState();
}

class _StartScreenSettingsBodyState
    extends ConsumerState<StartScreenSettingsBody> {
  late BottomNavBarItem _section = readDefaultBottomTab();
  late ForYouTab _homePage = readDefaultForYouTab();

  Future<void> _pickSection() async {
    final allowed = await requirePremiumGuard(
      context,
      ref,
      featureId: 'default_start_tab',
      returnTo: 'settings',
    );
    if (!allowed || !mounted) return;
    final picked = await showStartScreenPicker<BottomNavBarItem>(
      context: context,
      title: 'Start section',
      options: bottomNavBarOrder,
      label: (item) => namesBottomNavBarIcons[item]!,
      selected: _section,
    );
    if (picked == null || picked == _section) return;
    await writeDefaultBottomTab(picked);
    HapticFeedbackService.success();
    if (mounted) setState(() => _section = picked);
  }

  Future<void> _pickHomePage() async {
    final allowed = await requirePremiumGuard(
      context,
      ref,
      featureId: 'default_start_tab',
      returnTo: 'settings',
    );
    if (!allowed || !mounted) return;
    final picked = await showStartScreenPicker<ForYouTab>(
      context: context,
      title: 'Home page',
      options: ForYouTab.values,
      label: (tab) => tab.label,
      selected: _homePage,
    );
    if (picked == null || picked == _homePage) return;
    await writeDefaultForYouTab(picked);
    HapticFeedbackService.success();
    if (mounted) setState(() => _homePage = picked);
  }

  @override
  Widget build(BuildContext context) {
    return SettingCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PickerRow(
            title: 'Start section',
            value: namesBottomNavBarIcons[_section]!,
            onTap: _pickSection,
          ),
          Divider(
            height: 1.h,
            thickness: 0.5.w,
            color: context.colors.divider,
          ),
          _PickerRow(
            title: 'Home page',
            caption: 'Used when Home is the start section',
            value: _homePage.label,
            onTap: _pickHomePage,
          ),
        ],
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.title,
    required this.value,
    required this.onTap,
    this.caption,
  });

  final String title;
  final String value;
  final VoidCallback onTap;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedbackService.cardTap();
        onTap();
      },
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 10.h),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: AppTypography.textSmMedium.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                  if (caption != null) ...[
                    SizedBox(height: 2.h),
                    Text(
                      caption!,
                      style: AppTypography.textXsRegular.copyWith(
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Text(
              value,
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
            SizedBox(width: 4.w),
            Icon(
              Icons.chevron_right_rounded,
              size: 20.ic,
              color: context.colors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom-sheet option picker with a check on the current value.
Future<T?> showStartScreenPicker<T extends Enum>({
  required BuildContext context,
  required String title,
  required List<T> options,
  required String Function(T) label,
  required T selected,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    constraints: ResponsiveHelper.bottomSheetConstraints,
    builder: (context) => Container(
      decoration: BoxDecoration(
        color: context.colors.background,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        20.sp,
        12.sp,
        20.sp,
        20.sp + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: context.colors.divider,
                borderRadius: BorderRadius.circular(2.br),
              ),
            ),
          ),
          SizedBox(height: 12.h),
          Text(
            title,
            style: AppTypography.textMdMedium.copyWith(
              color: context.colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8.h),
          for (final option in options)
            InkWell(
              onTap: () {
                HapticFeedbackService.selection();
                Navigator.of(context).pop(option);
              },
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12.h),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label(option),
                        style: AppTypography.textSmMedium.copyWith(
                          color: context.colors.textPrimary,
                        ),
                      ),
                    ),
                    if (option == selected)
                      Icon(
                        Icons.check_rounded,
                        size: 20.ic,
                        color: context.colors.accentText,
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
