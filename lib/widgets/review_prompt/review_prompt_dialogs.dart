import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

class ReviewResult {
  final int rating;
  final String? feedback;

  ReviewResult({required this.rating, this.feedback});
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
  final PageController _pageController = PageController();
  int _rating = 0;
  
  // Feedback state
  final TextEditingController _feedbackController = TextEditingController();
  final Set<String> _selectedFeatures = {};
  bool _canSubmitFeedback = false;

  /// Feature suggestions for the survey
  static const List<String> _featureSuggestions = [
    'Offline mode',
    'Opening preparation',
    'Advanced analysis',
    'Player tracking',
  ];

  @override
  void dispose() {
    _pageController.dispose();
    _feedbackController.dispose();
    super.dispose();
  }

  void _onRatingSelected(int rating) {
    HapticFeedbackService.selection();
    setState(() {
      _rating = rating;
    });
  }

  void _goToFeedback() {
    if (_rating == 0) return;
    
    HapticFeedbackService.buttonPress();

    // If high rating and we're skipping the survey, return immediately
    if (_rating >= 4 && widget.skipSurveyForHighRating) {
      Navigator.of(context).pop(ReviewResult(rating: _rating, feedback: null));
      return;
    }

    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _updateCanSubmitFeedback() {
    setState(() {
      _canSubmitFeedback = _feedbackController.text.trim().isNotEmpty ||
          _selectedFeatures.isNotEmpty;
    });
  }

  String _buildFeedbackString() {
    final parts = <String>[];
    if (_selectedFeatures.isNotEmpty) {
      parts.add('Interested in: ${_selectedFeatures.join(', ')}');
    }
    if (_feedbackController.text.trim().isNotEmpty) {
      parts.add(_feedbackController.text.trim());
    }
    return parts.join('\n\n');
  }

  void _submit() {
    HapticFeedbackService.buttonPress();
    Navigator.of(context).pop(ReviewResult(
      rating: _rating,
      feedback: _buildFeedbackString(),
    ));
  }

  void _skip() {
    Navigator.of(context).pop(ReviewResult(
      rating: _rating,
      feedback: null, // Just the rating
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(maxWidth: 360.w, maxHeight: 500.h),
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
        // Use a PageView with physics: NeverScrollableScrollPhysics to prevent manual swiping
        child: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildRatingPage(),
            _buildFeedbackPage(),
          ],
        ),
      ),
    );
  }

  Widget _buildRatingPage() {
    return Padding(
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
                  onPressed: _rating == 0 ? null : _goToFeedback,
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
    final isHighRating = _rating >= 4;

    return SingleChildScrollView(
      padding: EdgeInsets.all(20.sp),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            isHighRating ? 'Thanks for the love!' : 'Thanks for the feedback',
            style: AppTypography.textLgBold.copyWith(
              color: kWhiteColor,
            ),
          ),
          SizedBox(height: 4.sp),
          Text(
            isHighRating
                ? 'What premium feature would you love to see?'
                : 'What can we do better?',
            style: AppTypography.textSmRegular.copyWith(
              color: kWhiteColor.withValues(alpha: 0.6),
            ),
          ),
          SizedBox(height: 12.sp),
          
          // Small star display to remind them of their rating
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

          // Quick-tap suggestions (only for high ratings)
          if (isHighRating) ...[
            Text(
              'Quick picks (tap to select)',
              style: AppTypography.textXsRegular.copyWith(
                color: kWhiteColor.withValues(alpha: 0.5),
              ),
            ),
            SizedBox(height: 8.sp),
            Wrap(
              spacing: 8.sp,
              runSpacing: 8.sp,
              children: _featureSuggestions.map((feature) {
                final isSelected = _selectedFeatures.contains(feature);
                return GestureDetector(
                  onTap: () {
                    HapticFeedbackService.selection();
                    setState(() {
                      if (isSelected) {
                        _selectedFeatures.remove(feature);
                      } else {
                        _selectedFeatures.add(feature);
                      }
                    });
                    _updateCanSubmitFeedback();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: EdgeInsets.symmetric(
                      horizontal: 12.sp,
                      vertical: 8.sp,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? kPrimaryColor.withValues(alpha: 0.15)
                          : kWhiteColor.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(20.br),
                      border: Border.all(
                        color: isSelected
                            ? kPrimaryColor.withValues(alpha: 0.5)
                            : kWhiteColor.withValues(alpha: 0.1),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      feature,
                      style: AppTypography.textXsMedium.copyWith(
                        color: isSelected
                            ? kPrimaryColor
                            : kWhiteColor.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            SizedBox(height: 12.sp),
          ],

          // Text Input
          TextField(
            controller: _feedbackController,
            onChanged: (_) => _updateCanSubmitFeedback(),
            maxLines: isHighRating ? 3 : 5,
            minLines: isHighRating ? 2 : 3,
            maxLength: 500,
            style: AppTypography.textSmRegular.copyWith(
              color: kWhiteColor,
            ),
            decoration: InputDecoration(
              hintText: isHighRating
                  ? 'Or share your own feature idea...'
                  : 'Tell us what went wrong or what we can improve...',
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

          // Buttons
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: _skip,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 12.sp),
                    backgroundColor: kWhiteColor.withValues(alpha: 0.04),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.br),
                    ),
                  ),
                  child: Text(
                    // If high rating, "Skip" implies "Skip survey" but still allows native review
                    // If low rating, "Skip" implies "Close"
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
                  onPressed: _canSubmitFeedback ? _submit : null,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 12.sp),
                    backgroundColor:
                        _canSubmitFeedback ? kPrimaryColor : kDarkGreyColor,
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
    );
  }
}
