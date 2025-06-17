import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Add this import

class SplashAuthScreen extends StatelessWidget {
  const SplashAuthScreen({Key? key}) : super(key: key);

  void _onSignIn(BuildContext context) {
    Navigator.pushReplacementNamed(context, '/tournaments');
  }

  @override
  Widget build(BuildContext context) {
    // Hide system overlays (including home indicator)
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
