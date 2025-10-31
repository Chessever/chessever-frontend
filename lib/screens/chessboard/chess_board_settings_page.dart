import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ChessBoardSettingsPage extends ConsumerWidget {
  const ChessBoardSettingsPage({super.key});

  static Route<void> route() {
    return MaterialPageRoute<void>(builder: (_) => const ChessBoardSettingsPage());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(engineSettingsProvider);
    final settings = settingsAsync.valueOrNull ?? const EngineSettings();
    final notifier = ref.read(engineSettingsProvider.notifier);

    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        title: Text('Board Settings', style: AppTypography.textLgMedium.copyWith(color: kWhiteColor, fontSize: 16.f)),
        backgroundColor: kBackgroundColor,
        centerTitle: false,
      ),
      body: ListView(
        padding: EdgeInsets.symmetric(horizontal: 20.sp, vertical: 16.sp),
        children: [
          _SectionLabel(title: 'Engine Experience'),
          SizedBox(height: 12.h),
          _SettingCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Engine Gauge', style: AppTypography.textMdMedium.copyWith(color: kWhiteColor, fontSize: 13.f)),
                      SizedBox(height: 4.h),
                      Text('Show the evaluation gauge beside the board.', style: AppTypography.textSmRegular.copyWith(color: kWhiteColor70, fontSize: 11.f)),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: settings.showEngineGauge,
                  thumbColor: const WidgetStatePropertyAll(kPrimaryColor),
                  trackColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected) ? kPrimaryColor.withValues(alpha: 0.35) : kDividerColor.withValues(alpha: 0.5),
                  ),
                  onChanged: (value) => notifier.update(settings.copyWith(showEngineGauge: value)),
                ),
              ],
            ),
          ),
          SizedBox(height: 18.h),
          _SettingCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Depth Overlay', style: AppTypography.textMdMedium.copyWith(color: kWhiteColor, fontSize: 13.f)),
                      SizedBox(height: 4.h),
                      Text('Show the live engine depth on the board.', style: AppTypography.textSmRegular.copyWith(color: kWhiteColor70, fontSize: 11.f)),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: settings.showDepthOverlay,
                  thumbColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? kPrimaryColor : kWhiteColor.withValues(alpha: 0.6)),
                  trackColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? kPrimaryColor.withValues(alpha: 0.35) : kDividerColor.withValues(alpha: 0.5)),
                  onChanged: (value) => notifier.update(settings.copyWith(showDepthOverlay: value)),
                ),
              ],
            ),
          ),
          SizedBox(height: 18.h),
          _SettingCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('PV Arrows', style: AppTypography.textMdMedium.copyWith(color: kWhiteColor, fontSize: 13.f)),
                      SizedBox(height: 4.h),
                      Text('Show arrows for best move suggestions on the board.', style: AppTypography.textSmRegular.copyWith(color: kWhiteColor70, fontSize: 11.f)),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: settings.showPvArrows,
                  thumbColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? kPrimaryColor : kWhiteColor.withValues(alpha: 0.6)),
                  trackColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? kPrimaryColor.withValues(alpha: 0.35) : kDividerColor.withValues(alpha: 0.5)),
                  onChanged: (value) => notifier.update(settings.copyWith(showPvArrows: value)),
                ),
              ],
            ),
          ),
          SizedBox(height: 18.h),
          _SettingCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Search Time', style: AppTypography.textMdMedium.copyWith(color: kWhiteColor, fontSize: 13.f)),
                SizedBox(height: 4.h),
                Text('Control how long Stockfish keeps thinking for each request.', style: AppTypography.textSmRegular.copyWith(color: kWhiteColor70, fontSize: 11.f)),
                SizedBox(height: 14.h),
                _DiscreteSlider(
                  value: settings.searchTimeIndex.toDouble(),
                  divisions: _searchTimeLabels.length - 1,
                  labels: _searchTimeLabels,
                  onChanged: (value) => notifier.update(settings.copyWith(searchTimeIndex: value.round())),
                ),
                SizedBox(height: 6.h),
                Text('Current: ${_searchTimeLabels[settings.searchTimeIndex.clamp(0, _searchTimeLabels.length - 1)]}',
                    style: AppTypography.textSmMedium.copyWith(color: kWhiteColor70, fontSize: 11.f)),
              ],
            ),
          ),
          SizedBox(height: 18.h),
          _SettingCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Principal Variations', style: AppTypography.textMdMedium.copyWith(color: kWhiteColor, fontSize: 13.f)),
                SizedBox(height: 4.h),
                Text('Choose how many engine lines to surface (1-5).', style: AppTypography.textSmRegular.copyWith(color: kWhiteColor70, fontSize: 11.f)),
                SizedBox(height: 14.h),
                Slider(
                  value: settings.principalVariationCount.toDouble(),
                  min: 1,
                  max: 5,
                  divisions: 4,
                  label: settings.principalVariationCount.toString(),
                  activeColor: kPrimaryColor,
                  onChanged: (value) => notifier.update(settings.copyWith(principalVariationCount: value.round())),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('${settings.principalVariationCount} line${settings.principalVariationCount == 1 ? '' : 's'}',
                      style: AppTypography.textSmMedium.copyWith(color: kWhiteColor70, fontSize: 11.f)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const List<String> _searchTimeLabels = <String>['5s', '10s', '20s', '30s', '60s', '∞'];

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) {
    return Text(title, style: AppTypography.textLgMedium.copyWith(color: kWhiteColor, fontSize: 14.f));
  }
}

class _SettingCard extends StatelessWidget {
  const _SettingCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16.sp),
      decoration: BoxDecoration(
        color: kPopUpColor,
        borderRadius: BorderRadius.circular(18.br),
        border: Border.all(color: kDividerColor.withValues(alpha: 0.4)),
      ),
      child: child,
    );
  }
}

class _DiscreteSlider extends StatelessWidget {
  const _DiscreteSlider({required this.value, required this.divisions, required this.labels, required this.onChanged});
  final double value;
  final int divisions;
  final List<String> labels;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: kPrimaryColor,
        inactiveTrackColor: kPrimaryColor.withValues(alpha: 0.2),
        thumbColor: kPrimaryColor,
        valueIndicatorTextStyle: AppTypography.textSmMedium.copyWith(color: kBlackColor, fontSize: 11.f),
      ),
      child: Slider(
        value: value.clamp(0, divisions.toDouble()),
        min: 0,
        max: divisions.toDouble(),
        divisions: divisions,
        label: labels[value.round()],
        onChanged: onChanged,
      ),
    );
  }
}

