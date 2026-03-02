import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shows a dialog to create a new folder
/// Returns the folder name if created, null if cancelled
Future<String?> showCreateFolderDialog(BuildContext context) async {
  return showDialog<String>(
    context: context,
    builder:
        (context) => const _FolderNameDialog(
          title: 'Create Database',
          description: 'Enter a name for your new database',
          confirmLabel: 'Create',
        ),
  );
}

/// Shows a dialog to rename a database.
/// Returns the new name if saved, null if cancelled.
Future<String?> showRenameFolderDialog(
  BuildContext context, {
  required String currentName,
}) async {
  return showDialog<String>(
    context: context,
    builder:
        (context) => _FolderNameDialog(
          title: 'Rename Database',
          description: 'Enter a new name',
          confirmLabel: 'Save',
          initialValue: currentName,
        ),
  );
}

class _FolderNameDialog extends StatefulWidget {
  const _FolderNameDialog({
    required this.title,
    required this.description,
    required this.confirmLabel,
    this.initialValue,
  });

  final String title;
  final String description;
  final String confirmLabel;
  final String? initialValue;

  @override
  State<_FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState extends State<_FolderNameDialog> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
    _focusNode = FocusNode();

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

  void _handleCreate() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) {
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(name);
    } else {
      HapticFeedback.lightImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: kBlack2Color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.br)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: ResponsiveHelper.isTablet ? 400 : double.infinity,
        ),
        child: Padding(
          padding: EdgeInsets.all(24.sp),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Text(
                widget.title,
                style: AppTypography.textLgBold.copyWith(color: kWhiteColor),
              ),
              SizedBox(height: 8.h),
              Text(
                widget.description,
                style: AppTypography.textSmRegular.copyWith(
                  color: kWhiteColor.withValues(alpha: 0.6),
                ),
              ),
              SizedBox(height: 20.h),

              // Text field
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                maxLength: 50,
                autofocus: true,
                style: AppTypography.textMdRegular.copyWith(color: kWhiteColor),
                decoration: InputDecoration(
                  hintText: 'Database name',
                  hintStyle: AppTypography.textMdRegular.copyWith(
                    color: kWhiteColor.withValues(alpha: 0.4),
                  ),
                  filled: true,
                  fillColor: kWhiteColor.withValues(alpha: 0.06),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.br),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.br),
                    borderSide: BorderSide(
                      color: const Color(0xFF52525B), // Zinc 600
                      width: 1.5,
                    ),
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16.w,
                    vertical: 12.h,
                  ),
                  counterStyle: AppTypography.textXsRegular.copyWith(
                    color: kWhiteColor.withValues(alpha: 0.5),
                  ),
                  suffixIcon:
                      _controller.text.isNotEmpty
                          ? IconButton(
                            icon: Icon(
                              Icons.clear,
                              color: kWhiteColor.withValues(alpha: 0.6),
                              size: 20.sp,
                            ),
                            onPressed: () {
                              setState(() {
                                _controller.clear();
                              });
                              HapticFeedback.lightImpact();
                            },
                          )
                          : null,
                ),
                onChanged: (value) {
                  setState(() {}); // Rebuild to show/hide clear button
                },
                onSubmitted: (_) => _handleCreate(),
              ),

              SizedBox(height: 24.h),

              // Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.of(context).pop();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: kWhiteColor.withValues(alpha: 0.7),
                      padding: EdgeInsets.symmetric(
                        horizontal: 20.w,
                        vertical: 10.h,
                      ),
                    ),
                    child: Text('Cancel', style: AppTypography.textSmMedium),
                  ),
                  SizedBox(width: 12.w),
                  ElevatedButton(
                    onPressed: _handleCreate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kWhiteColor,
                      foregroundColor: kBlackColor,
                      padding: EdgeInsets.symmetric(
                        horizontal: 24.w,
                        vertical: 10.h,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.br),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      widget.confirmLabel,
                      style: AppTypography.textSmBold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
