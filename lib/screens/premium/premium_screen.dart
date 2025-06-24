import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';
import 'package:chessever2/widgets/auth_button.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/theme/app_theme.dart'; // Import for color constants

// Define colors to match your theme
const Color kBackgroundColor = Color(0xFF000000);
const Color kWhiteColor = Color(0xFFFFFFFF);
const Color kPrimaryColor = Color(0xFF007AFF);

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  bool yearlySelected = true;

  @override
  Widget build(BuildContext context) {
    // Get screen size to make UI responsive
    final Size screenSize = MediaQuery.of(context).size;
    final double paddingHorizontal = screenSize.width < 360 ? 16.0 : 24.0;

    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kWhiteColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          // Main content
          SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: paddingHorizontal),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Exact 41px spacing from AppBar to title
                  const SizedBox(height: 41),

                  // Premium title
                  Text(
                    'Upgrade to Premium',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                      color: kWhiteColor,
                    ),
                  ),

                  // Exact 12px spacing from title to description
                  const SizedBox(height: 12),

                  // Description text
                  Text(
                    'You are currently on the free plan. upgrade to premium to access cool features',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w400,
                      fontSize: 16,
                      height: 24 / 16, // Line height 24px
                      color: kWhiteColor,
                    ),
                  ),

                  // Exact 24px spacing from description to subscription box
                  const SizedBox(height: 24),

                  // Subscription options - Yearly
                  Container(
                    height: 166, // Exact 166px height
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16, // 16px horizontal padding
                      vertical: 20, // 20px vertical padding
                    ),
                    decoration: BoxDecoration(
                      color: yearlySelected ? kBlack2Color : kPopUpColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Header row with title, price, and checkbox
                        Row(
                          children: [
                            // Title and price
                            Expanded(
                              child: Row(
                                children: [
                                  Text(
                                    'Yearly ',
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontWeight:
                                          FontWeight
                                              .w500, // Updated to weight 500
                                      fontSize: 16, // Updated to 16px
                                      color: kWhiteColor,
                                    ),
                                  ),
                                  Text(
                                    '\$49.99',
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontWeight:
                                          FontWeight
                                              .w500, // Updated to weight 500
                                      fontSize: 16, // Updated to 16px
                                      color: kWhiteColor,
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8.0),
                                    child: Text(
                                      'Save \$9.99',
                                      style: const TextStyle(
                                        fontFamily: 'Inter',
                                        fontWeight: FontWeight.w500,
                                        fontSize: 14,
                                        fontStyle: FontStyle.italic,
                                        color: kPrimaryColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Selection using SVG instead of radio button
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  yearlySelected = true;
                                });
                              },
                              child: SvgWidget(
                                yearlySelected 
                                    ? SvgAsset.premiumSelected
                                    : SvgAsset.premiumUnselected,
                                width: 24,
                                height: 24,
                              ),
                            ),
                          ],
                        ),

                        // Feature items - each with 12px gap between them
                        _FeatureItem(
                          text: 'Unlock Library & Database features',
                        ),
                        const SizedBox(height: 12), // Exact 12px spacing
                        _FeatureItem(
                          text: 'Fully customizable tournament list',
                        ),
                        const SizedBox(height: 12), // Exact 12px spacing
                        _FeatureItem(text: 'Unlimited access to Chess'),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Monthly subscription box
                  Container(
                    height: 166, // Exact 166px height
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16, // 16px horizontal padding
                      vertical: 20, // 20px vertical padding
                    ),
                    decoration: BoxDecoration(
                      color: !yearlySelected ? kBlack2Color : kPopUpColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Header row with title, price, and checkbox
                        Row(
                          children: [
                            // Title and price
                            Expanded(
                              child: Row(
                                children: [
                                  Text(
                                    'Monthly ',
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontWeight:
                                          FontWeight
                                              .w500, // Updated to weight 500
                                      fontSize: 16, // Updated to 16px
                                      color: kWhiteColor,
                                    ),
                                  ),
                                  Text(
                                    '\$4.99',
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontWeight:
                                          FontWeight
                                              .w500, // Updated to weight 500
                                      fontSize: 16, // Updated to 16px
                                      color: kWhiteColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Selection using SVG instead of radio button
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  yearlySelected = false;
                                });
                              },
                              child: SvgWidget(
                                !yearlySelected 
                                    ? SvgAsset.premiumSelected
                                    : SvgAsset.premiumUnselected,
                                width: 24,
                                height: 24,
                              ),
                            ),
                          ],
                        ),

                        // Feature items - each with 12px gap between them
                        _FeatureItem(
                          text: 'Unlock Library & Database features',
                        ),
                        const SizedBox(height: 12), // Exact 12px spacing
                        _FeatureItem(
                          text: 'Fully customizable tournament list',
                        ),
                        const SizedBox(height: 12), // Exact 12px spacing
                        _FeatureItem(text: 'Unlimited access to Chess'),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // Upgrade button
                  Container(
                    width: double.infinity,
                    margin: EdgeInsets.only(bottom: 36),
                    child: _PremiumButton(
                      text: 'Upgrade to Premium',
                      onPressed: () {
                        // Handle subscription
                      },
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
}

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
