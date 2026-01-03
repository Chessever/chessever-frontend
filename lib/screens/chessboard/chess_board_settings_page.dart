import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/board_customization_utils.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
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
    final boardSettingsAsync = ref.watch(boardSettingsProviderNew);

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
          data: (engineSettings) => boardSettingsAsync.when(
            data: (boardSettings) => _buildSettings(context, engineSettings, boardSettings),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Center(
              child: Text(
                'Error loading board settings',
                style: AppTypography.textMdRegular.copyWith(color: kWhiteColor),
              ),
            ),
          ),
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

  Widget _buildSettings(BuildContext context, EngineSettings settings, BoardSettingsNew boardSettings) {
    final notifier = ref.read(engineSettingsProviderNew.notifier);
    final boardNotifier = ref.read(boardSettingsProviderNew.notifier);

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
                      'Evaluation Bar',
                      style: AppTypography.textMdMedium.copyWith(
                        color: kWhiteColor,
                        fontSize: 13.f,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'Display a bar showing which side is winning.',
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
                      'Computer Analysis',
                      style: AppTypography.textMdMedium.copyWith(
                        color: kWhiteColor,
                        fontSize: 13.f,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'Enable Stockfish to analyze positions and suggest best moves.',
                      style: AppTypography.textSmRegular.copyWith(
                        color: kWhiteColor70,
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
                      : kWhiteColor.withValues(alpha: 0.6),
                ),
                trackColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? kPrimaryColor.withValues(alpha: 0.35)
                      : kDividerColor.withValues(alpha: 0.5),
                ),
                onChanged: (value) {
                  _trackPersist(notifier.toggleEngineAnalysis(value));
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
                      'Analysis Depth Indicator',
                      style: AppTypography.textMdMedium.copyWith(
                        color: kWhiteColor,
                        fontSize: 13.f,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'Show how deep the engine is calculating (higher = more accurate).',
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
                      'Show Arrows',
                      style: AppTypography.textMdMedium.copyWith(
                        color: kWhiteColor,
                        fontSize: 13.f,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'Draw arrows on the board showing recommended moves.',
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
                'Thinking Time',
                style: AppTypography.textMdMedium.copyWith(
                  color: kWhiteColor,
                  fontSize: 13.f,
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                'How long the engine thinks per move. Longer = stronger analysis.',
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
                'Number of Lines',
                style: AppTypography.textMdMedium.copyWith(
                  color: kWhiteColor,
                  fontSize: 13.f,
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                'How many alternative move sequences to show.',
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
        SizedBox(height: 18.h),
        _SettingCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Arrow Count',
                style: AppTypography.textMdMedium.copyWith(
                  color: kWhiteColor,
                  fontSize: 13.f,
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                'Maximum arrows to display for suggested moves.',
                style: AppTypography.textSmRegular.copyWith(
                  color: kWhiteColor70,
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
                  final label = EngineSettings.maxArrowsLabels[index];
                  debugPrint('🎛️  Settings UI: Max arrows changed to index=$index ($label)');
                  _trackPersist(notifier.setMaxArrowsOnBoard(index));
                },
              ),
              SizedBox(height: 6.h),
              Text(
                'Current: ${settings.maxArrowsLabel()}',
                style: AppTypography.textSmMedium.copyWith(
                  color: kWhiteColor70,
                  fontSize: 11.f,
                ),
              ),
            ],
          ),
        ),

        // Board Settings Section
        SizedBox(height: 24.h),
        _SectionLabel(title: 'Board Settings'),
        SizedBox(height: 12.h),

        // Board Theme Selector
        _SettingCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Board Theme',
                style: AppTypography.textMdMedium.copyWith(
                  color: kWhiteColor,
                  fontSize: 13.f,
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                'Choose your preferred board style.',
                style: AppTypography.textSmRegular.copyWith(
                  color: kWhiteColor70,
                  fontSize: 11.f,
                ),
              ),
              SizedBox(height: 16.h),
              // Horizontal scrolling board theme options
              SizedBox(
                height: 90.h,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: kBoardThemes.length,
                  separatorBuilder: (_, __) => SizedBox(width: 12.w),
                  itemBuilder: (context, index) {
                    final theme = kBoardThemes[index];
                    final isSelected = boardSettings.boardThemeIndex == index;
                    return _BoardThemeOption(
                      theme: theme,
                      isSelected: isSelected,
                      onTap: () {
                        _trackPersist(boardNotifier.setBoardThemeIndex(index));
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 18.h),

        // Piece Set Selector
        _SettingCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Piece Set',
                style: AppTypography.textMdMedium.copyWith(
                  color: kWhiteColor,
                  fontSize: 13.f,
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                'Choose your preferred piece style.',
                style: AppTypography.textSmRegular.copyWith(
                  color: kWhiteColor70,
                  fontSize: 11.f,
                ),
              ),
              SizedBox(height: 16.h),
              // Horizontal scrolling piece set options
              SizedBox(
                height: 90.h,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: kPieceSets.length,
                  separatorBuilder: (_, __) => SizedBox(width: 12.w),
                  itemBuilder: (context, index) {
                    final pieceSet = kPieceSets[index];
                    final isSelected = boardSettings.pieceStyleIndex == index;
                    return _PieceSetOption(
                      pieceSet: pieceSet,
                      isSelected: isSelected,
                      onTap: () {
                        _trackPersist(boardNotifier.setPieceSetIndex(index));
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),

      ],
    );
  }
}

/// Board theme option widget showing a preview of the theme colors
class _BoardThemeOption extends StatelessWidget {
  const _BoardThemeOption({
    required this.theme,
    required this.isSelected,
    required this.onTap,
  });

  final BoardThemeOption theme;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          // Mini board preview showing light/dark squares
          Container(
            width: 48.w,
            height: 48.h,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6.br),
              border: Border.all(
                color: isSelected ? kPrimaryColor : Colors.transparent,
                width: 2,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4.br),
              child: CustomPaint(
                painter: _BoardThemePreviewPainter(
                  lightColor: theme.colorScheme.lightSquare,
                  darkColor: theme.colorScheme.darkSquare,
                ),
              ),
            ),
          ),
          SizedBox(height: 6.h),
          SizedBox(
            width: 56.w,
            child: Text(
              theme.name,
              style: AppTypography.textXsRegular.copyWith(
                color: isSelected ? kPrimaryColor : kWhiteColor,
                fontSize: 10.f,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(height: 4.h),
          // Selection indicator
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? kPrimaryColor : kSecondaryTextColor,
                width: 2,
              ),
              color: isSelected ? kPrimaryColor : Colors.transparent,
            ),
            child: isSelected
                ? const Icon(Icons.check, color: Colors.white, size: 10)
                : null,
          ),
        ],
      ),
    );
  }
}

/// Custom painter for board theme preview (2x2 checkerboard)
class _BoardThemePreviewPainter extends CustomPainter {
  const _BoardThemePreviewPainter({
    required this.lightColor,
    required this.darkColor,
  });

  final Color lightColor;
  final Color darkColor;

  @override
  void paint(Canvas canvas, Size size) {
    final halfWidth = size.width / 2;
    final halfHeight = size.height / 2;

    final lightPaint = Paint()..color = lightColor;
    final darkPaint = Paint()..color = darkColor;

    // Draw 2x2 checkerboard pattern
    canvas.drawRect(Rect.fromLTWH(0, 0, halfWidth, halfHeight), lightPaint);
    canvas.drawRect(Rect.fromLTWH(halfWidth, 0, halfWidth, halfHeight), darkPaint);
    canvas.drawRect(Rect.fromLTWH(0, halfHeight, halfWidth, halfHeight), darkPaint);
    canvas.drawRect(Rect.fromLTWH(halfWidth, halfHeight, halfWidth, halfHeight), lightPaint);
  }

  @override
  bool shouldRepaint(covariant _BoardThemePreviewPainter oldDelegate) {
    return oldDelegate.lightColor != lightColor || oldDelegate.darkColor != darkColor;
  }
}

/// Piece set option widget showing a preview of the king piece
class _PieceSetOption extends StatelessWidget {
  const _PieceSetOption({
    required this.pieceSet,
    required this.isSelected,
    required this.onTap,
  });

  final PieceSet pieceSet;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          // Piece preview showing white king
          Container(
            width: 48.w,
            height: 48.h,
            decoration: BoxDecoration(
              color: kBlack3Color,
              borderRadius: BorderRadius.circular(6.br),
              border: Border.all(
                color: isSelected ? kPrimaryColor : Colors.transparent,
                width: 2,
              ),
            ),
            child: Padding(
              padding: EdgeInsets.all(4.sp),
              child: Image(
                image: pieceSet.assets[PieceKind.whiteKing]!,
                fit: BoxFit.contain,
              ),
            ),
          ),
          SizedBox(height: 6.h),
          SizedBox(
            width: 56.w,
            child: Text(
              pieceSet.label,
              style: AppTypography.textXsRegular.copyWith(
                color: isSelected ? kPrimaryColor : kWhiteColor,
                fontSize: 10.f,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(height: 4.h),
          // Selection indicator
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? kPrimaryColor : kSecondaryTextColor,
                width: 2,
              ),
              color: isSelected ? kPrimaryColor : Colors.transparent,
            ),
            child: isSelected
                ? const Icon(Icons.check, color: Colors.white, size: 10)
                : null,
          ),
        ],
      ),
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
