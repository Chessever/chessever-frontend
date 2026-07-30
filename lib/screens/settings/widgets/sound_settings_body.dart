import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/screens/settings/widgets/board_settings_body.dart'
    show TrackPersist;
import 'package:chessever2/screens/settings/widgets/settings_primitives.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/sound_preferences.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Lichess-style sound preferences as a non-scaffolded body widget.
class SoundSettingsBody extends ConsumerWidget {
  const SoundSettingsBody({super.key, required this.trackPersist});

  final TrackPersist trackPersist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardSettingsAsync = ref.watch(boardSettingsProviderNew);

    return boardSettingsAsync.when(
      data: (settings) => _buildContent(context, ref, settings),
      loading:
          () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          ),
      error:
          (error, stack) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'Error loading sound settings',
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
    BoardSettingsNew settings,
  ) {
    final notifier = ref.read(boardSettingsProviderNew.notifier);

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
                      'Move Sounds',
                      style: AppTypography.textMdMedium.copyWith(
                        color: context.colors.textPrimary,
                        fontSize: 13.f,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'Play sounds for moves, captures, and game events.',
                      style: AppTypography.textSmRegular.copyWith(
                        color: context.colors.textSecondary,
                        fontSize: 11.f,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: settings.soundEnabled,
                thumbColor: WidgetStateProperty.resolveWith(
                  (states) =>
                      states.contains(WidgetState.selected)
                          ? kPrimaryColor
                          : context.colors.textSecondary.withValues(alpha: 0.6),
                ),
                trackColor: WidgetStateProperty.resolveWith(
                  (states) =>
                      states.contains(WidgetState.selected)
                          ? kPrimaryColor.withValues(alpha: 0.35)
                          : context.colors.divider.withValues(alpha: 0.5),
                ),
                onChanged: (value) {
                  trackPersist(notifier.toggleSound(value));
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
                'Volume',
                style: AppTypography.textMdMedium.copyWith(
                  color: context.colors.textPrimary,
                  fontSize: 13.f,
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                'Default is 70%, matching Lichess without making every move too loud.',
                style: AppTypography.textSmRegular.copyWith(
                  color: context.colors.textSecondary,
                  fontSize: 11.f,
                ),
              ),
              SizedBox(height: 12.h),
              Row(
                children: [
                  Icon(
                    Icons.volume_down_outlined,
                    size: 18.ic,
                    color: context.colors.textSecondary,
                  ),
                  Expanded(
                    child: Slider(
                      value: settings.soundVolume,
                      min: 0,
                      max: 1,
                      divisions: 10,
                      activeColor: kPrimaryColor,
                      inactiveColor: context.colors.divider,
                      label: _volumeLabel(settings.soundVolume),
                      onChanged:
                          !settings.soundEnabled
                              ? null
                              : (value) {
                                trackPersist(notifier.setSoundVolume(value));
                              },
                      onChangeEnd:
                          !settings.soundEnabled
                              ? null
                              : (value) {
                                trackPersist(
                                  notifier.setSoundVolume(value, preview: true),
                                );
                              },
                    ),
                  ),
                  Text(
                    _volumeLabel(settings.soundVolume),
                    style: AppTypography.textSmMedium.copyWith(
                      color: context.colors.textPrimary,
                      fontSize: 11.f,
                    ),
                  ),
                ],
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
                'Sound Set',
                style: AppTypography.textMdMedium.copyWith(
                  color: context.colors.textPrimary,
                  fontSize: 13.f,
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                'Standard keeps ChessEver’s current sound. Lichess and the other sets are imported from Lichess Mobile.',
                style: AppTypography.textSmRegular.copyWith(
                  color: context.colors.textSecondary,
                  fontSize: 11.f,
                ),
              ),
              SizedBox(height: 14.h),
              _SoundThemeSelector(
                selected: settings.soundTheme,
                enabled: settings.soundEnabled,
                onSelected: (theme) {
                  trackPersist(notifier.setSoundThemeIndex(theme.index));
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _volumeLabel(double value) => '${(value * 100).round()}%';
}

class _SoundThemeSelector extends StatelessWidget {
  const _SoundThemeSelector({
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final SoundTheme selected;
  final bool enabled;
  final ValueChanged<SoundTheme> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8.w,
      runSpacing: 8.h,
      children:
          SoundTheme.values.map((theme) {
            final isSelected = selected == theme;
            return ChoiceChip(
              label: Text(theme.label),
              selected: isSelected,
              onSelected: !enabled ? null : (_) => onSelected(theme),
              selectedColor: kPrimaryColor.withValues(alpha: 0.22),
              backgroundColor: context.colors.surfaceElevated,
              disabledColor: context.colors.surfaceElevated.withValues(
                alpha: 0.45,
              ),
              side: BorderSide(
                color:
                    isSelected
                        ? kPrimaryColor.withValues(alpha: 0.7)
                        : context.colors.divider.withValues(alpha: 0.5),
              ),
              labelStyle: AppTypography.textSmMedium.copyWith(
                color:
                    !enabled
                        ? context.colors.textSecondary.withValues(alpha: 0.55)
                        : isSelected
                        ? kPrimaryColor
                        : context.colors.textPrimary,
                fontSize: 11.f,
              ),
            );
          }).toList(),
    );
  }
}
