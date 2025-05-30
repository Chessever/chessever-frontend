import 'dart:io' show Platform;
import 'package:flutter/material.dart';

class SplashAuthScreen extends StatelessWidget {
  const SplashAuthScreen({Key? key}) : super(key: key);

  void _onSignIn(BuildContext context) {
    Navigator.pushReplacementNamed(context, '/tournaments');
  }

  @override
  Widget build(BuildContext context) {
    // Determine button text/icon based on platform
    final isIOS = Platform.isIOS;
    final buttonIcon = isIOS ? Icons.apple : Icons.g_mobiledata;
    final buttonText = isIOS ? 'Continue with Apple' : 'Continue with Google';
    final buttonTextColor = isIOS ? Colors.black : Colors.white;
    final buttonBgColor = isIOS ? Colors.white : const Color(0xFF4285F4);

    return Scaffold(
      backgroundColor: const Color(0xFF101215),
      body: Stack(
        children: [
          // Status bar simulation
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '9:41',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    Row(
                      children: const [
                        Icon(Icons.signal_cellular_alt, color: Colors.white, size: 20),
                        SizedBox(width: 4),
                        Icon(Icons.wifi, color: Colors.white, size: 20),
                        SizedBox(width: 4),
                        Icon(Icons.battery_full, color: Colors.white, size: 20),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Center logo + app name
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Replace with your Image.asset if you have a local asset!
                Image.network(
                  'https://cdn.builder.io/api/v1/image/assets/TEMP/73af920bddf3b3b86a27c37e991ed537b65ee271?placeholderIfAbsent=true',
                  width: 120,
                  height: 120,
                ),
                const SizedBox(height: 20),
                const Text(
                  'CHESSEVER',
                  style: TextStyle(
                    color: Color(0xFF18C7FF),
                    fontSize: 32,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
          // Bottom Platform-specific Sign In Button
          Positioned(
            left: 0,
            right: 0,
            bottom: 40,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _onSignIn(context),
                    icon: Icon(buttonIcon, color: buttonTextColor, size: 28),
                    label: Text(
                      buttonText,
                      style: TextStyle(
                        color: buttonTextColor,
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: buttonBgColor,
                      minimumSize: const Size.fromHeight(60),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      elevation: 0,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Home indicator
                  Container(
                    width: 120,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(4),
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
