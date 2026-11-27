import 'package:chessever2/providers/board_engine_lines_visibility_provider.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/settings/widgets/settings_primitives.dart';
import 'package:chessever2/services/toby/toby_prediction.dart'
    show tobyReaderHasPremiumProvider;
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

typedef TrackPersist = void Function(Future<void> future);

/// Engine Experience settings as a non-scaffolded body widget.
/// Persist futures are reported via [trackPersist] so the host can await them
/// in a PopScope before navigation.
class EngineSettingsBody extends ConsumerWidget {
  const EngineSettingsBody({
    super.key,
    required this.trackPersist,
    this.boardOnly = false,
    this.bothAvailable = true,
  });

  final bool boardOnly;
  final bool bothAvailable;

  final TrackPersist trackPersist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(engineSettingsProviderNew);

    return settingsAsync.when(
      data: (settings) => _buildContent(context, ref, settings),
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'Error loading engine settings',
            style: AppTypography.textMdRegular.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    EngineSettings settings,
  ) {
    final notifier = ref.read(engineSettingsProviderNew.notifier);
    final entitled = ref.watch(tobyReaderHasPremiumProvider);
    final both = settings.wantsBothEngines && entitled && bothAvailable;
    final effectiveSource = settings.usesToby && entitled
        ? EngineSource.toby
        : EngineSource.stockfish;
    final linesVisible = ref.watch(boardEngineLinesVisibleProvider);
    final linesVisibility = ref.read(boardEngineLinesVisibleProvider.notifier);

    Future<void> selectToby({required bool both}) async {
      void select() {
        if (!context.mounted || !ref.read(tobyReaderHasPremiumProvider)) return;
        trackPersist(
          both
              ? notifier.selectBothEngines()
              : notifier.setEngineSource(EngineSource.toby),
        );
      }

      if (ref.read(tobyReaderHasPremiumProvider)) {
        select();
      } else {
        await showPremiumPaywallSheet(
          context: context,
          featureId: 'toby_engine',
          returnTo: boardOnly ? 'broadcast/board' : 'settings/engine',
          onEntitled: select,
        );
      }
    }

    final usesStockfish = both || effectiveSource == EngineSource.stockfish;
    final showLines = linesVisible.valueOrNull ?? true;
    final options = <Widget>[
      _EvaluationSurfaceSwitch(
        switchKey: const ValueKey('evaluation-bar-board-switch'),
        label: 'Evaluation Bar',
        subtitle: boardOnly ? null : 'Board View',
        value: settings.shouldShowEngineGaugeOnBoard,
        onChanged: (value) =>
            trackPersist(notifier.toggleEngineGaugeOnBoard(value)),
      ),
      if (both && settings.shouldShowEngineGaugeOnBoard)
        _EvaluationSurfaceSwitch(
          switchKey: const ValueKey('evaluation-bar-toby-both-switch'),
          label: 'Toby Evaluation Bar',
          value: settings.showTobyGaugeInBoth,
          onChanged: (value) =>
              trackPersist(notifier.toggleTobyGaugeInBoth(value)),
        ),
      if (!boardOnly)
        _EvaluationSurfaceSwitch(
          switchKey: const ValueKey('evaluation-bar-grid-switch'),
          label: 'Grid View',
          value: settings.shouldShowEngineGaugeInGrid,
          onChanged: (value) =>
              trackPersist(notifier.toggleEngineGaugeInGrid(value)),
        ),
      _SettingsControl(
        label: 'Engine',
        child: _SegmentTrack(
          children: [
            _ToggleSegment(
              key: const ValueKey('engine-source-stockfish'),
              label: 'Stockfish',
              selected: !both && effectiveSource == EngineSource.stockfish,
              onTap: () => trackPersist(
                notifier.setEngineSource(EngineSource.stockfish),
              ),
            ),
            _ToggleSegment(
              key: const ValueKey('engine-source-toby'),
              label: 'Toby',
              selected: !both && effectiveSource == EngineSource.toby,
              onTap: () => selectToby(both: false),
            ),
            if (bothAvailable)
              _ToggleSegment(
                key: const ValueKey('engine-source-both'),
                label: 'Both',
                selected: both,
                onTap: () => selectToby(both: true),
              ),
          ],
        ),
      ),
      if (usesStockfish)
        _SettingsControl(
          label: 'Engine Lines',
          child: _EngineLinesToggle(
            value: settings.engineLinesView,
            visible: showLines,
            onOff: () => trackPersist(linesVisibility.setVisible(false)),
            onChanged: (view) {
              trackPersist(notifier.setEngineLinesView(view));
              trackPersist(linesVisibility.setVisible(true));
            },
          ),
        )
      else
        _EvaluationSurfaceSwitch(
          switchKey: const ValueKey('toby-lines-visible-switch'),
          label: 'Show Engine Lines',
          value: showLines,
          onChanged: (value) => trackPersist(linesVisibility.setVisible(value)),
        ),
      _EvaluationSurfaceSwitch(
        switchKey: const ValueKey('engine-arrows-switch'),
        label: 'Show Arrows',
        value: settings.showPvArrows,
        onChanged: (value) => trackPersist(notifier.togglePvArrows(value)),
      ),
      if (settings.showPvArrows)
        _SettingsControl(
          label: 'Arrow Count',
          value: settings.maxArrowsLabel(),
          child: _DiscreteSlider(
            value: settings.maxArrowsOnBoard.toDouble(),
            divisions: EngineSettings.maxArrowsLabels.length - 1,
            labels: EngineSettings.maxArrowsLabels,
            onChanged: (value) =>
                trackPersist(notifier.setMaxArrowsOnBoard(value.toInt())),
          ),
        ),
      _SettingsControl(
        label: 'Number of Lines',
        value: settings.principalVariationLabel(),
        child: _DiscreteSlider(
          value: settings.principalVariationIndex.toDouble(),
          divisions: EngineSettings.principalVariationLabels.length - 1,
          labels: EngineSettings.principalVariationLabels,
          onChanged: (value) =>
              trackPersist(notifier.setPrincipalVariationIndex(value.toInt())),
        ),
      ),
      if (usesStockfish) ...[
        _SettingsControl(
          label: 'Thinking Time',
          value: settings.searchTimeLabel(),
          child: _DiscreteSlider(
            key: const ValueKey('thinking-time-slider'),
            value: settings.searchTimeIndex.toDouble(),
            divisions: EngineSettings.searchTimeLabels.length - 1,
            labels: EngineSettings.searchTimeLabels,
            onChanged: (value) =>
                trackPersist(notifier.setSearchTimeIndex(value.toInt())),
          ),
        ),
        _EvaluationSurfaceSwitch(
          switchKey: const ValueKey('depth-indicator-switch'),
          label: 'Analysis Depth Indicator',
          value: settings.showDepthOverlay,
          onChanged: (value) =>
              trackPersist(notifier.toggleDepthOverlay(value)),
        ),
      ],
    ];
    return SettingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, option) in options.indexed) ...[
            if (index > 0)
              Divider(
                height: 9.h,
                color: context.colors.divider.withValues(alpha: .45),
              ),
            option,
          ],
        ],
      ),
    );
  }
}

class _SettingsControl extends StatelessWidget {
  const _SettingsControl({
    required this.label,
    this.value,
    required this.child,
  });

  final String label;
  final String? value;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.textMdMedium.copyWith(
      color: context.colors.textPrimary,
      fontSize: 13.f,
    );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: style)),
              if (value != null)
                Text(
                  value!,
                  style: style.copyWith(color: context.colors.textSecondary),
                ),
            ],
          ),
          if (value == null) SizedBox(height: 5.h),
          child,
        ],
      ),
    );
  }
}

/// Off affects only in-game visibility; Cards/List retains the shared layout.
class _EngineLinesToggle extends StatelessWidget {
  const _EngineLinesToggle({
    required this.value,
    required this.visible,
    required this.onOff,
    required this.onChanged,
  });

  final EngineLinesView value;
  final bool visible;
  final VoidCallback onOff;
  final ValueChanged<EngineLinesView> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SegmentTrack(
      children: [
        _ToggleSegment(
          label: 'Off',
          icon: Icons.visibility_off_outlined,
          selected: !visible,
          onTap: onOff,
        ),
        _ToggleSegment(
          label: 'Cards',
          icon: Icons.view_carousel_outlined,
          selected: visible && value == EngineLinesView.cards,
          onTap: () => onChanged(EngineLinesView.cards),
        ),
        _ToggleSegment(
          label: 'List',
          icon: Icons.view_agenda_outlined,
          selected: visible && value == EngineLinesView.list,
          onTap: () => onChanged(EngineLinesView.list),
        ),
      ],
    );
  }
}

/// The recessed track the settings segmented controls sit in.
class _SegmentTrack extends StatelessWidget {
  const _SegmentTrack({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(3.w),
      decoration: BoxDecoration(
        color: context.colors.divider.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10.br),
      ),
      child: Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(width: 4.w),
            Expanded(child: children[i]),
          ],
        ],
      ),
    );
  }
}

/// One segment of a [_SegmentTrack]: accent fill when selected.
class _ToggleSegment extends StatelessWidget {
  const _ToggleSegment({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? (context.isLightTheme
              ? context.colors.inkOnAccent
              : context.colors.textInverse)
        : context.colors.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: EdgeInsets.symmetric(vertical: 7.h),
          decoration: BoxDecoration(
            color: selected ? kPrimaryColor : Colors.transparent,
            borderRadius: BorderRadius.circular(8.br),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16.f, color: color),
                  SizedBox(width: 6.w),
                ],
                Text(
                  label,
                  style: AppTypography.textSmMedium.copyWith(
                    color: color,
                    fontSize: 12.f,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EvaluationSurfaceSwitch extends StatelessWidget {
  const _EvaluationSurfaceSwitch({
    required this.switchKey,
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final Key switchKey;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTypography.textMdMedium.copyWith(
                  color: context.colors.textPrimary,
                  fontSize: 13.f,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: AppTypography.textSmRegular.copyWith(
                    color: context.colors.textSecondary,
                    fontSize: 11.f,
                  ),
                ),
            ],
          ),
        ),
        Switch.adaptive(
          key: switchKey,
          value: value,
          thumbColor: settingsSwitchThumb(context),
          trackColor: settingsSwitchTrack(context),
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

class _DiscreteSlider extends StatelessWidget {
  const _DiscreteSlider({
    super.key,
    required this.value,
    required this.divisions,
    required this.labels,
    required this.onChanged,
  });

  final double value;
  final int divisions;
  final List<String> labels;

  /// Null disables (and dims) the slider.
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final clampedValue = value.clamp(0.0, divisions.toDouble()).toDouble();
    final labelIndex = clampedValue.round().clamp(0, labels.length - 1);

    return SliderTheme(
      // Paper: the cyan track and thumb sit near 2:1, so light draws them in
      // the accent-text teal. Dark is unchanged.
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: context.isLightTheme
            ? context.colors.accentText
            : kPrimaryColor,
        inactiveTrackColor: context.isLightTheme
            ? context.colors.accentText.withValues(alpha: 0.25)
            : kPrimaryColor.withValues(alpha: 0.2),
        thumbColor: context.isLightTheme
            ? context.colors.accentText
            : kPrimaryColor,
        valueIndicatorColor: context.isLightTheme
            ? context.colors.accentText
            : null,
        valueIndicatorTextStyle: AppTypography.textSmMedium.copyWith(
          color: context.colors.textInverse,
          fontSize: 11.f,
        ),
      ),
      child: Slider(
        value: clampedValue,
        min: 0,
        max: divisions.toDouble(),
        divisions: divisions,
        label: labels[labelIndex],
        onChanged: onChanged,
      ),
    );
  }
}
