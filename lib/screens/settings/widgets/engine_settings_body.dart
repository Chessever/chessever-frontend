import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/settings/widgets/settings_primitives.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

typedef TrackPersist = void Function(Future<void> future);

/// Engine Experience settings as a non-scaffolded body widget.
/// Persist futures are reported via [trackPersist] so the host can await them
/// in a PopScope before navigation.
class EngineSettingsBody extends ConsumerWidget {
  const EngineSettingsBody({super.key, required this.trackPersist});

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Evaluation Bar',
                      style: AppTypography.textMdMedium.copyWith(
                        color: context.colors.textPrimary,
                        fontSize: 13.f,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'Display a bar showing which side is winning.',
                      style: AppTypography.textSmRegular.copyWith(
                        color: context.colors.textSecondary,
                        fontSize: 11.f,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: settings.showEngineGauge,
                thumbColor: WidgetStatePropertyAll(kPrimaryColor),
                trackColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? kPrimaryColor.withValues(alpha: 0.35)
                      : context.colors.divider.withValues(alpha: 0.5),
                ),
                onChanged: (value) {
                  trackPersist(notifier.toggleEngineGauge(value));
                },
              ),
            ],
          ),
        ),
        SizedBox(height: 18.h),
        SettingCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Computer Analysis',
                      style: AppTypography.textMdMedium.copyWith(
                        color: context.colors.textPrimary,
                        fontSize: 13.f,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'Enable Stockfish to analyze positions and suggest best moves.',
                      style: AppTypography.textSmRegular.copyWith(
                        color: context.colors.textSecondary,
                        fontSize: 11.f,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: settings.showEngineAnalysis,
                thumbColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? kPrimaryColor
                      : context.colors.textSecondary.withValues(alpha: 0.6),
                ),
                trackColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? kPrimaryColor.withValues(alpha: 0.35)
                      : context.colors.divider.withValues(alpha: 0.5),
                ),
                onChanged: (value) {
                  trackPersist(notifier.toggleEngineAnalysis(value));
                },
              ),
            ],
          ),
        ),
        SizedBox(height: 18.h),
        SettingCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Analysis Depth Indicator',
                      style: AppTypography.textMdMedium.copyWith(
                        color: context.colors.textPrimary,
                        fontSize: 13.f,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'Show how deep the engine is calculating (higher = more accurate).',
                      style: AppTypography.textSmRegular.copyWith(
                        color: context.colors.textSecondary,
                        fontSize: 11.f,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: settings.showDepthOverlay,
                thumbColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? kPrimaryColor
                      : context.colors.textSecondary.withValues(alpha: 0.6),
                ),
                trackColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? kPrimaryColor.withValues(alpha: 0.35)
                      : context.colors.divider.withValues(alpha: 0.5),
                ),
                onChanged: (value) {
                  trackPersist(notifier.toggleDepthOverlay(value));
                },
              ),
            ],
          ),
        ),
        SizedBox(height: 18.h),
        SettingCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Show Arrows',
                      style: AppTypography.textMdMedium.copyWith(
                        color: context.colors.textPrimary,
                        fontSize: 13.f,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'Draw arrows on the board showing recommended moves.',
                      style: AppTypography.textSmRegular.copyWith(
                        color: context.colors.textSecondary,
                        fontSize: 11.f,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: settings.showPvArrows,
                thumbColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? kPrimaryColor
                      : context.colors.textSecondary.withValues(alpha: 0.6),
                ),
                trackColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? kPrimaryColor.withValues(alpha: 0.35)
                      : context.colors.divider.withValues(alpha: 0.5),
                ),
                onChanged: (value) {
                  trackPersist(notifier.togglePvArrows(value));
                },
              ),
            ],
          ),
        ),
        SizedBox(height: 18.h),
        SettingCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Thinking Time',
                style: AppTypography.textMdMedium.copyWith(
                  color: context.colors.textPrimary,
                  fontSize: 13.f,
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                'How long the engine thinks per move. Longer = stronger analysis.',
                style: AppTypography.textSmRegular.copyWith(
                  color: context.colors.textSecondary,
                  fontSize: 11.f,
                ),
              ),
              SizedBox(height: 14.h),
              _DiscreteSlider(
                value: settings.searchTimeIndex.toDouble(),
                divisions: EngineSettings.searchTimeLabels.length - 1,
                labels: EngineSettings.searchTimeLabels,
                onChanged: (value) {
                  final index = value.toInt();
                  trackPersist(notifier.setSearchTimeIndex(index));
                },
              ),
              SizedBox(height: 6.h),
              Text(
                'Current: ${settings.searchTimeLabel()}',
                style: AppTypography.textSmMedium.copyWith(
                  color: context.colors.textSecondary,
                  fontSize: 11.f,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 18.h),
        SettingCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Number of Lines',
                style: AppTypography.textMdMedium.copyWith(
                  color: context.colors.textPrimary,
                  fontSize: 13.f,
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                'How many alternative move sequences to show.',
                style: AppTypography.textSmRegular.copyWith(
                  color: context.colors.textSecondary,
                  fontSize: 11.f,
                ),
              ),
              SizedBox(height: 14.h),
              _DiscreteSlider(
                value: settings.principalVariationIndex.toDouble(),
                divisions: EngineSettings.principalVariationLabels.length - 1,
                labels: EngineSettings.principalVariationLabels,
                onChanged: (value) {
                  final index = value.toInt();
                  trackPersist(notifier.setPrincipalVariationIndex(index));
                },
              ),
              SizedBox(height: 6.h),
              Text(
                'Current: ${settings.principalVariationLabel()}',
                style: AppTypography.textSmMedium.copyWith(
                  color: context.colors.textSecondary,
                  fontSize: 11.f,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 18.h),
        SettingCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Arrow Count',
                style: AppTypography.textMdMedium.copyWith(
                  color: context.colors.textPrimary,
                  fontSize: 13.f,
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                'Maximum arrows to display for suggested moves.',
                style: AppTypography.textSmRegular.copyWith(
                  color: context.colors.textSecondary,
                  fontSize: 11.f,
                ),
              ),
              SizedBox(height: 14.h),
              _DiscreteSlider(
                value: settings.maxArrowsOnBoard.toDouble(),
                divisions: EngineSettings.maxArrowsLabels.length - 1,
                labels: EngineSettings.maxArrowsLabels,
                onChanged: (value) {
                  final index = value.toInt();
                  trackPersist(notifier.setMaxArrowsOnBoard(index));
                },
              ),
              SizedBox(height: 6.h),
              Text(
                'Current: ${settings.maxArrowsLabel()}',
                style: AppTypography.textSmMedium.copyWith(
                  color: context.colors.textSecondary,
                  fontSize: 11.f,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DiscreteSlider extends StatelessWidget {
  const _DiscreteSlider({
    required this.value,
    required this.divisions,
    required this.labels,
    required this.onChanged,
  });

  final double value;
  final int divisions;
  final List<String> labels;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final clampedValue = value.clamp(0.0, divisions.toDouble()).toDouble();
    final labelIndex = clampedValue.round().clamp(0, labels.length - 1);

    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: kPrimaryColor,
        inactiveTrackColor: kPrimaryColor.withValues(alpha: 0.2),
        thumbColor: kPrimaryColor,
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
