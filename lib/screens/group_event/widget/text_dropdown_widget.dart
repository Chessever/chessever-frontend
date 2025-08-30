import 'package:chessever2/screens/group_event/model/games_app_bar_view_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/divider_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

class TextDropDownWidget extends StatefulWidget {
  const TextDropDownWidget({
    required this.items,
    required this.selectedId,
    required this.onChanged,
    super.key,
  });

  final List<Map<String, String>> items;
  final String selectedId;
  final ValueChanged<String> onChanged;

  @override
  State<TextDropDownWidget> createState() => _TextDropDownWidgetState();
}

class _TextDropDownWidgetState extends State<TextDropDownWidget> {
  late String _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.selectedId;
  }

  @override
  void didUpdateWidget(TextDropDownWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedId != widget.selectedId) {
      _selectedId = widget.selectedId;
    }
  }

  Widget _buildDropdownItem(String text, String status) {
    final roundStatus = RoundStatus.values.firstWhere(
      (e) => e.name == status,
      orElse: () => RoundStatus.completed,
    );

    Widget trailingIcon;

    switch (roundStatus) {
      case RoundStatus.completed:
        trailingIcon = SvgPicture.asset(
          SvgAsset.check,
          width: 16.w,
          height: 16.h,
        );
        break;
      case RoundStatus.live:
        trailingIcon = SvgPicture.asset(
          SvgAsset.selectedSvg,
          width: 16.w,
          height: 16.h,
        );
        break;
      case RoundStatus.ongoing:
        trailingIcon = SvgPicture.asset(
          SvgAsset.selectedSvg,
          width: 16.w,
          height: 16.h,
        );
        break;
      case RoundStatus.upcoming:
        trailingIcon = SvgPicture.asset(
          SvgAsset.calendarIcon,
          width: 16.w,
          height: 16.h,
        );
        break;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 8,
          child: Text(
            text,
            style: AppTypography.textXsRegular.copyWith(color: kWhiteColor),
            softWrap: true,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: Align(alignment: Alignment.centerRight, child: trailingIcon),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Ensure the selected ID exists in the items
    final hasValidSelection = widget.items.any(
      (item) => item['key'] == _selectedId,
    );
    final currentValue =
        hasValidSelection ? _selectedId : widget.items.first['key'];

    return DropdownButton<String>(
      value: currentValue,
      onChanged: (newValue) {
        if (newValue != null) {
          setState(() {
            _selectedId = newValue;
          });
          widget.onChanged(newValue);
        }
      },
      items:
          widget.items.asMap().entries.map<DropdownMenuItem<String>>((entry) {
            final index = entry.key;
            final item = entry.value;
            final isLast = index == widget.items.length - 1;

            return DropdownMenuItem<String>(
              value: item['key']!, // Use the key as the value
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Spacer(),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 10.sp),
                    alignment: Alignment.center,
                    child: _buildDropdownItem(item['value']!, item['status']!),
                  ),
                  Spacer(),
                  if (!isLast)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 2.h),
                      child: const DividerWidget(),
                    ),
                ],
              ),
            );
          }).toList(),
      underline: Container(),
      icon: Icon(
        Icons.keyboard_arrow_down_outlined,
        color: kWhiteColor,
        size: 20.ic,
      ),
      dropdownColor: kBlack2Color,
      borderRadius: BorderRadius.circular(20.br),
      isExpanded: true,
      style: AppTypography.textMdBold,
      selectedItemBuilder: (BuildContext context) {
        return widget.items.map((item) {
          return Container(
            padding: EdgeInsets.symmetric(horizontal: 10.sp, vertical: 4.h),
            alignment: Alignment.centerLeft,
            constraints: BoxConstraints(minHeight: 44.h),
            child: Text(
              item['value']!,
              style: AppTypography.textXsMedium.copyWith(color: kWhiteColor),
              maxLines: 3,
              overflow: TextOverflow.visible,
              softWrap: true,
            ),
          );
        }).toList();
      },
    );
  }
}
