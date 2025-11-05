import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ChessBoardSettingsPage extends ConsumerStatefulWidget {
  const ChessBoardSettingsPage({super.key});

  static Route<void> route() {
    return MaterialPageRoute<void>(
      builder: (_) => const ChessBoardSettingsPage(),
    );
  }

  @override
  ConsumerState<ChessBoardSettingsPage> createState() => _ChessBoardSettingsPageState();
}

class _ChessBoardSettingsPageState extends ConsumerState<ChessBoardSettingsPage> {
  final Set<Future<void>> _pendingPersists = {};

  void _trackPersist(Future<void> future) {
    _pendingPersists.add(future);
    future.whenComplete(() => _pendingPersists.remove(future));
  }

  Future<bool> _onWillPop() async {
    // Wait for all pending persistence operations to complete before allowing navigation
    if (_pendingPersists.isNotEmpty) {
      debugPrint('⏳ Waiting for ${_pendingPersists.length} pending settings to persist...');
      await Future.wait(_pendingPersists);
      debugPrint('✅ All settings persisted, allowing navigation');
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(engineSettingsProviderNew);

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
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Board Settings',
          style: AppTypography.textLgMedium.copyWith(
            color: kWhiteColor,
            fontSize: 16.f,
          ),
        ),
        backgroundColor: kBackgroundColor,
        centerTitle: false,
      ),
        body: settingsAsync.when(
          data: (settings) => _buildSettings(context, settings),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(
            child: Text(
              'Error loading settings',
              style: AppTypography.textMdRegular.copyWith(color: kWhiteColor),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettings(BuildContext context, EngineSettings settings) {
    final notifier = ref.read(engineSettingsProviderNew.notifier);

    return ListView(
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
                    Text(
                      'Engine Gauge',
                      style: AppTypography.textMdMedium.copyWith(
                        color: kWhiteColor,
                        fontSize: 13.f,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'Show the evaluation gauge beside the board.',
                      style: AppTypography.textSmRegular.copyWith(
                        color: kWhiteColor70,
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
                      : kDividerColor.withValues(alpha: 0.5),
                ),
                onChanged: (value) {
                  _trackPersist(notifier.toggleEngineGauge(value));
                },
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
                    Text(
                      'Computer Depth Badge',
                      style: AppTypography.textMdMedium.copyWith(
                        color: kWhiteColor,
                        fontSize: 13.f,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'Display the live Stockfish depth badge beneath the computer icon toggle.',
                      style: AppTypography.textSmRegular.copyWith(
                        color: kWhiteColor70,
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
                      : kWhiteColor.withValues(alpha: 0.6),
                ),
                trackColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? kPrimaryColor.withValues(alpha: 0.35)
                      : kDividerColor.withValues(alpha: 0.5),
                ),
                onChanged: (value) {
                  _trackPersist(notifier.toggleDepthOverlay(value));
                },
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
                    Text(
                      'PV Arrows',
                      style: AppTypography.textMdMedium.copyWith(
                        color: kWhiteColor,
                        fontSize: 13.f,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'Show arrows for best move suggestions on the board.',
                      style: AppTypography.textSmRegular.copyWith(
                        color: kWhiteColor70,
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
                      : kWhiteColor.withValues(alpha: 0.6),
                ),
                trackColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? kPrimaryColor.withValues(alpha: 0.35)
                      : kDividerColor.withValues(alpha: 0.5),
                ),
                onChanged: (value) {
                  _trackPersist(notifier.togglePvArrows(value));
                },
              ),
            ],
          ),
        ),
        SizedBox(height: 18.h),
        _SettingCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Search Time',
                style: AppTypography.textMdMedium.copyWith(
                  color: kWhiteColor,
                  fontSize: 13.f,
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                'Control how long Stockfish keeps thinking for each request.',
                style: AppTypography.textSmRegular.copyWith(
                  color: kWhiteColor70,
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
                  final label = EngineSettings.searchTimeLabels[index];
                  debugPrint('🎛️  Settings UI: Search time changed to index=$index ($label)');
                  _trackPersist(notifier.setSearchTimeIndex(index));
                },
              ),
              SizedBox(height: 6.h),
              Text(
                'Current: ${settings.searchTimeLabel()}',
                style: AppTypography.textSmMedium.copyWith(
                  color: kWhiteColor70,
                  fontSize: 11.f,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 18.h),
        _SettingCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Principal Variations',
                style: AppTypography.textMdMedium.copyWith(
                  color: kWhiteColor,
                  fontSize: 13.f,
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                'Choose how many engine lines to display.',
                style: AppTypography.textSmRegular.copyWith(
                  color: kWhiteColor70,
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
                  final label = EngineSettings.principalVariationLabels[index];
                  debugPrint('🎛️  Settings UI: PV setting changed to index=$index ($label)');
                  _trackPersist(notifier.setPrincipalVariationIndex(index));
                },
              ),
              SizedBox(height: 6.h),
              Text(
                'Current: ${settings.principalVariationLabel()}',
                style: AppTypography.textSmMedium.copyWith(
                  color: kWhiteColor70,
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: AppTypography.textLgMedium.copyWith(
        color: kWhiteColor,
        fontSize: 14.f,
      ),
    );
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
          color: kBlackColor,
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
