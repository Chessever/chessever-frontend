import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/back_drop_filter_widget.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';
import 'package:chessever2/widgets/auth_button.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:flutter_svg/flutter_svg.dart'; // Import for color constants

class PremiumScreen extends StatelessWidget {
  const PremiumScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        BackDropFilterWidget(),
        Container(
          decoration: const BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: kWhiteColor70,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              Text(
                'Premium',
                style: AppTypography.textLgMedium.copyWith(color: kWhiteColor),
              ),
              const SizedBox(height: 12),

              Align(
                alignment: Alignment.topLeft,
                child: Text(
                  'You are currently on the free plan. upgrade to\npremium to access cool features',
                  textAlign: TextAlign.start,
                  style: AppTypography.textSmBold.copyWith(
                    color: kBoardColorGrey,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Feature list
              _FeatureRow(
                icon: SvgAsset.libary_book,
                text: 'Unlock Library & Database features',
                iconColor: Colors.cyanAccent,
              ),
              const SizedBox(height: 12),
              _FeatureRow(
                icon: SvgAsset.tour_list,
                text: 'Fully customizable tournament list',
                iconColor: Colors.greenAccent,
              ),
              const SizedBox(height: 12),
              _FeatureRow(
                icon: SvgAsset.zero_ads,
                text: 'Zero Ads',
                iconColor: Colors.redAccent,
              ),
              const SizedBox(height: 24),

              // Pricing
              Text(
                '\$8.99/month',
                style: AppTypography.textSmRegular.copyWith(
                  color: kWhiteColor,
                  decoration: TextDecoration.lineThrough,
                ),

                // style: TextStyle(
                //   decoration: TextDecoration.lineThrough,
                //   color: Colors.grey,
                // ),
              ),
              Text(
                '\$58.99/year',
                style: AppTypography.textXlRegular.copyWith(color: kWhiteColor),
              ),

              const SizedBox(height: 16),

              // Toggle
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _PlanToggleButton(
                    isSelected: true,
                    text: 'Yearly',
                    onTap: () {},
                  ),
                  const SizedBox(width: 12),
                  _PlanToggleButton(
                    isSelected: false,
                    text: 'Monthly',
                    onTap: () {},
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Try for free button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyan,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Try for free',
                    style: AppTypography.textLgMedium.copyWith(
                      color: kBlackColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              Text(
                "You'll be billed at the end of your free trial. Feel free to cancel anytime through Google Play.",
                textAlign: TextAlign.center,
                style: AppTypography.textSmBold.copyWith(
                  color: kBoardColorGrey,
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final String icon;
  final String text;
  final Color iconColor;

  const _FeatureRow({
    required this.icon,
    required this.text,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SvgPicture.asset(icon, width: 16.w, height: 16.h),
        SizedBox(width: 5.w),
        Expanded(
          child: Text(
            text,
            style: AppTypography.textSmBold.copyWith(color: kBoardColorGrey),
          ),
        ),
      ],
    );
  }
}

class _PlanToggleButton extends StatelessWidget {
  final bool isSelected;
  final String text;
  final VoidCallback onTap;

  const _PlanToggleButton({
    required this.isSelected,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 20.sp, vertical: 8.sp),
        decoration: BoxDecoration(
          // color: isSelected ? kBoardColorGrey : Colors.transparent,
          border: Border.all(color: isSelected ? kBlackColor : kBoardColorGrey),
          borderRadius: BorderRadius.circular(12.br),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isSelected ? kBoardColorGrey : kWhiteColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// class PremiumScreen extends StatefulWidget {
//   const PremiumScreen({super.key});

//   @override
//   State<PremiumScreen> createState() => _PremiumScreenState();
// }

// class _PremiumScreenState extends State<PremiumScreen> {
//   bool yearlySelected = true;

//   @override
//   Widget build(BuildContext context) {
//     final Size screenSize = MediaQuery.of(context).size;
//     final double paddingHorizontal = screenSize.width < 360 ? 16.0 : 24.0;

//     return Scaffold(
//       backgroundColor: kBackgroundColor,
//       appBar: AppBar(
//         backgroundColor: Colors.transparent,
//         elevation: 0,
//         leading: IconButton(
//           icon: const Icon(Icons.arrow_back, color: kWhiteColor),
//           onPressed: () => Navigator.of(context).pop(),
//         ),
//       ),
//       body: Stack(
//         children: [
//           SafeArea(
//             child: Padding(
//               padding: EdgeInsets.symmetric(horizontal: paddingHorizontal),
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   const SizedBox(height: 41),
//                   const Text(
//                     'Upgrade to Premium',
//                     style: TextStyle(
//                       fontFamily: 'Inter',
//                       fontWeight: FontWeight.w600,
//                       fontSize: 18,
//                       color: kWhiteColor,
//                     ),
//                   ),
//                   const SizedBox(height: 12),
//                   const Text(
//                     'You are currently on the free plan. Upgrade to premium to access cool features.',
//                     style: TextStyle(
//                       fontFamily: 'Inter',
//                       fontWeight: FontWeight.w400,
//                       fontSize: 16,
//                       height: 1.5,
//                       color: kWhiteColor,
//                     ),
//                   ),
//                   const SizedBox(height: 24),

//                   // Subscription Options
//                   _subscriptionBox(
//                     title: 'Yearly',
//                     price: '\$49.99',
//                     subtext: 'Save \$9.99',
//                     selected: yearlySelected,
//                     onTap: () => setState(() => yearlySelected = true),
//                   ),
//                   const SizedBox(height: 20),
//                   _subscriptionBox(
//                     title: 'Monthly',
//                     price: '\$4.99',
//                     selected: !yearlySelected,
//                     onTap: () => setState(() => yearlySelected = false),
//                   ),

//                   const Spacer(),

//                   Container(
//                     width: double.infinity,
//                     margin: const EdgeInsets.only(bottom: 36),
//                     child: _PremiumButton(
//                       text: 'Try for free',
//                       onPressed: () {
//                         // Handle subscription logic here
//                       },
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _subscriptionBox({
//     required String title,
//     required String price,
//     String? subtext,
//     required bool selected,
//     required VoidCallback onTap,
//   }) {
//     return Container(
//       height: 166,
//       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
//       decoration: BoxDecoration(
//         color: selected ? kBlack2Color : kPopUpColor,
//         borderRadius: BorderRadius.circular(8),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//         children: [
//           Row(
//             children: [
//               Expanded(
//                 child: Row(
//                   children: [
//                     Text(
//                       '$title ',
//                       style: const TextStyle(
//                         fontFamily: 'Inter',
//                         fontWeight: FontWeight.w500,
//                         fontSize: 16,
//                         color: kWhiteColor,
//                       ),
//                     ),
//                     Text(
//                       price,
//                       style: const TextStyle(
//                         fontFamily: 'Inter',
//                         fontWeight: FontWeight.w500,
//                         fontSize: 16,
//                         color: kWhiteColor,
//                       ),
//                     ),
//                     if (subtext != null) ...[
//                       const SizedBox(width: 8),
//                       Text(
//                         subtext,
//                         style: const TextStyle(
//                           fontFamily: 'Inter',
//                           fontWeight: FontWeight.w500,
//                           fontSize: 14,
//                           fontStyle: FontStyle.italic,
//                           color: kPrimaryColor,
//                         ),
//                       ),
//                     ],
//                   ],
//                 ),
//               ),
//               GestureDetector(
//                 onTap: onTap,
//                 child: SvgWidget(
//                   selected
//                       ? SvgAsset.premiumSelected
//                       : SvgAsset.premiumUnselected,
//                   width: 24,
//                   height: 24,
//                 ),
//               ),
//             ],
//           ),
//           const SizedBox(height: 12),
//           _FeatureItem(text: 'Unlock Library & Database features'),
//           const SizedBox(height: 12),
//           _FeatureItem(text: 'Fully customizable tournament list'),
//           const SizedBox(height: 12),
//           _FeatureItem(text: 'Unlimited access to Chess'),
//         ],
//       ),
//     );
//   }
// }

class _FeatureItem extends StatelessWidget {
  final String text;

  const _FeatureItem({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Green checkmark
        Icon(Icons.check, color: const Color(0xFF26C940), size: 20),
        // Exactly 4px gap between icon and text
        const SizedBox(width: 4),
        // Feature text with updated typography
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w500, // Updated to weight 500 (medium)
              fontSize: 14, // Updated to 14px
              color: kWhiteColor,
            ),
          ),
        ),
      ],
    );
  }
}

class _PremiumButton extends StatefulWidget {
  final String text;
  final VoidCallback onPressed;
  final double height;
  final double? width;
  final double borderRadius;
  final EdgeInsetsGeometry padding;

  const _PremiumButton({
    required this.text,
    required this.onPressed,
    this.height = 48,
    this.width,
    this.borderRadius = 12,
    this.padding = const EdgeInsets.symmetric(horizontal: 24),
  });

  @override
  State<_PremiumButton> createState() => _PremiumButtonState();
}

class _PremiumButtonState extends State<_PremiumButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  bool _isPressed = false;

  @override
  void initState() {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      upperBound: 0.05,
    );
    super.initState();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void onTapDown(TapDownDetails _) {
    _isPressed = true;
    _animationController.forward().then((value) {
      if (_isPressed) return;
      _animationController.reverse();
    });
  }

  void onTapUp(TapUpDetails _) {
    _isPressed = false;
    if (_animationController.isAnimating) return;
    _animationController.reverse();
  }

  void onTapCancel() {
    _isPressed = false;
    _animationController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (cxt, child) {
        return Transform.scale(
          scale: 1 - _animationController.value,
          child: child,
        );
      },
      child: Container(
        height: widget.height,
        width: widget.width ?? MediaQuery.of(context).size.width,
        padding: widget.padding,
        decoration: BoxDecoration(
          color: kWhiteColor, // Pure white background
          borderRadius: BorderRadius.circular(widget.borderRadius),
          boxShadow: [],
        ),
        child: InkWell(
          onTap: () {
            Future.delayed(
              Duration(milliseconds: 100),
            ).then((_) => widget.onPressed());
          },
          onTapDown: onTapDown,
          onTapCancel: onTapCancel,
          onTapUp: onTapUp,
          child: Center(
            child: Text(
              widget.text,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w500,
                fontSize: 16,
                color: kBackgroundColor, // Black text
              ),
            ),
          ),
        ),
      ),
    );
  }
}
