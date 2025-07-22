import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/blur_background.dart';
import 'package:chessever2/widgets/divider_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/theme/app_theme.dart';
import '../providers/board_settings_provider.dart';
import 'board_color_dialog.dart';

class BoardSettingsDialog extends ConsumerWidget {
  const BoardSettingsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardSettings = ref.watch(boardSettingsProvider);

    return Stack(
      children: [
        // Backdrop filter for blur effect
        // Positioned.fill(child: BlurBackground()),
        // Dialog content
        GestureDetector(
          onTap: () {}, // Absorb the tap
          child: Container(
            // padding: EdgeInsets.symmetric(vertical: 10.h),
            decoration: BoxDecoration(
              color: kPopUpColor,
              borderRadius: BorderRadius.circular(20.br),
              boxShadow: [
                BoxShadow(
                  color: kBlackColor.withOpacity(0.3),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Row(
                    children: [
                      SizedBox(width: 16.w),
                      SvgPicture.asset(
                        SvgAsset.left_arrow,
                        height: 10.h,
                        width: 5.w,
                        semanticsLabel: 'Board Settings Icon',
                      ),
                      SizedBox(width: 8.w),
                      Text(
                        'Back',
                        style: AppTypography.textSmRegular.copyWith(
                          color: kBoardColorGrey,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 25.h),
                _MenuItem(
                  customIcon: SvgPicture.asset(SvgAsset.boardSettings),
                  title: 'Change Board Color',
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                      ),
                      backgroundColor: Colors.transparent,
                      builder: (BuildContext bottomSheetContext) {
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: MediaQuery.of(context).viewInsets.bottom,
                          ),
                          child: BoardColorDialog(),
                        );
                      },
                    );
                  },
                  showChevron: false,
                ),
                DividerWidget(),
                _SwitchItem(
                  title: 'Evaluation bar',
                  value: boardSettings.showEvaluationBar,
                  onChanged: (value) {
                    ref
                        .read(boardSettingsProvider.notifier)
                        .toggleEvaluationBar();
                  },
                ),

                DividerWidget(),
                _SwitchItem(
                  title: 'Sound',
                  value: boardSettings.soundEnabled,
                  onChanged: (_) {
                    // Use separate reference to prevent cross-interference
                    ref.read(boardSettingsProvider.notifier).toggleSound();
                  },
                ),
                DividerWidget(),
                _SwitchItem(
                  title: 'Chat',
                  value: boardSettings.chatEnabled,
                  onChanged: (_) {
                    // Use separate reference to prevent cross-interference
                    ref.read(boardSettingsProvider.notifier).toggleChat();
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    this.icon,
    this.customIcon,
    required this.title,
    required this.onPressed,
    required this.showChevron,
    super.key,
  });

  final IconData? icon;
  final Widget? customIcon;
  final String title;
  final VoidCallback onPressed;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36.h,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: EdgeInsets.all(8.sp),
          child: Row(
            children: [
              customIcon ?? Icon(icon!, color: kWhiteColor, size: 20.ic),
              SizedBox(width: 4.w),
              Expanded(child: Text(title, style: AppTypography.textMdMedium)),
              if (showChevron)
                Icon(
                  Icons.chevron_right_outlined,
                  color: kWhiteColor,
                  size: 20.ic,
                ),
              SizedBox(
                width: 36,
                child: SvgPicture.asset(
                  SvgAsset.right_arrow,
                  height: 12.h,
                  width: 6.w,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwitchItem extends StatelessWidget {
  const _SwitchItem({
    required this.title,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36.h,
      child: InkWell(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.sp, vertical: 8.sp),
          child: Row(
            children: [
              Expanded(child: Text(title, style: AppTypography.textMdMedium)),
              SizedBox(
                width: 34.w,
                height: 20.h,
                child: FittedBox(
                  fit: BoxFit.fill,
                  child: Switch.adaptive(
                    value: value,
                    onChanged: onChanged,
                    activeColor: kWhiteColor,
                    activeTrackColor: kPrimaryColor,
                    inactiveThumbColor: kWhiteColor,
                    inactiveTrackColor: kDarkGreyColor,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
