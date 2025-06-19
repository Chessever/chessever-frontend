import 'package:chessever2/utils/png_asset.dart' show PngAsset;
import 'package:chessever2/widgets/blur_background.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    Future.delayed(Duration(seconds: 2)).then((_) {
      Navigator.pushReplacementNamed(context, '/auth_screen');
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return ScreenWrapper(
      child: Scaffold(
        body: Stack(
          alignment: Alignment.center,
          children: [
            Hero(tag: 'blur', child: BlurBackground()),
            Positioned(
              top: (MediaQuery.of(context).size.height / 2) - 60,
              left: (MediaQuery.of(context).size.width / 2) - 60,
              child: Hero(
                tag: 'premium-icon',
                child: Image.asset(
                  PngAsset.premiumIcon,
                  height: 120,
                  width: 120,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
