import 'package:chessever2/providers/auto_pin_preferences_provider.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/repository/local_storage/auto_pin_preferences/auto_pin_preferences_repository.dart';
import 'package:chessever2/screens/settings/widgets/settings_primitives.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/board_customization_utils.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

typedef TrackPersist = void Function(Future<void> future);

/// Board + Auto-Pin settings as a non-scaffolded body widget.
/// Persist futures are reported via [trackPersist] so the host can await them
/// in a PopScope before navigation.
class BoardSettingsBody extends ConsumerWidget {
  const BoardSettingsBody({super.key, required this.trackPersist});

  final TrackPersist trackPersist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardSettingsAsync = ref.watch(boardSettingsProviderNew);

    return boardSettingsAsync.when(
      data: (boardSettings) => _buildContent(context, ref, boardSettings),
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'Error loading board settings',
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
    BoardSettingsNew boardSettings,
  ) {
    final boardNotifier = ref.read(boardSettingsProviderNew.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(title: 'Auto Pin'),
        SizedBox(height: 12.h),
        _AutoPinSection(trackPersist: trackPersist),

        SizedBox(height: 24.h),
        SectionLabel(title: 'Board'),
        SizedBox(height: 12.h),

        SettingCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Games View Mode',
                style: AppTypography.textMdMedium.copyWith(
                  color: context.colors.textPrimary,
                  fontSize: 13.f,
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                'Choose how games are displayed in tournament lists.',
                style: AppTypography.textSmRegular.copyWith(
                  color: context.colors.textSecondary,
                  fontSize: 11.f,
                ),
              ),
              SizedBox(height: 14.h),
              _ViewModeSelector(
                selectedIndex: boardSettings.gamesListViewModeIndex,
                onModeSelected: (index) {
                  trackPersist(
                    boardNotifier.setGamesListViewModeIndex(index),
                  );
                },
              ),
            ],
          ),
        ),
        SizedBox(height: 18.h),

        _BoardThemePickerCard(
          currentIndex: boardSettings.boardThemeIndex,
          onThemeSelected: (index) {
            trackPersist(boardNotifier.setBoardThemeIndex(index));
          },
        ),
        SizedBox(height: 18.h),

        _PieceSetPickerCard(
          currentIndex: boardSettings.pieceStyleIndex,
          onPieceSetSelected: (index) {
            trackPersist(boardNotifier.setPieceSetIndex(index));
          },
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
                      'Sound Effects',
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
                value: boardSettings.soundEnabled,
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
                  trackPersist(boardNotifier.toggleSound(value));
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
                    Row(
                      children: [
                        Text(
                          'Figurine Notation',
                          style: AppTypography.textMdMedium.copyWith(
                            color: context.colors.textPrimary,
                            fontSize: 13.f,
                          ),
                        ),
                        SizedBox(width: 8.w),
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
                        color: context.colors.textSecondary,
                        fontSize: 11.f,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: boardSettings.useFigurine,
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
                  trackPersist(boardNotifier.toggleFigurine(value));
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
                      'Board Coordinates',
                      style: AppTypography.textMdMedium.copyWith(
                        color: context.colors.textPrimary,
                        fontSize: 13.f,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'Show A–H and 1–8 labels along the board edges.',
                      style: AppTypography.textSmRegular.copyWith(
                        color: context.colors.textSecondary,
                        fontSize: 11.f,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: boardSettings.showCoordinates,
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
                  trackPersist(boardNotifier.toggleShowCoordinates(value));
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
                      'Raw PGN Mode',
                      style: AppTypography.textMdMedium.copyWith(
                        color: context.colors.textPrimary,
                        fontSize: 13.f,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'Hide auto symbols (!, ?, ±) and comments in the notation. Renders moves as clean PGN.',
                      style: AppTypography.textSmRegular.copyWith(
                        color: context.colors.textSecondary,
                        fontSize: 11.f,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: boardSettings.rawPgnMode,
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
                  trackPersist(boardNotifier.toggleRawPgnMode(value));
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AutoPinSection extends ConsumerWidget {
  const _AutoPinSection({required this.trackPersist});

  final TrackPersist trackPersist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoPinAsync = ref.watch(autoPinPreferencesProvider);
    final prefs = autoPinAsync.valueOrNull ?? AutoPinPreferences.defaults;
    final notifier = ref.read(autoPinPreferencesProvider.notifier);

    return Column(
      children: [
        SettingCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Favorite Players',
                      style: AppTypography.textMdMedium.copyWith(
                        color: context.colors.textPrimary,
                        fontSize: 13.f,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'Automatically pin games of your favorite players.',
                      style: AppTypography.textSmRegular.copyWith(
                        color: context.colors.textSecondary,
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
                  (states) => states.contains(WidgetState.selected)
                      ? kPrimaryColor.withValues(alpha: 0.35)
                      : context.colors.divider.withValues(alpha: 0.5),
                ),
                onChanged: (value) {
                  trackPersist(notifier.setFavoritePlayersAutoPin(value));
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
                      'Countrymen',
                      style: AppTypography.textMdMedium.copyWith(
                        color: context.colors.textPrimary,
                        fontSize: 13.f,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'Automatically pin games of players from your country.',
                      style: AppTypography.textSmRegular.copyWith(
                        color: context.colors.textSecondary,
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
                  (states) => states.contains(WidgetState.selected)
                      ? kPrimaryColor.withValues(alpha: 0.35)
                      : context.colors.divider.withValues(alpha: 0.5),
                ),
                onChanged: (value) {
                  trackPersist(notifier.setCountrymenAutoPin(value));
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

    return SettingCard(
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
                          color: context.colors.textPrimary,
                          fontSize: 13.f,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        'Choose from ${kBoardThemes.length} beautiful board styles',
                        style: AppTypography.textSmRegular.copyWith(
                          color: context.colors.textSecondary,
                          fontSize: 11.f,
                        ),
                      ),
                    ],
                  ),
                ),
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
            Container(
              padding: EdgeInsets.all(12.sp),
              decoration: BoxDecoration(
                color: context.colors.surfaceRecessed,
                borderRadius: BorderRadius.circular(12.br),
                border: Border.all(color: kPrimaryColor.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 56.w,
                    height: 56.h,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8.br),
                      boxShadow: [
                        BoxShadow(
                          color: context.colors.shadow,
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
                            color: context.colors.textPrimary,
                            fontSize: 14.f,
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          'Tap to browse all themes',
                          style: AppTypography.textSmRegular.copyWith(
                            color: context.colors.textTertiary,
                            fontSize: 11.f,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: context.colors.textTertiary,
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
    final isAuthenticated = await requireFullAuthGuard(context);
    if (!isAuthenticated || !context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: ResponsiveHelper.bottomSheetConstraints,
      builder: (context) => _BoardThemeGallerySheet(
        currentIndex: currentIndex,
        onThemeSelected: (index) {
          onThemeSelected(index);
          Navigator.pop(context);
        },
      ),
    );
  }
}

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
        color: context.colors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.br)),
      ),
      child: Column(
        children: [
          Container(
            margin: EdgeInsets.only(top: 12.sp),
            width: 40.w,
            height: 4.h,
            decoration: BoxDecoration(
              color: context.colors.divider,
              borderRadius: BorderRadius.circular(2.br),
            ),
          ),
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
                          color: context.colors.textPrimary,
                          fontSize: 18.f,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        '${kBoardThemes.length} styles available',
                        style: AppTypography.textSmRegular.copyWith(
                          color: context.colors.textTertiary,
                          fontSize: 12.f,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.close_rounded,
                    color: context.colors.textTertiary,
                    size: 24.ic,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: context.colors.surfaceRecessed,
                    padding: EdgeInsets.all(8.sp),
                  ),
                ),
              ],
            ),
          ),
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
          boxShadow: isSelected
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
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 4.sp, vertical: 6.sp),
              child: Text(
                theme.name,
                style: AppTypography.textXsRegular.copyWith(
                  color:
                      isSelected ? kPrimaryColor : context.colors.textPrimary,
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

    return SettingCard(
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
                          color: context.colors.textPrimary,
                          fontSize: 13.f,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        'Choose from ${kPieceSets.length} unique piece styles',
                        style: AppTypography.textSmRegular.copyWith(
                          color: context.colors.textSecondary,
                          fontSize: 11.f,
                        ),
                      ),
                    ],
                  ),
                ),
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
            Container(
              padding: EdgeInsets.all(12.sp),
              decoration: BoxDecoration(
                color: context.colors.surfaceRecessed,
                borderRadius: BorderRadius.circular(12.br),
                border: Border.all(color: kPrimaryColor.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 56.w,
                    height: 56.h,
                    decoration: BoxDecoration(
                      color: context.colors.surface,
                      borderRadius: BorderRadius.circular(8.br),
                      boxShadow: [
                        BoxShadow(
                          color: context.colors.shadow,
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
                            color: context.colors.textPrimary,
                            fontSize: 14.f,
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          'Tap to browse all pieces',
                          style: AppTypography.textSmRegular.copyWith(
                            color: context.colors.textTertiary,
                            fontSize: 11.f,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: context.colors.textTertiary,
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
    final isAuthenticated = await requireFullAuthGuard(context);
    if (!isAuthenticated || !context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: ResponsiveHelper.bottomSheetConstraints,
      builder: (context) => _PieceSetGallerySheet(
        currentIndex: currentIndex,
        onPieceSetSelected: (index) {
          onPieceSetSelected(index);
          Navigator.pop(context);
        },
      ),
    );
  }
}

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
        color: context.colors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.br)),
      ),
      child: Column(
        children: [
          Container(
            margin: EdgeInsets.only(top: 12.sp),
            width: 40.w,
            height: 4.h,
            decoration: BoxDecoration(
              color: context.colors.divider,
              borderRadius: BorderRadius.circular(2.br),
            ),
          ),
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
                          color: context.colors.textPrimary,
                          fontSize: 18.f,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        '${kPieceSets.length} styles available',
                        style: AppTypography.textSmRegular.copyWith(
                          color: context.colors.textTertiary,
                          fontSize: 12.f,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.close_rounded,
                    color: context.colors.textTertiary,
                    size: 24.ic,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: context.colors.surfaceRecessed,
                    padding: EdgeInsets.all(8.sp),
                  ),
                ),
              ],
            ),
          ),
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
          color: context.colors.surfaceRecessed,
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(
            color: isSelected ? kPrimaryColor : Colors.transparent,
            width: 2,
          ),
          boxShadow: isSelected
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
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(6.sp),
                child: Column(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Image(
                        image: pieceSet.assets[PieceKind.whiteKing]!,
                        fit: BoxFit.contain,
                      ),
                    ),
                    SizedBox(height: 2.h),
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
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 4.sp, vertical: 6.sp),
              decoration: BoxDecoration(
                color: isSelected
                    ? kPrimaryColor.withValues(alpha: 0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(10.br),
                ),
              ),
              child: Text(
                pieceSet.label,
                style: AppTypography.textXsRegular.copyWith(
                  color:
                      isSelected ? kPrimaryColor : context.colors.textPrimary,
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
        color: context.colors.surfaceRecessed,
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
            color: isSelected
                ? kPrimaryColor.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8.br),
            border: Border.all(
              color: isSelected ? kPrimaryColor : Colors.transparent,
              width: isSelected ? 1.5 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: kPrimaryColor.withValues(alpha: 0.18),
                      blurRadius: 8,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected
                    ? context.colors.textPrimary
                    : context.colors.textTertiary,
                size: 20.ic,
              ),
              SizedBox(height: 4.h),
              Text(
                label,
                style: AppTypography.textXsMedium.copyWith(
                  color: isSelected
                      ? context.colors.textPrimary
                      : context.colors.textTertiary,
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
