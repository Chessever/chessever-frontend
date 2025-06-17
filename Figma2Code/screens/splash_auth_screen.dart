import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;

class SplashAuthScreen extends StatelessWidget {
  const SplashAuthScreen({Key? key}) : super(key: key);

  void _onSignIn(BuildContext context) {
    Navigator.pushReplacementNamed(context, '/tournaments');
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    const blueColor = Color(0xFF18C7FF);
    const logoUrl =
        'https://cdn.builder.io/api/v1/image/assets/TEMP/73af920bddf3b3b86a27c37e991ed537b65ee271?placeholderIfAbsent=true';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Subtle radial background
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, 0.1),
                radius: 0.9,
                colors: [
                  Color(0xFF07232F),
                  Colors.black,
                ],
                stops: [0.0, 1.0],
              ),
            ),
          ),
          // Removed status bar simulation (time, battery, wifi, signal icons)
          // Main content
          SafeArea(
            child: Column(
              children: [
                Spacer(flex: 4),
                Center(
                  child: Image.network(
                    logoUrl,
                    width: size.width * 0.32,
                    height: size.width * 0.32,
                    fit: BoxFit.contain,
                  ),
                ),
                SizedBox(height: size.height * 0.03),
                const Center(
                  child: Text(
                    'CHESSEVER',
                    style: TextStyle(
                      color: blueColor,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Arial',
                      letterSpacing: 2,
                    ),
                  ),
                ),
                Spacer(flex: 6),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: size.width * 0.045),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: size.height * 0.065,
                        child: ElevatedButton.icon(
                          onPressed: () => _onSignIn(context),
                          icon: const Icon(Icons.apple, color: Colors.black, size: 28),
                          label: const Text(
                            'Continue with Apple',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 19,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Arial',
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                          ),
                        ),
                      ),
                      SizedBox(height: size.height * 0.018),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}