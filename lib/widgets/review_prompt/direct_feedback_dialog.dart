import 'dart:io';
import 'dart:typed_data';

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

const int _maxPictureBytes = 8 * 1024 * 1024;

typedef FeedbackPicturePicker = Future<FeedbackPicture?> Function();

class FeedbackPicture {
  const FeedbackPicture({required this.bytes, required this.fileName});

  final Uint8List bytes;
  final String fileName;
}

class DirectFeedbackResult {
  const DirectFeedbackResult({required this.feedback, this.picture});

  final String feedback;
  final FeedbackPicture? picture;
}

/// Image extensions offered through the iOS document picker.
const List<String> _pictureExtensions = <String>[
  'png',
  'jpg',
  'jpeg',
  'heic',
  'webp',
];

Future<FeedbackPicture?> pickFeedbackPicture() async {
  // The vendored file_picker compiles only the document picker on iOS
  // (see third_party/file_picker/PATCH.md): FileType.image would fail there
  // with "Unsupported picker type". Ask for image documents instead, which
  // is the UIDocumentPickerViewController path. Android keeps the gallery
  // picker, which needs no permission.
  final result = await FilePicker.platform.pickFiles(
    type: Platform.isIOS ? FileType.custom : FileType.image,
    allowedExtensions: Platform.isIOS ? _pictureExtensions : null,
    allowMultiple: false,
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;
  final file = result.files.first;

  final bytes =
      file.bytes ??
      (file.path == null ? null : await File(file.path!).readAsBytes());
  if (bytes == null || bytes.isEmpty) return null;
  if (bytes.length > _maxPictureBytes) {
    throw const FeedbackPictureTooLargeException();
  }

  return FeedbackPicture(bytes: bytes, fileName: file.name);
}

class FeedbackPictureTooLargeException implements Exception {
  const FeedbackPictureTooLargeException();
}

Future<DirectFeedbackResult?> showDirectFeedbackDialog(
  BuildContext context, {
  FeedbackPicturePicker? pickPicture,
}) {
  return showAlertModal<DirectFeedbackResult>(
    context: context,
    horizontalPadding: 16,
    verticalPadding: 24,
    barrierDismissible: true,
    child: DirectFeedbackDialog(pickPicture: pickPicture),
  );
}

class DirectFeedbackDialog extends StatefulWidget {
  const DirectFeedbackDialog({super.key, this.pickPicture});

  final FeedbackPicturePicker? pickPicture;

  @override
  State<DirectFeedbackDialog> createState() => _DirectFeedbackDialogState();
}

class _DirectFeedbackDialogState extends State<DirectFeedbackDialog> {
  final TextEditingController _feedbackController = TextEditingController();
  FeedbackPicture? _picture;
  String? _pictureError;
  bool _canSend = false;
  bool _isPicking = false;

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _pickPicture() async {
    if (_isPicking) return;
    HapticFeedbackService.buttonPress();
    setState(() {
      _isPicking = true;
      _pictureError = null;
    });
    try {
      final picture = await (widget.pickPicture ?? pickFeedbackPicture)();
      if (!mounted || picture == null) return;
      setState(() => _picture = picture);
    } on FeedbackPictureTooLargeException {
      if (!mounted) return;
      setState(() => _pictureError = 'Choose a picture smaller than 8 MB.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _pictureError = 'We could not add that picture.');
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  void _removePicture() {
    HapticFeedbackService.selection();
    setState(() {
      _picture = null;
      _pictureError = null;
    });
  }

  void _send() {
    final feedback = _feedbackController.text.trim();
    if (feedback.isEmpty) return;
    HapticFeedbackService.buttonPress();
    Navigator.of(
      context,
    ).pop(DirectFeedbackResult(feedback: feedback, picture: _picture));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxWidth: 360.w, maxHeight: 680.h),
      decoration: BoxDecoration(
        color: context.colors.background,
        borderRadius: BorderRadius.circular(20.br),
        border: Border.all(
          color: context.colors.textPrimary.withValues(alpha: 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(20.sp),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Your Feedback',
                      style: AppTypography.textLgBold.copyWith(
                        color: context.colors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      Icons.close_rounded,
                      color: context.colors.iconPrimary,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 4.sp),
              Text(
                'Tell us what happened or what we can improve.',
                style: AppTypography.textSmRegular.copyWith(
                  color: context.colors.textPrimary.withValues(alpha: 0.6),
                ),
              ),
              SizedBox(height: 16.sp),
              TextField(
                controller: _feedbackController,
                autofocus: true,
                onChanged: (value) {
                  final canSend = value.trim().isNotEmpty;
                  if (canSend != _canSend) setState(() => _canSend = canSend);
                },
                textInputAction: TextInputAction.newline,
                maxLines: 5,
                minLines: 4,
                maxLength: 500,
                style: AppTypography.textSmRegular.copyWith(
                  color: context.colors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Type your feedback here...',
                  hintStyle: AppTypography.textSmRegular.copyWith(
                    color: context.colors.textPrimary.withValues(alpha: 0.35),
                  ),
                  filled: true,
                  fillColor: context.colors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.br),
                    borderSide: BorderSide(
                      color: context.colors.textPrimary.withValues(alpha: 0.08),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.br),
                    borderSide: BorderSide(
                      color: context.colors.textPrimary.withValues(alpha: 0.08),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.br),
                    borderSide: const BorderSide(color: kPrimaryColor),
                  ),
                  counterStyle: AppTypography.textXsRegular.copyWith(
                    color: context.colors.textPrimary.withValues(alpha: 0.35),
                  ),
                ),
              ),
              SizedBox(height: 8.sp),
              if (_picture == null)
                OutlinedButton.icon(
                  onPressed: _isPicking ? null : _pickPicture,
                  icon:
                      _isPicking
                          ? SizedBox(
                            width: 18.ic,
                            height: 18.ic,
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                          : const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Add picture'),
                )
              else
                Container(
                  padding: EdgeInsets.all(8.sp),
                  decoration: BoxDecoration(
                    color: context.colors.surface,
                    borderRadius: BorderRadius.circular(12.br),
                    border: Border.all(
                      color: context.colors.textPrimary.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8.br),
                        child: Image.memory(
                          _picture!.bytes,
                          width: 52.w,
                          height: 52.w,
                          fit: BoxFit.cover,
                          errorBuilder:
                              (_, __, ___) => SizedBox(
                                width: 52.w,
                                height: 52.w,
                                child: const Icon(Icons.image_outlined),
                              ),
                        ),
                      ),
                      SizedBox(width: 10.w),
                      Expanded(
                        child: Text(
                          _picture!.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.textSmMedium.copyWith(
                            color: context.colors.textPrimary,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _removePicture,
                        child: const Text('Remove'),
                      ),
                    ],
                  ),
                ),
              SizedBox(height: 4.sp),
              Text(
                'A picture can help us understand the issue faster. Optional.',
                style: AppTypography.textXsRegular.copyWith(
                  color: context.colors.textPrimary.withValues(alpha: 0.5),
                ),
              ),
              if (_pictureError != null) ...[
                SizedBox(height: 6.sp),
                Text(
                  _pictureError!,
                  style: AppTypography.textXsRegular.copyWith(
                    color: context.colors.danger,
                  ),
                ),
              ],
              SizedBox(height: 18.sp),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _canSend ? _send : null,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 12.sp),
                    backgroundColor:
                        _canSend
                            ? kPrimaryColor
                            : context.colors.surfaceRecessed,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.br),
                    ),
                  ),
                  child: Text(
                    'Send',
                    style: AppTypography.textSmMedium.copyWith(
                      color: kBlackColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
