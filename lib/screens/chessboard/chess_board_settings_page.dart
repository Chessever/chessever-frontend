import 'package:chessever2/providers/auto_pin_preferences_provider.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/repository/local_storage/auto_pin_preferences/auto_pin_preferences_repository.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/board_customization_utils.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
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
  ConsumerState<ChessBoardSettingsPage> createState() =>
      _ChessBoardSettingsPageState();
}

class _ChessBoardSettingsPageState
    extends ConsumerState<ChessBoardSettingsPage> {
  final Set<Future<void>> _pendingPersists = {};

  void _trackPersist(Future<void> future) {
    _pendingPersists.add(future);
    future.whenComplete(() => _pendingPersists.remove(future));
  }

  Future<bool> _onWillPop() async {
    // Wait for all pending persistence operations to complete before allowing navigation
    if (_pendingPersists.isNotEmpty) {
      debugPrint(
        '⏳ Waiting for ${_pendingPersists.length} pending settings to persist...',
      );
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
          data:
              (engineSettings) => boardSettingsAsync.when(
                data:
                    (boardSettings) =>
                        _buildSettings(context, engineSettings, boardSettings),
                loading: () => const Center(child: CircularProgressIndicator()),
                error:
                    (error, stack) => Center(
                      child: Text(
                        'Error loading board settings',
                        style: AppTypography.textMdRegular.copyWith(
                          color: kWhiteColor,
                        ),
                      ),
                    ),
              ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error:
              (error, stack) => Center(
                child: Text(
                  'Error loading settings',
                  style: AppTypography.textMdRegular.copyWith(
                    color: kWhiteColor,
                  ),
                ),
              ),
        ),
      ),
    );
  }

  Widget _buildSettings(
    BuildContext context,
    EngineSettings settings,
    BoardSettingsNew boardSettings,
  ) {
    final notifier = ref.read(engineSettingsProviderNew.notifier);
    final boardNotifier = ref.read(boardSettingsProviderNew.notifier);

    // Tablet-specific horizontal padding
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 20.sp,
      tablet: 32.sp,
    );

    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: ResponsiveHelper.contentMaxWidth),
        child: ListView(
          padding: EdgeInsets.only(
            left: horizontalPadding,
            right: horizontalPadding,
            top: 16.sp,
            bottom: 16.sp + bottomPadding,
          ),
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
                      (states) =>
                          states.contains(WidgetState.selected)
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
                      (states) =>
                          states.contains(WidgetState.selected)
                              ? kPrimaryColor
                              : kWhiteColor.withValues(alpha: 0.6),
                    ),
                    trackColor: WidgetStateProperty.resolveWith(
                      (states) =>
                          states.contains(WidgetState.selected)
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
                      (states) =>
                          states.contains(WidgetState.selected)
                              ? kPrimaryColor
                              : kWhiteColor.withValues(alpha: 0.6),
                    ),
                    trackColor: WidgetStateProperty.resolveWith(
                      (states) =>
                          states.contains(WidgetState.selected)
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
                      (states) =>
                          states.contains(WidgetState.selected)
                              ? kPrimaryColor
                              : kWhiteColor.withValues(alpha: 0.6),
                    ),
                    trackColor: WidgetStateProperty.resolveWith(
                      (states) =>
                          states.contains(WidgetState.selected)
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
                      debugPrint(
                        '🎛️  Settings UI: Search time changed to index=$index ($label)',
                      );
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
                    divisions:
                        EngineSettings.principalVariationLabels.length - 1,
                    labels: EngineSettings.principalVariationLabels,
                    onChanged: (value) {
                      final index = value.toInt();
                      final label =
                          EngineSettings.principalVariationLabels[index];
                      debugPrint(
                        '🎛️  Settings UI: PV setting changed to index=$index ($label)',
                      );
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
                      debugPrint(
                        '🎛️  Settings UI: Max arrows changed to index=$index ($label)',
                      );
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

            // Auto Pin Section
            SizedBox(height: 24.h),
            _SectionLabel(title: 'Auto Pin'),
            SizedBox(height: 12.h),
            _buildAutoPinSection(),

            // Board Settings Section
            SizedBox(height: 24.h),
            _SectionLabel(title: 'Board Settings'),
            SizedBox(height: 12.h),

            _SettingCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Games View Mode',
                    style: AppTypography.textMdMedium.copyWith(
                      color: kWhiteColor,
                      fontSize: 13.f,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    'Choose how games are displayed in tournament lists.',
                    style: AppTypography.textSmRegular.copyWith(
                      color: kWhiteColor70,
                      fontSize: 11.f,
                    ),
                  ),
                  SizedBox(height: 14.h),
                  _ViewModeSelector(
                    selectedIndex: boardSettings.gamesListViewModeIndex,
                    onModeSelected: (index) {
                      debugPrint(
                        '🎛️  Settings UI: Games view mode changed to index=$index',
                      );
                      _trackPersist(
                        boardNotifier.setGamesListViewModeIndex(index),
                      );
                    },
                  ),
                ],
              ),
            ),
            SizedBox(height: 18.h),

            // Board Theme Selector - Tap to open gallery
            _BoardThemePickerCard(
              currentIndex: boardSettings.boardThemeIndex,
              onThemeSelected: (index) {
                _trackPersist(boardNotifier.setBoardThemeIndex(index));
              },
            ),
            SizedBox(height: 18.h),

            // Piece Set Selector - Tap to open gallery
            _PieceSetPickerCard(
              currentIndex: boardSettings.pieceStyleIndex,
              onPieceSetSelected: (index) {
                _trackPersist(boardNotifier.setPieceSetIndex(index));
              },
            ),
            SizedBox(height: 18.h),

            // Sound Effects Toggle
            _SettingCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sound Effects',
                          style: AppTypography.textMdMedium.copyWith(
                            color: kWhiteColor,
                            fontSize: 13.f,
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          'Play sounds for moves, captures, and game events.',
                          style: AppTypography.textSmRegular.copyWith(
                            color: kWhiteColor70,
                            fontSize: 11.f,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: boardSettings.soundEnabled,
                    thumbColor: WidgetStateProperty.resolveWith(
                      (states) =>
                          states.contains(WidgetState.selected)
                              ? kPrimaryColor
                              : kWhiteColor.withValues(alpha: 0.6),
                    ),
                    trackColor: WidgetStateProperty.resolveWith(
                      (states) =>
                          states.contains(WidgetState.selected)
                              ? kPrimaryColor.withValues(alpha: 0.35)
                              : kDividerColor.withValues(alpha: 0.5),
                    ),
                    onChanged: (value) {
                      _trackPersist(boardNotifier.toggleSound(value));
                    },
                  ),
                ],
              ),
            ),
            SizedBox(height: 18.h),

            // Figurine Notation Toggle
            _SettingCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Figurine Notation',
                              style: AppTypography.textMdMedium.copyWith(
                                color: kWhiteColor,
                                fontSize: 13.f,
                              ),
                            ),
                            SizedBox(width: 8.w),
                            // Preview badge showing the difference
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 8.sp,
                                vertical: 2.sp,
                              ),
                              decoration: BoxDecoration(
                                color: kPrimaryColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6.br),
                                border: Border.all(
                                  color: kPrimaryColor.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Text(
                                boardSettings.useFigurine ? '♞f3' : 'Nf3',
                                style: AppTypography.textSmMedium.copyWith(
                                  color: kPrimaryColor,
                                  fontSize: 11.f,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          'Show chess piece symbols (♔♕♖♗♘) instead of letters (K, Q, R, B, N) in move notation.',
                          style: AppTypography.textSmRegular.copyWith(
                            color: kWhiteColor70,
                            fontSize: 11.f,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: boardSettings.useFigurine,
                    thumbColor: WidgetStateProperty.resolveWith(
                      (states) =>
                          states.contains(WidgetState.selected)
                              ? kPrimaryColor
                              : kWhiteColor.withValues(alpha: 0.6),
                    ),
                    trackColor: WidgetStateProperty.resolveWith(
                      (states) =>
                          states.contains(WidgetState.selected)
                              ? kPrimaryColor.withValues(alpha: 0.35)
                              : kDividerColor.withValues(alpha: 0.5),
                    ),
                    onChanged: (value) {
                      _trackPersist(boardNotifier.toggleFigurine(value));
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAutoPinSection() {
    final autoPinAsync = ref.watch(autoPinPreferencesProvider);
    final prefs = autoPinAsync.valueOrNull ?? AutoPinPreferences.defaults;
    final notifier = ref.read(autoPinPreferencesProvider.notifier);

    return Column(
      children: [
        _SettingCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Favorite Players',
                      style: AppTypography.textMdMedium.copyWith(
                        color: kWhiteColor,
                        fontSize: 13.f,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'Automatically pin games of your favorite players.',
                      style: AppTypography.textSmRegular.copyWith(
                        color: kWhiteColor70,
                        fontSize: 11.f,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: prefs.favoritePlayersAutoPinEnabled,
                thumbColor: WidgetStatePropertyAll(kPrimaryColor),
                trackColor: WidgetStateProperty.resolveWith(
                  (states) =>
                      states.contains(WidgetState.selected)
                          ? kPrimaryColor.withValues(alpha: 0.35)
                          : kDividerColor.withValues(alpha: 0.5),
                ),
                onChanged: (value) {
                  _trackPersist(notifier.setFavoritePlayersAutoPin(value));
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
                      'Countrymen',
                      style: AppTypography.textMdMedium.copyWith(
                        color: kWhiteColor,
                        fontSize: 13.f,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'Automatically pin games of players from your country.',
                      style: AppTypography.textSmRegular.copyWith(
                        color: kWhiteColor70,
                        fontSize: 11.f,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: prefs.countrymenAutoPinEnabled,
                thumbColor: WidgetStatePropertyAll(kPrimaryColor),
                trackColor: WidgetStateProperty.resolveWith(
                  (states) =>
                      states.contains(WidgetState.selected)
                          ? kPrimaryColor.withValues(alpha: 0.35)
                          : kDividerColor.withValues(alpha: 0.5),
                ),
                onChanged: (value) {
                  _trackPersist(notifier.setCountrymenAutoPin(value));
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Board Theme Picker Card - Shows current selection and opens gallery on tap
class _BoardThemePickerCard extends StatelessWidget {
  const _BoardThemePickerCard({
    required this.currentIndex,
    required this.onThemeSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onThemeSelected;

  @override
  Widget build(BuildContext context) {
    final currentTheme = getBoardThemeByIndex(currentIndex);

    return _SettingCard(
      child: InkWell(
        onTap: () => _showBoardThemeGallery(context),
        borderRadius: BorderRadius.circular(12.br),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
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
                        'Choose from ${kBoardThemes.length} beautiful board styles',
                        style: AppTypography.textSmRegular.copyWith(
                          color: kWhiteColor70,
                          fontSize: 11.f,
                        ),
                      ),
                    ],
                  ),
                ),
                // Count badge
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 10.sp,
                    vertical: 4.sp,
                  ),
                  decoration: BoxDecoration(
                    color: kPrimaryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12.br),
                    border: Border.all(
                      color: kPrimaryColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    '${kBoardThemes.length}',
                    style: AppTypography.textSmMedium.copyWith(
                      color: kPrimaryColor,
                      fontSize: 12.f,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16.h),
            // Current selection preview
            Container(
              padding: EdgeInsets.all(12.sp),
              decoration: BoxDecoration(
                color: kBlack2Color,
                borderRadius: BorderRadius.circular(12.br),
                border: Border.all(color: kPrimaryColor.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  // Board preview (4x4 checkerboard)
                  Container(
                    width: 56.w,
                    height: 56.h,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8.br),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8.br),
                      child: SizedBox.expand(
                        child: CustomPaint(
                          painter: _BoardThemePreviewPainter(
                            lightColor: currentTheme.colorScheme.lightSquare,
                            darkColor: currentTheme.colorScheme.darkSquare,
                            gridSize: 4,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 16.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentTheme.name,
                          style: AppTypography.textMdMedium.copyWith(
                            color: kWhiteColor,
                            fontSize: 14.f,
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          'Tap to browse all themes',
                          style: AppTypography.textSmRegular.copyWith(
                            color: kSecondaryTextColor,
                            fontSize: 11.f,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: kSecondaryTextColor,
                    size: 24.ic,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBoardThemeGallery(BuildContext context) async {
    // Check if user is authenticated (not anonymous), show auth sheet if not
    final isAuthenticated = await requireFullAuthGuard(context);
    if (!isAuthenticated || !context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: ResponsiveHelper.bottomSheetConstraints,
      builder:
          (context) => _BoardThemeGallerySheet(
            currentIndex: currentIndex,
            onThemeSelected: (index) {
              onThemeSelected(index);
              Navigator.pop(context);
            },
          ),
    );
  }
}

/// Board Theme Gallery Bottom Sheet
class _BoardThemeGallerySheet extends StatefulWidget {
  const _BoardThemeGallerySheet({
    required this.currentIndex,
    required this.onThemeSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onThemeSelected;

  @override
  State<_BoardThemeGallerySheet> createState() =>
      _BoardThemeGallerySheetState();
}

class _BoardThemeGallerySheetState extends State<_BoardThemeGallerySheet> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.currentIndex;
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: kBlack2Color,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.br)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: EdgeInsets.only(top: 12.sp),
            width: 40.w,
            height: 4.h,
            decoration: BoxDecoration(
              color: kDividerColor,
              borderRadius: BorderRadius.circular(2.br),
            ),
          ),
          // Header
          Padding(
            padding: EdgeInsets.all(20.sp),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Board Themes',
                        style: AppTypography.textLgMedium.copyWith(
                          color: kWhiteColor,
                          fontSize: 18.f,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        '${kBoardThemes.length} styles available',
                        style: AppTypography.textSmRegular.copyWith(
                          color: kSecondaryTextColor,
                          fontSize: 12.f,
                        ),
                      ),
                    ],
                  ),
                ),
                // Close button
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.close_rounded,
                    color: kSecondaryTextColor,
                    size: 24.ic,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: kBlack3Color,
                    padding: EdgeInsets.all(8.sp),
                  ),
                ),
              ],
            ),
          ),
          // Grid of themes with scroll indicator
          Expanded(
            child: Scrollbar(
              thumbVisibility: true,
              radius: Radius.circular(4.br),
              child: GridView.builder(
                padding: EdgeInsets.only(
                  left: 16.sp,
                  right: 16.sp,
                  bottom: bottomPadding + 24.sp,
                ),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 16.sp,
                  crossAxisSpacing: 12.sp,
                  childAspectRatio: 0.75,
                ),
                itemCount: kBoardThemes.length,
                itemBuilder: (context, index) {
                  final theme = kBoardThemes[index];
                  final isSelected = _selectedIndex == index;

                  return _BoardThemeGridItem(
                    theme: theme,
                    isSelected: isSelected,
                    onTap: () {
                      setState(() => _selectedIndex = index);
                      widget.onThemeSelected(index);
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Individual board theme grid item
class _BoardThemeGridItem extends StatelessWidget {
  const _BoardThemeGridItem({
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(
            color: isSelected ? kPrimaryColor : Colors.transparent,
            width: 2,
          ),
          boxShadow:
              isSelected
                  ? [
                    BoxShadow(
                      color: kPrimaryColor.withValues(alpha: 0.3),
                      blurRadius: 12,
                      spreadRadius: 0,
                    ),
                  ]
                  : null,
        ),
        child: Column(
          children: [
            // Board preview (4x4 checkerboard)
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(4.sp),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Container(
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8.br),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8.br),
                        child: CustomPaint(
                          size: Size(
                            constraints.maxWidth,
                            constraints.maxHeight,
                          ),
                          painter: _BoardThemePreviewPainter(
                            lightColor: theme.colorScheme.lightSquare,
                            darkColor: theme.colorScheme.darkSquare,
                            gridSize: 4,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            // Theme name
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 4.sp, vertical: 6.sp),
              child: Text(
                theme.name,
                style: AppTypography.textXsRegular.copyWith(
                  color: isSelected ? kPrimaryColor : kWhiteColor,
                  fontSize: 10.f,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom painter for board theme preview (configurable grid size)
class _BoardThemePreviewPainter extends CustomPainter {
  const _BoardThemePreviewPainter({
    required this.lightColor,
    required this.darkColor,
    this.gridSize = 2,
  });

  final Color lightColor;
  final Color darkColor;
  final int gridSize;

  @override
  void paint(Canvas canvas, Size size) {
    final cellWidth = size.width / gridSize;
    final cellHeight = size.height / gridSize;

    final lightPaint = Paint()..color = lightColor;
    final darkPaint = Paint()..color = darkColor;

    for (int row = 0; row < gridSize; row++) {
      for (int col = 0; col < gridSize; col++) {
        final isLight = (row + col) % 2 == 0;
        final paint = isLight ? lightPaint : darkPaint;
        canvas.drawRect(
          Rect.fromLTWH(
            col * cellWidth,
            row * cellHeight,
            cellWidth,
            cellHeight,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BoardThemePreviewPainter oldDelegate) {
    return oldDelegate.lightColor != lightColor ||
        oldDelegate.darkColor != darkColor ||
        oldDelegate.gridSize != gridSize;
  }
}

/// Piece Set Picker Card - Shows current selection and opens gallery on tap
class _PieceSetPickerCard extends StatelessWidget {
  const _PieceSetPickerCard({
    required this.currentIndex,
    required this.onPieceSetSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onPieceSetSelected;

  @override
  Widget build(BuildContext context) {
    final currentPieceSet = getPieceSetByIndex(currentIndex);

    return _SettingCard(
      child: InkWell(
        onTap: () => _showPieceSetGallery(context),
        borderRadius: BorderRadius.circular(12.br),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
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
                        'Choose from ${kPieceSets.length} unique piece styles',
                        style: AppTypography.textSmRegular.copyWith(
                          color: kWhiteColor70,
                          fontSize: 11.f,
                        ),
                      ),
                    ],
                  ),
                ),
                // Count badge
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 10.sp,
                    vertical: 4.sp,
                  ),
                  decoration: BoxDecoration(
                    color: kPrimaryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12.br),
                    border: Border.all(
                      color: kPrimaryColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    '${kPieceSets.length}',
                    style: AppTypography.textSmMedium.copyWith(
                      color: kPrimaryColor,
                      fontSize: 12.f,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16.h),
            // Current selection preview
            Container(
              padding: EdgeInsets.all(12.sp),
              decoration: BoxDecoration(
                color: kBlack2Color,
                borderRadius: BorderRadius.circular(12.br),
                border: Border.all(color: kPrimaryColor.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  // Piece preview (King and Queen)
                  Container(
                    width: 56.w,
                    height: 56.h,
                    decoration: BoxDecoration(
                      color: kBlack3Color,
                      borderRadius: BorderRadius.circular(8.br),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.all(4.sp),
                            child: Image(
                              image:
                                  currentPieceSet.assets[PieceKind.whiteKing]!,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.all(4.sp),
                            child: Image(
                              image:
                                  currentPieceSet.assets[PieceKind.blackQueen]!,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 16.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentPieceSet.label,
                          style: AppTypography.textMdMedium.copyWith(
                            color: kWhiteColor,
                            fontSize: 14.f,
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          'Tap to browse all pieces',
                          style: AppTypography.textSmRegular.copyWith(
                            color: kSecondaryTextColor,
                            fontSize: 11.f,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: kSecondaryTextColor,
                    size: 24.ic,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPieceSetGallery(BuildContext context) async {
    // Check if user is authenticated (not anonymous), show auth sheet if not
    final isAuthenticated = await requireFullAuthGuard(context);
    if (!isAuthenticated || !context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: ResponsiveHelper.bottomSheetConstraints,
      builder:
          (context) => _PieceSetGallerySheet(
            currentIndex: currentIndex,
            onPieceSetSelected: (index) {
              onPieceSetSelected(index);
              Navigator.pop(context);
            },
          ),
    );
  }
}

/// Piece Set Gallery Bottom Sheet
class _PieceSetGallerySheet extends StatefulWidget {
  const _PieceSetGallerySheet({
    required this.currentIndex,
    required this.onPieceSetSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onPieceSetSelected;

  @override
  State<_PieceSetGallerySheet> createState() => _PieceSetGallerySheetState();
}

class _PieceSetGallerySheetState extends State<_PieceSetGallerySheet> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.currentIndex;
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: BoxDecoration(
        color: kBlack2Color,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.br)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: EdgeInsets.only(top: 12.sp),
            width: 40.w,
            height: 4.h,
            decoration: BoxDecoration(
              color: kDividerColor,
              borderRadius: BorderRadius.circular(2.br),
            ),
          ),
          // Header
          Padding(
            padding: EdgeInsets.all(20.sp),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Piece Sets',
                        style: AppTypography.textLgMedium.copyWith(
                          color: kWhiteColor,
                          fontSize: 18.f,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        '${kPieceSets.length} styles available',
                        style: AppTypography.textSmRegular.copyWith(
                          color: kSecondaryTextColor,
                          fontSize: 12.f,
                        ),
                      ),
                    ],
                  ),
                ),
                // Close button
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.close_rounded,
                    color: kSecondaryTextColor,
                    size: 24.ic,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: kBlack3Color,
                    padding: EdgeInsets.all(8.sp),
                  ),
                ),
              ],
            ),
          ),
          // Grid of piece sets with scroll indicator
          Expanded(
            child: Scrollbar(
              thumbVisibility: true,
              radius: Radius.circular(4.br),
              child: GridView.builder(
                padding: EdgeInsets.only(
                  left: 16.sp,
                  right: 16.sp,
                  bottom: bottomPadding + 24.sp,
                ),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 16.sp,
                  crossAxisSpacing: 12.sp,
                  childAspectRatio: 0.72,
                ),
                itemCount: kPieceSets.length,
                itemBuilder: (context, index) {
                  final pieceSet = kPieceSets[index];
                  final isSelected = _selectedIndex == index;

                  return _PieceSetGridItem(
                    pieceSet: pieceSet,
                    isSelected: isSelected,
                    onTap: () {
                      setState(() => _selectedIndex = index);
                      widget.onPieceSetSelected(index);
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Individual piece set grid item
class _PieceSetGridItem extends StatelessWidget {
  const _PieceSetGridItem({
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: kBlack3Color,
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(
            color: isSelected ? kPrimaryColor : Colors.transparent,
            width: 2,
          ),
          boxShadow:
              isSelected
                  ? [
                    BoxShadow(
                      color: kPrimaryColor.withValues(alpha: 0.3),
                      blurRadius: 12,
                      spreadRadius: 0,
                    ),
                  ]
                  : null,
        ),
        child: Column(
          children: [
            // Pieces preview (King on top row, Queen + Knight on bottom)
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(6.sp),
                child: Column(
                  children: [
                    // Top: White King (larger)
                    Expanded(
                      flex: 3,
                      child: Image(
                        image: pieceSet.assets[PieceKind.whiteKing]!,
                        fit: BoxFit.contain,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    // Bottom: Black Queen + Knight (smaller)
                    Expanded(
                      flex: 2,
                      child: Row(
                        children: [
                          Expanded(
                            child: Image(
                              image: pieceSet.assets[PieceKind.blackQueen]!,
                              fit: BoxFit.contain,
                            ),
                          ),
                          Expanded(
                            child: Image(
                              image: pieceSet.assets[PieceKind.whiteKnight]!,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Piece set name
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 4.sp, vertical: 6.sp),
              decoration: BoxDecoration(
                color:
                    isSelected
                        ? kPrimaryColor.withValues(alpha: 0.1)
                        : Colors.transparent,
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(10.br),
                ),
              ),
              child: Text(
                pieceSet.label,
                style: AppTypography.textXsRegular.copyWith(
                  color: isSelected ? kPrimaryColor : kWhiteColor,
                  fontSize: 9.f,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
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

class _ViewModeSelector extends StatelessWidget {
  const _ViewModeSelector({
    required this.selectedIndex,
    required this.onModeSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onModeSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(4.sp),
      decoration: BoxDecoration(
        color: kBlack3Color,
        borderRadius: BorderRadius.circular(12.br),
      ),
      child: Row(
        children: [
          _buildOption(
            context,
            index: 0,
            icon: Icons.view_headline_rounded,
            label: 'List',
          ),
          SizedBox(width: 4.w),
          _buildOption(
            context,
            index: 1,
            icon: Icons.grid_view_rounded,
            label: 'Grid',
          ),
          SizedBox(width: 4.w),
          _buildOption(
            context,
            index: 2,
            icon: Icons.crop_square_rounded,
            label: 'Board',
          ),
        ],
      ),
    );
  }

  Widget _buildOption(
    BuildContext context, {
    required int index,
    required IconData icon,
    required String label,
  }) {
    final isSelected = selectedIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => onModeSelected(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(vertical: 8.sp),
          decoration: BoxDecoration(
            color: isSelected ? kPrimaryColor : Colors.transparent,
            borderRadius: BorderRadius.circular(8.br),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? kWhiteColor : kSecondaryTextColor,
                size: 20.ic,
              ),
              SizedBox(height: 4.h),
              Text(
                label,
                style: AppTypography.textXsMedium.copyWith(
                  color: isSelected ? kWhiteColor : kSecondaryTextColor,
                  fontSize: 10.f,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
