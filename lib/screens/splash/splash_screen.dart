import 'package:chessever2/screens/splash/splash_screen_provider.dart';
import 'package:chessever2/utils/png_asset.dart' show PngAsset;
import 'package:chessever2/widgets/blur_background.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    ///Remove Native Splash Screen
    FlutterNativeSplash.remove();
    ref.read(splashScreenProvider).runAuthenticationPreProcessor(context);
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
