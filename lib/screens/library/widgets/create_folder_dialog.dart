import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Result from the creation dialog
class LibraryFolderCreationData {
  final String name;
  final String? parentId;
  LibraryFolderCreationData(this.name, this.parentId);
}

/// Shows a refined dialog to create a new database or sub-database.
Future<LibraryFolderCreationData?> showCreateFolderDialog(
  BuildContext context, {
  String? initialParentId,
  bool lockToParent = false,
}) async {
  return showDialog<LibraryFolderCreationData>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.8),
    builder:
        (context) => _FolderNameDialog(
          title: initialParentId != null ? 'New Sub-database' : 'New Database',
          confirmLabel: 'Create',
          initialParentId: initialParentId,
          isLocked: lockToParent,
        ),
  );
}

/// Shows a dialog to rename a database.
Future<String?> showRenameFolderDialog(
  BuildContext context, {
  required String currentName,
}) async {
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.8),
    builder:
        (context) => _FolderNameDialog(
          title: 'Rename Database',
          confirmLabel: 'Save',
          initialValue: currentName,
          isRename: true,
        ),
  );
}

class _FolderNameDialog extends ConsumerStatefulWidget {
  const _FolderNameDialog({
    required this.title,
    required this.confirmLabel,
    this.initialValue,
    this.initialParentId,
    this.isRename = false,
    this.isLocked = false,
  });

  final String title;
  final String confirmLabel;
  final String? initialValue;
  final String? initialParentId;
  final bool isRename;
  final bool isLocked;

  @override
  ConsumerState<_FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState extends ConsumerState<_FolderNameDialog> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  String? _selectedParentId;
  bool _isSubdatabase = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
    _focusNode = FocusNode();
    _selectedParentId = widget.initialParentId;
    _isSubdatabase = widget.initialParentId != null;

    // Auto-focus the text field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleConfirm() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) {
      HapticFeedbackService.medium();
      if (widget.isRename) {
        Navigator.of(context).pop(name);
      } else {
        Navigator.of(context).pop(
          LibraryFolderCreationData(
            name,
            _isSubdatabase ? _selectedParentId : null,
          ),
        );
      }
    } else {
      HapticFeedbackService.light();
    }
  }

  @override
  Widget build(BuildContext context) {
    final rootFolders = ref.watch(rootLibraryFoldersProvider);
    final availableParents =
        rootFolders.where((f) => f.id != kTwicBookId).toList();

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: ResponsiveHelper.isTablet ? 420 : double.infinity,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF121214),
            borderRadius: BorderRadius.circular(24.br),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 40,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(28.sp),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(10.sp),
                      decoration: BoxDecoration(
                        color: kPrimaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12.br),
                      ),
                      child: Icon(
                        widget.isRename
                            ? Icons.edit_rounded
                            : (_isSubdatabase
                                ? Icons.folder_open_rounded
                                : Icons.folder_rounded),
                        color: kPrimaryColor,
                        size: 22.sp,
                      ),
                    ),
                    SizedBox(width: 16.w),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: AppTypography.textLgBold.copyWith(
                          color: context.colors.textPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ],
                ),

                SizedBox(height: 24.h),

                // Type Selection (only if not renaming and not locked)
                if (!widget.isRename && !widget.isLocked) ...[
                  _buildTypeSelector(),
                  SizedBox(height: 20.h),
                ],

                // Parent selection (if sub-database selected and not locked)
                if (_isSubdatabase && !widget.isLocked && !widget.isRename) ...[
                  _buildParentSelector(availableParents),
                  SizedBox(height: 20.h),
                ],

                // Context message for locked sub-database
                if (widget.isLocked && _selectedParentId != null) ...[
                  _buildLockedContext(availableParents),
                  SizedBox(height: 20.h),
                ],

                // Input Field
                _buildTextField(),

                SizedBox(height: 32.h),

                // Actions
                _buildActions(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTypeSelector() {
    return Container(
      padding: EdgeInsets.all(4.sp),
      decoration: BoxDecoration(
        color: context.colors.textPrimary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14.br),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TypeButton(
              label: 'Database',
              isSelected: !_isSubdatabase,
              onTap: () {
                setState(() => _isSubdatabase = false);
                HapticFeedbackService.light();
              },
            ),
          ),
          Expanded(
            child: _TypeButton(
              label: 'Subdatabase',
              isSelected: _isSubdatabase,
              onTap: () {
                setState(() {
                  _isSubdatabase = true;
                  // Default to first parent if none selected
                  final roots = ref.read(rootLibraryFoldersProvider);
                  if (_selectedParentId == null && roots.isNotEmpty) {
                    _selectedParentId =
                        roots.firstWhere((f) => f.id != kTwicBookId).id;
                  }
                });
                HapticFeedbackService.light();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParentSelector(List<LibraryFolder> parents) {
    if (parents.isEmpty) {
      return Text(
        'Create a database first to create a sub-database inside.',
        style: AppTypography.textXsRegular.copyWith(color: kRedColor),
      ).animate().fadeIn();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PARENT DATABASE',
          style: AppTypography.textXsBold.copyWith(
            color: context.colors.textPrimary.withValues(alpha: 0.4),
            letterSpacing: 1.0,
          ),
        ),
        SizedBox(height: 10.h),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          decoration: BoxDecoration(
            color: context.colors.textPrimary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12.br),
            border: Border.all(color: context.colors.textPrimary.withValues(alpha: 0.08)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedParentId,
              dropdownColor: const Color(0xFF1A1A1C),
              borderRadius: BorderRadius.circular(12.br),
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: context.colors.textPrimary.withValues(alpha: 0.4),
              ),
              isExpanded: true,
              items:
                  parents.map((folder) {
                    return DropdownMenuItem<String>(
                      value: folder.id,
                      child: Text(
                        folder.name,
                        style: AppTypography.textSmMedium.copyWith(
                          color: context.colors.textPrimary,
                        ),
                      ),
                    );
                  }).toList(),
              onChanged: (value) {
                setState(() => _selectedParentId = value);
                HapticFeedbackService.light();
              },
            ),
          ),
        ),
      ],
    ).animate().slideY(begin: 0.1, curve: Curves.easeOut);
  }

  Widget _buildLockedContext(List<LibraryFolder> parents) {
    final parent = parents.firstWhere(
      (p) => p.id == _selectedParentId,
      orElse: () => parents.first,
    );
    return Container(
      padding: EdgeInsets.all(12.sp),
      decoration: BoxDecoration(
        color: kPrimaryColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(color: kPrimaryColor.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: kPrimaryColor, size: 16.sp),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              'Inside database "${parent.name}"',
              style: AppTypography.textXsMedium.copyWith(
                color: context.colors.textPrimary.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'NAME',
          style: AppTypography.textXsBold.copyWith(
            color: context.colors.textPrimary.withValues(alpha: 0.4),
            letterSpacing: 1.0,
          ),
        ),
        SizedBox(height: 10.h),
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          maxLength: 40,
          style: AppTypography.textMdMedium.copyWith(color: kWhiteColor),
          cursorColor: kPrimaryColor,
          decoration: InputDecoration(
            hintText: 'e.g. My Openings',
            hintStyle: AppTypography.textMdRegular.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.2),
            ),
            filled: true,
            fillColor: context.colors.textPrimary.withValues(alpha: 0.04),
            contentPadding: EdgeInsets.symmetric(
              horizontal: 16.w,
              vertical: 16.h,
            ),
            counterText: '',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.br),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.br),
              borderSide: const BorderSide(color: kPrimaryColor, width: 1.5),
            ),
          ),
          onSubmitted: (_) => _handleConfirm(),
        ),
      ],
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: 16.h),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.br),
              ),
            ),
            child: Text(
              'Cancel',
              style: AppTypography.textSmMedium.copyWith(
                color: context.colors.textPrimary.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
        SizedBox(width: 16.w),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: _handleConfirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: kWhiteColor,
              foregroundColor: kBlackColor,
              padding: EdgeInsets.symmetric(vertical: 16.h),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.br),
              ),
            ),
            child: Text(widget.confirmLabel, style: AppTypography.textSmBold),
          ),
        ),
      ],
    );
  }
}

class _TypeButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _TypeButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(vertical: 10.h),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? context.colors.textPrimary.withValues(alpha: 0.08)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(10.br),
          border: Border.all(
            color:
                isSelected
                    ? context.colors.textPrimary.withValues(alpha: 0.1)
                    : Colors.transparent,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: AppTypography.textXsBold.copyWith(
              color:
                  isSelected ? kWhiteColor : context.colors.textPrimary.withValues(alpha: 0.4),
            ),
          ),
        ),
      ),
    );
  }
}
