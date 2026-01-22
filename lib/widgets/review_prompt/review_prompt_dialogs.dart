import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

class ReviewResult {
  final int rating;
  final String? feedback;
  final String? featureRequest;

  ReviewResult({
    required this.rating,
    this.feedback,
    this.featureRequest,
  });
}

Future<ReviewResult?> showReviewFlowDialog(
  BuildContext context, {
  bool skipSurveyForHighRating = false,
}) {
  return showDialog<ReviewResult>(
    context: context,
    barrierDismissible: true,
    builder:
        (context) => ReviewFlowDialog(
          skipSurveyForHighRating: skipSurveyForHighRating,
        ),
  );
}

class ReviewFlowDialog extends StatefulWidget {
  final bool skipSurveyForHighRating;

  const ReviewFlowDialog({super.key, this.skipSurveyForHighRating = false});

  @override
  State<ReviewFlowDialog> createState() => _ReviewFlowDialogState();
}

class _ReviewFlowDialogState extends State<ReviewFlowDialog> {
  int _step = 1;
  int _rating = 0;

  // Controllers
  final TextEditingController _feedbackController = TextEditingController();
  final TextEditingController _featureController = TextEditingController();

  // State
  bool _canSubmitFeedback = false;
  bool _canSubmitFeature = false;

  @override
  void dispose() {
    _feedbackController.dispose();
    _featureController.dispose();
    super.dispose();
  }

  void _onRatingSelected(int rating) {
    HapticFeedbackService.selection();
    setState(() {
      _rating = rating;
    });
  }

  void _goToStep(int step) {
    HapticFeedbackService.buttonPress();
    setState(() {
      _step = step;
    });
  }

  // Step 1 -> Step 2
  void _onRatingContinue() {
    if (_rating == 0) return;
    
    // If high rating and skipping survey, we might want to skip Step 2 AND 3?
    // The previous logic was: High Rating -> Survey (if not skipped) -> Native.
    // Low Rating -> Feedback -> Done.
    // The new requirement seems to unify this.
    // For now, I'll follow the unified flow: Rating -> Feedback -> Feature.
    // If "skipSurveyForHighRating" is true and rating is high, we probably still skip everything?
    if (_rating >= 4 && widget.skipSurveyForHighRating) {
      Navigator.of(context).pop(ReviewResult(rating: _rating));
      return;
    }

    _goToStep(2);
  }

  // Step 2 -> Step 3
  void _onFeedbackNext() {
    // Keep feedback
    _goToStep(3);
  }

  void _onFeedbackSkip() {
    // Clear feedback
    _feedbackController.clear();
    _goToStep(3);
  }

  // Step 3 -> Finish
  void _onFeatureSend() {
    HapticFeedbackService.buttonPress();
    _submit();
  }

  void _onFeatureSkip() {
    _featureController.clear();
    // Just submit whatever we have (rating + potentially feedback)
    Navigator.of(context).pop(ReviewResult(
      rating: _rating,
      feedback: _feedbackController.text.trim().isNotEmpty 
          ? _feedbackController.text.trim() 
          : null,
      featureRequest: null,
    ));
  }

  void _submit() {
    Navigator.of(context).pop(ReviewResult(
      rating: _rating,
      feedback: _feedbackController.text.trim().isNotEmpty 
          ? _feedbackController.text.trim() 
          : null,
      featureRequest: _featureController.text.trim().isNotEmpty 
          ? _featureController.text.trim() 
          : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 24.sp),
      child: Container(
        constraints: BoxConstraints(maxWidth: 360.w),
        decoration: BoxDecoration(
          color: kBackgroundColor,
          borderRadius: BorderRadius.circular(20.br),
          border: Border.all(
            color: kWhiteColor.withValues(alpha: 0.08),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.1, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: _buildCurrentStep(),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_step) {
      case 1:
        return _buildRatingPage();
      case 2:
        return _buildFeedbackPage();
      case 3:
        return _buildFeaturePage();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildRatingPage() {
    return Padding(
      key: const ValueKey(1),
      padding: EdgeInsets.all(20.sp),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.star_rounded,
            color: kPrimaryColor,
            size: 42.ic,
          ),
          SizedBox(height: 12.sp),
          Text(
            'Enjoying ChessEver?',
            style: AppTypography.textLgBold.copyWith(
              color: kWhiteColor,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 6.sp),
          Text(
            'Tap a star to rate your experience',
            style: AppTypography.textSmRegular.copyWith(
              color: kWhiteColor.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 16.sp),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final isActive = index < _rating;
              return IconButton(
                onPressed: () => _onRatingSelected(index + 1),
                icon: Icon(
                  isActive ? Icons.star_rounded : Icons.star_border_rounded,
                  color: isActive
                      ? kPrimaryColor
                      : kWhiteColor.withValues(alpha: 0.35),
                  size: 30.ic,
                ),
              );
            }),
          ),
          SizedBox(height: 24.sp),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 12.sp),
                    backgroundColor: kWhiteColor.withValues(alpha: 0.04),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.br),
                    ),
                  ),
                  child: Text(
                    'Not now',
                    style: AppTypography.textSmMedium.copyWith(
                      color: kWhiteColor.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 10.sp),
              Expanded(
                child: TextButton(
                  onPressed: _rating == 0 ? null : _onRatingContinue,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 12.sp),
                    backgroundColor:
                        _rating == 0 ? kDarkGreyColor : kPrimaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.br),
                    ),
                  ),
                  child: Text(
                    'Continue',
                    style: AppTypography.textSmMedium.copyWith(
                      color: kBlackColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackPage() {
    return SingleChildScrollView(
      key: const ValueKey(2),
      child: Padding(
        padding: EdgeInsets.all(20.sp),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your Feedback',
              style: AppTypography.textLgBold.copyWith(
                color: kWhiteColor,
              ),
            ),
            SizedBox(height: 4.sp),
            Text(
              'Tell us what went wrong or what we can improve...',
              style: AppTypography.textSmRegular.copyWith(
                color: kWhiteColor.withValues(alpha: 0.6),
              ),
            ),
            SizedBox(height: 12.sp),
            
            // Small star display
            Row(
              children: List.generate(5, (index) {
                final isActive = index < _rating;
                return Icon(
                  isActive ? Icons.star_rounded : Icons.star_border_rounded,
                  color: isActive
                      ? kPrimaryColor
                      : kWhiteColor.withValues(alpha: 0.25),
                  size: 18.ic,
                );
              }),
            ),
            SizedBox(height: 16.sp),

            TextField(
              controller: _feedbackController,
              onChanged: (val) {
                setState(() {
                  _canSubmitFeedback = val.trim().isNotEmpty;
                });
              },
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _onFeedbackNext(),
              maxLines: 4,
              minLines: 3,
              maxLength: 500,
              style: AppTypography.textSmRegular.copyWith(
                color: kWhiteColor,
              ),
              decoration: InputDecoration(
                hintText: 'Type your feedback here...',
                hintStyle: AppTypography.textSmRegular.copyWith(
                  color: kWhiteColor.withValues(alpha: 0.35),
                ),
                filled: true,
                fillColor: kBlack2Color,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.br),
                  borderSide: BorderSide(
                    color: kWhiteColor.withValues(alpha: 0.08),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.br),
                  borderSide: BorderSide(
                    color: kWhiteColor.withValues(alpha: 0.08),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.br),
                  borderSide: const BorderSide(color: kPrimaryColor),
                ),
                counterStyle: AppTypography.textXsRegular.copyWith(
                  color: kWhiteColor.withValues(alpha: 0.35),
                ),
              ),
            ),
            SizedBox(height: 12.sp),

            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _onFeedbackSkip,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 12.sp),
                      backgroundColor: kWhiteColor.withValues(alpha: 0.04),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.br),
                      ),
                    ),
                    child: Text(
                      'Skip',
                      style: AppTypography.textSmMedium.copyWith(
                        color: kWhiteColor.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 10.sp),
                Expanded(
                  child: TextButton(
                    onPressed: _canSubmitFeedback ? _onFeedbackNext : null,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 12.sp),
                      backgroundColor:
                          _canSubmitFeedback ? kPrimaryColor : kDarkGreyColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.br),
                      ),
                    ),
                    child: Text(
                      'Next',
                      style: AppTypography.textSmMedium.copyWith(
                        color: kBlackColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturePage() {
    return SingleChildScrollView(
      key: const ValueKey(3),
      child: Padding(
        padding: EdgeInsets.all(20.sp),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Feature Request',
              style: AppTypography.textLgBold.copyWith(
                color: kWhiteColor,
              ),
            ),
            SizedBox(height: 4.sp),
            Text(
              'What premium feature would you love to see?',
              style: AppTypography.textSmRegular.copyWith(
                color: kWhiteColor.withValues(alpha: 0.6),
              ),
            ),
            SizedBox(height: 16.sp),

            TextField(
              controller: _featureController,
              onChanged: (val) {
                setState(() {
                  _canSubmitFeature = val.trim().isNotEmpty;
                });
              },
              textInputAction: TextInputAction.send,
              onSubmitted: (_) {
                if (_canSubmitFeature) _onFeatureSend();
              },
              maxLines: 3,
              minLines: 2,
              maxLength: 200,
              style: AppTypography.textSmRegular.copyWith(
                color: kWhiteColor,
              ),
              decoration: InputDecoration(
                hintText: 'e.g. Offline Mode, More statistics...',
                hintStyle: AppTypography.textSmRegular.copyWith(
                  color: kWhiteColor.withValues(alpha: 0.35),
                ),
                filled: true,
                fillColor: kBlack2Color,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.br),
                  borderSide: BorderSide(
                    color: kWhiteColor.withValues(alpha: 0.08),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.br),
                  borderSide: BorderSide(
                    color: kWhiteColor.withValues(alpha: 0.08),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.br),
                  borderSide: const BorderSide(color: kPrimaryColor),
                ),
                counterStyle: AppTypography.textXsRegular.copyWith(
                  color: kWhiteColor.withValues(alpha: 0.35),
                ),
              ),
            ),
            SizedBox(height: 12.sp),

            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _onFeatureSkip,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 12.sp),
                      backgroundColor: kWhiteColor.withValues(alpha: 0.04),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.br),
                      ),
                    ),
                    child: Text(
                      'Skip',
                      style: AppTypography.textSmMedium.copyWith(
                        color: kWhiteColor.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 10.sp),
                Expanded(
                  child: TextButton(
                    onPressed: _canSubmitFeature ? _onFeatureSend : null,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 12.sp),
                      backgroundColor:
                          _canSubmitFeature ? kPrimaryColor : kDarkGreyColor,
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
          ],
        ),
      ),
    );
  }
}
