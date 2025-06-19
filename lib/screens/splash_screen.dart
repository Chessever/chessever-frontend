import 'package:chessever2/utils/png_asset.dart' show PngAsset;
import 'package:chessever2/widgets/blur_background.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    Future.delayed(Duration(seconds: 2)).then((_) {
      FlutterNativeSplash.remove();
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
          fit: StackFit.expand,
          children: [
            Align(
              alignment: Alignment.center,
              child: Hero(tag: 'blur', child: AnimatedBlurBackground()),
            ),
            Align(
              alignment: Alignment.center,
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
