import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/screens/chessboard/widgets/smooth_sheet_config.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';
import 'package:smooth_sheets/smooth_sheets.dart';

/// Configuration for save analysis sheet
class SaveAnalysisSheetConfig {
  final ChessBoardStateNew state;
  final ChessBoardProviderParams params;
  final BuildContext hostContext;

  const SaveAnalysisSheetConfig({
    required this.state,
    required this.params,
    required this.hostContext,
  });
}

/// Show save analysis modal bottom sheet
Future<void> showSaveAnalysisSheet({
  required BuildContext context,
  required ChessBoardStateNew state,
  required ChessBoardProviderParams params,
}) async {
  final route = ChessSheetRoutes.commentEditor(
    context: context,
    builder: (_) => _SaveAnalysisSheet(
      config: SaveAnalysisSheetConfig(
        state: state,
        params: params,
        hostContext: context,
      ),
    ),
  );

  await Navigator.of(context).push(route);
}

/// Preset folder colors for new folder creation
const List<Color> _folderColorPresets = [
  Color(0xFF0FB4E5), // Cyan (primary)
  Color(0xFF10B981), // Emerald
  Color(0xFFF59E0B), // Amber
  Color(0xFFEF4444), // Red
  Color(0xFF8B5CF6), // Purple
  Color(0xFFEC4899), // Pink
  Color(0xFF06B6D4), // Teal
  Color(0xFFF97316), // Orange
];

/// Outer shell widget that sets up the smooth_sheets structure
class _SaveAnalysisSheet extends ConsumerWidget {
  final SaveAnalysisSheetConfig config;

  const _SaveAnalysisSheet({required this.config});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navigator = Navigator(
      onGenerateInitialRoutes: (_, __) => [
        SpringPagedSheetRoute(
          scrollConfiguration: const SheetScrollConfiguration(),
          dragConfiguration: ChessSheetConfigs.commentEditor,
          initialOffset: const SheetOffset.proportionalToViewport(0.75),
          snapGrid: SheetSnapGrid(
            snaps: const [
              SheetOffset.proportionalToViewport(0.55),
              SheetOffset.proportionalToViewport(0.75),
              SheetOffset.proportionalToViewport(0.92),
            ],
            minFlingSpeed: 600.0,
          ),
          builder: (context) => _SaveAnalysisPage(config: config),
        ),
      ],
    );

    return SheetKeyboardDismissible(
      dismissBehavior: const DragDownSheetKeyboardDismissBehavior(
        isContentScrollAware: true,
      ),
      child: PagedSheet(
        decoration: ChessSheetDecoration.dark(alpha: 0.97, borderRadius: 28.sp),
        shrinkChildToAvoidDynamicOverlap: true,
        navigator: navigator,
      ),
    );
  }
}

/// Inner page widget with actual content
class _SaveAnalysisPage extends ConsumerStatefulWidget {
  final SaveAnalysisSheetConfig config;

  const _SaveAnalysisPage({required this.config});

  @override
  ConsumerState<_SaveAnalysisPage> createState() => _SaveAnalysisPageState();
}

class _SaveAnalysisPageState extends ConsumerState<_SaveAnalysisPage>
    with SingleTickerProviderStateMixin {
  late TextEditingController _titleController;
  late TextEditingController _newFolderNameController;
  late FocusNode _titleFocusNode;
  late FocusNode _newFolderNameFocusNode;

  LibraryFolder? _selectedFolder;
  bool _isSaving = false;
  String? _errorMessage;
  bool _isCreatingNewFolder = false;
  Color _selectedFolderColor = _folderColorPresets.first;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: _generateDefaultTitle());
    _newFolderNameController = TextEditingController();
    _titleFocusNode = FocusNode();
    _newFolderNameFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _newFolderNameController.dispose();
    _titleFocusNode.dispose();
    _newFolderNameFocusNode.dispose();
    super.dispose();
  }

  String _generateDefaultTitle() {
    final game = widget.config.state.game;
    final whiteName = game.whitePlayer.name;
    final blackName = game.blackPlayer.name;
    return '$whiteName vs $blackName';
  }

  Future<void> _handleSave() async {
    if (_isSaving) return;

    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a title';
      });
      HapticFeedback.lightImpact();
      return;
    }

    // Validate new folder name if creating one
    if (_isCreatingNewFolder) {
      final newFolderName = _newFolderNameController.text.trim();
      if (newFolderName.isEmpty) {
        setState(() {
          _errorMessage = 'Please enter a folder name';
        });
        HapticFeedback.lightImpact();
        return;
      }
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final repository = ref.read(libraryRepositoryProvider);
      final userId = repository.supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Create new folder if needed
      String? targetFolderId = _selectedFolder?.id;
      if (_isCreatingNewFolder) {
        final newFolderName = _newFolderNameController.text.trim();
        final newFolder = await repository.createFolder(
          name: newFolderName,
          color:
              '#${_selectedFolderColor.toARGB32().toRadixString(16).substring(2)}',
        );
        targetFolderId = newFolder.id;
      }

      final state = widget.config.state;
      final analysisGame = state.analysisState.game;
      if (analysisGame == null) {
        throw Exception('No analysis game to save');
      }

      // Build analysis_state JSONB with navigation info
      final analysisStateJson = <String, dynamic>{
        'move_pointer': state.analysisState.movePointer,
        'is_board_flipped': state.isBoardFlipped,
      };

      // Create SavedAnalysis object
      final savedAnalysis = SavedAnalysis(
        id: '', // Will be generated by database
        userId: userId,
        folderId: targetFolderId,
        title: title,
        sourceGameId: state.game.gameId,
        sourceTournamentId: state.game.tourId,
        chessGame: analysisGame,
        analysisState: analysisStateJson,
        variationComments: state.variationComments,
        lastViewedPosition: state.analysisState.currentMoveIndex,
        tags: const [],
        notes: null,
        isFavorite: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Save to database
      await repository.createSavedAnalysis(savedAnalysis);

      if (mounted && context.mounted) {
        HapticFeedback.mediumImpact();

        // Show success feedback
        ScaffoldMessenger.of(widget.config.hostContext).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF1A1A1C).withValues(alpha: 0.95),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.br),
            ),
            content: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(6.sp),
                  decoration: BoxDecoration(
                    color: kPrimaryColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8.br),
                  ),
                  child: Icon(
                    Icons.check_rounded,
                    color: kPrimaryColor,
                    size: 16.sp,
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Text(
                    'Analysis saved successfully',
                    style: AppTypography.textSmMedium.copyWith(
                      color: kWhiteColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

        // Close the sheet - pop twice to exit both Navigator and route
        Navigator.of(widget.config.hostContext).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to save: ${e.toString()}';
          _isSaving = false;
        });
        HapticFeedback.lightImpact();
      }
    }
  }

  void _toggleCreateNewFolder() {
    setState(() {
      _isCreatingNewFolder = !_isCreatingNewFolder;
      if (_isCreatingNewFolder) {
        _selectedFolder = null;
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            _newFolderNameFocusNode.requestFocus();
          }
        });
      }
    });
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final foldersAsync = ref.watch(_foldersProvider);

    // CRITICAL: Wrap with Material to prevent yellow underline bug
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle
                _buildDragHandle(),

                // Header
                _buildHeader()
                    .animate()
                    .fadeIn(duration: 300.ms, delay: 50.ms)
                    .slideY(
                      begin: 0.1,
                      end: 0,
                      duration: 350.ms,
                      curve: Curves.easeOutCubic,
                    ),

                SizedBox(height: 24.h),

                // Title input section
                _buildTitleSection()
                    .animate()
                    .fadeIn(duration: 300.ms, delay: 100.ms)
                    .slideY(
                      begin: 0.1,
                      end: 0,
                      duration: 350.ms,
                      curve: Curves.easeOutCubic,
                    ),

                SizedBox(height: 24.h),

                // Folder section
                _buildFolderSection(foldersAsync)
                    .animate()
                    .fadeIn(duration: 300.ms, delay: 150.ms)
                    .slideY(
                      begin: 0.1,
                      end: 0,
                      duration: 350.ms,
                      curve: Curves.easeOutCubic,
                    ),

                // Error messages
                if (_errorMessage != null) ...[
                  SizedBox(height: 16.h),
                  _buildErrorMessage()
                      .animate()
                      .fadeIn(duration: 200.ms)
                      .shake(hz: 2, curve: Curves.easeInOut),
                ],

                SizedBox(height: 28.h),

                // Action buttons
                _buildActionButtons()
                    .animate()
                    .fadeIn(duration: 300.ms, delay: 200.ms)
                    .slideY(
                      begin: 0.1,
                      end: 0,
                      duration: 350.ms,
                      curve: Curves.easeOutCubic,
                    ),

                SizedBox(height: 16.h),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDragHandle() {
    return Center(
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 12.h),
        width: 40.w,
        height: 4.h,
        decoration: BoxDecoration(
          color: kWhiteColor.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(2.br),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Icon with gradient background
              Container(
                padding: EdgeInsets.all(10.sp),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      kPrimaryColor.withValues(alpha: 0.2),
                      kPrimaryColor.withValues(alpha: 0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12.br),
                  border: Border.all(
                    color: kPrimaryColor.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Icon(
                  Icons.bookmark_add_rounded,
                  color: kPrimaryColor,
                  size: 22.sp,
                ),
              ),
              SizedBox(width: 14.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Save Analysis',
                      style: AppTypography.textLgBold.copyWith(
                        color: kWhiteColor,
                        letterSpacing: -0.3,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      'Keep your variations & comments',
                      style: AppTypography.textSmRegular.copyWith(
                        color: kWhiteColor.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTitleSection() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Title',
                style: AppTypography.textSmMedium.copyWith(
                  color: kWhiteColor.withValues(alpha: 0.8),
                  letterSpacing: 0.3,
                ),
              ),
              SizedBox(width: 6.w),
              Text(
                '*',
                style: AppTypography.textSmMedium.copyWith(
                  color: kPrimaryColor,
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          Container(
            decoration: BoxDecoration(
              color: kWhiteColor.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(14.br),
              border: Border.all(
                color: _titleFocusNode.hasFocus
                    ? kPrimaryColor.withValues(alpha: 0.5)
                    : kWhiteColor.withValues(alpha: 0.08),
                width: 1.5,
              ),
            ),
            child: TextField(
              controller: _titleController,
              focusNode: _titleFocusNode,
              enabled: !_isSaving,
              maxLength: 100,
              style: AppTypography.textMdRegular.copyWith(color: kWhiteColor),
              decoration: InputDecoration(
                hintText: 'Enter a memorable title...',
                hintStyle: AppTypography.textMdRegular.copyWith(
                  color: kWhiteColor.withValues(alpha: 0.3),
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16.w,
                  vertical: 14.h,
                ),
                counterText: '',
                suffixIcon: _titleController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          color: kWhiteColor.withValues(alpha: 0.4),
                          size: 18.sp,
                        ),
                        onPressed: _isSaving
                            ? null
                            : () {
                                setState(() {
                                  _titleController.clear();
                                });
                                HapticFeedback.lightImpact();
                              },
                      )
                    : null,
              ),
              onChanged: (value) {
                setState(() {}); // Rebuild to show/hide clear button
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderSection(AsyncValue<List<LibraryFolder>> foldersAsync) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header with toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Save to Folder',
                style: AppTypography.textSmMedium.copyWith(
                  color: kWhiteColor.withValues(alpha: 0.8),
                  letterSpacing: 0.3,
                ),
              ),
              // Create new folder toggle
              GestureDetector(
                onTap: _isSaving ? null : _toggleCreateNewFolder,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: EdgeInsets.symmetric(
                    horizontal: 12.w,
                    vertical: 6.h,
                  ),
                  decoration: BoxDecoration(
                    color: _isCreatingNewFolder
                        ? kPrimaryColor.withValues(alpha: 0.15)
                        : kWhiteColor.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(20.br),
                    border: Border.all(
                      color: _isCreatingNewFolder
                          ? kPrimaryColor.withValues(alpha: 0.4)
                          : kWhiteColor.withValues(alpha: 0.1),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isCreatingNewFolder
                            ? Icons.folder_outlined
                            : Icons.create_new_folder_outlined,
                        size: 14.sp,
                        color: _isCreatingNewFolder
                            ? kPrimaryColor
                            : kWhiteColor.withValues(alpha: 0.6),
                      ),
                      SizedBox(width: 6.w),
                      Text(
                        _isCreatingNewFolder ? 'Choose Existing' : 'New Folder',
                        style: AppTypography.textXsMedium.copyWith(
                          color: _isCreatingNewFolder
                              ? kPrimaryColor
                              : kWhiteColor.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 14.h),

          // Content based on mode
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SizeTransition(sizeFactor: animation, child: child),
              );
            },
            child: _isCreatingNewFolder
                ? _buildNewFolderInput(key: const ValueKey('new_folder'))
                : _buildFolderList(
                    foldersAsync,
                    key: const ValueKey('folder_list'),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewFolderInput({Key? key}) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Folder name input
        Container(
          decoration: BoxDecoration(
            color: kWhiteColor.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14.br),
            border: Border.all(
              color: _newFolderNameFocusNode.hasFocus
                  ? kPrimaryColor.withValues(alpha: 0.5)
                  : kWhiteColor.withValues(alpha: 0.08),
              width: 1.5,
            ),
          ),
          child: TextField(
            controller: _newFolderNameController,
            focusNode: _newFolderNameFocusNode,
            enabled: !_isSaving,
            maxLength: 50,
            style: AppTypography.textMdRegular.copyWith(color: kWhiteColor),
            decoration: InputDecoration(
              hintText: 'Folder name',
              hintStyle: AppTypography.textMdRegular.copyWith(
                color: kWhiteColor.withValues(alpha: 0.3),
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16.w,
                vertical: 14.h,
              ),
              counterText: '',
              prefixIcon: Padding(
                padding: EdgeInsets.only(left: 14.w, right: 10.w),
                child: Container(
                  padding: EdgeInsets.all(6.sp),
                  decoration: BoxDecoration(
                    color: _selectedFolderColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8.br),
                  ),
                  child: Icon(
                    Icons.folder_rounded,
                    color: _selectedFolderColor,
                    size: 18.sp,
                  ),
                ),
              ),
              prefixIconConstraints: BoxConstraints(
                minWidth: 50.w,
                minHeight: 36.h,
              ),
            ),
            onChanged: (value) {
              setState(() {});
            },
          ),
        ),

        SizedBox(height: 14.h),

        // Color picker
        Text(
          'Folder Color',
          style: AppTypography.textXsRegular.copyWith(
            color: kWhiteColor.withValues(alpha: 0.5),
          ),
        ),
        SizedBox(height: 10.h),
        SizedBox(
          height: 36.h,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _folderColorPresets.length,
            separatorBuilder: (_, __) => SizedBox(width: 10.w),
            itemBuilder: (context, index) {
              final color = _folderColorPresets[index];
              final isSelected = _selectedFolderColor == color;

              return GestureDetector(
                onTap: _isSaving
                    ? null
                    : () {
                        setState(() {
                          _selectedFolderColor = color;
                        });
                        HapticFeedback.selectionClick();
                      },
                child: SingleMotionBuilder(
                  motion: const CupertinoMotion.smooth(),
                  value: isSelected ? 1.0 : 0.0,
                  builder: (context, value, child) {
                    final animValue = value.clamp(0.0, 1.0).toDouble();
                    return Transform.scale(
                      scale: 1.0 + (animValue * 0.15),
                      child: Container(
                        width: 36.w,
                        height: 36.h,
                        decoration: BoxDecoration(
                          color: color.withValues(
                            alpha: 0.2 + (animValue * 0.3),
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: color.withValues(
                              alpha: 0.5 + (animValue * 0.5),
                            ),
                            width: 2 + animValue,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: color.withValues(alpha: 0.4),
                                    blurRadius: 12,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                        child: isSelected
                            ? Icon(
                                Icons.check_rounded,
                                color: color,
                                size: 18.sp,
                              )
                            : null,
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFolderList(
    AsyncValue<List<LibraryFolder>> foldersAsync, {
    Key? key,
  }) {
    return foldersAsync.when(
      data: (folders) => _buildFolderListContent(folders, key: key),
      loading: () => _buildFolderListLoading(key: key),
      error: (e, _) => _buildFolderListError(e, key: key),
    );
  }

  Widget _buildFolderListContent(List<LibraryFolder> folders, {Key? key}) {
    // If no folders exist, prompt user to create one
    if (folders.isEmpty) {
      return Container(
        key: key,
        padding: EdgeInsets.all(20.sp),
        decoration: BoxDecoration(
          color: kWhiteColor.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16.br),
          border: Border.all(color: kWhiteColor.withValues(alpha: 0.06)),
        ),
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.all(12.sp),
              decoration: BoxDecoration(
                color: kPrimaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12.br),
              ),
              child: Icon(
                Icons.create_new_folder_outlined,
                color: kPrimaryColor,
                size: 28.sp,
              ),
            ),
            SizedBox(height: 14.h),
            Text(
              'No folders yet',
              style: AppTypography.textSmMedium.copyWith(
                color: kWhiteColor.withValues(alpha: 0.9),
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              'Create a folder to organize your analyses',
              style: AppTypography.textXsRegular.copyWith(
                color: kWhiteColor.withValues(alpha: 0.5),
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16.h),
            GestureDetector(
              onTap: _isSaving ? null : _toggleCreateNewFolder,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
                decoration: BoxDecoration(
                  color: kPrimaryColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20.br),
                  border: Border.all(
                    color: kPrimaryColor.withValues(alpha: 0.4),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, size: 16.sp, color: kPrimaryColor),
                    SizedBox(width: 6.w),
                    Text(
                      'Create Folder',
                      style: AppTypography.textSmMedium.copyWith(
                        color: kPrimaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Show folders list (without "No folder" option)
    return Container(
      key: key,
      decoration: BoxDecoration(
        color: kWhiteColor.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16.br),
        border: Border.all(color: kWhiteColor.withValues(alpha: 0.06)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16.br),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: folders.asMap().entries.map((entry) {
            final index = entry.key;
            final folder = entry.value;
            final isSelected = _selectedFolder?.id == folder.id;
            final isLast = index == folders.length - 1;

            return Column(
              children: [
                _FolderListItem(
                  folder: folder,
                  isSelected: isSelected,
                  isDisabled: _isSaving,
                  onTap: () {
                    setState(() {
                      _selectedFolder = folder;
                    });
                    HapticFeedback.selectionClick();
                  },
                ),
                if (!isLast)
                  Container(
                    height: 1,
                    margin: EdgeInsets.only(left: 56.w),
                    color: kWhiteColor.withValues(alpha: 0.05),
                  ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildFolderListLoading({Key? key}) {
    return Container(
      key: key,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 20.h),
      decoration: BoxDecoration(
        color: kWhiteColor.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16.br),
        border: Border.all(color: kWhiteColor.withValues(alpha: 0.06)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 18.w,
            height: 18.h,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                kPrimaryColor.withValues(alpha: 0.6),
              ),
            ),
          ),
          SizedBox(width: 12.w),
          Text(
            'Loading folders...',
            style: AppTypography.textSmRegular.copyWith(
              color: kWhiteColor.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderListError(Object error, {Key? key}) {
    return Container(
      key: key,
      padding: EdgeInsets.all(16.sp),
      decoration: BoxDecoration(
        color: kRedColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16.br),
        border: Border.all(color: kRedColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8.sp),
            decoration: BoxDecoration(
              color: kRedColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10.br),
            ),
            child: Icon(
              Icons.error_outline_rounded,
              color: kRedColor,
              size: 18.sp,
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Text(
              'Failed to load folders',
              style: AppTypography.textSmRegular.copyWith(
                color: kRedColor.withValues(alpha: 0.9),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorMessage() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.w),
      child: Container(
        padding: EdgeInsets.all(14.sp),
        decoration: BoxDecoration(
          color: kRedColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14.br),
          border: Border.all(color: kRedColor.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(6.sp),
              decoration: BoxDecoration(
                color: kRedColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8.br),
              ),
              child: Icon(
                Icons.warning_amber_rounded,
                color: kRedColor,
                size: 16.sp,
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                _errorMessage ?? '',
                style: AppTypography.textSmRegular.copyWith(
                  color: kRedColor.withValues(alpha: 0.9),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    // Save is enabled only when:
    // - Not currently saving, AND
    // - A folder is selected, OR new folder mode is on with a non-empty name
    final trimmedNewFolderName = _newFolderNameController.text.trim();
    final hasExistingFolder = _selectedFolder != null;
    final hasValidNewFolderName =
        _isCreatingNewFolder && trimmedNewFolderName.isNotEmpty;
    final canSave = !_isSaving && (hasValidNewFolderName || hasExistingFolder);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.w),
      child: Row(
        children: [
          // Cancel button
          Expanded(
            child: GestureDetector(
              onTap: _isSaving
                  ? null
                  : () {
                      HapticFeedback.lightImpact();
                      Navigator.of(widget.config.hostContext).pop();
                    },
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 16.h),
                decoration: BoxDecoration(
                  color: kWhiteColor.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14.br),
                  border: Border.all(color: kWhiteColor.withValues(alpha: 0.1)),
                ),
                child: Center(
                  child: Text(
                    'Cancel',
                    style: AppTypography.textSmMedium.copyWith(
                      color: kWhiteColor.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: 12.w),
          // Save button
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: canSave ? _handleSave : null,
              child: SingleMotionBuilder(
                motion: const CupertinoMotion.smooth(),
                value: _isSaving ? 0.95 : 1.0,
                builder: (context, value, child) {
                  final scale = value.clamp(0.0, 1.0).toDouble();
                  return Transform.scale(
                    scale: scale,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: EdgeInsets.symmetric(vertical: 16.h),
                      decoration: BoxDecoration(
                        gradient: canSave
                            ? LinearGradient(
                                colors: [
                                  kPrimaryColor,
                                  kPrimaryColor.withValues(alpha: 0.8),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        color: canSave
                            ? null
                            : kWhiteColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14.br),
                        boxShadow: canSave
                            ? [
                                BoxShadow(
                                  color: kPrimaryColor.withValues(alpha: 0.3),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ]
                            : null,
                      ),
                      child: Center(
                        child: _isSaving
                            ? SizedBox(
                                width: 20.w,
                                height: 20.h,
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    kWhiteColor,
                                  ),
                                ),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.bookmark_add_rounded,
                                    color: canSave
                                        ? kWhiteColor
                                        : kWhiteColor.withValues(alpha: 0.3),
                                    size: 18.sp,
                                  ),
                                  SizedBox(width: 8.w),
                                  Text(
                                    canSave
                                        ? 'Save Analysis'
                                        : _isCreatingNewFolder
                                        ? 'Name your folder'
                                        : 'Select a Folder',
                                    style: AppTypography.textSmBold.copyWith(
                                      color: canSave
                                          ? kWhiteColor
                                          : kWhiteColor.withValues(alpha: 0.3),
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
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

class _FolderListItem extends StatelessWidget {
  final LibraryFolder folder;
  final bool isSelected;
  final bool isDisabled;
  final VoidCallback onTap;

  const _FolderListItem({
    required this.folder,
    required this.isSelected,
    required this.isDisabled,
    required this.onTap,
  });

  Color _parseColorString(String colorString) {
    try {
      final hex = colorString.replaceAll('#', '');
      final colorValue = hex.length == 6 ? 'FF$hex' : hex;
      return Color(int.parse(colorValue, radix: 16));
    } catch (e) {
      return kPrimaryColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final folderColor = _parseColorString(folder.color);

    return GestureDetector(
      onTap: isDisabled ? null : onTap,
      child: SingleMotionBuilder(
        motion: const CupertinoMotion.smooth(),
        value: isSelected ? 1.0 : 0.0,
        builder: (context, value, child) {
          final animValue = value.clamp(0.0, 1.0).toDouble();
          return Container(
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
            decoration: BoxDecoration(
              color: Color.lerp(
                Colors.transparent,
                kPrimaryColor.withValues(alpha: 0.08),
                animValue,
              ),
            ),
            child: Row(
              children: [
                // Folder icon
                Container(
                  padding: EdgeInsets.all(8.sp),
                  decoration: BoxDecoration(
                    color: folderColor.withValues(
                      alpha: 0.12 + (animValue * 0.08),
                    ),
                    borderRadius: BorderRadius.circular(10.br),
                    border: Border.all(
                      color: folderColor.withValues(
                        alpha: 0.2 + (animValue * 0.2),
                      ),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    Icons.folder_rounded,
                    size: 18.sp,
                    color: folderColor,
                  ),
                ),
                SizedBox(width: 14.w),

                // Folder name
                Expanded(
                  child: Text(
                    folder.name,
                    style: AppTypography.textSmMedium.copyWith(
                      color: kWhiteColor.withValues(alpha: 0.9),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // Selection indicator
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  width: 22.w,
                  height: 22.h,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? kPrimaryColor
                        : kWhiteColor.withValues(alpha: 0.05),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? kPrimaryColor
                          : kWhiteColor.withValues(alpha: 0.15),
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? Icon(
                          Icons.check_rounded,
                          size: 14.sp,
                          color: kWhiteColor,
                        )
                      : null,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Provider to fetch folders for the current user
final _foldersProvider = FutureProvider.autoDispose<List<LibraryFolder>>((
  ref,
) async {
  final repository = ref.watch(libraryRepositoryProvider);
  return repository.getFolders();
});
